import Foundation

struct UserProfile: Identifiable, Codable {
    let id: UUID
    var displayName: String
    var avatarPath: String?
    let createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
