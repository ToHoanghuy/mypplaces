import XCTest

/// Modules 02–03 against the live backend as QA user A.
final class B02MapPlacesUITests: MPUITestCase {
    /// 03e: soft-delete through Edit → "Xóa địa điểm" → confirm card.
    func test00DeletePlace() {
        let name = env["QA_DELETE_TITLE"] ?? "Cà phê Giảng"
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(1)
        guard el("place.row.\(name)").waitForExistence(timeout: 15) else { return }
        tap("place.row.\(name)")
        tap("place.more")
        let edit = app.buttons["Sửa địa điểm"].firstMatch
        wait(edit, 5); press(edit)
        tap("editplace.delete")
        wait(el("confirm.ok"))
        shot("03e_delete_confirm")
        tap("confirm.ok")
        waitGone(el("confirm.ok"), 15)
        sleep(2)
        XCTAssertFalse(el("place.row.\(name)").exists)
    }

    func test01CreateFirstPlaceFromEmptyMap() {
        launch(signedInAs: emailA)
        waitSignedIn()
        if el("map.empty.add").waitForExistence(timeout: 8) {
            shot("02a_map_empty")
            tap("map.empty.add")
        } else {
            tap("map.add")
        }
        wait(el("addplace.title"))
        sleep(2)
        type("addplace.title", "Cà phê Giảng")
        tap("chip.Cà phê")
        shot("03b_add_place")
        tap("addplace.save")
        waitGone(el("addplace.save"), 20)
        sleep(2)
        shot("02b_map_after_create")
    }

    private func addViaSearch(_ query: String, chip: String, shotName: String? = nil) {
        tap("map.search")
        type("search.field", query)
        let first = el("search.result")
        wait(first, 20)
        if let shotName { shot(shotName, keepKeyboard: true) }
        press(first)
        wait(el("addplace.title"), 15)
        sleep(2)
        tap("chip.\(chip)")
        tap("addplace.save")
        waitGone(el("addplace.save"), 20)
        sleep(1)
    }

    func test02AddPlacesViaSearch() {
        launch(signedInAs: emailA)
        waitSignedIn()
        addViaSearch("phở bát đàn", chip: "Ẩm thực", shotName: "02d_map_search")
        addViaSearch("khách sạn metropole hà nội", chip: "Khách sạn")
        addViaSearch("nhà thờ lớn hà nội", chip: "Du lịch")
        addViaSearch("hồ hoàn kiếm", chip: "Du lịch")
        shot("02c_map_pins")
    }

    func test03MapPreviewFilterAndOwnSearch() {
        launch(signedInAs: emailA)
        waitSignedIn()
        sleep(3)
        tap("chip.Du lịch")
        sleep(2)
        shot("02c_map_filter_travel")
        tap("chip.Tất cả")
        // search own place → focuses and shows preview
        tap("map.search")
        type("search.field", "Giảng")
        let own = el("search.own")
        wait(own, 10)
        shot("02d_search_own")
        press(own)
        wait(el("map.preview"), 10)
        shot("02b_map_preview")
        tap("map.preview")
        wait(el("place.title"), 10)
        shot("03c_place_detail_owner")
    }

    private func editPlace(_ current: String, title: String? = nil, address: String? = nil, shotName: String? = nil) {
        goTab(1)
        tap("place.row.\(current)", 20)
        tap("place.more")
        let edit = app.buttons["Sửa địa điểm"].firstMatch
        wait(edit, 5); press(edit)
        wait(el("editplace.title"))
        if let title { type("editplace.title", title, clear: true) }
        if let address { type("editplace.address", address, clear: true) }
        if let shotName { shot(shotName) }
        tap("editplace.save")
        waitGone(el("editplace.save"), 15)
        wait(app.staticTexts[title ?? current].firstMatch, 15)
        if shotName != nil { shot("03c_place_detail_edited") }
        tap("nav.back")
    }

    func test04PlaceListAndEdit() {
        launch(signedInAs: emailA)
        waitSignedIn()
        goTab(1)
        wait(el("place.row.Cà phê Giảng"), 15)
        editPlace("Khách sạn Metropole Hanoi", title: "Khách sạn Metropole", address: "15 Ngô Quyền, Hoàn Kiếm")
        editPlace("St. Joseph's Cathedral", title: "Nhà thờ Lớn", address: "40 Nhà Chung, Hoàn Kiếm")
        editPlace("Ho Hoan Kiem", title: "Hồ Hoàn Kiếm", address: "Đinh Tiên Hoàng, Hoàn Kiếm")
        editPlace("Cà phê Giảng", address: "39 Nguyễn Hữu Huân, Hoàn Kiếm", shotName: "03d_edit_place")
        goTab(1)
        sleep(2)
        shot("03a_place_list")
    }
}
