import XCTest

/// Modules 05 (timeline + filter) and 06 (journals) — live backend, QA user A.
final class D05TimelineJournalUITests: MPUITestCase {
    func test01TimelineAndFilter() {
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(2)
        wait(el("timeline.item.Cà phê Giảng"), 20)
        wait(el("timeline.item.Phở Bát Đàn"), 10)
        sleep(4)
        shot("05a_timeline")
        tap("timeline.filter")
        tap("chip.Cà phê")
        shot("05b_timeline_filter")
        tap("filter.apply")
        sleep(3)
        wait(el("timeline.item.Cà phê Giảng"), 15)
        XCTAssertFalse(el("timeline.item.Phở Bát Đàn").exists)
        shot("05a_timeline_filtered")
        tap("timeline.item.Cà phê Giảng")
        wait(el("visit.addMemory"), 15)
    }

    func test00OpenCreateJournal() {
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(3)
        tap("journals.add", 15)
        wait(el("journal.create"), 10)
    }

    /// Self-cleaning: uses a unique title (never duplicates the shared "Hà Nội mùa thu") and deletes it at the end.
    func test02CreateJournalAndAddItems() {
        let title = "Chuyến thử \(runTag)"
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(3)
        wait(el("journals.add"), 15)
        sleep(2)
        shot("06a_journals_before")
        tap("journals.add")
        wait(el("journal.create"))
        tap("journal.cover")
        type("journal.title", title)
        shot("06b_create_journal")
        tap("journal.create")
        // lands in the new journal (06c) or back on the list
        if !el("journal.add").waitForExistence(timeout: 20) {
            tap("journal.card.\(title)", 15)
        }
        tap("journal.add", 20)
        wait(el("addtojournal.save"))
        tap("select.Cà phê Giảng", 15)
        tap("select.Phở Bát Đàn")
        tap("select.Hồ Hoàn Kiếm")
        shot("06e_add_to_journal")
        let visitsTab = app.buttons["Lần ghé"].firstMatch
        press(visitsTab)
        sleep(2)
        tap("select.Cà phê Giảng", 15)
        tap("addtojournal.save")
        waitGone(el("addtojournal.save"), 20)
        wait(el("journal.row.Cà phê Giảng"), 20)
        sleep(4)
        shot("06c_journal_detail")
        if el("journal.tab.1").exists { tap("journal.tab.1"); sleep(3); shot("06d_journal_map") ; tap("journal.tab.0") }
        // Cleanup: soft-delete the journal (places / visits stay).
        menuThenConfirm(menu: "journal.more", "Xóa nhật ký")
        waitGone(el("journal.more"), 20)
        sleep(3)
        XCTAssertFalse(el("journal.card.\(title)").exists)
        shot("06a_journals")
    }
}
