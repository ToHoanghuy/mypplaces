import Foundation
import SwiftData

/// Offline-first outbox (BR-HY-01, BRULE-PL-10). Every local write is persisted here first and
/// replayed in order; client-generated UUIDs make every replay idempotent.
@Model
final class OutboxOperation {
    @Attribute(.unique) var id: UUID
    var kind: String
    var resourceID: UUID
    var ownerID: UUID?
    var label: String
    var payload: Data
    var state: String
    var attemptCount: Int
    var errorMessage: String?
    var createdAt: Date
    var lastAttemptAt: Date?

    init(kind: OutboxKind, resourceID: UUID, ownerID: UUID?, label: String, payload: Data) {
        self.id = UUID()
        self.kind = kind.rawValue
        self.resourceID = resourceID
        self.ownerID = ownerID
        self.label = label
        self.payload = payload
        self.state = OutboxState.pending.rawValue
        self.attemptCount = 0
        self.createdAt = Date()
    }
}

enum OutboxKind: String, Codable {
    case placeCreate = "PLACE_CREATE"
    case placeUpdate = "PLACE_UPDATE"
    case placeDelete = "PLACE_DELETE"
    case visitCreate = "VISIT_CREATE"
    case placeOrder = "PLACE_ORDER"
}

enum OutboxState: String, Codable {
    case pending = "PENDING"
    case failed = "FAILED"
}

struct PlaceUpdatePayload: Codable, Hashable { var id: UUID; var update: PlaceUpdate }
struct PlaceDeletePayload: Codable, Hashable { var id: UUID }
/// MYP-4: the viewer's full custom order (index 0 = top). Only the latest one is kept in the outbox.
struct PlaceOrderPayload: Codable, Hashable {
    static let resourceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d4")!
    var ids: [UUID]
}

/// A Visit recorded locally: visit + companions + photos (files kept until uploaded).
struct VisitDraftPayload: Codable, Hashable {
    struct Photo: Codable, Hashable { var id: UUID; var width: Int; var height: Int }
    var visit: VisitInsert
    var participants: [ParticipantInsert]
    var memoryId: UUID
    var photos: [Photo]
}

/// Read-only snapshot for the UI (08c).
struct OutboxItem: Identifiable, Hashable {
    var id: UUID
    var kind: OutboxKind
    var resourceID: UUID
    var label: String
    var state: OutboxState
    var errorMessage: String?
}

enum OutboxFiles {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("outbox-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func url(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).jpg") }
}
