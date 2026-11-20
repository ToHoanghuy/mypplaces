import XCTest

/// Module 04: log visit (photos + companions), visit detail, add memory — live backend, QA user A.
final class C04VisitsUITests: MPUITestCase {
    private func openPlace(_ title: String) {
        goTab(1)
        tap("place.row.\(title)", 20)
        wait(el("place.logVisit"))
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

    func test01LogVisitWithPhotoAndCompanions() {
        launch(signedInAs: emailA)
        waitSignedIn()
        openPlace("Cà phê Giảng")
        logVisit(note: "Trời se lạnh, uống cà phê trứng với Linh", photos: 2, guests: ["Linh", "Minh"], shots: true)
        wait(el("visit.row"), 30)
        sleep(4)
        shot("03c_place_detail_with_visit")
        tap("visit.row")
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
    }

    func test02MoreVisitsForTimeline() {
        launch(signedInAs: emailA)
        waitSignedIn()
        openPlace("Phở Bát Đàn")
        logVisit(note: "Xếp hàng 15 phút, đáng!", photos: 1, guests: ["Hà"], shots: false)
        wait(el("visit.row"), 30)
        tap("nav.back")
        openPlace("Hồ Hoàn Kiếm")
        logVisit(note: "Đi dạo buổi tối quanh hồ", photos: 1, guests: [], shots: false)
        wait(el("visit.row"), 30)
        tap("nav.back")
        goTab(0)
        sleep(5)
        shot("02a_map_photo_pins")
    }
}
