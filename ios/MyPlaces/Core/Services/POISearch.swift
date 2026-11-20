import Foundation
import CoreLocation

/// One row of the `search_pois` RPC (Overture Maps fallback POIs, read-only for signed-in users).
struct POIResult: Decodable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var category: PlaceCategory
    var address: String?
    var latitude: Double
    var longitude: Double
    var confidence: Double?
    var distanceM: Double?
    var score: Double?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Attribution required by the Overture Maps data licences. Shown under fallback results and in Profile.
enum POIAttribution {
    static let text = "Dữ liệu địa điểm: Overture Maps Foundation, © OpenStreetMap contributors"
    static let provider = "overture"
}

/// Pure merge/dedupe rules for "Apple MapKit first, Overture fallback second". Unit-tested.
enum SearchMerge {
    /// Below this many relevant Apple results, the Overture fallback is queried.
    static let minRelevantApple = 3
    /// An Overture POI this close to an Apple result with a similar name is treated as the same place.
    static let dedupeRadius: CLLocationDistance = 50

    /// Lowercase, strip Vietnamese diacritics (incl. đ), collapse punctuation/whitespace.
    static func normalize(_ s: String) -> String {
        let folded = s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "vi_VN"))
            .lowercased()
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func tokens(_ s: String) -> Set<String> { Set(normalize(s).split(separator: " ").map(String.init)) }

    /// An Apple result is relevant when its name contains the query, or shares at least half of the query's words.
    static func isRelevant(name: String, query: String) -> Bool {
        let n = normalize(name), q = normalize(query)
        guard !q.isEmpty, !n.isEmpty else { return false }
        if n.contains(q) || q.contains(n) { return true }
        let qt = tokens(query)
        guard !qt.isEmpty else { return false }
        let hit = qt.intersection(tokens(name)).count
        return Double(hit) / Double(qt.count) >= 0.5
    }

    static func needsFallback(appleNames: [String], query: String) -> Bool {
        appleNames.filter { isRelevant(name: $0, query: query) }.count < minRelevantApple
    }

    /// Two names describe the same place: one contains the other, or word overlap ≥ 2/3 of the shorter name.
    static func similarNames(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb || na.contains(nb) || nb.contains(na) { return true }
        let ta = tokens(a), tb = tokens(b)
        let smaller = min(ta.count, tb.count)
        guard smaller > 0 else { return false }
        return Double(ta.intersection(tb).count) / Double(smaller) >= 0.66
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Drops POIs that duplicate an Apple result (≤ 50 m and similar name) or an earlier POI; keeps RPC order.
    static func dedupe(pois: [POIResult], against apple: [(name: String, coordinate: CLLocationCoordinate2D)], limit: Int = 5) -> [POIResult] {
        var kept: [POIResult] = []
        for p in pois {
            let dupApple = apple.contains { similarNames($0.name, p.name) && distance($0.coordinate, p.coordinate) <= dedupeRadius }
            let dupSelf = kept.contains { similarNames($0.name, p.name) && distance($0.coordinate, p.coordinate) <= dedupeRadius }
            if !dupApple && !dupSelf { kept.append(p) }
            if kept.count >= limit { break }
        }
        return kept
    }

    /// Cache key: normalized query + location rounded to ~1 km so panning slightly reuses results.
    static func cacheKey(query: String, center: CLLocationCoordinate2D?) -> String {
        let q = normalize(query)
        guard let c = center else { return q }
        return "\(q)|\((c.latitude * 100).rounded() / 100)|\((c.longitude * 100).rounded() / 100)"
    }
}

/// Small in-memory LRU of recent fallback queries (per app session).
final class POISearchCache: @unchecked Sendable {
    static let shared = POISearchCache()
    private let capacity: Int
    private var order: [String] = []
    private var store: [String: [POIResult]] = [:]
    private let lock = NSLock()

    init(capacity: Int = 40) { self.capacity = capacity }

    func get(_ key: String) -> [POIResult]? {
        lock.lock(); defer { lock.unlock() }
        guard let v = store[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return v
    }

    func set(_ key: String, _ value: [POIResult]) {
        lock.lock(); defer { lock.unlock() }
        store[key] = value
        order.removeAll { $0 == key }; order.append(key)
        while order.count > capacity { store.removeValue(forKey: order.removeFirst()) }
    }
}
