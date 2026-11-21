import XCTest

/// Read-only tour of every main screen in light and dark, for design reviews (Liquid Glass before/after).
/// File names: SHOT_DIR/liquid-glass/<SHOT_PREFIX>_<mode>_NN_screen.png (SHOT_PREFIX defaults to "shot").
/// Does not create or change any data: every form opened here is cancelled.
final class I11ScreensUITests: MPUITestCase {
    func test01Light() { tour(mode: "light") }
    func test02Dark() { tour(mode: "dark") }

    private var prefix: String { env["SHOT_PREFIX"] ?? "shot" }
    /// Optional: SHOT_FOLDER (default liquid-glass) and TEXT_SIZE (a UIContentSizeCategory name such as
    /// UICTContentSizeCategoryXXXL or UICTContentSizeCategoryAccessibilityXL) for Dynamic Type reviews.
    private var folder: String { env["SHOT_FOLDER"] ?? "liquid-glass" }
    private var sizeArgs: [String] { env["TEXT_SIZE"].map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [] }
    private var sizeTag: String {
        guard let t = env["TEXT_SIZE"] else { return "" }
        return t.replacingOccurrences(of: "UICTContentSizeCategory", with: "").lowercased() + "_"
    }
    private func s(_ mode: String, _ name: String) { shot("\(folder)/\(prefix)_\(sizeTag)\(mode)_\(name)") }

    private func dismissModal() {
        hideKeyboard()
        for id in ["modal.cancel", "search.cancel", "addplace.cancel"] where el(id).exists { press(el(id)); sleep(1); return }
        let cancel = app.buttons["Hủy"].firstMatch
        if cancel.exists { press(cancel); sleep(1); return }
        let close = app.buttons["Đóng"].firstMatch
        if close.exists { press(close); sleep(1); return }
        app.swipeDown(velocity: .fast); sleep(1)
    }

    private func back() {
        if el("nav.back").exists { press(el("nav.back")) } else { app.navigationBars.buttons.firstMatch.tap() }
        sleep(1)
    }

    private func tour(mode: String) {
        // Auth (signed out)
        launch(signedInAs: nil, args: sizeArgs + ["-QASignOut", "-appearance.mode", mode])
        if el("welcome.signin").waitForExistence(timeout: 20) {
            sleep(1); s(mode, "00_welcome")
            tap("welcome.signin"); sleep(1); s(mode, "00b_signin")
        }
        app.terminate()

        launch(signedInAs: emailA, args: sizeArgs + ["-appearance.mode", mode])
        waitSignedIn()
        sleep(4); s(mode, "01_map")

        // Search + Overture fallback
        tap("map.search")
        type("search.field", "Ốc Oanh Vĩnh Khánh")
        _ = el("search.poi").waitForExistence(timeout: 30)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)))
        sleep(1); s(mode, "02_search")
        dismissModal()

        // Add place (cancel)
        if el("map.add").waitForExistence(timeout: 5) {
            press(el("map.add"))
            if el("addplace.title").waitForExistence(timeout: 10) { sleep(2); s(mode, "03_add_place") }
            dismissModal()
        }

        // Places list + detail + visit
        goTab(1)
        let row = el("place.row.Cà phê Giảng")
        if row.waitForExistence(timeout: 15) {
            sleep(2); s(mode, "04_places")
            press(row)
            if el("place.title").waitForExistence(timeout: 15) {
                sleep(3); s(mode, "05_place_detail")
                if el("place.logVisit").exists {
                    press(el("place.logVisit"))
                    if el("visit.save").waitForExistence(timeout: 10) { sleep(1); s(mode, "07_log_visit") }
                    dismissModal()
                }
                if el("visit.row").waitForExistence(timeout: 8) {
                    press(el("visit.row"))
                    if el("visit.addMemory").waitForExistence(timeout: 15) { sleep(3); s(mode, "06_visit_detail") }
                    back()
                }
                back()
            }
        }

        // Timeline
        goTab(2)
        sleep(4); s(mode, "08_timeline")

        // Journals + detail + share + members
        goTab(3)
        sleep(3); s(mode, "09_journals")
        let card = el("journal.card.Hà Nội mùa thu")
        if card.waitForExistence(timeout: 10) {
            press(card)
            sleep(3); s(mode, "10_journal_detail")
            if el("journal.invite").waitForExistence(timeout: 8) {
                press(el("journal.invite"))
                if el("share.create").waitForExistence(timeout: 10) { sleep(1); s(mode, "11_share") }
                if el("share.members").exists {
                    press(el("share.members"))
                    sleep(3); s(mode, "12_members")
                    back()
                } else { dismissModal() }
            }
            if el("nav.back").exists { back() }
        }

        // Profile + sync
        goTab(4)
        sleep(2); s(mode, "13_profile")
        if el("profile.sync").exists {
            press(el("profile.sync"))
            if el("sync.status").waitForExistence(timeout: 10) { sleep(1); s(mode, "14_sync") }
            back()
        }
    }
}
