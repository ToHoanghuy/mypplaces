import XCTest

/// Extra feature: Overture POI fallback when Apple MapKit misses a place ("Ốc Oanh Vĩnh Khánh").
/// Hits the live `search_pois` RPC, so it needs the QA account and network.
final class H10SearchFallbackUITests: MPUITestCase {
    func test01FallbackLight() { run(mode: "light") }
    func test02FallbackDark() { run(mode: "dark") }

    private func run(mode: String) {
        launch(signedInAs: emailA, args: ["-appearance.mode", mode])
        waitSignedIn()
        tap("map.search")
        type("search.field", "Ốc Oanh Vĩnh Khánh")
        let poi = el("search.poi")
        wait(poi, 30)
        XCTAssertTrue(poi.label.contains("Ốc Oanh") || app.staticTexts["Ốc Oanh"].exists, "fallback row should be Ốc Oanh, got \(poi.label)")
        XCTAssertTrue(text("GỢI Ý THÊM").exists)
        XCTAssertTrue(el("search.attribution").waitForExistence(timeout: 5))
        // Drag the list a little: dismisses the keyboard (scrollDismissesKeyboard) without scrolling far.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)))
        sleep(1)
        shot("search/\(mode)_01_fallback_results")
        press(poi)
        let title = field("addplace.title")
        wait(title, 15)
        XCTAssertTrue((title.value as? String ?? "").contains("Ốc Oanh"), "title prefilled, got \(String(describing: title.value))")
        XCTAssertTrue(text("Ẩm thực").exists || app.buttons["Ẩm thực"].exists)
        shot("search/\(mode)_02_prefilled_form")
        app.buttons["Hủy"].firstMatch.tap()
        // Attribution in Profile › Giới thiệu.
        goTab(4)
        let about = el("about.attribution")
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        shot("search/\(mode)_03_profile_about")
    }
}
