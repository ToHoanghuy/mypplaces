import Foundation

/// MYP-4 – how the "Địa điểm" list is sorted. Raw values are persisted in UserDefaults.
enum PlaceSort: String, CaseIterable, Identifiable {
    case custom, recent, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .custom: return "Tùy chỉnh"
        case .recent: return "Hoạt động gần nhất"
        case .name: return "Tên"
        }
    }
    var systemImage: String {
        switch self {
        case .custom: return "hand.draw"
        case .recent: return "clock"
        case .name: return "textformat"
        }
    }
}

/// Pure ordering logic (unit tested). `positions` is the viewer's saved order (place id -> index).
enum PlaceOrdering {
    static func activity(_ p: MapPlace) -> Date { p.lastVisitedAt ?? p.updatedAt ?? .distantPast }

    static func byRecent(_ a: MapPlace, _ b: MapPlace) -> Bool {
        let (da, db) = (activity(a), activity(b))
        return da != db ? da > db : a.id.uuidString < b.id.uuidString
    }

    static func sorted(_ places: [MapPlace], by sort: PlaceSort, positions: [UUID: Int]) -> [MapPlace] {
        switch sort {
        case .recent:
            return places.sorted(by: byRecent)
        case .name:
            return places.sorted {
                let r = $0.title.compare($1.title, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN"))
                return r != .orderedSame ? r == .orderedAscending : byRecent($0, $1)
            }
        case .custom:
            // Places without a saved position (new or newly shared) go on top, newest activity first;
            // then the saved order. With no saved order at all this equals "Hoạt động gần nhất".
            let unpositioned = places.filter { positions[$0.id] == nil }.sorted(by: byRecent)
            let positioned = places.filter { positions[$0.id] != nil }.sorted {
                let (pa, pb) = (positions[$0.id]!, positions[$1.id]!)
                return pa != pb ? pa < pb : byRecent($0, $1)
            }
            return unpositioned + positioned
        }
    }

    /// The full id order after a List `.onMove` (same semantics as `Array.move(fromOffsets:toOffset:)`).
    static func moved(_ ids: [UUID], from source: IndexSet, to destination: Int) -> [UUID] {
        var result = ids
        let moving = source.sorted().map { ids[$0] }
        for i in source.sorted(by: >) { result.remove(at: i) }
        let shift = source.filter { $0 < destination }.count
        let insertAt = max(0, min(result.count, destination - shift))
        result.insert(contentsOf: moving, at: insertAt)
        return result
    }

    static func positions(for ids: [UUID]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (i, id) in ids.enumerated() where map[id] == nil { map[id] = i }
        return map
    }

    /// Reordering only makes sense on the complete, unfiltered list in custom mode.
    static func canReorder(sort: PlaceSort, query: String, category: PlaceCategory?, count: Int) -> Bool {
        sort == .custom && query.trimmingCharacters(in: .whitespaces).isEmpty && category == nil && count > 1
    }
}
