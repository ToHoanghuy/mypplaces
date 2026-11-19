import Foundation
import Observation

/// Personal map / list read model: `map_places` from the server, cached on disk for offline
/// launch, merged with not-yet-synced outbox writes (optimistic UI).
@MainActor
@Observable
final class PlacesStore {
    static let shared = PlacesStore()

    private(set) var serverPlaces: [MapPlace] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    @ObservationIgnored private let api = MyPlacesAPI.shared
    private var sync: SyncEngine { SyncEngine.shared }

    private init() { serverPlaces = loadCache() }

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
        hasLoaded = false
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: Cache

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("map_places.json")
    }
    private func saveCache() {
        if let data = try? JSONCoding.localEncoder.encode(serverPlaces) { try? data.write(to: cacheURL, options: .atomic) }
    }
    private func loadCache() -> [MapPlace] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONCoding.localDecoder.decode([MapPlace].self, from: data)) ?? []
    }
}
