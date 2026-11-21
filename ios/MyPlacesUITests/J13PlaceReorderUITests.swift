import XCTest

/// MYP-4 – long-press + drag to reorder the "Địa điểm" list (custom sort), persisted per viewer.
/// Leaves the list in its original order (drags back at the end).
final class J13PlaceReorderUITests: MPUITestCase {
    private func rows() -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place.row.'")).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 0 }
            .sorted { $0.frame.minY < $1.frame.minY }
    }
    private func order() -> [String] { rows().map(\.identifier) }

    private func openList() {
        goTab(1)
        wait(el("places.sort"))
        _ = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place.row.'")).firstMatch.waitForExistence(timeout: 15)
        sleep(1)
    }

    private func choose(_ title: String) {
        tap("places.sort")
        let item = app.buttons[title].firstMatch
        wait(item, 5); press(item)
        sleep(1)
    }

    /// Long-press `row`, drag it onto `target` (lands just past it), hold, release.
    private func drag(_ row: XCUIElement, to target: XCUIElement, below: Bool) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.85 : 0.1))
        start.press(forDuration: 1.0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(2)
    }

    func test01DragReorderPersists() throws {
        launch(signedInAs: emailA)
        waitSignedIn()
        openList()
        choose("Tùy chỉnh")
        let before = order()
        guard before.count >= 3 else { throw XCTSkip("Need at least 3 places, have \(before.count)") }
        shot("reorder/01_before")

        let r = rows()
        drag(r[0], to: r[1], below: true)
        let after = order()
        shot("reorder/02_after_drag")
        XCTAssertEqual(Set(after.prefix(before.count)), Set(before.prefix(after.count)), "drag must not drop rows")
        let oldIndex = try XCTUnwrap(after.firstIndex(of: before[0]))
        XCTAssertGreaterThan(oldIndex, 0, "first row should have moved down: \(before) -> \(after)")
        XCTAssertEqual(after.first, before[1], "second row should now be first")

        // Persists across relaunch (outbox -> set_place_order -> place_user_order).
        sleep(2)
        app.terminate()
        launch(signedInAs: emailA)
        waitSignedIn()
        openList()
        XCTAssertEqual(Array(order().prefix(3)), Array(after.prefix(3)), "custom order survives relaunch")

        // Other sorts don't use the custom order; filtering disables dragging and explains why.
        choose("Tên")
        shot("reorder/03_sort_name")
        choose("Tùy chỉnh")
        let chip = app.buttons.matching(NSPredicate(format: "label == %@", "Ẩm thực")).firstMatch
        if chip.waitForExistence(timeout: 5) {
            press(chip)
            sleep(1)
            XCTAssertTrue(app.staticTexts["Bỏ tìm kiếm và bộ lọc để sắp xếp lại"].exists || el("places.reorderHint").exists)
            shot("reorder/04_filtered_hint")
            press(chip)
            sleep(1)
        }

        // Restore: drag the original first row back to the top.
        let now = rows()
        guard let moved = now.first(where: { $0.identifier == before[0] }), let top = now.first else { return XCTFail("rows vanished") }
        drag(moved, to: top, below: false)
        XCTAssertEqual(order().first, before[0], "restored original first row")
    }
}
