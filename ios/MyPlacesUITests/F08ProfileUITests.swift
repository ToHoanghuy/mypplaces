import XCTest

/// Module 08: profile, edit display name, sync / permissions screen, sign out. Live backend, QA user A.
final class F08ProfileUITests: MPUITestCase {
    func test01ProfileEditSync() {
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(4)
        wait(app.staticTexts["QA Minh Anh"].firstMatch, 20)
        sleep(1)
        shot("08a_profile")
        tap("profile.edit")
        wait(el("profile.save"))
        type("profile.nameField", "Minh Anh", clear: true)
        shot("08b_edit_profile")
        tap("profile.save")
        waitGone(el("profile.save"), 15)
        wait(app.staticTexts["Minh Anh"].firstMatch, 15)
        // restore the original name for later runs
        tap("profile.edit")
        type("profile.nameField", "QA Minh Anh", clear: true)
        tap("profile.save")
        waitGone(el("profile.save"), 15)
        wait(app.staticTexts["QA Minh Anh"].firstMatch, 15)
        tap("profile.sync")
        wait(el("sync.status"), 10)
        sleep(1)
        shot("08c_sync")
        tap("nav.back")
        // members screen avatar regression check lives in E07; sign-out confirm here
        tap("profile.signout")
        let confirm = app.buttons["Đăng xuất"].firstMatch
        wait(confirm, 5)
        shot("08a_signout_confirm")
    }
}
