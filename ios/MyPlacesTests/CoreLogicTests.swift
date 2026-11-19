import XCTest
import CoreLocation
import MapKit
@testable import MyPlaces

final class DateParsingTests: XCTestCase {
    func testParsesPostgrestMicroseconds() throws {
        let d = try XCTUnwrap(DateParsing.parse("2026-10-12T08:30:00.123456+00:00"))
        XCTAssertEqual(d.timeIntervalSince1970, 1791793800.123456, accuracy: 0.001)
    }
    func testParsesShortOffsetAndZ() {
        XCTAssertEqual(DateParsing.parse("2026-10-12T08:30:00+00"), DateParsing.parse("2026-10-12T08:30:00Z"))
        XCTAssertEqual(DateParsing.parse("2026-10-12 15:30:00+07:00"), DateParsing.parse("2026-10-12T08:30:00Z"))
    }
    func testZonelessIsWallClock() throws {
        let c = try XCTUnwrap(DateParsing.localComponents("2026-10-12T15:30:00"))
        XCTAssertEqual(c.hour, 15); XCTAssertEqual(c.minute, 30); XCTAssertEqual(c.day, 12); XCTAssertEqual(c.weekday, 2)
    }
    func testDateOnly() throws {
        let d = try XCTUnwrap(DateParsing.parse("2026-10-01"))
        XCTAssertEqual(DateParsing.day.string(from: d), "2026-10-01")
    }
}

final class FormattingTests: XCTestCase {
    func testWeekdayDay() {
        var c = DateComponents(); c.weekday = 7; c.day = 12; c.month = 10
        XCTAssertEqual(VNFormat.weekdayDay(c), "Thứ Bảy, 12 thg 10")
    }
    func testDateRangeSameMonth() {
        XCTAssertEqual(VNFormat.dateRange(start: "2026-10-01", end: "2026-10-15"), "01 – 15 thg 10, 2026")
    }
    func testDateRangeCrossMonth() {
        XCTAssertEqual(VNFormat.dateRange(start: "2026-11-28", end: "2026-12-02"), "28 thg 11 – 02 thg 12, 2026")
    }
    func testVisitInOwnTimezone() {
        // 2026-10-12 08:30 UTC is 15:30 in Hà Nội and 17:30 in Tokyo (UI decision #6).
        let d = DateParsing.parse("2026-10-12T08:30:00Z")!
        XCTAssertEqual(VNFormat.time(d, tz: TimeZone(identifier: "Asia/Ho_Chi_Minh")!), "15:30")
        XCTAssertEqual(VNFormat.time(d, tz: TimeZone(identifier: "Asia/Tokyo")!), "17:30")
    }
    func testExpiresIn() {
        let now = Date()
        XCTAssertEqual(VNFormat.expiresIn(now.addingTimeInterval(6 * 86400 - 60), now: now), "hết hạn sau 6 ngày")
        XCTAssertEqual(VNFormat.expiresIn(now.addingTimeInterval(-1), now: now), "đã hết hạn")
    }
}

final class DeepLinkTests: XCTestCase {
    func testInviteLink() {
        let token = String(repeating: "ab", count: 32)
        XCTAssertEqual(DeepLink(url: DeepLink.inviteURL(token: token)), .invite(token))
        XCTAssertEqual(DeepLink.parseInvite("  myplaces://invite/\(token) "), token)
        XCTAssertEqual(DeepLink.parseInvite(token), token)
        XCTAssertNil(DeepLink.parseInvite("https://example.com"))
    }
    func testRoutes() {
        let id = UUID()
        XCTAssertEqual(DeepLink(url: URL(string: "myplaces://place/\(id)")!), .place(id))
        XCTAssertEqual(DeepLink(url: URL(string: "myplaces://tab/2")!), .tab(2))
        XCTAssertNil(DeepLink(url: URL(string: "other://place/\(id)")!))
    }
}

final class DecodingTests: XCTestCase {
    func testMapPlaceRow() throws {
        let json = """
        [{"place_id":"8d0c7f53-58a4-4e0b-9c1e-3a8f0b8e2a11","owner_id":"0b6f0f0e-1c1d-4b0a-8a7e-1f2e3d4c5b6a","title":"Cà phê Giảng",
          "category":"CAFE","latitude":21.03,"longitude":105.85,"address":"39 Nguyễn Hữu Huân","updated_at":"2026-11-19T02:00:00.5+00:00",
          "is_owner":true,"my_role":"OWNER","is_shared":false,"visit_count":4,"last_visited_at":"2026-10-12T08:30:00+00:00",
          "visit_status":"VISITED","cover_memory_id":null,"cover_storage_path":null}]
        """.data(using: .utf8)!
        let rows = try JSONCoding.decoder.decode([MapPlace].self, from: json)
        XCTAssertEqual(rows.first?.category, .cafe)
        XCTAssertEqual(rows.first?.visitStatus, .visited)
        XCTAssertEqual(rows.first?.role, .owner)
        XCTAssertEqual(PlaceCopy.visitSummary(rows[0]).hasPrefix("4 lần ghé · gần nhất"), true)
    }
    func testUnknownCategoryFallsBackToOther() throws {
        let c = try JSONCoding.decoder.decode([PlaceCategory].self, from: #"["SPA"]"#.data(using: .utf8)!)
        XCTAssertEqual(c, [.other])
    }
    func testTimelineRowUsesVisitedLocal() throws {
        let json = """
        {"visit_id":"8d0c7f53-58a4-4e0b-9c1e-3a8f0b8e2a11","visited_at":"2026-10-12T08:30:00+00:00","timezone_id":"Asia/Tokyo",
         "visited_local":"2026-10-12T17:30:00","note":null,"owner_id":"0b6f0f0e-1c1d-4b0a-8a7e-1f2e3d4c5b6a","my_role":"VIEWER",
         "place_id":"8d0c7f53-58a4-4e0b-9c1e-3a8f0b8e2a12","place_title":null,"place_category":null,"latitude":null,"longitude":null,
         "place_available":false,"cover_memory_id":null,"cover_storage_path":null}
        """.data(using: .utf8)!
        let item = try JSONCoding.decoder.decode(TimelineItem.self, from: json)
        XCTAssertEqual(VNFormat.time(item.local), "17:30")
        XCTAssertEqual(item.title, "Địa điểm không còn khả dụng")
    }
    func testInsertEncodingIsSnakeCaseWithoutServerColumns() throws {
        let p = PlaceInsert(id: UUID(), title: "A", category: .food, latitude: 1, longitude: 2, address: nil, provider: "apple", providerPlaceId: "X")
        let obj = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(p)) as! [String: Any]
        XCTAssertEqual(obj["provider_place_id"] as? String, "X")
        XCTAssertNil(obj["owner_id"]); XCTAssertNil(obj["created_at"]); XCTAssertNil(obj["address"])
    }
    func testPlaceUpdateSendsExplicitNullAddress() throws {
        let u = PlaceUpdate(title: "A", category: .food, latitude: 1, longitude: 2, address: nil)
        let obj = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(u)) as! [String: Any]
        XCTAssertTrue(obj.keys.contains("address"))
        XCTAssertTrue(obj["address"] is NSNull)
    }
}

final class ClusteringTests: XCTestCase {
    private func place(_ lat: Double, _ lon: Double, photo: String? = nil) -> MapPlace {
        MapPlace(placeId: UUID(), ownerId: UUID(), title: "P", category: .food, latitude: lat, longitude: lon, address: nil, updatedAt: nil,
                 isOwner: true, myRole: nil, isShared: false, visitCount: 0, lastVisitedAt: nil, visitStatus: .wantToVisit,
                 coverMemoryId: nil, coverStoragePath: photo)
    }
    func testNearbyPlacesMergeAndPhotoRepresents() {
        let region = MKCoordinateRegion(center: .init(latitude: 21.03, longitude: 105.85), span: .init(latitudeDelta: 0.04, longitudeDelta: 0.04))
        let a = place(21.0300, 105.8500), b = place(21.0301, 105.8501, photo: "x"), c = place(21.045, 105.865)
        let clusters = MapClustering.clusters([a, b, c], region: region, size: CGSize(width: 390, height: 844))
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.first { $0.count == 2 }?.representative.coverStoragePath, "x")
    }
    func testFitRegion() {
        let r = MapClustering.region(fitting: [.init(latitude: 21, longitude: 105), .init(latitude: 21.1, longitude: 105.2)])!
        XCTAssertEqual(r.center.latitude, 21.05, accuracy: 0.0001)
        XCTAssertGreaterThan(r.span.longitudeDelta, 0.2)
    }
}
