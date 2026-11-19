import Foundation
import SwiftData
import Network
import Observation

@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    private(set) var items: [OutboxItem] = []
    private(set) var isSyncing = false
    private(set) var isOnline = true
    var lastSyncedAt: Date? {
        didSet { UserDefaults.standard.set(lastSyncedAt, forKey: "sync.lastSyncedAt") }
    }

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let api = MyPlacesAPI.shared

    private init() {
        lastSyncedAt = UserDefaults.standard.object(forKey: "sync.lastSyncedAt") as? Date
    }

    func userChanged() { reloadItems() }

    func configure(container: ModelContainer) {
        guard context == nil else { return }
        context = ModelContext(container)
        reloadItems()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let regained = online && !self.isOnline
                self.isOnline = online
                if regained { await self.syncNow() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "myplaces.network"))
    }

    var pendingCount: Int { items.count }
    var hasFailures: Bool { items.contains { $0.state == .failed } }

    func state(for resourceID: UUID) -> OutboxState? {
        let matching = items.filter { $0.resourceID == resourceID }
        if matching.contains(where: { $0.state == .failed }) { return .failed }
        return matching.isEmpty ? nil : .pending
    }

    // MARK: Enqueue

    func enqueue<T: Encodable>(_ kind: OutboxKind, resourceID: UUID, label: String, payload: T) throws {
        guard let context else { return }
        let data = try JSONCoding.localEncoder.encode(payload)
        context.insert(OutboxOperation(kind: kind, resourceID: resourceID, ownerID: api.userID, label: label, payload: data))
        try context.save()
        reloadItems()
    }

    func payloads<T: Decodable>(_ kind: OutboxKind, as type: T.Type) -> [T] {
        rawPayloads.filter { $0.kind == kind }.compactMap { try? JSONCoding.localDecoder.decode(T.self, from: $0.data) }
    }

    @ObservationIgnored private var rawPayloads: [(kind: OutboxKind, data: Data)] = []

    // MARK: Sync

    func syncNow() async {
        guard !isSyncing, let context else { return }
        isSyncing = true
        defer { isSyncing = false; reloadItems() }
        var didSync = false
        for op in operations() where op.state == OutboxState.pending.rawValue {
            op.attemptCount += 1
            op.lastAttemptAt = Date()
            do {
                try await perform(op)
                cleanupFiles(op)
                context.delete(op)
                try? context.save()
                didSync = true
            } catch {
                if AppError.isNetwork(error) {
                    try? context.save()
                    break   // offline: keep order, retry later
                }
                op.state = OutboxState.failed.rawValue
                op.errorMessage = AppError.message(error)
                try? context.save()
            }
        }
        if operations().allSatisfy({ $0.state != OutboxState.pending.rawValue }) { lastSyncedAt = Date() }
        if didSync { AppEvents.shared.bump() }
    }

    func retryFailed() async {
        for op in operations() where op.state == OutboxState.failed.rawValue {
            op.state = OutboxState.pending.rawValue
            op.errorMessage = nil
        }
        try? context?.save()
        reloadItems()
        await syncNow()
    }

    func discard(_ id: UUID) {
        guard let context, let op = operations().first(where: { $0.id == id }) else { return }
        cleanupFiles(op)
        context.delete(op)
        try? context.save()
        reloadItems()
        AppEvents.shared.bump()
    }

    /// Called on sign-out: local queue belongs to the previous account.
    /// Called on sign-out / account switch. Pending writes stay on disk, tagged with their
    /// owner, and are replayed when that account signs in again.
    func reset() {
        lastSyncedAt = nil
        reloadItems()
    }

    // MARK: Private

    private func operations() -> [OutboxOperation] {
        guard let context else { return [] }
        let uid = api.userID
        let all = (try? context.fetch(FetchDescriptor<OutboxOperation>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.filter { $0.ownerID == nil || $0.ownerID == uid }
    }

    private func reloadItems() {
        let ops = operations()
        rawPayloads = ops.compactMap { op in OutboxKind(rawValue: op.kind).map { ($0, op.payload) } }
        items = ops.compactMap { op in
            guard let kind = OutboxKind(rawValue: op.kind) else { return nil }
            return OutboxItem(id: op.id, kind: kind, resourceID: op.resourceID, label: op.label,
                              state: OutboxState(rawValue: op.state) ?? .pending, errorMessage: op.errorMessage)
        }
    }

    private func perform(_ op: OutboxOperation) async throws {
        let dec = JSONCoding.localDecoder
        switch OutboxKind(rawValue: op.kind) {
        case .placeCreate:
            let p = try dec.decode(PlaceInsert.self, from: op.payload)
            do { try await api.insertPlace(p) } catch { if !AppError.isDuplicate(error) { throw error } }
        case .placeUpdate:
            let p = try dec.decode(PlaceUpdatePayload.self, from: op.payload)
            try await api.updatePlace(p.id, p.update)
        case .placeDelete:
            let p = try dec.decode(PlaceDeletePayload.self, from: op.payload)
            try await api.softDeletePlace(p.id)
        case .visitCreate:
            let d = try dec.decode(VisitDraftPayload.self, from: op.payload)
            do { try await api.insertVisit(d.visit) } catch { if !AppError.isDuplicate(error) { throw error } }
            for row in d.participants {
                do { try await api.insertParticipants([row]) } catch { if !AppError.isDuplicate(error) { throw error } }
            }
            if !d.photos.isEmpty {
                let photos: [PreparedPhoto] = d.photos.compactMap { ph in
                    guard let data = try? Data(contentsOf: OutboxFiles.url(ph.id)) else { return nil }
                    return PreparedPhoto(id: ph.id, data: data, width: ph.width, height: ph.height)
                }
                try await api.createMemory(parent: .visit(d.visit.id), body: nil, photos: photos, memoryId: d.memoryId)
            }
        case .none:
            break
        }
    }

    private func cleanupFiles(_ op: OutboxOperation) {
        guard op.kind == OutboxKind.visitCreate.rawValue,
              let d = try? JSONCoding.localDecoder.decode(VisitDraftPayload.self, from: op.payload) else { return }
        for p in d.photos { try? FileManager.default.removeItem(at: OutboxFiles.url(p.id)) }
    }
}

/// Global "something changed" signal; screens reload with `.task(id: events.revision)`.
@MainActor
@Observable
final class AppEvents {
    static let shared = AppEvents()
    private(set) var revision = 0
    func bump() { revision += 1 }
}
