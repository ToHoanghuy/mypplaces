import XCTest
@testable import MyPlaces

/// MYP-4 – custom order of the "Địa điểm" list.
final class PlaceOrderingTests: XCTestCase {
    private func place(_ title: String, daysAgo: Double?) -> MapPlace {
        MapPlace(placeId: UUID(), ownerId: UUID(), title: title, category: .food, latitude: 21, longitude: 105, address: nil,
                 updatedAt: Date(timeIntervalSince1970: 1_000_000), isOwner: true, myRole: nil, isShared: false, visitCount: 0,
                 lastVisitedAt: daysAgo.map { Date(timeIntervalSince1970: 2_000_000_000 - $0 * 86_400) },
                 visitStatus: .wantToVisit, coverMemoryId: nil, coverStoragePath: nil)
    }

    func testRecentSortsByLastActivity() {
        let a = place("A", daysAgo: 5), b = place("B", daysAgo: 1), c = place("C", daysAgo: nil)
        XCTAssertEqual(PlaceOrdering.sorted([a, b, c], by: .recent, positions: [:]).map(\.title), ["B", "A", "C"])
    }

    func testNameSortIsVietnameseAndCaseInsensitive() {
        let list = [place("Đền Ngọc Sơn", daysAgo: 1), place("bún chả", daysAgo: 2), place("Ăn vặt", daysAgo: 3), place("Cà phê", daysAgo: 4)]
        XCTAssertEqual(PlaceOrdering.sorted(list, by: .name, positions: [:]).map(\.title), ["Ăn vặt", "bún chả", "Cà phê", "Đền Ngọc Sơn"])
    }

    func testCustomWithoutSavedOrderEqualsRecent() {
        let list = [place("A", daysAgo: 5), place("B", daysAgo: 1), place("C", daysAgo: 3)]
        XCTAssertEqual(PlaceOrdering.sorted(list, by: .custom, positions: [:]).map(\.title),
                       PlaceOrdering.sorted(list, by: .recent, positions: [:]).map(\.title))
    }

    func testCustomFollowsPositionsAndNewPlacesGoOnTop() {
        let a = place("A", daysAgo: 5), b = place("B", daysAgo: 1), c = place("C", daysAgo: 3), new = place("Mới", daysAgo: nil)
        let positions = [c.id: 0, a.id: 1, b.id: 2]
        XCTAssertEqual(PlaceOrdering.sorted([a, b, c, new], by: .custom, positions: positions).map(\.title), ["Mới", "C", "A", "B"])
    }

    func testCustomIgnoresPositionsOfPlacesNoLongerVisible() {
        let a = place("A", daysAgo: 1), b = place("B", daysAgo: 2)
        let positions = [UUID(): 0, b.id: 1, a.id: 2]
        XCTAssertEqual(PlaceOrdering.sorted([a, b], by: .custom, positions: positions).map(\.title), ["B", "A"])
    }

    func testMovedMatchesArrayMoveSemantics() {
        let ids = (0..<5).map { _ in UUID() }
        for from in 0..<5 {
            for to in 0...5 {
                var expected = ids
                expected.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                XCTAssertEqual(PlaceOrdering.moved(ids, from: IndexSet(integer: from), to: to), expected, "from \(from) to \(to)")
            }
        }
        var expected = ids
        expected.move(fromOffsets: IndexSet([0, 2]), toOffset: 5)
        XCTAssertEqual(PlaceOrdering.moved(ids, from: IndexSet([0, 2]), to: 5), expected)
    }

    func testPositionsAreDenseAndKeepFirstDuplicate() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(PlaceOrdering.positions(for: [b, a, b]), [b: 0, a: 1])
    }

    func testReorderOnlyInCustomUnfilteredList() {
        XCTAssertTrue(PlaceOrdering.canReorder(sort: .custom, query: "", category: nil, count: 3))
        XCTAssertTrue(PlaceOrdering.canReorder(sort: .custom, query: "  ", category: nil, count: 3))
        XCTAssertFalse(PlaceOrdering.canReorder(sort: .custom, query: "phở", category: nil, count: 3))
        XCTAssertFalse(PlaceOrdering.canReorder(sort: .custom, query: "", category: .food, count: 3))
        XCTAssertFalse(PlaceOrdering.canReorder(sort: .recent, query: "", category: nil, count: 3))
        XCTAssertFalse(PlaceOrdering.canReorder(sort: .name, query: "", category: nil, count: 3))
        XCTAssertFalse(PlaceOrdering.canReorder(sort: .custom, query: "", category: nil, count: 1))
    }

    func testSortRawValuesAreStable() {
        XCTAssertEqual(PlaceSort.allCases.map(\.rawValue), ["custom", "recent", "name"])
        XCTAssertEqual(PlaceSort.allCases.map(\.title), ["Tùy chỉnh", "Hoạt động gần nhất", "Tên"])
    }
}
