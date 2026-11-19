import Foundation
import CoreLocation

struct UserProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var avatarPath: String?
    var createdAt: Date?
    var updatedAt: Date?
}

/// Minimal profile embedded through PostgREST resource embedding.
struct ProfileStub: Codable, Hashable {
    var displayName: String
    var avatarPath: String?
}

struct Place: Codable, Identifiable, Hashable {
    let id: UUID
    var ownerId: UUID
    var title: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var address: String?
    var provider: String?
    var providerPlaceId: String?
    var createdAt: Date?
    var updatedAt: Date?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// Row of the `map_places` read model (security_invoker view).
struct MapPlace: Codable, Identifiable, Hashable {
    let placeId: UUID
    var ownerId: UUID
    var title: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var address: String?
    var updatedAt: Date?
    var isOwner: Bool
    var myRole: MemberRole?
    var isShared: Bool
    var visitCount: Int
    var lastVisitedAt: Date?
    var visitStatus: VisitStatus
    var coverMemoryId: UUID?
    var coverStoragePath: String?

    var id: UUID { placeId }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var role: MemberRole { isOwner ? .owner : (myRole ?? .viewer) }
}

struct Visit: Codable, Identifiable, Hashable {
    let id: UUID
    var placeId: UUID
    var ownerId: UUID
    var visitedAt: Date
    var timezoneId: String
    var note: String?
    var createdAt: Date?
}

struct VisitParticipant: Codable, Identifiable, Hashable {
    let id: UUID
    var visitId: UUID
    var userId: UUID?
    var displayNameSnapshot: String?
    var profile: ProfileStub?

    var name: String { profile?.displayName ?? displayNameSnapshot ?? "Khách" }
}

struct MemoryAttachment: Codable, Identifiable, Hashable {
    let id: UUID
    var memoryId: UUID
    var storagePath: String
    var mimeType: String
    var sizeBytes: Int
    var width: Int?
    var height: Int?
    var createdAt: Date?
}

struct Memory: Codable, Identifiable, Hashable {
    let id: UUID
    var authorId: UUID
    var placeId: UUID?
    var visitId: UUID?
    var journalId: UUID?
    var type: MemoryType
    var body: String?
    var createdAt: Date
    var author: ProfileStub?
    var memoryAttachments: [MemoryAttachment]?

    var attachments: [MemoryAttachment] { (memoryAttachments ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) } }
}

/// Row of `rpc/my_timeline`.
struct TimelineItem: Codable, Identifiable, Hashable {
    let visitId: UUID
    var visitedAt: Date
    var timezoneId: String
    var visitedLocal: String
    var note: String?
    var ownerId: UUID
    var myRole: MemberRole
    var placeId: UUID
    var placeTitle: String?
    var placeCategory: PlaceCategory?
    var latitude: Double?
    var longitude: Double?
    var placeAvailable: Bool
    var coverMemoryId: UUID?
    var coverStoragePath: String?

    var id: UUID { visitId }
    /// Wall-clock components in the Visit's own timezone (BRD §34.5, UI decision #6).
    var local: DateComponents {
        DateParsing.localComponents(visitedLocal)
            ?? VNFormat.calendar(VNFormat.tz(timezoneId)).dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: visitedAt)
    }
    var title: String { placeTitle ?? "Địa điểm không còn khả dụng" }
}

struct CompanionSuggestion: Codable, Identifiable, Hashable {
    let userId: UUID
    var displayName: String
    var avatarPath: String?
    var lastSharedAt: Date?
    var id: UUID { userId }
}

struct Journal: Codable, Identifiable, Hashable {
    let id: UUID
    var ownerId: UUID
    var title: String
    var description: String?
    var coverPath: String?
    var startDate: String?
    var endDate: String?
    var createdAt: Date?
    var updatedAt: Date?
    var archivedAt: Date?

    var isArchived: Bool { archivedAt != nil }
    var dateRange: String? { VNFormat.dateRange(start: startDate, end: endDate) }
}

struct JournalPlaceItem: Codable, Identifiable, Hashable {
    let journalPlaceId: UUID
    var journalId: UUID
    var placeId: UUID
    var title: String
    var category: PlaceCategory
    var latitude: Double
    var longitude: Double
    var sortOrder: Int
    var addedBy: UUID
    var linkedAt: Date
    var id: UUID { journalPlaceId }
}

struct JournalVisitItem: Codable, Identifiable, Hashable {
    let journalVisitId: UUID
    var journalId: UUID
    var visitId: UUID
    var visitedAt: Date
    var timezoneId: String
    var placeId: UUID
    var placeTitle: String
    var placeCategory: PlaceCategory
    var latitude: Double
    var longitude: Double
    var sortOrder: Int
    var addedBy: UUID
    var linkedAt: Date
    var id: UUID { journalVisitId }
}

/// Membership row (place_members / visit_members / journal_members) + embedded profile.
struct MemberRow: Codable, Identifiable, Hashable {
    let id: UUID
    var userId: UUID
    var role: MemberRole
    var status: MemberStatus
    var joinedAt: Date
    var profile: ProfileStub?
}

struct InvitationRow: Codable, Identifiable, Hashable {
    let id: UUID
    var role: MemberRole
    var status: InvitationStatus
    var inviteeUserId: UUID?
    var inviteeEmailNormalized: String?
    var expiresAt: Date
    var createdAt: Date
}

struct CreatedInvitation: Codable, Hashable {
    var invitationId: UUID
    var token: String
    var expiresAt: Date
    var link: URL { DeepLink.inviteURL(token: token) }
}

struct InvitationPreview: Codable, Hashable {
    var invitationId: UUID
    var resourceType: ResourceType
    var resourceId: UUID
    var resourceTitle: String?
    var resourceVisitedAt: Date?
    var resourceCoverPath: String?
    var inviterDisplayName: String?
    var role: MemberRole
    var expiresAt: Date
    var emailBound: Bool
}

struct AcceptedInvitation: Codable, Hashable {
    var resourceType: ResourceType
    var resourceId: UUID
    var role: MemberRole
}

/// A shareable resource reference used by sharing screens.
struct ShareTarget: Identifiable, Hashable {
    var type: ResourceType
    var id: UUID
    var title: String
    var coverPath: String?
    var category: PlaceCategory?
}
