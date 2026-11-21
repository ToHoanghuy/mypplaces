import XCTest

/// Module 07: invite link → accept as a second user → member / viewer views. Live backend, QA users A + B.
final class E07SharingUITests: MPUITestCase {
    private func createLink(role: String, ttl: Int, shotPrefix: String?) -> String {
        wait(el("share.create"), 15)
        tap("share.role.\(role)")
        tap("share.ttl.\(ttl)")
        if let p = shotPrefix { shot("\(p)_share_sheet") }
        tap("share.create")
        let link = el("share.link")
        wait(link, 20)
        if let p = shotPrefix { shot("\(p)_share_link") }
        print("QA_INVITE_LINK=\(link.label)")
        return link.label
    }

    /// Idempotent setup: if QA user B is still a member from an earlier run, leave first
    /// (accept_invitation reactivates LEFT members) so the invite can be accepted again.
    private func ensureBLeftPlace(_ name: String) {
        app?.terminate()
        launch(signedInAs: emailB)
        waitSignedIn()
        goTab(1)
        let row = el("place.row.\(name)")
        if row.waitForExistence(timeout: 12) {
            press(row)
            let leave = el("place.leave")
            if leave.waitForExistence(timeout: 10) {
                press(leave)
                let ok = app.buttons["Rời địa điểm"].firstMatch
                if ok.waitForExistence(timeout: 5) { press(ok); sleep(3) }
            }
        }
        app.terminate()
    }

    private func ensureBLeftJournal(_ title: String) {
        app?.terminate()
        launch(signedInAs: emailB)
        waitSignedIn()
        goTab(3)
        let card = el("journal.card.\(title)")
        if card.waitForExistence(timeout: 12) {
            press(card)
            if el("journal.more").waitForExistence(timeout: 10) {
                menuThenConfirm(menu: "journal.more", "Rời nhật ký")
                sleep(3)
            }
        }
        app.terminate()
    }

    private func accept(as email: String, link: String, shotName: String) {
        app.terminate()
        launch(signedInAs: email, open: link)
        wait(el("invite.accept"), 40)
        sleep(2)
        shot(shotName)
        tap("invite.accept")
        sleep(4)
        shot("\(shotName)_after_accept")
    }

    func test01ShareJournalAsEditorAndAccept() {
        ensureBLeftJournal("Hà Nội mùa thu")
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(3)
        tap("journal.card.Hà Nội mùa thu", 20)
        tap("journal.invite", 15)
        let link = createLink(role: "EDITOR", ttl: 7, shotPrefix: "07a_journal")
        XCTAssertTrue(link.hasPrefix("myplaces://invite/"), link)
        accept(as: emailB, link: link, shotName: "07c_invitation")
        wait(el("journal.title.label"), 20)
        sleep(3)
        shot("07e_journal_as_editor")
        // Back to A: members list
        app.terminate()
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(3)
        tap("journal.card.Hà Nội mùa thu", 20)
        tap("journal.invite", 15)
        tap("share.members", 10)
        wait(app.staticTexts["QA Bảo Ngọc"].firstMatch, 20)
        sleep(2)
        shot("07b_members")
    }

    func test02SharePlaceAsViewerAndAccept() {
        ensureBLeftPlace("Phở Bát Đàn")
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(1)
        tap("place.row.Phở Bát Đàn", 20)
        tap("place.share", 15)
        let link = createLink(role: "VIEWER", ttl: 1, shotPrefix: nil)
        accept(as: emailB, link: link, shotName: "07c_invitation_place")
        wait(el("place.leave"), 20)
        sleep(3)
        shot("07e_place_as_viewer")
        XCTAssertFalse(el("place.logVisit").exists, "Viewer must not log visits")
        tap("nav.back")
        goTab(0)
        sleep(4)
        shot("02_map_user_b_shared")
    }

    func test03MembersScreen() {
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(3)
        tap("journal.card.Hà Nội mùa thu", 20)
        tap("journal.invite", 15)
        tap("share.members", 10)
        wait(app.staticTexts["QA Bảo Ngọc"].firstMatch, 20)
        sleep(2)
        shot("07b_members")
    }
}
