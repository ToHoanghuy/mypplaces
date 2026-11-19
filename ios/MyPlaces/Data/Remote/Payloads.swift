import Foundation

// Write payloads. Server-owned columns (owner_id, author_id, created_by, added_by, timestamps)
// are never sent: they default to auth.uid()/now() and RLS forces them (BRD §33, ERD §6).

struct PlaceInsert: Codable, Hashable {
    var id: UUID
    var title: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var address: String?
    var provider: String?
    var providerPlaceId: String?
}

struct PlaceUpdate: Codable, Hashable {
    var title: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var address: String?

    enum CodingKeys: String, CodingKey { case title, category, latitude, longitude, address }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(category, forKey: .category)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(address, forKey: .address)   // explicit null clears the address
    }
}

struct VisitInsert: Codable, Hashable {
    var id: UUID
    var placeId: UUID
    var visitedAt: Date
    var timezoneId: String
    var note: String?
}

struct ParticipantInsert: Codable, Hashable {
    var id: UUID
    var visitId: UUID
    var userId: UUID?
    var displayNameSnapshot: String?
}

struct MemoryInsert: Codable, Hashable {
    var id: UUID
    var placeId: UUID?
    var visitId: UUID?
    var journalId: UUID?
    var type: MemoryType
    var body: String?
}

struct AttachmentInsert: Codable, Hashable {
    var id: UUID
    var memoryId: UUID
    var storagePath: String
    var mimeType: String
    var sizeBytes: Int
    var width: Int?
    var height: Int?
}

struct JournalInsert: Codable, Hashable {
    var id: UUID
    var title: String
    var description: String?
    var startDate: String?
    var endDate: String?
}

struct JournalPlaceInsert: Codable, Hashable { var journalId: UUID; var placeId: UUID; var sortOrder: Int }
struct JournalVisitInsert: Codable, Hashable { var journalId: UUID; var visitId: UUID; var sortOrder: Int }

/// Parent of a Memory (ERD-05: exactly one).
enum MemoryParent: Hashable {
    case place(UUID), visit(UUID), journal(UUID)

    var resourceType: ResourceType {
        switch self { case .place: return .place; case .visit: return .visit; case .journal: return .journal }
    }
    var id: UUID {
        switch self { case .place(let i), .visit(let i), .journal(let i): return i }
    }
}

/// A photo prepared for upload (already JPEG encoded).
struct PreparedPhoto: Hashable, Identifiable {
    let id: UUID
    var data: Data
    var width: Int
    var height: Int
}
