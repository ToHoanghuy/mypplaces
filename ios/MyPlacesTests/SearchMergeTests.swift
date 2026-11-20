import XCTest
import CoreLocation
@testable import MyPlaces

final class SearchMergeTests: XCTestCase {
    private func poi(_ name: String, _ lat: Double, _ lng: Double, cat: PlaceCategory = .food) -> POIResult {
        POIResult(id: UUID(), name: name, category: cat, address: nil, latitude: lat, longitude: lng, confidence: 0.9, distanceM: nil, score: 1)
    }
    private let ocOanh = CLLocationCoordinate2D(latitude: 10.7608, longitude: 106.7033)

    func testNormalizeFoldsVietnamese() {
        XCTAssertEqual(SearchMerge.normalize("  Ốc   Oanh – Vĩnh Khánh! "), "oc oanh vinh khanh")
        XCTAssertEqual(SearchMerge.normalize("Đường Đinh Tiên Hoàng"), "duong dinh tien hoang")
    }

    func testRelevance() {
        XCTAssertTrue(SearchMerge.isRelevant(name: "Ốc Oanh", query: "oc oanh"))
        XCTAssertTrue(SearchMerge.isRelevant(name: "Phở Thìn Lò Đúc", query: "phở thìn"))
        XCTAssertFalse(SearchMerge.isRelevant(name: "Vinh Khanh Street", query: "Ốc Oanh"))
        XCTAssertFalse(SearchMerge.isRelevant(name: "", query: "oc"))
    }

    func testNeedsFallbackBelowThreeRelevant() {
        XCTAssertTrue(SearchMerge.needsFallback(appleNames: [], query: "Ốc Oanh"))
        XCTAssertTrue(SearchMerge.needsFallback(appleNames: ["Ốc Oanh", "Quận 4", "Bến Vân Đồn"], query: "Ốc Oanh"))
        XCTAssertFalse(SearchMerge.needsFallback(appleNames: ["Highlands Coffee", "Highlands Coffee Lý Thái Tổ", "Highlands Coffee Hồ Gươm"], query: "highlands coffee"))
    }

    func testDedupeAgainstAppleWithin50mAndSimilarName() {
        let apple = [(name: "Ốc Oanh", coordinate: ocOanh)]
        let near = poi("Oc Oanh", 10.76090, 106.70335)        // ~12 m, same name → dropped
        let farSame = poi("Ốc Oanh", 10.7700, 106.7033)       // ~1 km → kept (other branch)
        let nearOther = poi("Ốc Đào", 10.76085, 106.70332)    // close but different name → kept
        let out = SearchMerge.dedupe(pois: [near, farSame, nearOther], against: apple)
        XCTAssertEqual(out.map(\.id), [farSame.id, nearOther.id])
    }

    func testDedupeAmongPOIsKeepsOrderAndLimit() {
        let a = poi("Lăng Chủ tịch Hồ Chí Minh", 21.0368, 105.8346, cat: .travel)
        let b = poi("Lang Chu tich Ho Chi Minh", 21.0369, 105.8347, cat: .travel)
        let c = poi("Quảng trường Ba Đình", 21.0373, 105.8363, cat: .travel)
        XCTAssertEqual(SearchMerge.dedupe(pois: [a, b, c], against: []).map(\.id), [a.id, c.id])
        let many = (0..<20).map { poi("Quán \($0)", 21 + Double($0) * 0.01, 105.8) }
        XCTAssertEqual(SearchMerge.dedupe(pois: many, against: [], limit: 8).count, 8)
    }

    func testSimilarNames() {
        XCTAssertTrue(SearchMerge.similarNames("Bún chả Hương Liên", "Bun Cha Huong Lien (Obama)"))
        XCTAssertFalse(SearchMerge.similarNames("Bún chả Hương Liên", "Phở Bát Đàn"))
    }

    func testCacheKeyRoundsLocationAndLRU() {
        let k1 = SearchMerge.cacheKey(query: "Ốc Oanh", center: CLLocationCoordinate2D(latitude: 10.7612, longitude: 106.7031))
        let k2 = SearchMerge.cacheKey(query: "oc  oanh", center: CLLocationCoordinate2D(latitude: 10.7598, longitude: 106.7029))
        XCTAssertEqual(k1, k2)
        let cache = POISearchCache(capacity: 2)
        cache.set("a", [poi("A", 1, 1)]); cache.set("b", []); _ = cache.get("a"); cache.set("c", [])
        XCTAssertNotNil(cache.get("a")); XCTAssertNil(cache.get("b")); XCTAssertNotNil(cache.get("c"))
    }

    func testSeedFromPOIPrefillsForm() {
        var p = poi("Ốc Oanh", 10.7608, 106.7033)
        p.address = "534 Vĩnh Khánh, Quận 4"
        let s = PlaceSeed(poi: p)
        XCTAssertEqual(s.title, "Ốc Oanh"); XCTAssertEqual(s.category, .food)
        XCTAssertEqual(s.address, "534 Vĩnh Khánh, Quận 4")
        XCTAssertEqual(s.provider, "overture"); XCTAssertEqual(s.providerPlaceId, p.id.uuidString.lowercased())
        XCTAssertEqual(s.latitude, 10.7608, accuracy: 1e-9)
    }

    func testDecodesRPCRow() throws {
        let json = #"[{"id":"0b0a2f3e-1c1d-4e5f-8a9b-0c1d2e3f4a5b","name":"Ốc Oanh","category":"FOOD","address":"534 Vĩnh Khánh","latitude":10.76,"longitude":106.70,"confidence":0.95,"distance_m":123.4,"score":0.9}]"#
        let rows = try JSONCoding.decoder.decode([POIResult].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.category, .food); XCTAssertEqual(rows.first?.distanceM ?? 0, 123.4, accuracy: 0.01)
    }
}
