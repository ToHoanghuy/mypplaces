import Foundation

struct Place: Identifiable, Codable, Hashable {
    let id: UUID
    let ownerID: UUID
    var title: String
    var category: PlaceCategory
    let latitude: Double
    let longitude: Double
    var address: String?
    var note: String?
    var visitedAt: Date?
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    
    var isDeleted: Bool {
        deletedAt != nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case category
        case latitude
        case longitude
        case address
        case note
        case visitedAt = "visited_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
    
    init(
        id: UUID = UUID(),
        ownerID: UUID,
        title: String,
        category: PlaceCategory,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        note: String? = nil,
        visitedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
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
    }
}

enum PlaceCategory: String, Codable, CaseIterable {
    case food = "FOOD"
    case cafe = "CAFE"
    case travel = "TRAVEL"
    case hotel = "HOTEL"
    case shopping = "SHOPPING"
    case entertainment = "ENTERTAINMENT"
    case other = "OTHER"
    
    var displayName: String {
        switch self {
        case .food: return "Ăn uống"
        case .cafe: return "Café"
        case .travel: return "Du lịch"
        case .hotel: return "Khách sạn"
        case .shopping: return "Mua sắm"
        case .entertainment: return "Giải trí"
        case .other: return "Khác"
        }
    }
    
    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .travel: return "airplane"
        case .hotel: return "bed.double.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "theatermasks.fill"
        case .other: return "mappin.circle.fill"
        }
    }
}
