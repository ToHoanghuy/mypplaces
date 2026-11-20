import Foundation
import Supabase
import CoreLocation

/// Thin, typed wrapper over the live Supabase API (tables under RLS, projection RPCs,
/// sharing RPCs and the private `memory-media` bucket). No business rule is re-implemented
/// here: the server is the source of truth.
final class MyPlacesAPI: @unchecked Sendable {
    static let shared = MyPlacesAPI()
    static let mediaBucket = "memory-media"

    private var client: SupabaseClient { SupabaseService.shared.client }
    var userID: UUID? { client.auth.currentUser?.id }

    // MARK: Profiles

    func profile(_ id: UUID) async throws -> UserProfile {
        try await client.from("profiles").select().eq("id", value: id).single().execute().value
    }

    func profiles(_ ids: [UUID]) async throws -> [UserProfile] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("profiles").select().in("id", values: ids.map(\.uuidString)).execute().value
    }

    func updateDisplayName(_ name: String) async throws {
        guard let uid = userID else { return }
        try await client.from("profiles").update(["display_name": name]).eq("id", value: uid).execute()
    }

    // MARK: Places

    func mapPlaces() async throws -> [MapPlace] {
        try await client.from("map_places").select().order("title").execute().value
    }

    func mapPlace(_ id: UUID) async throws -> MapPlace? {
        let rows: [MapPlace] = try await client.from("map_places").select().eq("place_id", value: id).limit(1).execute().value
        return rows.first
    }

    func place(_ id: UUID) async throws -> Place? {
        let rows: [Place] = try await client.from("places").select().eq("id", value: id).is("deleted_at", value: nil).limit(1).execute().value
        return rows.first
    }

    func insertPlace(_ p: PlaceInsert) async throws {
        try await client.from("places").insert(p, returning: .minimal).execute()
    }

    func updatePlace(_ id: UUID, _ u: PlaceUpdate) async throws {
        try await client.from("places").update(u, returning: .minimal).eq("id", value: id).execute()
    }

    /// Soft delete (BRULE-PL-09). deleted_at is a server timestamp in spirit; the trigger audits it.
    func softDeletePlace(_ id: UUID) async throws {
        try await client.from("places").update(["deleted_at": DateParsing.isoString(Date())], returning: .minimal)
            .eq("id", value: id).execute()
    }

    /// Counts shown in the delete confirmation (03e).
    func placeUsage(_ id: UUID) async throws -> (visits: Int, journals: Int) {
        let v = try await client.from("visits").select("id", head: true, count: .exact)
            .eq("place_id", value: id).is("deleted_at", value: nil).execute().count ?? 0
        let j = try await client.from("journal_places").select("id", head: true, count: .exact)
            .eq("place_id", value: id).execute().count ?? 0
        return (v, j)
    }

    struct JournalLink: Codable, Hashable { var journalId: UUID; var journals: JournalTitle? }
    struct JournalTitle: Codable, Hashable { var title: String; var coverPath: String?; var deletedAt: Date? }

    func journalsContaining(place id: UUID) async throws -> [JournalLink] {
        try await client.from("journal_places").select("journal_id, journals(title, cover_path, deleted_at)")
            .eq("place_id", value: id).execute().value
    }

    // MARK: Visits

    func visits(place id: UUID) async throws -> [Visit] {
        try await client.from("visits").select().eq("place_id", value: id).is("deleted_at", value: nil)
            .order("visited_at", ascending: false).execute().value
    }

    func insertVisit(_ v: VisitInsert) async throws {
        try await client.from("visits").insert(v, returning: .minimal).execute()
    }

    func softDeleteVisit(_ id: UUID) async throws {
        try await client.from("visits").update(["deleted_at": DateParsing.isoString(Date())], returning: .minimal)
            .eq("id", value: id).execute()
    }

    func participants(visit id: UUID) async throws -> [VisitParticipant] {
        try await client.from("visit_participants")
            .select("id, visit_id, user_id, display_name_snapshot, profile:profiles!visit_participants_user_id_fkey(display_name, avatar_path)")
            .eq("visit_id", value: id).order("created_at").execute().value
    }

    func participants(visits ids: [UUID]) async throws -> [VisitParticipant] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("visit_participants")
            .select("id, visit_id, user_id, display_name_snapshot, profile:profiles!visit_participants_user_id_fkey(display_name, avatar_path)")
            .in("visit_id", values: ids.map(\.uuidString)).order("created_at").execute().value
    }

    func insertParticipants(_ rows: [ParticipantInsert]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from("visit_participants").insert(rows, returning: .minimal).execute()
    }

    func companionSuggestions(query: String? = nil, limit: Int = 30) async throws -> [CompanionSuggestion] {
        struct P: Encodable { var pQuery: String?; var pLimit: Int }
        return try await client.rpc("list_companion_suggestions", params: P(pQuery: query, pLimit: limit)).execute().value
    }

    /// Overture fallback POIs (`search_pois`; server clamps q to 100 chars and limit to 1…20).
    func searchPOIs(query: String, near center: CLLocationCoordinate2D?, limit: Int = 10) async throws -> [POIResult] {
        struct P: Encodable { var q: String; var lat: Double?; var lng: Double?; var maxResults: Int }
        return try await client.rpc("search_pois", params: P(q: query, lat: center?.latitude, lng: center?.longitude, maxResults: limit)).execute().value
    }

    struct TimelineParams: Encodable {
        var pFrom: Date?
        var pTo: Date?
        var pCategory: PlaceCategory?
        var pVisitId: UUID?
        var pLimit: Int = 100
        func encode(to encoder: Encoder) throws {
            enum K: String, CodingKey { case pFrom = "p_from", pTo = "p_to", pCategory = "p_category", pVisitId = "p_visit_id", pLimit = "p_limit" }
            var c = encoder.container(keyedBy: K.self)
            try c.encode(pFrom.map(DateParsing.isoString), forKey: .pFrom)
            try c.encode(pTo.map(DateParsing.isoString), forKey: .pTo)
            try c.encode(pCategory, forKey: .pCategory)
            try c.encode(pVisitId, forKey: .pVisitId)
            try c.encode(pLimit, forKey: .pLimit)
        }
    }

    func timeline(_ p: TimelineParams) async throws -> [TimelineItem] {
        try await client.rpc("my_timeline", params: p).execute().value
    }

    func timelineItem(visit id: UUID) async throws -> TimelineItem? {
        try await timeline(.init(pVisitId: id, pLimit: 1)).first
    }

    // MARK: Memories

    private static let memorySelect = "id, author_id, place_id, visit_id, journal_id, type, body, created_at, author:profiles!memories_author_id_fkey(display_name, avatar_path), memory_attachments(*)"

    func memories(_ parent: MemoryParent) async throws -> [Memory] {
        let column: String
        switch parent { case .place: column = "place_id"; case .visit: column = "visit_id"; case .journal: column = "journal_id" }
        return try await client.from("memories").select(Self.memorySelect)
            .eq(column, value: parent.id).is("deleted_at", value: nil)
            .order("created_at", ascending: false).execute().value
    }

    func memories(visits ids: [UUID]) async throws -> [Memory] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("memories").select(Self.memorySelect)
            .in("visit_id", values: ids.map(\.uuidString)).is("deleted_at", value: nil)
            .order("created_at", ascending: false).execute().value
    }

    func softDeleteMemory(_ id: UUID) async throws {
        try await client.from("memories").update(["deleted_at": DateParsing.isoString(Date())], returning: .minimal)
            .eq("id", value: id).execute()
    }

    func insertMemory(_ m: MemoryInsert) async throws {
        try await client.from("memories").insert(m, returning: .minimal).execute()
    }

    /// Storage flow (migration 08): memory row -> object upload -> attachment row (finalize).
    @discardableResult
    func uploadAttachment(memoryId: UUID, photo: PreparedPhoto) async throws -> String {
        guard let uid = userID else { throw URLError(.userAuthenticationRequired) }
        let path = "\(uid.uuidString.lowercased())/\(memoryId.uuidString.lowercased())/\(photo.id.uuidString.lowercased()).jpg"
        do {
            try await client.storage.from(Self.mediaBucket).upload(path, data: photo.data,
                options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg", upsert: false))
        } catch {
            if !AppError.isDuplicate(error) { throw error }   // idempotent retry
        }
        do {
            try await client.from("memory_attachments").insert(AttachmentInsert(
                id: photo.id, memoryId: memoryId, storagePath: path, mimeType: "image/jpeg",
                sizeBytes: photo.data.count, width: photo.width, height: photo.height), returning: .minimal).execute()
        } catch {
            if !AppError.isDuplicate(error) { throw error }
        }
        await ImageStore.shared.seed(path: path, data: photo.data)
        return path
    }

    /// Creates a memory with optional photos (PHOTO if any photo, else NOTE).
    func createMemory(parent: MemoryParent, body: String?, photos: [PreparedPhoto], memoryId: UUID = UUID()) async throws {
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (trimmed?.isEmpty ?? true) ? nil : trimmed
        var insert = MemoryInsert(id: memoryId, type: photos.isEmpty ? .note : .photo, body: text)
        switch parent {
        case .place(let id): insert.placeId = id
        case .visit(let id): insert.visitId = id
        case .journal(let id): insert.journalId = id
        }
        do { try await insertMemory(insert) } catch { if !AppError.isDuplicate(error) { throw error } }
        for p in photos { try await uploadAttachment(memoryId: memoryId, photo: p) }
    }

    func signedURL(path: String, expiresIn: Int = 3600) async throws -> URL {
        try await client.storage.from(Self.mediaBucket).createSignedURL(path: path, expiresIn: expiresIn)
    }

    // MARK: Journals

    func journals() async throws -> [Journal] {
        try await client.from("journals").select().is("deleted_at", value: nil)
            .order("created_at", ascending: false).execute().value
    }

    func journal(_ id: UUID) async throws -> Journal? {
        let rows: [Journal] = try await client.from("journals").select().eq("id", value: id).is("deleted_at", value: nil).limit(1).execute().value
        return rows.first
    }

    func insertJournal(_ j: JournalInsert) async throws {
        try await client.from("journals").insert(j, returning: .minimal).execute()
    }

    func setJournalCover(_ id: UUID, path: String?) async throws {
        struct U: Encodable { var coverPath: String?
            func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: K.self); try c.encode(coverPath, forKey: .coverPath) }
            enum K: String, CodingKey { case coverPath = "cover_path" } }
        try await client.from("journals").update(U(coverPath: path), returning: .minimal).eq("id", value: id).execute()
    }

    func setJournalArchived(_ id: UUID, archived: Bool) async throws {
        struct U: Encodable { var archivedAt: String?
            func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: K.self); try c.encode(archivedAt, forKey: .archivedAt) }
            enum K: String, CodingKey { case archivedAt = "archived_at" } }
        try await client.from("journals").update(U(archivedAt: archived ? DateParsing.isoString(Date()) : nil), returning: .minimal)
            .eq("id", value: id).execute()
    }

    func softDeleteJournal(_ id: UUID) async throws {
        try await client.from("journals").update(["deleted_at": DateParsing.isoString(Date())], returning: .minimal).eq("id", value: id).execute()
    }

    func journalPlaces(_ id: UUID) async throws -> [JournalPlaceItem] {
        try await client.rpc("journal_places_projection", params: ["p_journal_id": id]).execute().value
    }

    func journalVisits(_ id: UUID) async throws -> [JournalVisitItem] {
        try await client.rpc("journal_visits_projection", params: ["p_journal_id": id]).execute().value
    }

    func linkPlaces(_ rows: [JournalPlaceInsert]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from("journal_places").insert(rows, returning: .minimal).execute()
    }

    func linkVisits(_ rows: [JournalVisitInsert]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from("journal_visits").insert(rows, returning: .minimal).execute()
    }

    struct MemberCount: Codable { var journalId: UUID; var userId: UUID; var role: MemberRole; var status: MemberStatus }

    /// All ACTIVE journal memberships visible to the caller (for list badges / counts).
    func journalMemberships() async throws -> [MemberCount] {
        try await client.from("journal_members").select("journal_id, user_id, role, status").eq("status", value: "ACTIVE").execute().value
    }

    // MARK: Sharing

    private func memberTable(_ t: ResourceType) -> (table: String, fk: String) {
        switch t {
        case .place: return ("place_members", "place_id")
        case .visit: return ("visit_members", "visit_id")
        case .journal: return ("journal_members", "journal_id")
        }
    }

    func members(_ type: ResourceType, _ id: UUID) async throws -> [MemberRow] {
        let m = memberTable(type)
        return try await client.from(m.table)
            .select("id, user_id, role, status, joined_at, profile:profiles!\(m.table)_user_id_fkey(display_name, avatar_path)")
            .eq(m.fk, value: id).eq("status", value: "ACTIVE").order("joined_at").execute().value
    }

    func myMembership(_ type: ResourceType, _ id: UUID) async throws -> MemberRow? {
        guard let uid = userID else { return nil }
        let m = memberTable(type)
        let rows: [MemberRow] = try await client.from(m.table)
            .select("id, user_id, role, status, joined_at")
            .eq(m.fk, value: id).eq("user_id", value: uid).eq("status", value: "ACTIVE").limit(1).execute().value
        return rows.first
    }

    func createInvitation(_ type: ResourceType, _ id: UUID, role: MemberRole, email: String?, ttlDays: Int) async throws -> CreatedInvitation {
        struct P: Encodable {
            var pResourceType: ResourceType; var pResourceId: UUID; var pRole: MemberRole
            var pInviteeEmail: String?; var pTtl: String
        }
        let mail = email?.trimmingCharacters(in: .whitespaces)
        let rows: [CreatedInvitation] = try await client.rpc("create_invitation", params: P(
            pResourceType: type, pResourceId: id, pRole: role,
            pInviteeEmail: (mail?.isEmpty ?? true) ? nil : mail, pTtl: "\(ttlDays) days")).execute().value
        guard let first = rows.first else { throw URLError(.badServerResponse) }
        return first
    }

    func listInvitations(_ type: ResourceType, _ id: UUID) async throws -> [InvitationRow] {
        try await client.rpc("list_invitations", params: ListP(pResourceType: type, pResourceId: id)).execute().value
    }
    private struct ListP: Encodable { var pResourceType: ResourceType; var pResourceId: UUID }

    func resolveInvitation(token: String) async throws -> InvitationPreview {
        let rows: [InvitationPreview] = try await client.rpc("resolve_invitation", params: ["p_token": token]).execute().value
        guard let first = rows.first else { throw PostgrestError(code: "PT404", message: "INVITATION_NOT_FOUND") }
        return first
    }

    func acceptInvitation(token: String) async throws -> AcceptedInvitation {
        let rows: [AcceptedInvitation] = try await client.rpc("accept_invitation", params: ["p_token": token]).execute().value
        guard let first = rows.first else { throw URLError(.badServerResponse) }
        return first
    }

    func declineInvitation(token: String) async throws {
        try await client.rpc("decline_invitation", params: ["p_token": token]).execute()
    }

    func revokeInvitation(_ id: UUID) async throws {
        try await client.rpc("revoke_invitation", params: ["p_invitation_id": id]).execute()
    }

    func changeRole(_ type: ResourceType, _ id: UUID, user: UUID, role: MemberRole) async throws {
        struct P: Encodable { var pResourceType: ResourceType; var pResourceId: UUID; var pUserId: UUID; var pRole: MemberRole }
        try await client.rpc("change_member_role", params: P(pResourceType: type, pResourceId: id, pUserId: user, pRole: role)).execute()
    }

    func removeMember(_ type: ResourceType, _ id: UUID, user: UUID) async throws {
        struct P: Encodable { var pResourceType: ResourceType; var pResourceId: UUID; var pUserId: UUID }
        try await client.rpc("remove_member", params: P(pResourceType: type, pResourceId: id, pUserId: user)).execute()
    }

    func leave(_ type: ResourceType, _ id: UUID) async throws {
        try await client.rpc("leave_resource", params: ListP(pResourceType: type, pResourceId: id)).execute()
    }

    func unshare(_ type: ResourceType, _ id: UUID) async throws {
        try await client.rpc("unshare_resource", params: ListP(pResourceType: type, pResourceId: id)).execute()
    }

    func transferOwnership(_ type: ResourceType, _ id: UUID, to user: UUID) async throws {
        struct P: Encodable { var pResourceType: ResourceType; var pResourceId: UUID; var pNewOwnerId: UUID; var pPreviousOwnerRole: MemberRole }
        try await client.rpc("transfer_ownership", params: P(pResourceType: type, pResourceId: id, pNewOwnerId: user, pPreviousOwnerRole: .editor)).execute()
    }
}
