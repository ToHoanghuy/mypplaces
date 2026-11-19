import Foundation

enum PlaceCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case food = "FOOD"
    case cafe = "CAFE"
    case travel = "TRAVEL"
    case hotel = "HOTEL"
    case shopping = "SHOPPING"
    case entertainment = "ENTERTAINMENT"
    case other = "OTHER"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: return "Ẩm thực"
        case .cafe: return "Cà phê"
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
        case .cafe: return "cup.and.saucer"
        case .travel: return "binoculars"
        case .hotel: return "bed.double"
        case .shopping: return "bag"
        case .entertainment: return "theatermasks"
        case .other: return "mappin"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlaceCategory(rawValue: raw) ?? .other   // unknown category -> OTHER (BRD §8.1)
    }
}

enum MemberRole: String, Codable, Hashable {
    case owner = "OWNER"
    case editor = "EDITOR"
    case viewer = "VIEWER"

    var displayName: String {
        switch self {
        case .owner: return "Chủ sở hữu"
        case .editor: return "Biên tập"
        case .viewer: return "Người xem"
        }
    }
    var canContribute: Bool { self != .viewer }
}

enum MemberStatus: String, Codable { case active = "ACTIVE", removed = "REMOVED", left = "LEFT" }

enum InvitationStatus: String, Codable { case pending = "PENDING", accepted = "ACCEPTED", declined = "DECLINED", revoked = "REVOKED", expired = "EXPIRED" }

enum ResourceType: String, Codable, Hashable {
    case place = "PLACE"
    case visit = "VISIT"
    case journal = "JOURNAL"

    /// "địa điểm" / "lần ghé" / "nhật ký"
    var noun: String {
        switch self {
        case .place: return "địa điểm"
        case .visit: return "lần ghé"
        case .journal: return "nhật ký"
        }
    }
}

enum MemoryType: String, Codable { case note = "NOTE", photo = "PHOTO" }

enum VisitStatus: String, Codable { case visited = "VISITED", wantToVisit = "WANT_TO_VISIT" }
