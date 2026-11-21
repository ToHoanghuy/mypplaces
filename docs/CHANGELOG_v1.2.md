# MyPlaces – Changelog v1.2 (17/11/2026)

## 1. Sáu quyết định đã chốt và tác động backend

| ID | Quyết định | Có đổi backend? | Tác động |
|---|---|---|---|
| UI-01 | Điều hướng 5 tab | Không | Không đổi schema. Dòng thời gian dùng RPC mới my_timeline (xem UI-06). |
| UI-02 | Muốn đến / Đã ghé | Có | Thêm view map_places (security_invoker) trả visit_count, last_visited_at, visit_status, ảnh bìa. Không thêm cột vào places. |
| UI-03 | Yêu thích (favorite) | Không | Không đổi. DB không có cột favorite. |
| UI-04 | Chọn người đi cùng | Có | Thêm RPC list_companion_suggestions (SECURITY INVOKER). Policy thêm visit_participants giữ nguyên. |
| UI-05 | Hạn lời mời | Có | create_invitation chỉ nhận p_ttl = 1, 7 hoặc 30 ngày (trước đây nhận mọi giá trị trong (0, 30 ngày]); giá trị khác trả PT400 INVALID_EXPIRY. |
| UI-06 | Múi giờ trên Dòng thời gian | Có (RPC hiển thị; schema đã đủ) | visits.timezone_id đã có (NOT NULL, kiểm IANA, không default – client gửi múi giờ khi tạo). Thêm RPC my_timeline trả visited_local. |

## 2. Backend / database (Supabase `ektlcjoxnjlyiyzzzjob`)

- `20261117000001_map_places_view.sql` – Tạo view map_places (UI-02).
- `20261117000002_timeline_and_companion_rpcs.sql` – Tạo RPC my_timeline (UI-06) và list_companion_suggestions (UI-04).
- `20261117000003_invitation_ttl_options.sql` – create_invitation chỉ nhận hạn 1/7/30 ngày (UI-05).
- `20261117000004_companion_suggestions_invoker.sql` – Chuyển list_companion_suggestions sang SECURITY INVOKER sau khi security advisor cảnh báo.

Đối tượng mới/thay đổi:

- **public.map_places** (View (security_invoker = true)): Bản đồ cá nhân: Place còn hiệu lực mà user đọc được + is_owner, my_role, is_shared, visit_count, last_visited_at, visit_status (VISITED / WANT_TO_VISIT), cover_memory_id, cover_storage_path. Quyền: Chạy bằng quyền của người gọi nên RLS của places/visits/memories/memory_attachments/place_members áp dụng đầy đủ. Viewer/Editor của Place chỉ đếm Visit của chính họ hoặc Visit được chia sẻ riêng (ERD-03). Chỉ authenticated được SELECT.
- **public.my_timeline(p_from, p_to, p_category, p_visit_id, p_limit)** (RPC (SECURITY DEFINER, search_path rỗng)): Dòng thời gian: Visit còn hiệu lực mà user sở hữu hoặc là thành viên ACTIVE, mới nhất trước; mỗi dòng có timezone_id, visited_local (giờ địa phương theo timezone_id), note, my_role, projection tối thiểu của Place (title, category, tọa độ), place_available, ảnh bìa của Visit. Lọc theo khoảng ngày [from, to), danh mục; giới hạn 1–500 dòng. Quyền: Tự lọc theo auth.uid(). Visit owner luôn thấy projection Place (D3, kể cả Place đã xóa mềm). Visit member chỉ thấy projection khi Place còn hiệu lực. Không trả address/provider, không trả sibling Visit; RLS của places không mở rộng.
- **public.list_companion_suggestions(p_query, p_limit)** (RPC (SECURITY INVOKER)): Gợi ý người đi cùng: user_id, display_name, avatar_path, last_shared_at. Lọc theo chuỗi con của tên (không dùng ký tự đại diện), giới hạn 1–100. Quyền: Chạy bằng quyền người gọi; mọi kết quả đều thỏa private.can_read_profile, tức đúng tập mà policy thêm visit_participants chấp nhận. Không gửi lời mời, không cấp quyền.
- **public.create_invitation(..., p_ttl)** (RPC hiện có – sửa): Hạn lời mời chỉ nhận 1 ngày, 7 ngày (mặc định) hoặc 30 ngày. Quyền: Chữ ký, quyền EXECUTE, audit giữ nguyên; chỉ đổi điều kiện kiểm tra p_ttl.

Không thêm cột/bảng nào; không có cột trạng thái hay favorite. Nguyên tắc giữ nguyên: RLS, xóa mềm `deleted_at`, timestamp do server, client chỉ sửa `profiles.display_name`/`avatar_path`.

**Lưu ý cần xác nhận:** `my_timeline` cho Visit member thấy projection tối thiểu của Place (title, category, toạ độ) khi Place còn hiệu lực – mở rộng có kiểm soát so với điểm tự quyết #3 trước đây (chỉ Visit owner thấy Place). RLS của bảng `places` không đổi.

## 3. Kiểm thử và advisor

- Local: 460/460 assertion pass (8 file; 399 cũ + 61 mới trong `07_ui_v1_1_support.test.sql`).
- Live (transaction + rollback): 36 + 80 + 54 + 69 + 112 + 45 + 61 = 457/457 pass; không để lại dữ liệu test.
- Security advisor: cảnh báo DEFINER mới của `list_companion_suggestions` đã xử lý bằng migration 000004 (INVOKER). Còn lại: `my_timeline` SECURITY DEFINER (có chủ đích, cùng nhóm 14 RPC hiện có) và `auth_leaked_password_protection` (bật trong Auth dashboard nếu muốn).
- Performance advisor: chỉ INFO `unused_index` (DB chưa có dữ liệu).

## 4. BRD v1.2 – `MyPlaces_BRD_v1.2.docx`

| # | Mục | Thay đổi |
|---|---|---|
| 1 | Bìa – Phiên bản | 1.1 → 1.2. |
| 2 | Bìa – Ngày lập | Thêm ngày cập nhật 17/11/2026. |
| 3 | Bìa – Trạng thái | Ghi nhận 6 quyết định đã chốt. |
| 4 | 1.1 Lịch sử phiên bản | Thêm dòng 1.2. |
| 5 | 5. Phạm vi – Place detail | Bỏ favorite khỏi MVP; note/ảnh/ngày ghé nằm ở Visit. |
| 6 | 6.2 Điều hướng cấp cao | Đổi thành 5 tab Bản đồ · Địa điểm · Dòng thời gian · Nhật ký · Cá nhân; Activity giữ P1, không phải tab; chia sẻ là hành động trong từng mục. |
| 7 | 9. BRULE-JR-09 | Thêm quy tắc hạn lời mời 1/7/30 ngày, mặc định 7. |
| 8 | 11. FR-PL-08 | Ghi rõ favorite chưa làm trong MVP. |
| 9 | 11.1 Hành vi Map | Thêm quy tắc pin ảnh và pin 'Muốn đến'. |
| 10 | 11.2 Place Detail | Bỏ favorite khỏi header; nội dung lấy từ danh sách Visit theo §32.2. |
| 11 | 12. Timeline rules | Hiển thị theo timezone_id của từng Visit. |
| 12 | 13. FR-SH-01 | Ghi rõ lựa chọn hạn lời mời. |
| 13 | 18. UC-13 | Chốt cách nhóm theo ngày. |
| 14 | 30. DEC-07 (v1.0) | Đóng câu hỏi timezone. |
| 15 | 32.2 Nguyên tắc Place và Visit | Chốt quy tắc suy ra Muốn đến/Đã ghé. |
| 16 | 33.4 Invitation lifecycle | Ghi rõ hạn lời mời ở trạng thái EXPIRED. |
| 17 | 34.1 Workflow A | Ghi rõ nguồn gợi ý người đi cùng. |
| 18 | 34.2 Workflow B | Ghi rõ lựa chọn hạn lời mời. |
| 19 | 34.5 Workflow E | Ghi rõ cách hiển thị múi giờ. |
| 20 | 38. Decision log | Thêm 6 quyết định UI-01..UI-06 ở trạng thái Selected. |
| 21 | 40. Change control | Thêm quy tắc ưu tiên mục 41. |
| 22 | 41 (mới) | Thêm mục 41: 6 quyết định, điều hướng, quy tắc trạng thái, hạn lời mời, nguồn gợi ý người đi cùng, hiển thị múi giờ, view/RPC mới. |

## 5. ERD & Permission Design v1.2 – `MyPlaces_ERD_Permission_v1.2.docx`

| # | Mục | Thay đổi |
|---|---|---|
| 1 | Bìa | v1.1 → v1.2. |
| 2 | Bìa – Ngày | Cập nhật 17/11/2026. |
| 3 | 1. Mục tiêu và phạm vi | Trỏ tới mục 13 (v1.2). |
| 4 | 3.2 places | Ghi rõ không có cột trạng thái/favorite; trạng thái suy ra từ Visit. |
| 5 | 3.3 visits – timezone_id | Ghi rõ NOT NULL, kiểm IANA, dùng để hiển thị trên Dòng thời gian. |
| 6 | 3.4 visit_participants | Thêm nguồn gợi ý người đi cùng. |
| 7 | 3.8 invitations – expires_at | Hạn lời mời chỉ 1/7/30 ngày, mặc định 7. |
| 8 | 5.3 Access rules – Visit | Ghi ngoại lệ projection Place tối thiểu trên Dòng thời gian. |
| 9 | 6.3 RLS test cases | Thêm 5 test case cho view/RPC v1.2. |
| 10 | 9. API boundaries | Thêm map_places, my_timeline, list_companion_suggestions. |
| 11 | 10. Decisions | Thêm ERD-09..ERD-13. |
| 12 | Document status | Cập nhật trạng thái v1.2. |
| 13 | 13 (mới) | Thêm mục 13: quyết định, đối tượng mới, migration và kiểm thử. |

## Bổ sung 20/11/2026 – Tìm kiếm dự phòng Overture Maps

- `20261120000001_poi_overture_fallback.sql` – extension `pg_trgm`, `unaccent` (schema `extensions`); `private.vn_norm()`; bảng `public.poi_overture` (id, name, category, address, latitude, longitude, confidence + cột sinh `name_norm`, `search_norm`), `public.poi_overture_imports`; RLS chỉ đọc cho `authenticated`; index GIN trigram + GiST vị trí; RPC `search_pois`.
- `20261120000002_search_pois_coverage.sql` – xếp hạng thêm 0.15 × tỉ lệ từ khoá có mặt nguyên từ trong tên + địa chỉ.
- `20261120000003_search_pois_short_query_guard.sql` – q ≥ 3 ký tự sau chuẩn hoá; truy vấn ngắn có vị trí chỉ tìm trong ~28 km; giới hạn 10.000 ứng viên. Thời gian xấu nhất trên DB thật: 14 s ("ph") → ~1 s ("nhà hàng").
- Dữ liệu: 422.329 POI (Overture `2026-11-18.0`, lọc Việt Nam, ngưỡng confidence theo danh mục, bỏ tên rác, gộp trùng 30 m). Script: `scripts/overture/build_vn_pois.py`.
- iOS: `POISearch.swift` (model, quy tắc gộp/bỏ trùng, cache), mục "Gợi ý thêm" trong màn tìm kiếm, điền sẵn form Thêm địa điểm (cả danh mục), Cá nhân › Giới thiệu ghi nguồn dữ liệu.
- Test: pgTAP `08_poi_overture_search.test.sql` (31), `SearchMergeTests` (9), `H10SearchFallbackUITests` (2).

## Bổ sung 21/11/2026 – Nén ảnh trước khi tải lên

- iOS: `ImageCompressor.swift` (ImageIO `CGImageSourceCreateThumbnailAtIndex`, cạnh dài ≤ 1600 px, không phóng to, áp dụng hướng EXIF, mã hoá lại chỉ từ điểm ảnh nên không còn EXIF/GPS, JPEG 0,7 → tối thiểu 0,5 nếu > 500 KB, chạy ngoài main thread). `ImageProcessing` dùng bộ nén này cho PhotosPicker và ảnh mẫu QA; upload vẫn là `image/jpeg`, đường dẫn `.jpg`.
- Đo thật (6 ảnh mẫu của simulator, gốc 1,27–2,81 MB): cũ 432/488/1029/707/754/1344 KB → mới 248/262/434/390/399/464 KB.
- `20261121000001_media_size_limit_2mb.sql` – bucket `memory-media` giới hạn 2 MB (trước 10 MB), ràng buộc `memory_attachments.size_bytes` ≤ 2 MB; MIME giữ nguyên. Object lớn nhất hiện có 970 KB.
- Test: `ImageCompressorTests` (8), pgTAP 06 (46). Local 492/492.


## Bổ sung 21/11/2026 – Giao diện Liquid Glass (iOS 26)

- Kế hoạch và quyết định từng màn: `docs/design/LIQUID_GLASS_PLAN.md`. Kính chỉ dùng cho lớp điều hướng và điều khiển nổi; thẻ nội dung giữ nền đặc; không đặt kính chồng lên kính.
- Lớp design system `DesignSystem/Glass.swift`: `mpGlass`, `MPGlassGroup` (GlassEffectContainer), `mpGlassButton`, `mpProminentButton`, `mpScrollEdgeSoft`, `mpBackgroundExtension`, `mpSheetBackground`, `mpSheetContentBackground`. Mọi API iOS 26 nằm sau `if #available(iOS 26, *)`; deployment target vẫn iOS 17.
- iOS 26: tab bar hệ thống (`TabView` + `Tab`, thu nhỏ khi cuộn xuống), ẩn ở màn chi tiết; CTA là glass tô cam; nút tròn, chip lọc và ô tìm trên bản đồ là glass; panel Thêm địa điểm nổi dạng glass; sheet thấp dùng nền glass hệ thống; hộp xác nhận và toast dạng glass.
- iOS 17–25: tab bar nổi tự vẽ nền vật liệu mờ; CTA viên đặc như cũ; bật "Giảm độ trong suốt" thì mọi nền kính thành nền đặc.
- Không đổi backend, chuỗi tiếng Việt hay accessibility identifier. Test UI tìm nút tab hệ thống theo vị trí.
- Ảnh trước/sau (16 màn × sáng/tối): `docs/screenshots/liquid-glass/` (`before_*`, `after_*`), test `I11ScreensUITests`.

## Bổ sung 21/11/2026 – Liquid Glass vòng 2

- Tab Địa điểm / Dòng thời gian / Nhật ký / Cá nhân dùng tiêu đề lớn hệ thống thu gọn khi cuộn; nút trên toolbar; tìm trong Địa điểm bằng `.searchable`; chip cuộn cùng danh sách.
- Menu "…" trên ảnh bìa và nút Thành viên trong sheet chia sẻ dùng chung nút tròn glass.
- Đã chạy thử trên máy ảo iOS 18.6 (giao diện dự phòng) và chụp ảnh Dynamic Type cỡ lớn / Giảm độ trong suốt (`I12AccessibilityUITests`).
- UI test không còn phụ thuộc dữ liệu QA còn sót: B02 test00 tự tạo rồi xoá địa điểm tạm; test01/02 chỉ tạo dữ liệu mẫu còn thiếu (bỏ qua nếu đã có); test04 sửa được cả tên gốc lẫn tên đã đổi; C04 dùng ghi chú gắn mã chạy và tự xoá lần ghé đã tạo; D05 tạo nhật ký tên riêng rồi tự xoá; E07 cho user B rời địa điểm / nhật ký trước khi nhận lời mời lại.
- Ảnh: `docs/screenshots/liquid-glass/r2_*` (iOS 26), `ios18/` (iOS 18.6, dự phòng), `a11y/` (chữ cỡ lớn, Giảm độ trong suốt).
