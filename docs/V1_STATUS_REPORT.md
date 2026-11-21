# MyPlaces v1 – Thống kê tính năng so với BRD v1.2

Cập nhật 19/11/2026 (giờ Việt Nam). Đối chiếu từng mã yêu cầu trong BRD v1.2 và ERD_Permission v1.2 với code iOS (`ios/`), migrations (`supabase/migrations`) và bộ test.

## Tóm tắt

- **Hoàn thiện v1: 91.1%** trên 140 yêu cầu P0/Should (không gồm 6 mã P1).
- Hoàn thành 121 · Một phần 13 · Chưa làm 3 · Khác tài liệu 3.
- Nếu tính cả P1: 88.4%. Nếu tính "Khác tài liệu" = 0,5: 92.1%.
- Bằng chứng: XCUITest A01Auth, B02MapPlaces, C04Visits, D05TimelineJournal, E07Sharing (3 test), F08Profile – pass trên backend thật; pgTAP 457/457 live; 18 unit test CoreLogicTests. Mục ghi "chỉ code"/"chưa test" chưa được kiểm thử end-to-end.

## Cách tính

`% = (Hoàn thành + 0,5 × Một phần) / Tổng yêu cầu trong phạm vi (không gồm P1) × 100` — "Chưa làm" và "Khác tài liệu" tính 0.

## Theo module

| Module | Số mã (P0) | Hoàn thành | Một phần | Chưa làm | Khác TL | % | Mã P1 |
|---|---|---|---|---|---|---|---|
| 01 Xác thực | 8 | 8 | 0 | 0 | 0 | 100.0% | 0 |
| 02 Bản đồ | 6 | 6 | 0 | 0 | 0 | 100.0% | 0 |
| 03 Địa điểm | 23 | 20 | 1 | 0 | 2 | 89.1% | 1 |
| 04 Lần ghé & Kỷ niệm | 12 | 12 | 0 | 0 | 0 | 100.0% | 0 |
| 05 Dòng thời gian | 6 | 6 | 0 | 0 | 0 | 100.0% | 0 |
| 06 Nhật ký | 19 | 16 | 2 | 1 | 0 | 89.5% | 1 |
| 07 Chia sẻ & Quyền | 43 | 41 | 2 | 0 | 0 | 97.7% | 1 |
| 08 Cá nhân & Đồng bộ | 5 | 2 | 3 | 0 | 0 | 70.0% | 3 |
| 09 Backend & NFR | 18 | 10 | 5 | 2 | 1 | 69.4% | 0 |

## Bảng yêu cầu đầy đủ (146 mã)

| Mã | Module | Mô tả | Ưu tiên | Trạng thái | Bằng chứng / ghi chú |
|---|---|---|---|---|---|
| BR-01 | 03 Địa điểm | Tạo và quản lý Place cá nhân | P0 | Hoàn thành | AddPlace/PlaceDetail/EditPlace; UI test B02MapPlaces |
| BR-02 | 02 Bản đồ | Xem Place trên bản đồ theo tọa độ | P0 | Hoàn thành | MapScreen + view map_places, gom cụm, pin ảnh; B02MapPlaces |
| BR-03 | 02 Bản đồ | Phân loại Place, lọc category | P0 | Hoàn thành | Chip category trên Map + Danh sách; B02MapPlaces |
| BR-04 | 06 Nhật ký | Tạo Journal có title + ngày | P0 | Hoàn thành | CreateJournalView (title, khoảng ngày, ảnh bìa); D05TimelineJournal |
| BR-05 | 06 Nhật ký | Journal chứa nhiều Place, không nhân bản Place | P0 | Hoàn thành | journal_places (link, unique); AddToJournalView; D05 |
| BR-06 | 07 Chia sẻ & Quyền | Owner mời người khác vào Journal | P0 | Hoàn thành | RPC create_invitation (trạng thái + hạn); E07Sharing/test01 |
| BR-07 | 07 Chia sẻ & Quyền | Vai trò Owner/Editor/Viewer, backend kiểm soát | P0 | Hoàn thành | RLS + RPC; pgTAP 05_invitations_membership; E07 |
| BR-08 | 07 Chia sẻ & Quyền | Đóng góp ảnh/ghi chú có attribution | P0 | Hoàn thành | Memory hiển thị tác giả + thời gian; C04Visits, D05 |
| BR-09 | 07 Chia sẻ & Quyền | Rời Journal / Owner gỡ thành viên | P0 | Hoàn thành | RPC leave_resource, remove_member + MembersView; pgTAP 05 (UI chưa test riêng thao tác rời/gỡ) |
| BR-10 | 09 Backend & NFR | Không lộ dữ liệu cá nhân | P0 | Hoàn thành | RLS mọi bảng; pgTAP 457/457 live |
| BR-11 | 05 Dòng thời gian | Xem lại timeline và ảnh | P0 | Hoàn thành | TimelineView + RPC my_timeline; D05 |
| BR-12 | 08 Cá nhân & Đồng bộ | Nhận biết trạng thái đồng bộ | Should | Hoàn thành | Badge 'Chưa đồng bộ/Lỗi đồng bộ' + màn Đồng bộ; F08Profile (chưa test mất mạng thật) |
| BRULE-PL-01 | 03 Địa điểm | Place có UUID, owner_id, title, lat, lng, created_at | P0 | Hoàn thành | migration 02_tables; pgTAP 01 |
| BRULE-PL-02 | 03 Địa điểm | Lat ∈ [-90,90], lng ∈ [-180,180] | P0 | Hoàn thành | Check constraint DB; pgTAP 01 |
| BRULE-PL-03 | 03 Địa điểm | Title trim không rỗng, 1–100 ký tự | P0 | Hoàn thành | AddPlace/EditPlace validate + check DB |
| BRULE-PL-04 | 03 Địa điểm | Ghi chú optional, tối đa 1.000 ký tự | P0 | Hoàn thành | LogVisit giới hạn 1.000 + check DB |
| BRULE-PL-05 | 03 Địa điểm | Category thuộc danh sách; mặc định Other | P0 | Hoàn thành | Enum category, mặc định other |
| BRULE-PL-06 | 03 Địa điểm | Place có owner cá nhân; vào Journal qua JournalPlace | P0 | Hoàn thành | Schema + RLS |
| BRULE-PL-07 | 03 Địa điểm | Place link được nhiều Journal khi có quyền | P0 | Hoàn thành | AddToJournalView; RLS journal_places |
| BRULE-PL-08 | 03 Địa điểm | Gỡ link khỏi Journal không xóa Place | P0 | Một phần | Backend: DELETE journal_places chỉ xóa liên kết; UI CHƯA có nút gỡ |
| BRULE-PL-09 | 03 Địa điểm | Xóa Place là soft delete/tombstone | P0 | Hoàn thành | softDeletePlace (deleted_at) + outbox |
| BRULE-PL-10 | 03 Địa điểm | Không bắt buộc quyền vị trí; chọn vị trí thủ công | P0 | Hoàn thành | AddPlace: tìm kiếm + kéo bản đồ dưới ghim |
| BRULE-JR-01 | 06 Nhật ký | Journal có owner_id, title, visibility, created_at, status | P0 | Hoàn thành | migration 02_tables |
| BRULE-JR-02 | 06 Nhật ký | Title trim không rỗng, tối đa 120 | P0 | Hoàn thành | CreateJournal validate 1–120 + check DB |
| BRULE-JR-03 | 06 Nhật ký | start_date optional; end_date ≥ start_date | P0 | Hoàn thành | Check DB + DatePicker khoảng ngày |
| BRULE-JR-04 | 06 Nhật ký | Journal mặc định PRIVATE; chỉ member truy cập | P0 | Hoàn thành | RLS; pgTAP 04 |
| BRULE-JR-05 | 07 Chia sẻ & Quyền | Một Owner tại một thời điểm | P0 | Hoàn thành | Schema + RPC; pgTAP 05 |
| BRULE-JR-06 | 07 Chia sẻ & Quyền | Chuyển ownership có xác nhận | P0 | Hoàn thành | RPC transfer_ownership + MembersView 'Chuyển quyền sở hữu' (UI chưa test) |
| BRULE-JR-07 | 07 Chia sẻ & Quyền | Editor không quản lý membership/role | P0 | Hoàn thành | RPC kiểm Owner; pgTAP 05; UI ẩn với Editor |
| BRULE-JR-08 | 07 Chia sẻ & Quyền | Viewer chỉ đọc | P0 | Hoàn thành | RLS; pgTAP; E07Sharing/test02 |
| BRULE-JR-09 | 07 Chia sẻ & Quyền | Invitation token ngẫu nhiên, hạn 1/7/30 (mặc định 7), email optional | P0 | Hoàn thành | create_invitation; ShareSheet; pgTAP 07 |
| BRULE-JR-10 | 07 Chia sẻ & Quyền | Invitation chỉ accept một lần | P0 | Hoàn thành | RPC accept_invitation; pgTAP 05 |
| BRULE-JR-11 | 07 Chia sẻ & Quyền | Owner revoke invitation trước khi accept | P0 | Hoàn thành | MembersView 'Thu hồi' + RPC revoke |
| BRULE-JR-12 | 07 Chia sẻ & Quyền | Member bị gỡ mất quyền ngay | P0 | Hoàn thành | RLS dựa membership ACTIVE; pgTAP 05 |
| BRULE-JR-13 | 07 Chia sẻ & Quyền | Owner không được leave khi chưa chuyển quyền | P0 | Hoàn thành | RPC leave_resource chặn Owner; UI ẩn nút Rời với Owner |
| BRULE-JR-14 | 07 Chia sẻ & Quyền | Không tự mời / không trùng membership | P0 | Hoàn thành | RPC trả ALREADY_OWNER/ALREADY_MEMBER (gặp thật khi QA) |
| BRULE-JR-15 | 07 Chia sẻ & Quyền | Một user tham gia nhiều Journal với role khác nhau | P0 | Hoàn thành | Schema journal_members; pgTAP 05 |
| FR-AU-01 | 01 Xác thực | Đăng ký email/password | P0 | Hoàn thành | SignUpView + SessionStore.signUp; A01Auth (bật xác nhận email) |
| FR-AU-02 | 01 Xác thực | Đăng nhập, khôi phục session | P0 | Hoàn thành | SignIn + supabase-swift Keychain; A01Auth |
| FR-AU-03 | 01 Xác thực | Đăng xuất, xóa credential | P0 | Hoàn thành | SessionStore.signOut; F08Profile |
| FR-AU-04 | 01 Xác thực | Reset password | P0 | Hoàn thành | ForgotPasswordView → resetPasswordForEmail (chưa test E2E do giới hạn email Supabase) |
| FR-AU-05 | 08 Cá nhân & Đồng bộ | Profile: display_name, avatar | P0 | Một phần | Đổi tên OK (F08); 'Đổi ảnh' bị tắt – chưa có bucket avatars |
| FR-AU-06 | 08 Cá nhân & Đồng bộ | Privacy settings cơ bản | P1 | Một phần | Chỉ có màn 'Quyền vị trí & ảnh'; chưa có cài đặt riêng tư |
| FR-AU-07 | 08 Cá nhân & Đồng bộ | Xóa tài khoản | P1 | Chưa làm | Chưa có UI/RPC |
| FR-PL-01 | 02 Bản đồ | Map + vị trí user khi được cấp quyền | P0 | Hoàn thành | MapScreen + LocationService; B02 (chưa test khi từ chối quyền) |
| FR-PL-02 | 03 Địa điểm | Tìm địa điểm qua MapKit search | P0 | Hoàn thành | AddPlaceView (MKLocalSearch); B02 |
| FR-PL-03 | 03 Địa điểm | Tạo Place bằng long press/tap map | P0 | Khác tài liệu | Không có long-press: kéo bản đồ dưới ghim cố định trong màn Thêm địa điểm (theo Stitch) |
| FR-PL-04 | 03 Địa điểm | Tạo Place từ kết quả tìm kiếm | P0 | Hoàn thành | Lưu title, tọa độ, địa chỉ; B02 |
| FR-PL-05 | 03 Địa điểm | Place detail: metadata, ảnh, note, linked journals | P0 | Hoàn thành | PlaceDetailView + journalsContaining |
| FR-PL-06 | 03 Địa điểm | Sửa Place sở hữu | P0 | Hoàn thành | EditPlaceView + outbox; B02 |
| FR-PL-07 | 03 Địa điểm | Xóa Place có xác nhận | P0 | Hoàn thành | ConfirmCard + placeUsage cảnh báo tham chiếu; soft delete; B02 |
| FR-PL-08 | 03 Địa điểm | Favorite | P1 | Chưa làm | Không làm theo quyết định UI-03 |
| FR-PL-09 | 03 Địa điểm | Lọc category + search text | P0 | Hoàn thành | PlaceListView; B02 |
| FR-PL-10 | 08 Cá nhân & Đồng bộ | Hiển thị trạng thái sync | P0 | Hoàn thành | Badge pending/failed + màn Đồng bộ (chưa test offline thật) |
| FR-JR-01 | 06 Nhật ký | Tạo Journal | P0 | Hoàn thành | CreateJournalView; owner membership tạo bởi trigger; D05 |
| FR-JR-02 | 06 Nhật ký | Cập nhật title, cover, date range | P0 | Một phần | Chỉ đặt khi tạo; chưa có màn sửa Journal sau khi tạo |
| FR-JR-03 | 06 Nhật ký | Journal list, phân biệt private/shared | P0 | Hoàn thành | JournalListView: badge Riêng tư/Chia sẻ, mục Đã lưu trữ |
| FR-JR-04 | 06 Nhật ký | Thêm Place vào Journal, không trùng | P0 | Hoàn thành | AddToJournalView + unique DB; D05 |
| FR-JR-05 | 06 Nhật ký | Gỡ Place khỏi Journal | P0 | Chưa làm | Backend sẵn (DELETE journal_places); UI chưa có |
| FR-JR-06 | 06 Nhật ký | Timeline Journal theo visited_at, fallback created_at | P0 | Hoàn thành | JournalDetail tab Dòng thời gian (RPC projection); D05 |
| FR-JR-07 | 06 Nhật ký | Thêm/sửa note ngắn cho Journal | P0 | Một phần | 'Thêm ghi chú' (AddMemory parent journal) có; chưa sửa được |
| FR-JR-08 | 06 Nhật ký | Ảnh cover + ảnh kỷ niệm, upload status | P0 | Hoàn thành | Cover khi tạo; ô 'Đang tải lên…'; ImageProcessing ≤2048px |
| FR-JR-09 | 06 Nhật ký | Map các Place trong Journal | P0 | Hoàn thành | JournalDetail tab Bản đồ; D05 |
| FR-JR-10 | 06 Nhật ký | Archive Journal | P1 | Hoàn thành | setJournalArchived + mục Đã lưu trữ (làm sớm, P1) |
| FR-SH-01 | 07 Chia sẻ & Quyền | Tạo link/mã mời có hạn | P0 | Hoàn thành | create_invitation 1/7/30; ShareSheet; E07 (chỉ custom scheme myplaces://) |
| FR-SH-02 | 07 Chia sẻ & Quyền | Chọn role khi mời (Editor/Viewer) | P0 | Hoàn thành | ShareSheet; RPC chặn Owner |
| FR-SH-03 | 07 Chia sẻ & Quyền | Invitee preview, accept/decline | P0 | Hoàn thành | InvitationView + EnterInviteSheet; E07 accept (decline chỉ code) |
| FR-SH-04 | 07 Chia sẻ & Quyền | Owner xem member + role | P0 | Hoàn thành | MembersView; không lộ email; E07/test03 |
| FR-SH-05 | 07 Chia sẻ & Quyền | Đổi role Editor/Viewer, có audit | P0 | Hoàn thành | changeRole UI + RPC change_member_role ghi audit_log |
| FR-SH-06 | 07 Chia sẻ & Quyền | Owner remove member | P0 | Hoàn thành | MembersView + RPC remove_member; pgTAP 05 |
| FR-SH-07 | 07 Chia sẻ & Quyền | Member leave | P0 | Hoàn thành | Nút Rời ở Place/Visit/Journal + RPC leave_resource |
| FR-SH-08 | 07 Chia sẻ & Quyền | Editor thêm ảnh/note/Place link | P0 | Hoàn thành | RLS created_by = auth.uid(); pgTAP 03/04 (UI Editor chưa test riêng) |
| FR-SH-09 | 07 Chia sẻ & Quyền | Viewer chỉ đọc | P0 | Hoàn thành | pgTAP + E07/test02 (Viewer không có nút ghi) |
| FR-SH-10 | 07 Chia sẻ & Quyền | Hiển thị attribution | P0 | Hoàn thành | Tên/avatar chữ cái + thời gian trên Memory |
| FR-SH-11 | 07 Chia sẻ & Quyền | Realtime cập nhật | P1 | Chưa làm | Backend đã publish supabase_realtime 11 bảng; app chưa subscribe (kéo để làm mới) |
| UC-01 | 01 Xác thực | Đăng ký tài khoản | P0 | Hoàn thành | A01Auth |
| UC-02 | 01 Xác thực | Đăng nhập | P0 | Hoàn thành | A01Auth |
| UC-03 | 02 Bản đồ | Xem bản đồ và vị trí hiện tại | P0 | Hoàn thành | B02MapPlaces |
| UC-04 | 03 Địa điểm | Tìm kiếm và tạo Place | P0 | Hoàn thành | B02MapPlaces |
| UC-05 | 03 Địa điểm | Tạo Place bằng chọn pin | P0 | Khác tài liệu | Ghim cố định + kéo bản đồ thay vì long-press (xem FR-PL-03) |
| UC-06 | 03 Địa điểm | Cập nhật/xóa Place | P0 | Hoàn thành | B02MapPlaces |
| UC-07 | 06 Nhật ký | Tạo Journal | P0 | Hoàn thành | D05 |
| UC-08 | 06 Nhật ký | Thêm Place vào Journal | P0 | Hoàn thành | D05 |
| UC-09 | 07 Chia sẻ & Quyền | Tạo và gửi invitation | P0 | Hoàn thành | E07/test01, test02 |
| UC-10 | 07 Chia sẻ & Quyền | Accept/decline invitation | P0 | Hoàn thành | E07 (accept); decline chỉ code |
| UC-11 | 07 Chia sẻ & Quyền | Quản lý member và role | P0 | Hoàn thành | E07/test03 |
| UC-12 | 04 Lần ghé & Kỷ niệm | Đóng góp ảnh và note | P0 | Hoàn thành | C04Visits, D05 |
| UC-13 | 06 Nhật ký | Xem timeline và map Journal | P0 | Hoàn thành | D05 |
| UC-14 | 07 Chia sẻ & Quyền | Rời Journal | P0 | Hoàn thành | Code + RPC; UI chưa test riêng |
| UC-15 | 08 Cá nhân & Đồng bộ | Đồng bộ local/cloud | P0 | Một phần | Outbox chỉ cho Place CRUD + tạo Visit; Memory/Journal/Chia sẻ cần mạng; chưa test offline |
| UC-16 | 08 Cá nhân & Đồng bộ | Xóa tài khoản và xử lý dữ liệu | P1 | Chưa làm | Chưa làm |
| NFR-01 | 09 Backend & NFR | Map/List mượt; pagination collection lớn | P0 | Một phần | Mượt trong test; map_places tải toàn bộ, timeline giới hạn, chưa có cursor |
| NFR-02 | 09 Backend & NFR | Không tải ảnh gốc; thumbnail + lazy | P0 | Một phần | Ảnh thu ≤2048px khi upload + cache + lazy; chưa có bản thumbnail riêng |
| NFR-03 | 09 Backend & NFR | Không crash khi từ chối Location/Photos | P0 | Hoàn thành | LocationService xử lý denied; PhotosPicker không cần quyền (chưa test từ chối) |
| NFR-04 | 09 Backend & NFR | Mutation có pending record local trước network | P0 | Một phần | Outbox SwiftData cho Place CRUD + tạo Visit; phần khác online |
| NFR-05 | 09 Backend & NFR | RLS + JWT cho mọi mutation | P0 | Hoàn thành | pgTAP 457/457 live |
| NFR-06 | 09 Backend & NFR | Không background location; giải thích quyền | P0 | Hoàn thành | Chỉ WhenInUse; màn Quyền vị trí & ảnh |
| NFR-07 | 09 Backend & NFR | Dynamic Type, VoiceOver, contrast, touch target | P0 | Một phần | Có accessibilityIdentifier, ít accessibilityLabel (3 chỗ), font cố định – chưa Dynamic Type |
| NFR-08 | 09 Backend & NFR | Text tách khỏi code; vi/en | P0 | Khác tài liệu | Chỉ tiếng Việt, chuỗi viết thẳng trong code (chưa có Localizable) |
| NFR-09 | 09 Backend & NFR | Tách module, repository, logic test được | P0 | Hoàn thành | Core/Data/Presentation; 18 unit test CoreLogicTests |
| NFR-10 | 09 Backend & NFR | Log request_id, error code, sync state | P0 | Chưa làm | Chưa có logging có cấu trúc |
| NFR-11 | 09 Backend & NFR | Index, pagination cursor, giới hạn upload | P0 | Một phần | Index DB + bucket 10 MB/mime có; chưa có cursor pagination |
| NFR-12 | 09 Backend & NFR | FK, check, unique, transaction | P0 | Hoàn thành | Migrations + RPC transactional; pgTAP 01 |
| NFR-13 | 09 Backend & NFR | Minimum iOS xác định | P0 | Hoàn thành | iOS 17+ (project.yml) |
| NFR-14 | 09 Backend & NFR | Kế hoạch export dữ liệu + xóa tài khoản | P0 | Chưa làm | Chưa có |
| BR-HY-01 | 03 Địa điểm | Kho Place cá nhân độc lập Journal | P0 | Hoàn thành | B02 |
| BR-HY-02 | 04 Lần ghé & Kỷ niệm | Một Place nhiều Visit độc lập | P0 | Hoàn thành | C04Visits |
| BR-HY-03 | 04 Lần ghé & Kỷ niệm | Memory gắn Place/Visit/Journal | P0 | Hoàn thành | AddMemoryView (3 loại parent); C04, D05 |
| BR-HY-04 | 04 Lần ghé & Kỷ niệm | Ghi nhận người tham gia Visit (user hoặc tên) | P0 | Hoàn thành | LogVisit: gợi ý + tên tự do ≤40; không cấp quyền |
| BR-HY-05 | 07 Chia sẻ & Quyền | Share Place độc lập | P0 | Hoàn thành | E07/test02; không lộ Visit |
| BR-HY-06 | 07 Chia sẻ & Quyền | Share một Visit độc lập | P0 | Hoàn thành | Nút visit.share + RLS visit_members (UI chưa test riêng) |
| BR-HY-07 | 07 Chia sẻ & Quyền | Shared Journal + mời cộng tác | P0 | Hoàn thành | E07/test01 |
| BR-HY-08 | 05 Dòng thời gian | Personal Timeline không nhân đôi Visit | P0 | Hoàn thành | my_timeline theo Visit; D05 |
| BR-HY-09 | 07 Chia sẻ & Quyền | Kiểm soát quyền, thu hồi chia sẻ | P0 | Hoàn thành | Thu hồi, gỡ, Ngừng chia sẻ; pgTAP 05 |
| BR-HY-10 | 08 Cá nhân & Đồng bộ | Place/Visit/Journal dùng offline mức draft/cache | P0 | Một phần | Place/Visit có outbox; Journal chưa offline |
| DEC-01 | 01 Xác thực | Guest mode: chưa triển khai (yêu cầu account) | P0 | Hoàn thành | Đúng quyết định: bắt buộc đăng nhập |
| DEC-02 | 07 Chia sẻ & Quyền | Share Place độc lập (P0) | P0 | Hoàn thành | Xem BR-HY-05 |
| DEC-03 | 07 Chia sẻ & Quyền | Share Visit độc lập (P0) | P0 | Hoàn thành | Xem BR-HY-06 |
| DEC-04 | 07 Chia sẻ & Quyền | Journal sharing Owner/Editor/Viewer | P0 | Hoàn thành | Xem BR-HY-07 |
| DEC-05 | 04 Lần ghé & Kỷ niệm | Visit là entity lõi | P0 | Hoàn thành | Bảng visits; C04 |
| DEC-06 | 04 Lần ghé & Kỷ niệm | VisitMember tách khỏi participant | P0 | Hoàn thành | visit_members ≠ visit_participants |
| DEC-07 | 09 Backend & NFR | Deny by default, không kế thừa quyền | P0 | Hoàn thành | RLS; pgTAP 02/04 |
| DEC-08 | 07 Chia sẻ & Quyền | Editor chỉ sửa nội dung mình; Owner moderation | P0 | Một phần | RLS tác giả có; UI chưa có sửa/xóa Memory, chưa có moderation |
| DEC-09 | 07 Chia sẻ & Quyền | Một Owner, chuyển quyền có xác nhận | P0 | Hoàn thành | transfer_ownership + confirmationDialog |
| DEC-10 | 04 Lần ghé & Kỷ niệm | Không auto GPS tracking | P0 | Hoàn thành | Ghi Visit thủ công |
| DEC-11 | 09 Backend & NFR | Collections là P1 | P0 | Hoàn thành | Không làm, đúng quyết định |
| DEC-12 | 05 Dòng thời gian | Personal Timeline cơ bản P0 | P0 | Hoàn thành | TimelineView |
| ERD-01 | 04 Lần ghé & Kỷ niệm | Guest participant không cần account, không có quyền | P0 | Hoàn thành | display_name_snapshot; tên tự do ≤40 |
| ERD-02 | 09 Backend & NFR | Editor không sửa metadata Place/Visit | P0 | Hoàn thành | RLS; pgTAP 02 |
| ERD-03 | 07 Chia sẻ & Quyền | Share Place không lộ Visit history | P0 | Hoàn thành | RLS; E07/test02 |
| ERD-04 | 06 Nhật ký | Member Journal chỉ thấy projection | P0 | Hoàn thành | RPC journal_places/visits_projection; pgTAP 04 |
| ERD-05 | 04 Lần ghé & Kỷ niệm | Memory đúng một parent | P0 | Hoàn thành | Check constraint; pgTAP 03 |
| ERD-06 | 04 Lần ghé & Kỷ niệm | Người tạo Visit là owner Visit | P0 | Hoàn thành | Trigger/RLS |
| ERD-07 | 07 Chia sẻ & Quyền | Một Owner mỗi resource | P0 | Hoàn thành | Schema + RPC |
| ERD-08 | 07 Chia sẻ & Quyền | Giữ attribution sau khi gỡ; quy trình moderation/xóa | P0 | Một phần | Attribution giữ nguyên; chưa có quy trình moderation/xóa pháp lý |
| ERD-09 | 02 Bản đồ | Muốn đến/Đã ghé suy ra từ Visit (map_places) | P0 | Hoàn thành | view map_places; B02 |
| ERD-10 | 07 Chia sẻ & Quyền | Hạn mời 1/7/30, mặc định 7 | P0 | Hoàn thành | pgTAP 07; ShareSheet |
| ERD-11 | 04 Lần ghé & Kỷ niệm | Gợi ý người đi cùng không friend graph | P0 | Hoàn thành | RPC list_companion_suggestions; C04 |
| ERD-12 | 05 Dòng thời gian | Timeline theo timezone_id từng Visit | P0 | Hoàn thành | CoreLogicTests; TimelineView |
| ERD-13 | 05 Dòng thời gian | Visit member thấy projection tối thiểu của Place | P0 | Hoàn thành | my_timeline; pgTAP 07 |
| UI-01 | 01 Xác thực | 5 tab, Chia sẻ là hành động | P0 | Hoàn thành | MainTabView |
| UI-02 | 02 Bản đồ | Muốn đến/Đã ghé qua map_places | P0 | Hoàn thành | MapPins; B02 |
| UI-03 | 03 Địa điểm | Không có nút Yêu thích | P0 | Hoàn thành | Đúng quyết định |
| UI-04 | 04 Lần ghé & Kỷ niệm | Gợi ý người đi cùng + tên tự do ≤40 | P0 | Hoàn thành | LogVisitView; C04 |
| UI-05 | 07 Chia sẻ & Quyền | Hạn mời 1/7/30, mặc định 7 | P0 | Hoàn thành | ShareSheetView; E07 |
| UI-06 | 05 Dòng thời gian | Timeline theo timezone_id Visit | P0 | Hoàn thành | TimelineView; CoreLogicTests |

## Khác so với tài liệu

| Điểm khác | Lý do / hiện trạng |
|---|---|
| Tạo Place bằng ghim cố định + kéo bản đồ, không có long-press (FR-PL-03, UC-05) | Theo thiết kế Stitch màn 03c; vẫn điền tọa độ + nhập tiêu đề đúng tiêu chí chấp nhận. |
| Chỉ tiếng Việt, chuỗi viết thẳng trong code (NFR-08) | Ưu tiên giao diện tiếng Việt cho v1; chưa tách Localizable nên chưa có tiếng Anh. |
| Offline chỉ cho Place (tạo/sửa/xóa) và tạo Visit (NFR-04, UC-15, BR-HY-10) | Kỷ niệm, ảnh, Nhật ký và chia sẻ cần mạng; outbox SwiftData mới phủ luồng lõi. |
| Ảnh đại diện: nút 'Đổi ảnh' bị tắt (FR-AU-05) | Backend chưa có bucket avatars; hiện avatar chữ cái đầu. |
| Link mời chỉ dùng custom scheme myplaces://  | Chưa có domain cho universal link; người nhận cần cài app hoặc nhập mã trong app. |
| Bộ lọc Dòng thời gian chỉ chọn 1 loại địa điểm | RPC my_timeline nhận một p_category; thiết kế gợi ý chọn nhiều. |
| Font hệ thống SF thay cho Inter | Không đóng gói font Inter vào app. |
| Chip loại địa điểm luôn hiện trên Bản đồ | Đơn giản hóa thay cho bảng lọc ẩn/hiện. |
| Viewer thấy icon loại thay vì ảnh bìa Place được chia sẻ | Policy storage chỉ cấp ảnh trong phạm vi quyền; ảnh bìa lấy từ kỷ niệm của Visit chưa chia sẻ. |
| Dòng trong Nhật ký hiện người thêm thay vì người đi cùng | Projection của Nhật ký không trả danh sách người đi cùng. |
| Lưu trữ Nhật ký (FR-JR-10, P1) đã làm sớm | Có sẵn cột archived_at, chi phí thấp. |
| Xác nhận email vẫn bật khi đăng ký | Chưa được duyệt tắt; người dùng mới phải mở email xác nhận (giới hạn tốc độ email mặc định của Supabase). |

## Việc còn lại (theo ưu tiên)

| # | Ưu tiên | Việc | Ghi chú |
|---|---|---|---|
| 1 | P0 | Gỡ Place khỏi Nhật ký (FR-JR-05, BRULE-PL-08) | Backend sẵn DELETE journal_places; chỉ cần UI + test. |
| 2 | P0 | Màn sửa Nhật ký: tiêu đề, khoảng ngày, ảnh bìa (FR-JR-02) | API setJournalCover có sẵn; thêm update title/date. |
| 3 | P0 | Sửa/xóa Kỷ niệm của chính mình + Owner kiểm duyệt (DEC-08, FR-JR-07, ERD-08) | RLS tác giả đã có; thiếu UI. |
| 4 | P0 | Mở rộng outbox offline cho Kỷ niệm/ảnh/Nhật ký + test mất mạng thật (NFR-04, UC-15, BR-HY-10) |  |
| 5 | P0 | Bucket avatars + upload ảnh đại diện (FR-AU-05) | Việc backend + bật nút 'Đổi ảnh'. |
| 6 | P0 | Phân trang cursor cho map_places/timeline + thumbnail ảnh (NFR-01, NFR-02, NFR-11) |  |
| 7 | P0 | Accessibility: Dynamic Type, VoiceOver label (NFR-07) |  |
| 8 | P0 | Tách chuỗi Localizable + bản tiếng Anh (NFR-08) |  |
| 9 | P0 | Logging có cấu trúc request_id/error code/sync state (NFR-10) |  |
| 10 | P0 | Kế hoạch export dữ liệu + xóa tài khoản trước production (NFR-14, FR-AU-07, UC-16) |  |
| 11 | Vận hành | Domain universal link, SMTP riêng, bật leaked password protection, dọn 2 lời mời test còn pending |  |
| 12 | P1 | Realtime trong Nhật ký (FR-SH-11), Favorite (FR-PL-08), cài đặt riêng tư (FR-AU-06) | Backend đã publish realtime 11 bảng. |

## Tính năng bổ sung ngoài BRD v1.2

| Ngày | Tính năng | Ghi chú |
|---|---|---|
| 20/11/2026 | Giao diện Sáng / Tối / Tự động theo giờ (Cá nhân › Giao diện) | Giữ nguyên nền tối cũ; thêm nền trắng. Mặc định "Tự động theo giờ": sáng 06:00–18:00, tối ngoài khung đó (chỉnh được 2 mốc giờ), tự đổi khi app đang mở. Không tính vào % hoàn thiện so với BRD. Ảnh: `docs/screenshots/theme/`. Test: `ThemeScheduleTests` (unit), `G09ThemeUITests` (UI). |
| 20/11/2026 | Tìm kiếm dự phòng bằng dữ liệu mở (Overture Maps) khi Apple Maps không tìm thấy | Bản đồ và tìm kiếm chính vẫn là MapKit. Khi Apple trả < 3 kết quả liên quan (từ khoá ≥ 3 ký tự), app gọi RPC `search_pois` (Supabase, bảng `poi_overture` 422.329 POI Việt Nam, release Overture 2026-11-18.0, chỉ đọc cho user đã đăng nhập) và hiện mục "Gợi ý thêm" (tối đa 5, bỏ trùng với kết quả Apple trong 50 m + tên giống). Chọn một gợi ý sẽ điền sẵn tên, danh mục, toạ độ, địa chỉ (provider `overture`). Ghi nguồn "Dữ liệu địa điểm: Overture Maps Foundation, © OpenStreetMap contributors" dưới các gợi ý và ở Cá nhân › Giới thiệu. Debounce 400 ms, cache 40 truy vấn gần nhất. Bộ 30 truy vấn thật (HN + HCM): Apple một mình 23 đúng / 1 gần đúng / 6 sai → Apple + dự phòng 26 / 3 / 1. Ảnh: `docs/screenshots/search/`. Test: `SearchMergeTests` (unit, 9), `H10SearchFallbackUITests` (UI, sáng + tối), pgTAP `08_poi_overture_search` (31). Không tính vào % hoàn thiện so với BRD. |
| 21/11/2026 | Nén ảnh trên máy trước khi tải lên | Mọi ảnh kỷ niệm/ảnh bìa nhật ký đi qua `ImageCompressor`: thu nhỏ bằng ImageIO (không giải mã toàn ảnh) để cạnh dài ≤ 1600 px (không phóng to), xoay đúng chiều, bỏ toàn bộ EXIF/GPS, JPEG chất lượng 0,7 (hạ dần tới 0,5 nếu > 500 KB), chạy nền. Đo trên 6 ảnh mẫu (1,3–2,8 MB gốc): cách cũ 2048 px/0,82 trung bình 792 KB → mới 366 KB (248–464 KB), giảm ~54%. Bucket `memory-media` hạ giới hạn từ 10 MB xuống 2 MB. Chưa tạo ảnh thumbnail riêng (chưa có chỗ lưu/hiển thị). Test: `ImageCompressorTests` (8), `C04VisitsUITests/test01`, pgTAP 06. |
