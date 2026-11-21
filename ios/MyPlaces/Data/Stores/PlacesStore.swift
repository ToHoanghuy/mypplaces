import Foundation
import Observation

/// Personal map / list read model: `map_places` from the server, cached on disk for offline
/// launch, merged with not-yet-synced outbox writes (optimistic UI).
@MainActor
@Observable
final class PlacesStore {
    static let shared = PlacesStore()

    private(set) var serverPlaces: [MapPlace] = []
    /// MYP-4: last order fetched from the server (place id -> position); mirrored on disk.
    private(set) var serverOrder: [UUID: Int] = [:]
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    @ObservationIgnored private let api = MyPlacesAPI.shared
    private var sync: SyncEngine { SyncEngine.shared }

    private init() {
        serverPlaces = loadCache()
        serverOrder = loadOrderCache()
    }

    /// Viewer's custom order: a queued (not yet synced) reorder wins over the server copy.
    var orderPositions: [UUID: Int] {
        _ = sync.items
        if let pending = sync.payloads(.placeOrder, as: PlaceOrderPayload.self).last {
            return PlaceOrdering.positions(for: pending.ids)
        }
        return serverOrder
    }

    /// Saves a new custom order (outbox first, so it works offline and survives relaunch).
    func setOrder(_ ids: [UUID]) {
        try? sync.enqueueReplacing(.placeOrder, resourceID: PlaceOrderPayload.resourceID,
                                   label: "Sắp xếp danh sách địa điểm", payload: PlaceOrderPayload(ids: ids))
        Task { await sync.syncNow() }
    }

    /// Server rows + local pending writes.
    var places: [MapPlace] {
        _ = sync.items
        var list = serverPlaces
        for p in sync.payloads(.placeCreate, as: PlaceInsert.self) where !list.contains(where: { $0.id == p.id }) {
            list.append(MapPlace(placeId: p.id, ownerId: api.userID ?? UUID(), title: p.title, category: p.category,
                                 latitude: p.latitude, longitude: p.longitude, address: p.address, updatedAt: Date(),
                                 isOwner: true, myRole: nil, isShared: false, visitCount: 0, lastVisitedAt: nil,
                                 visitStatus: .wantToVisit, coverMemoryId: nil, coverStoragePath: nil))
        }
        for u in sync.payloads(.placeUpdate, as: PlaceUpdatePayload.self) {
            if let i = list.firstIndex(where: { $0.id == u.id }) {
                list[i].title = u.update.title; list[i].category = u.update.category
                list[i].latitude = u.update.latitude; list[i].longitude = u.update.longitude
                list[i].address = u.update.address
            }
        }
        let deleted = Set(sync.payloads(.placeDelete, as: PlaceDeletePayload.self).map(\.id))
        list.removeAll { deleted.contains($0.id) }
        for v in sync.payloads(.visitCreate, as: VisitDraftPayload.self) {
            if let i = list.firstIndex(where: { $0.id == v.visit.placeId }) {
                list[i].visitCount += 1
                list[i].visitStatus = .visited
                if (list[i].lastVisitedAt ?? .distantPast) < v.visit.visitedAt { list[i].lastVisitedAt = v.visit.visitedAt }
            }
        }
        return list
    }

    func place(_ id: UUID) -> MapPlace? { places.first { $0.id == id } }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            serverPlaces = try await api.mapPlaces()
            hasLoaded = true
            errorMessage = nil
            saveCache()
            // Order is optional: a failure here must not hide the list.
            if let order = try? await api.placeOrder() {
                serverOrder = order
                saveOrderCache()
            }
        } catch {
            hasLoaded = true
            if !AppError.isNetwork(error) { errorMessage = AppError.message(error) }
        }
    }

    // MARK: Writes (outbox first)

    func create(_ p: PlaceInsert) async throws {
        try sync.enqueue(.placeCreate, resourceID: p.id, label: "\(p.title) · Địa điểm mới", payload: p)
        AppEvents.shared.bump()
        await sync.syncNow()
        await refresh()
    }

    func update(_ id: UUID, _ u: PlaceUpdate) async throws {
        try sync.enqueue(.placeUpdate, resourceID: id, label: "\(u.title) · Sửa địa điểm", payload: PlaceUpdatePayload(id: id, update: u))
        AppEvents.shared.bump()
        await sync.syncNow()
        await refresh()
    }

    func delete(_ id: UUID, title: String) async throws {
        try sync.enqueue(.placeDelete, resourceID: id, label: "\(title) · Xóa địa điểm", payload: PlaceDeletePayload(id: id))
        AppEvents.shared.bump()
        await sync.syncNow()
        await refresh()
    }

    func reset() {
        serverPlaces = []
        serverOrder = [:]
        hasLoaded = false
        try? FileManager.default.removeItem(at: cacheURL)
        try? FileManager.default.removeItem(at: orderCacheURL)
    }

    // MARK: Cache

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("map_places.json")
    }
    private func saveCache() {
        if let data = try? JSONCoding.localEncoder.encode(serverPlaces) { try? data.write(to: cacheURL, options: .atomic) }
    }
    private var orderCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("place_order.json")
    }
    private func saveOrderCache() {
        if let data = try? JSONEncoder().encode(serverOrder) { try? data.write(to: orderCacheURL, options: .atomic) }
    }
    private func loadOrderCache() -> [UUID: Int] {
        guard let data = try? Data(contentsOf: orderCacheURL) else { return [:] }
        return (try? JSONDecoder().decode([UUID: Int].self, from: data)) ?? [:]
    }
    private func loadCache() -> [MapPlace] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONCoding.localDecoder.decode([MapPlace].self, from: data)) ?? []
    }
}
