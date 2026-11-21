import XCTest

/// Shared helpers for the simulator QA flows. Driven by env passed as TEST_RUNNER_* from xcodebuild:
///   QA_EMAIL / QA_PASSWORD / QA_EMAIL_B / QA_NAME, SHOT_DIR (absolute host path for screenshots).
class MPUITestCase: XCTestCase {
    var app: XCUIApplication!
    var env: [String: String] { ProcessInfo.processInfo.environment }
    var emailA: String { env["QA_EMAIL"] ?? "myplaces.qa+1@mailinator.com" }
    var emailB: String { env["QA_EMAIL_B"] ?? "myplaces.qa+2@mailinator.com" }
    var password: String { env["QA_PASSWORD"] ?? "" }

    override func setUp() {
        continueAfterFailure = false
    }

    @discardableResult
    func launch(signedInAs email: String?, open: String? = nil, args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-QAStubPhotos", "-QANoAutofill", "-AppleLanguages", "(vi)", "-AppleLocale", "vi_VN"] + args
        if let email {
            app.launchEnvironment["QA_EMAIL"] = email
            app.launchEnvironment["QA_PASSWORD"] = password
        }
        if let open { app.launchEnvironment["QA_OPEN"] = open }
        app.launch()
        self.app = app
        return app
    }

    func shot(_ name: String, keepKeyboard: Bool = false) {
        if !keepKeyboard, app != nil { hideKeyboard() }
        sleep(1)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let att = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        att.name = name; att.lifetime = .keepAlways; add(att)
        if let dir = env["SHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: url)
        }
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    func btn(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    func text(_ label: String) -> XCUIElement { app.staticTexts[label].firstMatch }

    @discardableResult
    func wait(_ e: XCUIElement, _ t: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(e)", file: file, line: line)
        return e
    }

    func tap(_ id: String, _ t: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let e = el(id)
        XCTAssertTrue(e.waitForExistence(timeout: t), "Missing \(id)", file: file, line: line)
        press(e)
    }

    /// Coordinate tap: SwiftUI fields inside ScrollViews often report "not hittable" on iOS 26 even when visible.
    func press(_ e: XCUIElement) {
        if !e.isHittable { revealAboveKeyboard(e) }
        if e.isHittable { e.tap() } else { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    func waitHittable(_ e: XCUIElement, _ t: TimeInterval = 10) {
        let end = Date().addingTimeInterval(t)
        while !e.isHittable && Date() < end { usleep(200_000) }
    }

    func field(_ id: String) -> XCUIElement {
        let tf = app.textFields[id].firstMatch
        if tf.exists { return tf }
        let sf = app.secureTextFields[id].firstMatch
        if sf.exists { return sf }
        let tv = app.textViews[id].firstMatch
        if tv.exists { return tv }
        return el(id)
    }

    func type(_ id: String, _ value: String, clear: Bool = false) {
        _ = el(id).waitForExistence(timeout: 15)
        let e = field(id)
        wait(e)
        revealAboveKeyboard(e)
        if clear {
            // Put the caret at the end so the deletes remove the whole value.
            e.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        } else {
            press(e)
        }
        usleep(400_000)
        if clear, let current = e.value as? String, !current.isEmpty {
            e.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        e.typeText(value)
    }

    /// SecureField typing drops characters on the iOS 26 simulator: reveal, type into the plain field, then hide again.
    func typeSecret(_ id: String, _ value: String) {
        tap("\(id).reveal")
        usleep(300_000)
        type(id, value)
        tap("\(id).reveal")
    }

    /// Scroll a field out from under the keyboard (coordinate taps would otherwise land on keys).
    func revealAboveKeyboard(_ e: XCUIElement) {
        for _ in 0..<4 {
            let kb = app.keyboards.firstMatch
            guard kb.exists, e.frame.maxY > kb.frame.minY - 8 else { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
            usleep(400_000)
        }
    }

    /// Tap an empty strip of background near the top (modal title row) to drop the keyboard before a screenshot.
    func hideKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.115)).tap()
        usleep(500_000)
    }

    func waitGone(_ e: XCUIElement, _ t: TimeInterval = 15) {
        let p = NSPredicate(format: "exists == false")
        let ex = expectation(for: p, evaluatedWith: e)
        wait(for: [ex], timeout: t)
    }

    /// Tab button: app-drawn bar (iOS < 26, id "tab.N") or the system Liquid Glass tab bar (iOS 26, by position).
    func tabButton(_ i: Int) -> XCUIElement {
        let custom = btn("tab.\(i)")
        if custom.exists { return custom }
        return app.tabBars.buttons.element(boundBy: i)
    }

    var tabsVisible: Bool { btn("tab.0").exists || app.tabBars.buttons.count > 0 }

    func waitSignedIn(file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(30)
        while !tabsVisible && Date() < end { usleep(300_000) }
        XCTAssertTrue(tabsVisible, "Tab bar missing (not signed in?)", file: file, line: line)
    }

    func goTab(_ i: Int, file: StaticString = #filePath, line: UInt = #line) {
        let b = tabButton(i)
        XCTAssertTrue(b.waitForExistence(timeout: 15), "Missing tab \(i)", file: file, line: line)
        if b.isHittable { b.tap() } else { b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }
}
