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
        app.launchArguments = ["-QAStubPhotos", "-QANoAutofill"] + args
        if let email {
            app.launchEnvironment["QA_EMAIL"] = email
            app.launchEnvironment["QA_PASSWORD"] = password
        }
        if let open { app.launchEnvironment["QA_OPEN"] = open }
        app.launch()
        self.app = app
        return app
    }

    func shot(_ name: String) {
        sleep(1)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let att = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        att.name = name; att.lifetime = .keepAlways; add(att)
        if let dir = env["SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
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
        if e.isHittable { e.tap() } else { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    func waitHittable(_ e: XCUIElement, _ t: TimeInterval = 10) {
        let end = Date().addingTimeInterval(t)
        while !e.isHittable && Date() < end { usleep(200_000) }
    }

    func type(_ id: String, _ value: String, clear: Bool = false) {
        let e = el(id)
        wait(e); press(e)
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

    func waitGone(_ e: XCUIElement, _ t: TimeInterval = 15) {
        let p = NSPredicate(format: "exists == false")
        let ex = expectation(for: p, evaluatedWith: e)
        wait(for: [ex], timeout: t)
    }

    func waitSignedIn() { wait(btn("tab.0"), 30) }

    func goTab(_ i: Int) { tap("tab.\(i)") }
}
