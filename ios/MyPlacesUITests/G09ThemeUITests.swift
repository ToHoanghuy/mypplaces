import XCTest

/// Extra feature: light/dark appearance (Cá nhân › Giao diện) + screenshots of key screens in both themes.
final class G09ThemeUITests: MPUITestCase {
    private func openProfileAppearance() {
        goTab(4)
        wait(el("appearance.auto"), 20)
        let e = el("appearance.auto")
        for _ in 0..<4 where !e.isHittable { app.swipeUp() }
    }

    func test01SwitchThemeInSettings() {
        launch(signedInAs: emailA)
        waitSignedIn()
        openProfileAppearance()
        tap("appearance.light")
        XCTAssertTrue(app.staticTexts["Đang dùng: Sáng"].waitForExistence(timeout: 5))
        shotTheme("light_08_appearance")
        tap("appearance.dark")
        XCTAssertTrue(app.staticTexts["Đang dùng: Tối"].waitForExistence(timeout: 5))
        shotTheme("dark_08_appearance")
        tap("appearance.auto")
        XCTAssertTrue(el("appearance.current").waitForExistence(timeout: 5))
        shotTheme("auto_08_appearance")
    }

    func test02ScreensLight() { screens(mode: "light") }
    func test03ScreensDark() { screens(mode: "dark") }

    private func screens(mode: String) {
        // NSArgumentDomain overrides @AppStorage for this run only (does not touch the saved setting).
        launch(signedInAs: emailA, args: ["-appearance.mode", mode])
        waitSignedIn()
        sleep(4)
        shotTheme("\(mode)_01_map")
        goTab(1)
        let row = el("place.row.Cà phê Giảng")
        if row.waitForExistence(timeout: 15) {
            shotTheme("\(mode)_02_places")
            press(row)
            sleep(3)
            shotTheme("\(mode)_03_place_detail")
            tap("nav.back")
        }
        goTab(2)
        sleep(4)
        shotTheme("\(mode)_04_timeline")
        goTab(3)
        sleep(3)
        shotTheme("\(mode)_05_journals")
        let card = el("journal.card.Hà Nội mùa thu")
        if card.waitForExistence(timeout: 10) {
            press(card)
            sleep(3)
            shotTheme("\(mode)_06_journal_detail")
            tap("nav.back")
        }
        goTab(4)
        sleep(2)
        shotTheme("\(mode)_07_profile")
        let a = el("appearance.auto")
        for _ in 0..<4 where !a.isHittable { app.swipeUp() }
        shotTheme("\(mode)_08_appearance")
    }

    private func shotTheme(_ name: String) { shot("theme/\(name)") }
}
