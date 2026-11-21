import XCTest

/// Read-only accessibility review shots: very large Dynamic Type (test01), and whatever system
/// accessibility settings the simulator currently has, e.g. Reduce Transparency (test02).
/// Files: SHOT_DIR/liquid-glass/a11y_<SHOT_PREFIX>_<name>.png
final class I12AccessibilityUITests: MPUITestCase {
    private var prefix: String { env["SHOT_PREFIX"] ?? "shot" }
    private func s(_ name: String) { shot("liquid-glass/a11y_\(prefix)_\(name)") }

    func test01LargeText() {
        tour(tag: "xxxl", args: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
    }

    func test02CurrentSettings() {
        tour(tag: "system", args: [])
    }

    private func tour(tag: String, args: [String]) {
        for mode in ["light", "dark"] {
            launch(signedInAs: emailA, args: args + ["-appearance.mode", mode])
            waitSignedIn()
            sleep(4); s("\(tag)_\(mode)_01_map")
            goTab(1); sleep(2); s("\(tag)_\(mode)_04_places")
            let row = el("place.row.Cà phê Giảng")
            if row.waitForExistence(timeout: 10) {
                press(row); sleep(3); s("\(tag)_\(mode)_05_place_detail")
                tap("nav.back"); sleep(1)
            }
            goTab(4); sleep(2); s("\(tag)_\(mode)_13_profile")
            app.terminate()
        }
    }
}
