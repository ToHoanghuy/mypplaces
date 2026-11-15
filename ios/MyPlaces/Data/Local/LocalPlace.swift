import Foundation
import SwiftData

@Model
final class LocalPlace {
    @Attribute(.unique) var id: UUID
    var ownerID: UUID
    var title: String
    var category: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var note: String?
    var visitedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncState: String
    var lastSyncAttempt: Date?
    var syncError: String?
    
    init(
        id: UUID = UUID(),
        ownerID: UUID,
        title: String,
        category: String,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        note: String? = nil,
        visitedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        syncState: String = SyncState.pending.rawValue
    ) {
        self.id = id
        self.ownerID = ownerID
        self.title = title
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.note = note
        self.visitedAt = visitedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncState = syncState
    }
    
    func toDomain() -> Place {
        Place(
            id: id,
            ownerID: ownerID,
            title: title,
            category: PlaceCategory(rawValue: category) ?? .other,
            latitude: latitude,
            longitude: longitude,
            address: address,
            note: note,
            visitedAt: visitedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
    
    static func fromDomain(_ place: Place, syncState: SyncState = .synced) -> LocalPlace {
        LocalPlace(
            id: place.id,
            ownerID: place.ownerID,
            title: place.title,
            category: place.category.rawValue,
            latitude: place.latitude,
            longitude: place.longitude,
            address: place.address,
            note: place.note,
            visitedAt: place.visitedAt,
            createdAt: place.createdAt,
            updatedAt: place.updatedAt,
            deletedAt: place.deletedAt,
            syncState: syncState.rawValue
        )
    }
}

enum SyncState: String, Codable {
    case pending = "PENDING"
    case syncing = "SYNCING"
    case synced = "SYNCED"
    case failedRetryable = "FAILED_RETRYABLE"
    case failedFinal = "FAILED_FINAL"
    case conflict = "CONFLICT"
}
