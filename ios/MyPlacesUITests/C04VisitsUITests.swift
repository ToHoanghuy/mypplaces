import XCTest

/// Module 04: log visit (photos + companions), visit detail, add memory — live backend, QA user A.
final class C04VisitsUITests: MPUITestCase {
    private func openPlace(_ title: String) {
        goTab(1)
        tap("place.row.\(title)", 20)
        wait(el("place.logVisit"))
    }

    /// Cleanup from the visit detail screen: soft-delete the visit this test created.
    private func deleteOpenVisit() {
        menuThenConfirm(menu: "visit.more", "Xóa lần ghé")
        waitGone(el("visit.more"), 20)
        sleep(2)
    }

    private func openVisit(note: String) {
        let row = app.staticTexts[note].firstMatch
        wait(row, 20); press(row)
        wait(el("visit.more"), 15)
    }

    private func logVisit(note: String, photos: Int, guests: [String], shots: Bool) {
        tap("place.logVisit")
        wait(el("visit.save"))
        for _ in 0..<photos { tap("visit.addPhoto"); usleep(500_000) }
        type("visit.note", note)
        if !guests.isEmpty {
            tap("visit.addCompanion")
            for g in guests {
                type("companion.query", g)
                tap("companion.addGuest")
            }
            if shots { shot("04b_companions") }
            tap("companion.done")
        }
        if shots { shot("04a_log_visit") }
        tap("visit.save")
        waitGone(el("visit.save"), 20)
    }

    /// Self-cleaning: unique notes, and each visit created here is soft-deleted at the end,
    /// so the seeded QA visits are never touched.
    func test01LogVisitWithPhotoAndCompanions() {
        let note = "Trời se lạnh, uống cà phê trứng với Linh · \(runTag)"
        launch(signedInAs: emailA)
        waitSignedIn()
        openPlace("Cà phê Giảng")
        logVisit(note: note, photos: 2, guests: ["Linh", "Minh"], shots: true)
        wait(el("visit.row"), 30)
        sleep(4)
        shot("03c_place_detail_with_visit")
        openVisit(note: note)
        wait(el("visit.addMemory"), 15)
        sleep(3)
        shot("04c_visit_detail")
        tap("visit.addMemory")
        wait(el("memory.post"))
        type("memory.text", "Ngồi góc cạnh cửa sổ, nghe mưa phùn.")
        tap("memory.library")
        sleep(1)
        shot("04d_add_memory")
        tap("memory.post")
        waitGone(el("memory.post"), 30)
        wait(app.staticTexts["Ngồi góc cạnh cửa sổ, nghe mưa phùn."].firstMatch, 20)
        sleep(4)
        shot("04c_visit_detail_with_memory")
        deleteOpenVisit()
    }

    func test02MoreVisitsForTimeline() {
        launch(signedInAs: emailA)
        waitSignedIn()
        for (place, note, guests) in [("Phở Bát Đàn", "Xếp hàng 15 phút, đáng!", ["Hà"]), ("Hồ Hoàn Kiếm", "Đi dạo buổi tối quanh hồ", [String]())] {
            let tagged = "\(note) · \(runTag)"
            openPlace(place)
            logVisit(note: tagged, photos: 1, guests: guests, shots: false)
            wait(el("visit.row"), 30)
            openVisit(note: tagged)
            deleteOpenVisit()
            backToRoot()
        }
        goTab(0)
        sleep(5)
        shot("02a_map_photo_pins")
    }

    private func backToRoot() {
        for _ in 0..<3 {
            let back = el("nav.back")
            guard back.waitForExistence(timeout: 3) else { return }
            press(back); sleep(1)
        }
    }
}
