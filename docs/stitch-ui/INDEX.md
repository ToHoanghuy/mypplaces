# MyPlaces – UI v1.1 (BRD) – Stitch

**Project duy nhất:** [MyPlaces – UI v1.1 (BRD)](https://stitch.withgoogle.com/projects/12999899683389188794) · id `12999899683389188794` · riêng tư · design system MyPlaces Minimal `assets/8094474840949808557` · 33 màn hình MOBILE.

Canvas: mỗi hàng là một module (01 → 08), nhãn dạng `02a · Bản đồ cá nhân`. Các màn là bản sao y hệt (cùng HTML + ảnh chụp) của bản đã duyệt. 8 project theo chức năng và project cũ `6102707061560221409` đã được xóa ngày 17/11/2026 theo yêu cầu của anh.

Quyết định đã duyệt (17/11/2026): nav 5 icon (Bản đồ · Địa điểm · Dòng thời gian · Nhật ký · Cá nhân); địa điểm chưa có lần ghé = "muốn đến"; chưa có Yêu thích (P1); người đi cùng gợi ý từ người từng chia sẻ + tên tự do; hạn lời mời 1/7/30 ngày (mặc định 7); timeline theo `timezone_id` của từng lần ghé.

Bản đồ BRD → màn hình: `brd-screen-map.md`. PNG/HTML: các thư mục con bên dưới.

## 01 Tài khoản (hàng 1)

| Màn hình | File | Stitch screen id | BRD | Bảng DB |
|---|---|---|---|---|
| 01a · Giới thiệu | 01-tai-khoan/01a-gioi-thieu.png / .html | 958f313389964ae886ea2b0ce9152475 | §4.1 Guest, §6.1, DEC-01 | – |
| 01b · Đăng nhập | 01-tai-khoan/01b-dang-nhap.png / .html | cf0a7e664e9c4273a94a6dc518b7d5ac | FR-AU-02, UC-02 | auth.users (Supabase Auth) |
| 01c · Đăng ký | 01-tai-khoan/01c-dang-ky.png / .html | 8aebb6f6c7004397a25e9855127187b9 | FR-AU-01, FR-AU-05, §10.1 | auth.users, profiles.display_name (trigger handle_new_user) |
| 01d · Quên mật khẩu | 01-tai-khoan/01d-quen-mat-khau.png / .html | b5407fb573b1436e80270b0fba331a59 | FR-AU-04 | Supabase Auth reset |

## 02 Bản đồ (hàng 2)

| Màn hình | File | Stitch screen id | BRD | Bảng DB |
|---|---|---|---|---|
| 02a · Bản đồ cá nhân | 02-ban-do/02a-ban-do.png / .html | 1527e1dd64c040ae92c0b3ec7ebb78b8 | FR-PL-01, BR-02, §11.1 | places, place_members, visits, memories, memory_attachments |
| 02b · Xem trước địa điểm | 02-ban-do/02b-xem-truoc.png / .html | 95728a7f1a934598b0d3058daa3a70bb | §11.1 (pin → preview → Place Detail) | places.title/category/address; count(visits), max(visits.visited_at) |
| 02c · Lọc theo danh mục | 02-ban-do/02c-loc-danh-muc.png / .html | 40e0714ff7fa478d898a77b33c9dc862 | BR-03, FR-PL-09 | places.category (enum place_category) |
| 02d · Tìm kiếm | 02-ban-do/02d-tim-kiem.png / .html | 43642fa0bac94b02ac1b3d902631e251 | FR-PL-02, FR-PL-09, UC-04 | places.title/address; MapKit → places.provider/provider_place_id |
| 02e · Bản đồ trống | 02-ban-do/02e-trong.png / .html | ba89580c92b5471db6f9d9fb54ff3ae4 | FR-PL-01, UC-04 A1/A4 | – |

## 03 Địa điểm (hàng 3)

| Màn hình | File | Stitch screen id | BRD | Bảng DB |
|---|---|---|---|---|
| 03a · Danh sách địa điểm | 03-dia-diem/03a-danh-sach.png / .html | 0615caf635284ab98c39162d1e8c8ecd | §6.2 Places, FR-PL-09/10, BR-HY-01 | places(title, category, address), place_members, visits count, local sync state |
| 03b · Thêm địa điểm | 03-dia-diem/03b-them-dia-diem.png / .html | 1a4453de74f24a649703501fd32afa7c | FR-PL-03/04, UC-04, §6.3, §32.2 | places.title, category, latitude, longitude, address, provider, provider_place_id |
| 03c · Chi tiết địa điểm | 03-dia-diem/03c-chi-tiet.png / .html | 7fbf0f3f204e4efbb936d0883473fecb | FR-PL-05, §11.2, §34.1 | places, visits(visited_at, note), visit_participants, memories, memory_attachments, journal_places |
| 03d · Sửa địa điểm | 03-dia-diem/03d-sua-dia-diem.png / .html | 9f6fc3b1cbe542e6b06c2f6896a41391 | FR-PL-06, UC-06, ERD-02 | places.title, category, address, latitude, longitude |
| 03e · Xác nhận xóa | 03-dia-diem/03e-xoa-dia-diem.png / .html | 5d908d2520834a3da26f53ebed009a4d | FR-PL-07, BRULE-PL-09, §34.6 | places.deleted_at (soft delete); visits, journal_places counts |

## 04 Lần ghé & Kỷ niệm (hàng 4)

| Màn hình | File | Stitch screen id | BRD | Bảng DB |
|---|---|---|---|---|
| 04a · Ghi lần ghé | 04-lan-ghe-ky-niem/04a-ghi-lan-ghe.png / .html | e1279ec6b1af4d83b1169af04795e5e9 | §34.1 Workflow A, §35.1 Visit, BR-HY-02/04 | visits(place_id, visited_at, timezone_id, note), memories(PHOTO, visit_id), memory_attachments, visit_participants |
| 04b · Thêm người đi cùng | 04-lan-ghe-ky-niem/04b-nguoi-di-cung.png / .html | 860ed7ecab3245019b0dc2548d1ddc4f | ERD-01, BR-HY-04, §36.1 participant vs member | visit_participants(user_id | display_name_snapshot) |
| 04c · Chi tiết lần ghé | 04-lan-ghe-ky-niem/04c-chi-tiet-lan-ghe.png / .html | ceb44e60a48b4329b5e1937da76f7634 | §34.3, BR-HY-03, FR-SH-10 | visits, visit_participants, memories(visit_id, author_id, body, created_at), memory_attachments, profiles |
| 04d · Thêm kỷ niệm | 04-lan-ghe-ky-niem/04d-them-ky-niem.png / .html | 40801ad726a5432392e7ca6426ef9011 | UC-12, §32.3, BR-HY-03 | memories(type NOTE/PHOTO, body, exactly one parent), memory_attachments(mime, size) |

## 05 Dòng thời gian (hàng 5)

| Màn hình | File | Stitch screen id | BRD | Bảng DB |
|---|---|---|---|---|
| 05a · Dòng thời gian | 05-dong-thoi-gian/05a-dong-thoi-gian.png / .html | d06d88f2ef9642c9acb1ea2e5d848107 | §34.5 Workflow E, BR-HY-08, §35.1 | visits(visited_at, timezone_id, note), places (my_visit_places), memories, memory_attachments |
| 05b · Lọc dòng thời gian | 05-dong-thoi-gian/05b-loc.png / .html | 43d7e6d1524c46f48481cfe4b9f3d3b7 | §35.1 (filter thời gian), §34.5 | visits.visited_at, places.category |

## 06 Nhật ký (hàng 6)

| Màn hình | File | Stitch screen id | BRD | Bảng DB |
|---|---|---|---|---|
| 06a · Danh sách nhật ký | 06-nhat-ky/06a-danh-sach-nhat-ky.png / .html | db806b812331417c866052bdf996ad04 | FR-JR-03, BRULE-JR-04, §34.4 | journals(title, cover_path, start_date, end_date, archived_at), journal_members(role) |
| 06b · Tạo nhật ký | 06-nhat-ky/06b-tao-nhat-ky.png / .html | 0d62d9d6c9b349318fafaaa43b99b9bb | UC-07, FR-JR-01/02, BRULE-JR-02/03/04 | journals(title, description, cover_path, start_date, end_date) |
| 06c · Chi tiết nhật ký | 06-nhat-ky/06c-chi-tiet-nhat-ky.png / .html | 4ef2d6d526d0426cb62765e4d335b4a7 | FR-JR-06/07/08, UC-13, §34.4 | journal_place_items / journal_visit_items projections, memories(journal_id), journal_members, profiles |
| 06d · Bản đồ nhật ký | 06-nhat-ky/06d-ban-do-nhat-ky.png / .html | b85c7d98fee84ee690de122075d42ac6 | FR-JR-09, UC-13 | journal_place_items/journal_visit_items (title, category, latitude, longitude, visited_at) |
| 06e · Thêm vào nhật ký | 06-nhat-ky/06e-them-vao-nhat-ky.png / .html | 96a7aa923c204e7fb8488c3159539937 | UC-08, BR-05, FR-JR-04 | journal_places / journal_visits (UNIQUE), places, visits |

## 07 Chia sẻ & Quyền (hàng 7)

| Màn hình | File | Stitch screen id | BRD | Bảng DB |
|---|---|---|---|---|
| 07a · Mời chia sẻ | 07-chia-se-quyen/07a-moi-chia-se.png / .html | 04fdb5735aa14f08b210624a844bd767 | FR-SH-01/02, §34.2, UC-09, BR-HY-05 | create_invitation → invitations(resource_type, role, invitee_email_normalized, expires_at) |
| 07b · Thành viên | 07-chia-se-quyen/07b-thanh-vien.png / .html | 7e88e4b9400c4ffca323108381c82dd9 | FR-SH-04/05/06, UC-11, BRULE-JR-06/11 | journal_members(role, status), invitations(status PENDING, expires_at), RPC change_member_role/remove_member/revoke_invitation/unshare/transfer_ownership |
| 07c · Nhận lời mời | 07-chia-se-quyen/07c-nhan-loi-moi.png / .html | 4309f39fc85b4c8ea9d0aaa1ff2c36bd | FR-SH-03, UC-10 | resolve_invitation (title, cover, inviter display_name, role) → accept_invitation / decline_invitation |
| 07d · Lời mời không hợp lệ | 07-chia-se-quyen/07d-loi-moi-het-han.png / .html | 852a884313704a0dae4fcdf21fcea562 | UC-10 edge cases, §33.4 | invitations.status EXPIRED/REVOKED/ACCEPTED (PT410/PT409) |
| 07e · Địa điểm được chia sẻ (Người xem) | 07-chia-se-quyen/07e-xem-voi-quyen-xem.png / .html | 651aa276d4c64e12842327f951fede48 | FR-SH-09, BR-HY-05, ERD-03, FR-SH-07 | places (RLS member read), place_members(role VIEWER), memories(place_id), leave_resource |

## 08 Cá nhân & Cài đặt (hàng 8)

| Màn hình | File | Stitch screen id | BRD | Bảng DB |
|---|---|---|---|---|
| 08a · Cá nhân | 08-ca-nhan-cai-dat/08a-ca-nhan.png / .html | c3271a3be1f44a5482cc230f3e7b4209 | FR-AU-05, FR-AU-03, §6.2 Profile | profiles(display_name, avatar_path), auth email |
| 08b · Sửa hồ sơ | 08-ca-nhan-cai-dat/08b-sua-ho-so.png / .html | 53de7c54dc684c5db6728e8d95ab1561 | FR-AU-05, §10.1 | profiles.display_name (1–40), profiles.avatar_path |
| 08c · Đồng bộ & quyền | 08-ca-nhan-cai-dat/08c-dong-bo.png / .html | 9529565a029149988e29ead81f3af3c3 | FR-PL-10, BR-12, §25.2, BRULE-PL-10 | local outbox (sync states), iOS permissions |
