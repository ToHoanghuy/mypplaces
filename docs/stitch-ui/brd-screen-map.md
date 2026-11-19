# MyPlaces – Bản đồ BRD → Màn hình → Dữ liệu (dùng cho UI mẫu Stitch theo chức năng)

Nguồn: BRD v1.1 (`/workspace/idea.txt`, 10/11/2026; v1.1 ưu tiên khi mâu thuẫn với v1.0 – mục 40), ERD & Permission v1.1 (`/workspace/erd.txt`), backend đã build (`/workspace/myplaces/supabase/migrations`, 10 migration).
Nguyên tắc: mỗi trường hiển thị phải map tới cột/quan hệ thật; không thêm tính năng ngoài BRD (không rating, giá, thống kê, feed, bạn bè, chat); P1/P2 không vẽ trong bộ P0.

## 0. Quyết định chung về UI
| Chủ đề | Quyết định | Căn cứ |
|---|---|---|
| Điều hướng | Pill nổi 5 icon (không nhãn): Bản đồ · Địa điểm · Dòng thời gian · Nhật ký · Cá nhân | BRD §6.2 (Map, Places, Journals, Profile; Activity là P1 → bỏ) + v1.1 §35.1 Personal Timeline P0, §34.5 Workflow E |
| Bỏ tab "Chia sẻ" của mockup cũ | Chia sẻ là hành động theo từng tài nguyên (Place/Visit/Journal), không phải tab; lời mời mở qua deep link/code | §33.1, §34.2–34.4, UC-09/10; Activity/notification là P1 (§5.2, §35.2) |
| Marker ảnh trên bản đồ | Marker = Place (`places`); ảnh = ảnh mới nhất trong `memory_attachments` của `memories` thuộc Visit gần nhất (hoặc của Place). Place chưa có Visit/ảnh → marker tròn màu danh mục + icon | BR-02, FR-PL-01, §11.1, §32.2 (Place có thể chưa có Visit) |
| Phân biệt Place được chia sẻ | Marker/hàng có badge nhỏ icon 2 người (không chỉ dựa vào màu) | §11.1 "phân biệt bằng badge/màu/cluster; không phụ thuộc màu duy nhất" |
| Cluster | Chồng ảnh + số đếm | §11.1 (cluster), §35.2 nâng cao là P1 – cluster cơ bản giữ |
| "Check-in" | Dùng thuật ngữ BRD: "Ghi lần ghé" (Record a Visit / I've been here) = tạo `visits` | §34.1 Workflow A |
| Danh mục | 7 giá trị enum `place_category`: Ẩm thực(FOOD) Cà phê(CAFE) Du lịch(TRAVEL) Khách sạn(HOTEL) Mua sắm(SHOPPING) Giải trí(ENTERTAINMENT) Khác(OTHER, mặc định) | §8.1, BRULE-PL-05, migration 01 |
| Trạng thái đồng bộ | Badge nhỏ "Chưa đồng bộ · Thử lại" / "Đang đồng bộ"; synced thì không hiện | FR-PL-10 (P0), §25.2, BR-12 |
| Quyền | UI chỉ hiện hành động theo role; Viewer không có nút thêm/sửa | §5.2 ERD, FR-SH-09, UC-08 |

## 1. Tài khoản (Account) – project "MyPlaces · 01 Tài khoản"
| Màn | Trường / hành động | BRD | DB |
|---|---|---|---|
| Onboarding (Guest) | 1 ảnh lớn + slogan "Nơi chốn là kỷ niệm"; Đăng ký / Đăng nhập. Không có guest mode tạo dữ liệu | §4.1 Guest, §6.1, DEC-01 | – |
| Đăng nhập | Email, mật khẩu, "Quên mật khẩu?", nút Đăng nhập, link Đăng ký | FR-AU-02, UC-02 | Supabase Auth |
| Đăng ký | Tên hiển thị (1–40), email, mật khẩu | FR-AU-01, §10.1 | auth.users + `raw_user_meta_data.display_name` → trigger `handle_new_user` → `profiles.display_name` |
| Quên mật khẩu | Email → "Gửi liên kết"; trạng thái đã gửi | FR-AU-04 | Supabase Auth reset |

## 2. Bản đồ cá nhân (Personal Map) – "MyPlaces · 02 Bản đồ"
| Màn | Trường / hành động | BRD | DB |
|---|---|---|---|
| Bản đồ (có dữ liệu) | Map tối, vị trí hiện tại (nếu cấp quyền), marker ảnh, cluster, badge shared, ô tìm kiếm, nút "+" (Thêm địa điểm), nút định vị | FR-PL-01, BR-02, §11.1 | places(title, category, latitude, longitude, deleted_at null), place_members (shared), visits, memories, memory_attachments |
| Chọn marker → xem trước | Ảnh, tên, chấm danh mục, "4 lần ghé · gần nhất 12 thg 10" → chạm mở Chi tiết | §11.1 "pin mở preview; preview mở Place Detail" | places.title/category; count(visits), max(visits.visited_at) |
| Lọc danh mục | Chip 7 danh mục + Tất cả | BR-03, FR-PL-09 | places.category |
| Tìm kiếm | Kết quả "Địa điểm của bạn" (search text trên places.title/address) + "Trên bản đồ" (MapKit) → chọn để tạo Place | FR-PL-02, FR-PL-09, UC-04 | places.title/address; MapKit → provider='apple', provider_place_id |
| Trống / chưa cấp quyền vị trí | "Chưa có nơi nào" + "Thêm địa điểm"; quyền vị trí bị từ chối không chặn app | FR-PL-01, A4, BRULE-PL-10 | – |

## 3. Địa điểm (Place) – "MyPlaces · 03 Địa điểm"
| Màn | Trường / hành động | BRD | DB |
|---|---|---|---|
| Danh sách địa điểm | Ô tìm, chip danh mục, hàng: ảnh, tên, chấm danh mục, địa chỉ ngắn, badge shared, badge sync | §6.2 Places, FR-PL-09/10, BR-HY-01 | places, place_members |
| Thêm địa điểm (chọn vị trí) | Map + ghim giữa (long-press/tap) + kết quả tìm; Tên*(1–100), Danh mục (mặc định Khác), Địa chỉ (gợi ý reverse-geocode, sửa được), Lưu. KHÔNG có ghi chú/ngày ghé/ảnh ở Place (v1.1 chuyển sang Visit/Memory) | FR-PL-03/04, UC-04, §6.3, §32.2 | places.title, category, latitude, longitude, address, provider, provider_place_id |
| Chi tiết địa điểm | Header: ảnh, tên, danh mục, địa chỉ; vai trò của tôi (Chủ sở hữu/Biên tập/Người xem); danh sách lần ghé (ngày, ảnh, note ngắn); Kỷ niệm của Place (ảnh/note + tác giả + thời gian); Nhật ký liên kết; hành động: Ghi lần ghé (chính), Chia sẻ, Thêm vào nhật ký, Sửa, Xóa (theo quyền) | FR-PL-05, §11.2 (v1.1 thay visited date bằng Visit list), §34.1 | places, visits(visited_at, note), memories(place_id), memory_attachments, journal_places, place_members.role |
| Sửa địa điểm | Tên, danh mục, địa chỉ, vị trí; chỉ Owner | FR-PL-06, §34.6, ERD-02 | places.* (update chỉ owner) |
| Xóa địa điểm (xác nhận) | Cảnh báo: ẩn khỏi bản đồ, có N lần ghé và M nhật ký liên kết; xóa mềm | FR-PL-07, BRULE-PL-09, §34.6 | places.deleted_at |

## 4. Lần ghé & Kỷ niệm (Visit & Memory) – "MyPlaces · 04 Lần ghé & Kỷ niệm"
| Màn | Trường / hành động | BRD | DB |
|---|---|---|---|
| Ghi lần ghé | Place (đã chọn), Thời điểm (mặc định bây giờ) + múi giờ, Ghi chú ngắn (≤1000), Ảnh (tùy chọn, JPEG/PNG/HEIC ≤10MB), Người đi cùng; Lưu | §34.1, §35.1 Visit, BR-HY-02/04 | visits(place_id, visited_at, timezone_id, note); memories(type PHOTO, visit_id)+memory_attachments; visit_participants |
| Thêm người đi cùng | Chọn người đã biết (thành viên đã chia sẻ chung) hoặc nhập tên tự do; ghi chú "Không gửi lời mời, không cấp quyền xem" | ERD-01, §3.4 ERD, BR-HY-04 | visit_participants(user_id \| display_name_snapshot ≤40) |
| Chi tiết lần ghé | Ảnh carousel, tên Place, ngày giờ (theo timezone_id), note, người đi cùng, Kỷ niệm (tác giả + thời gian), Chia sẻ lần ghé, menu Sửa/Xóa | §34.3, FR-SH-10, BR-HY-03 | visits, visit_participants, memories(visit_id), memory_attachments, profiles(display_name, avatar_path) |
| Thêm kỷ niệm | Ngữ cảnh (Place/Lần ghé/Nhật ký), ảnh + note (≤2000), xem trước, trạng thái tải lên | UC-12, §32.3 | memories(type NOTE/PHOTO, body, đúng 1 parent), memory_attachments |

## 5. Dòng thời gian (Personal Timeline) – "MyPlaces · 05 Dòng thời gian"
| Màn | Trường / hành động | BRD | DB |
|---|---|---|---|
| Dòng thời gian | Nhóm theo tháng/ngày; mỗi mục = 1 Visit: ảnh, tên Place, chấm danh mục, giờ, note 1 dòng; không nhân đôi Visit | §34.5, BR-HY-08, §35.1 | visits (owner/member), places (my_visit_places projection), memories |
| Lọc thời gian | Khoảng ngày (đơn giản), danh mục | §35.1 "filter theo thời gian đơn giản", §34.5 | visits.visited_at, places.category |

## 6. Nhật ký (Journal) – "MyPlaces · 06 Nhật ký"
| Màn | Trường / hành động | BRD | DB |
|---|---|---|---|
| Danh sách nhật ký | Ảnh bìa, tiêu đề, khoảng ngày, nhãn Riêng tư/Được chia sẻ + vai trò, mục Đã lưu trữ | FR-JR-03, BRULE-JR-04 | journals(title, cover_path, start_date, end_date, archived_at), journal_members |
| Tạo nhật ký | Tiêu đề* (≤120), mô tả (≤2000), từ ngày/đến ngày (tùy chọn, đến ≥ từ), ảnh bìa; mặc định Riêng tư | UC-07, BRULE-JR-02/03 | journals |
| Chi tiết nhật ký | Bìa, tiêu đề, ngày, avatar thành viên, timeline các Place/Visit liên kết (thiếu ngày ghé → "Ngày thêm"), kỷ niệm (tác giả), nút Thêm (Owner/Editor), Mời, menu (Sửa, Lưu trữ) | FR-JR-06/07/08, UC-13, §34.4 | journal_places/journal_visits (projection journal_place_items/journal_visit_items), memories(journal_id), journal_members |
| Bản đồ nhật ký | Chỉ các Place được liên kết | FR-JR-09 | projection lat/lng |
| Thêm vào nhật ký | Chọn Place/Visit của tôi; mục đã liên kết hiện "Đã có trong nhật ký"; tạo Place mới | UC-08, BR-05 | journal_places / journal_visits UNIQUE |

## 7. Chia sẻ & Quyền (Sharing) – "MyPlaces · 07 Chia sẻ & Quyền"
| Màn | Trường / hành động | BRD | DB / RPC |
|---|---|---|---|
| Mời chia sẻ | Tài nguyên (Place/Lần ghé/Nhật ký), vai trò Biên tập/Người xem (không có Chủ sở hữu), email tùy chọn hoặc link/mã, hạn lời mời, xem trước nội dung sẽ chia sẻ ("Lịch sử lần ghé không được chia sẻ") | FR-SH-01/02, §34.2–34.4, UC-09 | create_invitation; invitations(resource_type, role, invitee_email_normalized, expires_at) |
| Thành viên | Chủ sở hữu, thành viên (vai trò, đổi vai trò, xóa), lời mời đang chờ (thu hồi), "Ngừng chia sẻ", "Chuyển quyền sở hữu"; thành viên thường chỉ thấy "Rời" | FR-SH-04/05/06/07, UC-11, BRULE-JR-13 | *_members, list invitations RPC, change_member_role, remove_member, leave_resource, unshare, transfer_ownership |
| Nhận lời mời | Bìa, tiêu đề, người mời, vai trò; Chấp nhận / Từ chối | FR-SH-03, UC-10 | resolve_invitation, accept/decline_invitation |
| Lời mời không hợp lệ | Hết hạn / đã thu hồi / đã dùng (không lộ dữ liệu) | UC-10 edge cases | PT410/PT409 |
| Xem với quyền Người xem | Place được chia sẻ: không có nút sửa/thêm; không thấy lịch sử lần ghé | FR-SH-09, BR-HY-05, ERD-03 | place_members role VIEWER |

## 8. Cá nhân & Cài đặt – "MyPlaces · 08 Cá nhân & Cài đặt"
| Màn | Trường / hành động | BRD | DB |
|---|---|---|---|
| Cá nhân | Avatar, tên hiển thị, email; Sửa hồ sơ; Cài đặt | FR-AU-05, §6.2 Profile | profiles(display_name, avatar_path) |
| Sửa hồ sơ | Ảnh đại diện, tên (1–40) | FR-AU-05, §10.1 | profiles (client chỉ sửa display_name, avatar_path) |
| Cài đặt | Quyền Vị trí/Ảnh, Đồng bộ (N thao tác đang chờ, Thử lại), Đăng xuất | §6.2, FR-AU-03, §25 | local outbox |

## 9. Gap / mâu thuẫn cần anh quyết
1. **Favorite**: v1.0 §5.1 liệt kê "favorite" trong Place detail, nhưng FR-PL-08 = P1 và backend không có cột favorite → UI P0 không vẽ.
2. **Place.note / visited date / ảnh trên Place** (v1.0 §5.1, UC-04 bước 5) mâu thuẫn v1.1 §32.2 (Visit) – theo v1.1: Thêm địa điểm chỉ có tên/danh mục/địa chỉ/vị trí; note/ngày/ảnh nằm ở Ghi lần ghé. Mockup cũ có note ở Place → đã bỏ.
3. **Tab Chia sẻ / màn "Bạn bè"** trong mockup cũ: friend graph là P1 (§5.2), activity P1 → bỏ tab; thay bằng tab Địa điểm + Dòng thời gian theo §6.2/§35.1. Thanh nav đổi 4 → 5 icon (anh đã duyệt 4 icon trước đó).
4. **Collections** (P1, DEC-11), **Xóa tài khoản / privacy settings** (P1 FR-AU-06/07), **thông báo push** (P1) → không vẽ.
5. **Want to visit vs Visited** (§32.2 "cần phân biệt"): backend chưa có cột trạng thái; UI dùng "chưa có lần ghé" = marker icon danh mục (không ảnh). Cần PO chốt.
6. **Người đi cùng là tài khoản**: BRD cho chọn "account đã biết", nhưng không có friend graph → đề xuất chỉ gợi ý người từng chia sẻ chung + tên tự do.
7. **Múi giờ timeline** (UC-13 cần chốt): UI hiển thị theo timezone_id của Visit.
8. **Hạn lời mời**: BRD yêu cầu expiry nhưng không nêu giá trị → UI cho chọn 1/7/30 ngày (mặc định 7) – cần chốt.
9. Mockup cũ có giá/rating/thống kê/"khoảnh khắc" – đã loại.

## 10. Trạng thái (17/11/2026)
Anh Huy đã duyệt toàn bộ đề xuất ở mục 0 và mục 9 (nav 5 icon, chưa có lần ghé = muốn đến, chưa có Yêu thích, gợi ý người đi cùng, hạn lời mời 1/7/30 mặc định 7, timeline theo timezone_id). Toàn bộ UI đã gom vào một project Stitch: https://stitch.withgoogle.com/projects/12999899683389188794
