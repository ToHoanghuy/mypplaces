import XCTest

final class A01AuthUITests: MPUITestCase {
    func test01SignUpAndSignIn() {
        launch(signedInAs: nil, args: ["-QASignOut"])
        tap("welcome.signup", 20)
        shot("01b_signup_empty")
        let name = env["QA_NAME"] ?? "QA Minh Anh"
        type("signup.name", name)
        type("signup.email", env["QA_SIGNUP_EMAIL"] ?? emailA)
        type("signup.password", password)
        shot("01b_signup_filled")
        tap("signup.submit")
        // Either goes straight in (no confirmation) or shows the confirmation note.
        let tabs = btn("tab.0")
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Đã gửi email xác nhận'")).firstMatch
        let err = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'đã được đăng ký' OR label CONTAINS 'tồn tại'")).firstMatch
        let end = Date().addingTimeInterval(20)
        while Date() < end && !tabs.exists && !note.exists && !err.exists { usleep(300_000) }
        shot("01b_signup_result")
        XCTAssertTrue(tabs.exists || note.exists || err.exists, "Sign-up produced no visible outcome")
    }

    func test02SignInScreen() {
        launch(signedInAs: nil, args: ["-QASignOut"])
        tap("welcome.signin", 20)
        type("signin.email", emailA)
        type("signin.password", password)
        shot("01c_signin_filled")
        tap("signin.submit")
        waitSignedIn()
        shot("02_map_after_signin")
    }
}
