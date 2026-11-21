# MyPlaces – Kế hoạch chuyển giao diện sang Liquid Glass (21/11/2026)

Mục tiêu: theo ngôn ngữ thiết kế Liquid Glass của Apple (iOS 26, SDK Xcode 26.4) mà vẫn giữ tinh thần
"MyPlaces Minimal" kiểu Locket: ảnh là trung tâm, ít chữ, màu cam san hô dùng tiết kiệm, tiếng Việt, sáng/tối/tự động.

## 1. Nguyên tắc (theo HIG)

1. **Glass chỉ cho lớp điều hướng & điều khiển nổi trên nội dung**: tab bar, thanh công cụ, nút tròn nổi trên ảnh/bản đồ,
   ô tìm kiếm nổi, chip lọc nổi trên bản đồ, toast, bảng điều khiển nổi trên bản đồ. **Không** phủ glass lên thẻ nội dung
   (danh sách địa điểm, thẻ nhật ký, ô nhập liệu trong form) – những thứ đó giữ nền `Theme.surface` đặc.
2. **Không chồng glass lên glass.** Các nút nổi gần nhau được gom trong `GlassEffectContainer` để hoà/morph với nhau
   thay vì xếp nhiều lớp.
3. **Ưu tiên thành phần hệ thống** (TabView, toolbar, sheet) vì iOS 26 tự áp glass; bỏ các thanh/nền tự vẽ đang
   "đánh nhau" với glass hệ thống (tab bar nổi tự vẽ, nền mờ tự chồng).
4. **Màu**: glass trung tính; chỉ hành động chính dùng `.glassProminent` tô màu `Theme.accent`.
   Không tô màu cho mọi nút.
5. **Khả năng tiếp cận**: hệ thống tự xử lý *Giảm độ trong suốt* / *Tăng độ tương phản* cho glass trên iOS 26;
   bản dự phòng (iOS 17–25) đổi sang nền đặc `Theme.surface` khi bật Giảm độ trong suốt. Giữ nguyên Dynamic Type,
   accessibility identifier, nhãn VoiceOver.

## 2. Lớp design system (một chỗ, call site gọn)

File mới `Presentation/DesignSystem/Glass.swift`:

| API | iOS 26 | iOS 17–25 (dự phòng) |
|---|---|---|
| `.mpGlass(in: shape, interactive:, tint:)` | `.glassEffect(.regular[.tint][.interactive], in:)` | `.ultraThinMaterial` + viền hairline; Giảm độ trong suốt → `Theme.surface` |
| `MPGlassGroup(spacing:)` | `GlassEffectContainer` | `Group` |
| `.mpGlassButton()` / `.mpGlassProminentButton()` | `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` + `tint(accent)` | ButtonStyle tự viết: material / nền cam |
| `.mpScrollEdgeSoft()` | `.scrollEdgeEffectStyle(.soft, for: .top)` | không làm gì |
| `.mpBackgroundExtension()` | `.backgroundExtensionEffect()` | không làm gì |
| `.mpTabBarMinimize()` | `.tabBarMinimizeBehavior(.onScrollDown)` | không làm gì |

Các thành phần sẵn có được chuyển sang lớp này: `CircleIconButton` (nút tròn trên ảnh/bản đồ → glass tròn, tương tác),
`PillButton` ("Lưu/Đăng/Tạo" → glass prominent cam), `PrimaryButton` (CTA cuối màn hình → glass prominent cam;
tone `.surface` → glass trung tính), `Chip` (thêm biến thể `floating` cho chip nằm trên bản đồ), `SearchField`
(biến thể `floating`), `ModalBar` (nút Hủy thành nút glass tròn "xmark", hành động là glass prominent),
toast và `ConfirmCard` (glass như alert iOS 26).

## 3. Từng màn hình

| Màn hình | Thay đổi |
|---|---|
| **Khung tab** | iOS 26: `TabView` hệ thống (glass tự động, thu nhỏ khi cuộn xuống, giữ trạng thái từng tab), ẩn tab bar ở màn chi tiết như hiện tại. iOS 17–25: giữ tab bar nổi tự vẽ nhưng dùng `.mpGlass`. |
| **Chào mừng / Đăng nhập / Đăng ký** | Ảnh nền tràn viền giữ nguyên; nút chính glass prominent; nút quay lại glass tròn. Ô nhập liệu giữ nền đặc (nội dung). |
| **Bản đồ** | Ô "Tìm địa điểm", hàng chip lọc, nút định vị và nút "+" thành các phần tử glass nổi, gom trong `GlassEffectContainer`. Thẻ xem nhanh địa điểm là nội dung → nền đặc, bo góc lớn. |
| **Tìm kiếm (kể cả "Gợi ý thêm")** | Ô tìm kiếm glass ở đầu màn, nút Hủy glass; danh sách kết quả giữ dạng plain list; `scrollEdgeEffect` mềm dưới ô tìm kiếm. |
| **Thêm địa điểm** | Bản đồ tràn viền; thanh trên (Hủy + ô tìm) glass; bảng thông tin nổi trên bản đồ dùng glass (như bảng Apple Maps iOS 26); nút "Lưu địa điểm" glass prominent. |
| **Danh sách địa điểm** | Tiêu đề lớn; ô tìm và nút "+" glass; thẻ địa điểm giữ nền đặc. |
| **Chi tiết địa điểm / lần ghé / nhật ký** | Ảnh bìa tràn viền với `backgroundExtensionEffect`; nút quay lại / chia sẻ / thêm thành glass tròn gom nhóm; CTA cuối ("Ghi lần ghé", "Thêm kỷ niệm") glass prominent; nội dung giữ nền đặc. |
| **Form (ghi lần ghé, thêm kỷ niệm, sửa địa điểm, tạo nhật ký, chia sẻ)** | Thanh trên: nút xmark glass + tiêu đề + nút hành động glass prominent; trường nhập giữ nền đặc. |
| **Dòng thời gian / Nhật ký** | Tiêu đề lớn + nút lọc/"+" glass; thẻ giữ nguyên (ảnh là nội dung). |
| **Thành viên / Đồng bộ / Cá nhân** | Nút quay lại glass; nhóm cài đặt giữ nền đặc kiểu inset-grouped; nút "Mời thêm" glass prominent. |

## 4. Không làm trong đợt này

* Không đổi luồng/IA, không thêm tab tìm kiếm (5 tab + tab tìm kiếm sẽ chật; Bản đồ đã có ô tìm) – xem câu hỏi mở.
* Không đổi màu thương hiệu, font (SF), không thêm animation morph phức tạp ngoài nhóm nút nổi.

## 5. Kiểm tra

* Ảnh trước/sau: `docs/screenshots/liquid-glass/` (`before_*`, `after_*`, sáng & tối, 16 màn mỗi chế độ, test `I11ScreensUITests`).
* Unit + UI test đầy đủ; giữ mọi accessibility identifier (riêng tab hệ thống iOS 26: helper test tìm nút tab theo vị trí).

## 6. Kết quả triển khai (21/11/2026)

Đã làm theo kế hoạch, với vài điều chỉnh khi xem ảnh chụp thật:

| Màn hình | Đã làm | Khác kế hoạch |
|---|---|---|
| Khung tab | iOS 26: `TabView(selection:)` + `Tab(...)`, `.tabBarMinimizeBehavior(.onScrollDown)`, tint cam; ẩn tab bar ở mọi màn chi tiết (`Router.appRoutes`). iOS 17–25: tab bar nổi cũ, nền `.mpGlass`. | `Theme.tabInset`: trên iOS 26 tab bar hệ thống đã nằm trong safe area nên bỏ khoảng đệm 74 pt tự thêm trước đây. |
| Chào mừng / Đăng nhập | CTA "Tạo tài khoản", "Đăng nhập" là glass tô cam (`PrimaryButton`); nút quay lại glass tròn. | — |
| Bản đồ | Ô "Tìm địa điểm" glass (cao 48), chip lọc glass nổi (chip đang chọn giữ nền đặc để dễ đọc), nút định vị + nút "+" gom trong `GlassEffectContainer`; "+" là `FloatingActionButton` glass tô cam. Thẻ xem nhanh giữ nền đặc. | — |
| Tìm kiếm | Ô tìm glass + nút "Hủy" glass, kết quả dạng danh sách, `scrollEdgeEffectStyle(.soft)`. | — |
| Thêm địa điểm | Thanh trên: "Hủy" glass + ô tìm glass; bảng thông tin thành panel glass nổi, cách mép 8 pt, bo 34 (giống bảng Apple Maps). | Trường nhập và chip danh mục trong panel giữ nền đặc (tránh glass chồng glass). |
| Danh sách / Dòng thời gian / Nhật ký / Cá nhân | Giữ tiêu đề lớn tự vẽ; nút "+", lọc, cài đặt thành glass tròn; thẻ nội dung giữ nền đặc. | Không chuyển sang navigation bar hệ thống: ô tìm + hàng chip nằm ngoài vùng cuộn nên tiêu đề lớn hệ thống không thu gọn được, lợi ích nhỏ mà phải đổi nhiều test. |
| Chi tiết địa điểm / lần ghé / nhật ký | Nút quay lại / chia sẻ / "…" là glass tròn trên ảnh bìa; CTA "Ghi lần ghé", "Thêm kỷ niệm" glass tô cam; nút "+" của nhật ký là `FloatingActionButton`. | Chưa dùng `backgroundExtensionEffect`: ảnh bìa đã tràn lên vùng status bar, hiệu ứng phản chiếu không thêm gì. |
| Form | Thanh trên: nút "Hủy" glass dạng viên (giữ chữ, id `modal.cancel`) + nút hành động glass tô cam. | Giữ chữ "Hủy" thay vì icon xmark – rõ nghĩa hơn với tiếng Việt và giữ nguyên test. |
| Sheet thấp (lọc dòng thời gian, chọn nhật ký, chọn ngày, nhập mã mời) | iOS 26: dùng nền sheet glass của hệ thống (`mpSheetBackground`, `mpSheetContentBackground`). iOS < 26: nền đặc như cũ. | — |
| Hộp xác nhận, toast | Glass (bo 32) như alert iOS 26; nền mờ phía sau 40%. | — |

Fallback iOS 17–25: vật liệu `ultraThinMaterial` + viền mảnh + bóng nhẹ; khi bật "Giảm độ trong suốt" dùng nền đặc `surfaceHigh` (hoặc màu tô). CTA vẫn là viên đặc màu cam; `CircleIconButton` giữ kiểu cũ; `mpScrollEdgeSoft`/`mpBackgroundExtension` không làm gì.
