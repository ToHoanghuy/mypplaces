import Foundation

struct Journal: Identifiable, Codable {
    let id: UUID
    let ownerID: UUID
    var title: String
    var description: String?
    var coverPath: String?
    var startDate: Date?
    var endDate: Date?
    var visibility: Visibility
    var status: Status
    let createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var deletedAt: Date?
    
    var isArchived: Bool {
        archivedAt != nil
    }
    
    var isDeleted: Bool {
        deletedAt != nil
    }
    
    enum Visibility: String, Codable {
        case `private` = "PRIVATE"
        case linkReadOnly = "LINK_READ_ONLY"
    }
    
    enum Status: String, Codable {
        case active = "ACTIVE"
        case archived = "ARCHIVED"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case description
        case coverPath = "cover_path"
        case startDate = "start_date"
        case endDate = "end_date"
        case visibility
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
        case deletedAt = "deleted_at"
    }
}
