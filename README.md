
# MyPlaces

Ứng dụng iOS giúp lưu giữ địa điểm đã ghé thăm, tổ chức các địa điểm thành hành trình, ghi lại hình ảnh và ghi chú ngắn, đồng thời chia sẻ trải nghiệm với bạn bè.

## Tổng quan

MyPlaces là ứng dụng bản đồ ký ức cá nhân với khả năng cộng tác chọn lọc. Sản phẩm kết hợp ba nhu cầu: **bản đồ cá nhân** (Personal Map), **nhật ký chuyến đi** (Travel Journal) và **lịch sử địa điểm/cuộc sống** (Life Tracker), với năng lực **cộng tác** (Shared Experiences) là điểm khác biệt.

### Kiến trúc

- **iOS**: SwiftUI + MapKit (iOS 17+)
- **Backend**: Supabase (PostgreSQL + Auth + Storage + Realtime)
- **Mô hình dữ liệu**: Place → Visit → Memory → People với per-resource sharing

## Cài đặt và Chạy iOS App

### Yêu cầu

- macOS 14.0 (Sonoma) trở lên
- Xcode 15.0 trở lên
- iOS 17.0+ (device hoặc simulator)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (để tạo Xcode project từ `project.yml`)

### Các bước cài đặt

1. **Clone repository**

```bash
git clone <repository-url>
cd mypplaces
```

2. **Cài đặt XcodeGen** (nếu chưa có)

```bash
brew install xcodegen
```

3. **Tạo file cấu hình Supabase**

```bash
cd ios
cp Config.example.xcconfig Config.xcconfig
```

Mở `Config.xcconfig` và điền thông tin Supabase của bạn:

```xcconfig
SUPABASE_URL = https:/$()/your-project.supabase.co
SUPABASE_ANON_KEY = your-anon-key-here
```

> **Lưu ý**: File `Config.xcconfig` đã được thêm vào `.gitignore` để bảo mật thông tin Supabase. Publishable key tuy an toàn cho client nhưng vẫn nên tách khỏi source code.

4. **Tạo Xcode project**

```bash
xcodegen generate
```

Lệnh này sẽ tạo file `MyPlaces.xcodeproj` từ `project.yml`.

5. **Mở project trong Xcode**

```bash
open MyPlaces.xcodeproj
```

6. **Cài đặt Swift Package dependencies**

Xcode sẽ tự động tải `supabase-swift` package khi bạn mở project lần đầu. Nếu không, bạn có thể trigger việc này bằng cách:

- File → Packages → Resolve Package Versions

7. **Chọn team cho code signing**

- Mở project settings trong Xcode
- Chọn target `MyPlaces`
- Tab "Signing & Capabilities"
- Chọn Development Team của bạn

8. **Chạy ứng dụng**

- Chọn simulator hoặc device
- Nhấn `⌘ + R` hoặc nút Run

### Cấu trúc iOS Project

```
ios/
├── project.yml              # XcodeGen configuration
├── Config.example.xcconfig  # Template cho Supabase config
├── Config.xcconfig          # Supabase config thực (gitignored)
├── MyPlaces/
│   ├── MyPlacesApp.swift   # App entry point
│   ├── Info.plist          # App configuration
│   ├── Core/               # Core services và app state
│   │   ├── AppState.swift
│   │   ├── Config/
│   │   │   └── SupabaseConfig.swift
│   │   └── Services/
│   │       └── SupabaseService.swift
│   ├── Domain/             # Domain models
│   │   └── Models/
│   │       ├── Place.swift
│   │       ├── UserProfile.swift
│   │       └── Journal.swift
│   ├── Data/               # Data layer
│   │   ├── Local/          # SwiftData models
│   │   │   ├── LocalPlace.swift
│   │   │   └── OutboxOperation.swift
│   │   └── Repositories/   # Repository pattern
│   │       ├── AuthRepository.swift
│   │       └── PlaceRepository.swift
│   └── Presentation/       # UI layer
│       ├── ViewModels/
│       │   ├── AuthViewModel.swift
│       │   ├── MapViewModel.swift
│       │   └── PlaceListViewModel.swift
│       └── Views/
│           ├── RootView.swift
│           ├── MainTabView.swift
│           ├── Auth/
│           │   └── AuthView.swift
│           ├── Map/
│           │   └── MapView.swift
│           ├── Places/
│           │   ├── PlaceListView.swift
│           │   ├── PlaceDetailView.swift
│           │   ├── CreatePlaceView.swift
│           │   └── EditPlaceView.swift
│           ├── Journals/
│           │   └── JournalListView.swift
│           └── Profile/
│               └── ProfileView.swift
└── MyPlacesTests/          # Unit tests
    ├── ModelMappingTests.swift
    └── OutboxTests.swift
```

## Kiến trúc iOS

### Clean Architecture

Ứng dụng sử dụng kiến trúc phân lớp rõ ràng:

1. **Domain Layer**: Models thuần Swift, không phụ thuộc framework
2. **Data Layer**: Repository pattern với dual storage (SwiftData local + Supabase remote)
3. **Presentation Layer**: SwiftUI Views + Observable ViewModels

### Offline-First với Outbox Pattern

- **SwiftData**: Cache local và lưu pending operations
- **OutboxOperation**: Queue các mutations (create/update/delete)
- **Automatic Retry**: Exponential backoff với jitter
- **Idempotency**: Client-generated UUIDs để tránh duplicate

Luồng tạo Place:

```
User creates Place
    ↓
Save to LocalPlace (pending)
    ↓
Create OutboxOperation
    ↓
Show optimistically in UI
    ↓
Background sync worker
    ↓
POST to Supabase
    ↓
Update sync state (synced/failed)
```

### State Management

- `@Observable` macro cho ViewModels (iOS 17+)
- `@Environment(\.modelContext)` cho SwiftData access
- Centralized `AppState` cho app-level state

## Tính năng MVP (v1.0)

### ✅ Đã implement trong skeleton

- [x] Email authentication (email+password và magic link)
- [x] Sign in with Apple scaffolding
- [x] MapKit map với user location
- [x] Search địa điểm qua MapKit
- [x] Place CRUD (Create, Read, Update, soft Delete)
- [x] Place list với filter theo category
- [x] SwiftData local cache
- [x] Outbox pattern cho offline-first
- [x] Unit tests cho model mapping và outbox

### 🚧 Chưa implement (next iterations)

- [ ] Visit entity (nhiều lần ghé thăm cùng Place)
- [ ] Memory/Contribution (ảnh + note)
- [ ] Journal CRUD và timeline
- [ ] Sharing (Place/Visit/Journal) với Owner/Editor/Viewer roles
- [ ] Invitation flow
- [ ] Realtime sync
- [ ] Push notifications
- [ ] Image upload và Storage

## Testing

### Chạy tests

```bash
# Trong Xcode
⌘ + U

# Hoặc command line
xcodebuild test \
  -project MyPlaces.xcodeproj \
  -scheme MyPlaces \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Coverage

- Model mapping (Domain ↔ SwiftData)
- Outbox operation lifecycle
- Sync state transitions

## Cấu hình Supabase Backend

Backend Supabase cần có các bảng sau (xem ERD trong `docs/` để biết chi tiết schema):

### Tables cần thiết cho MVP

```sql
-- profiles: thông tin user
-- places: địa điểm canonical
-- journals: hành trình/nhật ký (stub)
```

### Row Level Security (RLS)

Tất cả tables phải enable RLS với policies:

- `places`: Owner có thể SELECT/UPDATE/DELETE
- `profiles`: User có thể SELECT/UPDATE own profile

### Auth Configuration

- Email authentication enabled
- Magic link enabled (optional)
- Sign in with Apple (sẵn sàng integrate khi có config)

## Troubleshooting

### Lỗi "SUPABASE_URL not configured"

→ Đảm bảo đã copy `Config.example.xcconfig` thành `Config.xcconfig` và điền đầy đủ thông tin.

### Lỗi code signing

→ Chọn Development Team trong Xcode project settings (Signing & Capabilities).

### XcodeGen không tìm thấy

→ Cài đặt: `brew install xcodegen`

### Swift Package dependencies không resolve

→ Thử: File → Packages → Reset Package Caches, sau đó Resolve Package Versions.

### Map không hiển thị user location

→ Kiểm tra Location permission trong Settings app → Privacy → Location Services → MyPlaces.

## Roadmap

### Phase 1: MVP Core (Current)
- [x] Authentication
- [x] Place CRUD
- [x] Map và search
- [x] Offline-first foundation

### Phase 2: Memory & Visit
- [ ] Visit entity và multiple visits per Place
- [ ] Memory/Contribution với ảnh
- [ ] Timeline view

### Phase 3: Collaboration
- [ ] Sharing Place/Visit/Journal
- [ ] Invitation system
- [ ] Role-based access (Owner/Editor/Viewer)
- [ ] Realtime updates

### Phase 4: Polish
- [ ] Push notifications
- [ ] Advanced search và filters
- [ ] Collections
- [ ] Export data

## Đóng góp

Đây là MVP skeleton. Các tính năng nâng cao sẽ được phát triển trong các iteration tiếp theo theo roadmap.

## License

TBD

# MyPlaces – Supabase migration package (v1.2)

Bộ migration SQL + pgTAP test cho backend Supabase của MyPlaces (iOS / SwiftUI / MapKit).
Nguồn: BRD v1.1 (10/11/2026, v1.1 thắng v1.0 khi mâu thuẫn) và ERD & Permission Design v1.1,
cùng 5 quyết định đã chốt (D1–D5, bên dưới). v1.2 (17/11/2026): thêm migration 11–14 cho 6 quyết định UI (xem mục 7).

```
supabase/
├── config.toml                      # cấu hình tối thiểu cho Supabase CLI (viết tay, chưa chạy với CLI thật)
├── seed.sql                         # rỗng (không có dữ liệu mẫu)
├── migrations/
│   ├── 20261115000001_extensions_and_enums.sql
│   ├── 20261115000002_tables.sql
│   ├── 20261115000003_triggers.sql
│   ├── 20261115000004_helper_functions.sql
│   ├── 20261115000005_rls_policies.sql
│   ├── 20261115000006_projections.sql
│   ├── 20261115000007_sharing_rpcs.sql
│   ├── 20261115000008_storage.sql
│   ├── 20261115000009_grants_and_realtime.sql
│   ├── 20261115000010_fk_covering_indexes.sql
│   ├── 20261117000001_map_places_view.sql
│   ├── 20261117000002_timeline_and_companion_rpcs.sql
│   ├── 20261117000003_invitation_ttl_options.sql
│   ├── 20261117000004_companion_suggestions_invoker.sql
│   ├── 20261120000001_poi_overture_fallback.sql      # bảng POI Overture (chỉ đọc) + search_pois()
│   ├── 20261120000002_search_pois_coverage.sql       # xếp hạng: thêm độ phủ từ khoá
│   ├── 20261120000003_search_pois_short_query_guard.sql  # chặn truy vấn ngắn/chung chung quá chậm
│   └── 20261121000001_media_size_limit_2mb.sql      # bucket ảnh: giới hạn 2 MB (app nén ảnh trước)
└── tests/database/                  # pgTAP (supabase test db)
    ├── 00000_test_helpers.test.sql  # schema `tests` + helper (PHẢI chạy đầu tiên)
    ├── 01_schema_hardening.test.sql
    ├── 02_places_visits_rls.test.sql
    ├── 03_memories_rls.test.sql
    ├── 04_journals_projection.test.sql
    ├── 05_invitations_membership.test.sql
    ├── 06_storage.test.sql
    ├── 07_ui_v1_1_support.test.sql   # v1.2: map_places, my_timeline, companions, TTL (61 assertion)
    └── 08_poi_overture_search.test.sql  # tìm kiếm dự phòng Overture: RLS, chuẩn hoá, xếp hạng, giới hạn (31 assertion)
local-validation/                    # chỉ để kiểm thử trên PostgreSQL thuần (không dùng cho Supabase thật)
├── stub_supabase.sql                # stub roles anon/authenticated/service_role, auth.*, storage.*
└── run.sh                           # DB mới → stub → migrations → tests → tổng kết
```

## 1. Thứ tự file (phải áp dụng theo thứ tự timestamp)

| # | File | Nội dung |
|---|------|----------|
| 01 | extensions_and_enums | `pgcrypto` (schema `extensions`), schema `private`, enum (`member_role`, `member_status`, `invitation_status`, `resource_type`, `memory_type`, `place_category`) |
| 02 | tables | 14 bảng, CHECK, partial unique index, index theo ERD §4, FK **không** `ON DELETE CASCADE` |
| 03 | triggers | `write_audit`, `updated_at`, đóng dấu `created_at` phía server, cột bất biến, guard moderation, kiểm tra IANA timezone, tạo profile khi đăng ký, audit vòng đời (xóa/khôi phục/archive), `audit_log` append-only |
| 04 | helper_functions | `private.can_read_* / can_contribute_* / is_*_owner / memory_visible / can_read_profile` (SECURITY DEFINER, STABLE, `search_path=''`) |
| 05 | rls_policies | Bật RLS mọi bảng; policy riêng cho SELECT/INSERT/UPDATE/DELETE |
| 06 | projections | `journal_places_projection`, `journal_visits_projection` (D5), `my_visit_places` (D3) |
| 07 | sharing_rpcs | `create/resolve/accept/decline/revoke/list_invitations`, `change_member_role`, `remove_member`, `leave_resource`, `unshare_resource`, `transfer_ownership`, `expire_pending_invitations` |
| 08 | storage | bucket `memory-media` (private, 10 MB, jpeg/png/heic) + policy `storage.objects` |
| 09 | grants_and_realtime | Thu hồi quyền mặc định của Supabase, cấp lại tối thiểu; thêm bảng vào publication `supabase_realtime` |
| 10 | fk_covering_indexes | Index phủ 10 foreign key mà performance advisor của Supabase báo thiếu (thêm sau khi áp dụng lên project thật) |
| 11 | map_places_view (20261117000001) | View `map_places` (security_invoker): Place đọc được + `visit_count`, `last_visited_at`, `visit_status` (VISITED/WANT_TO_VISIT, suy ra, không có cột), ảnh bìa |
| 12 | timeline_and_companion_rpcs (20261117000002) | RPC `my_timeline` (SECURITY DEFINER, `search_path=''`, trả `visited_local` theo `timezone_id`) và `list_companion_suggestions` |
| 13 | invitation_ttl_options (20261117000003) | `create_invitation` chỉ nhận `p_ttl` = 1, 7 (mặc định) hoặc 30 ngày → khác thì `PT400 INVALID_EXPIRY` |
| 14 | companion_suggestions_invoker (20261117000004) | Chuyển `list_companion_suggestions` sang SECURITY INVOKER (theo security advisor) |

## 2. Cách chạy

### Với Supabase CLI (khuyến nghị)
```bash
cd myplaces            # thư mục chứa supabase/
supabase start
supabase db reset      # áp dụng toàn bộ migrations (+ seed.sql rỗng)
supabase test db       # chạy pgTAP trong supabase/tests/database
```
Yêu cầu PostgreSQL ≥ 15 (cú pháp `ON DELETE SET NULL (journal_visit_id)`); `config.toml` đặt `major_version = 17`.
`00000_test_helpers.test.sql` tạo schema `tests` (không rollback) nên phải chạy trước các file còn lại
(đặt tên theo thứ tự chữ cái để `pg_prove` chạy đúng thứ tự).

### Kiểm thử trên PostgreSQL thuần (không cần Docker)
```bash
# cần một PostgreSQL >= 15 đang chạy + extension pgTAP; đặt PGHOST/PGPORT/PGUSER nếu khác mặc định
cd local-validation && ./run.sh
```
Script tạo DB mới, nạp `stub_supabase.sql` (mô phỏng rất tối thiểu `auth.users`, `auth.uid()`, `storage.*`,
các role Supabase và default privileges của Supabase để việc `REVOKE` được kiểm thật), áp dụng migrations rồi chạy
từng file test và so khớp kế hoạch `1..N`. **Không áp dụng stub này vào project Supabase thật.**

## 3. Kết quả đã kiểm chứng

* PostgreSQL 17.11 + pgTAP 1.3.5 (cài cục bộ trên box, không có Docker / Supabase CLI): 9 migration áp dụng sạch,
  **399 assertion / 7 file, 0 lỗi**.
* Có chạy "mutation check": cố ý làm yếu policy (mở `places_select`, cho Viewer tạo Visit, bỏ kiểm tra hết hạn khi accept,
  mở policy storage, cho Journal member đọc `places`, bỏ CHECK một-parent, cho mọi contributor sửa memory…) → test bắt được tất cả.
* Chạy thử đồng thời 2 session `accept_invitation` cùng token: một session thành công, session còn lại nhận `INVITATION_USED`, chỉ có 1 membership.
* **Chưa** chạy với Supabase CLI/Docker thật nên chưa kiểm: `config.toml`, thứ tự file của `supabase test db`,
  `INSERT` tối thiểu vào `auth.users` trên GoTrue thật, quyền tạo trigger trên `auth.users`/policy trên `storage.objects` (đều là thao tác
  Supabase cho phép với role `postgres`), và hành vi Realtime.

### Đã áp dụng lên Supabase thật (15/11/2026)

* Project `ektlcjoxnjlyiyzzzjob` (region `ap-southeast-2`, PostgreSQL 17.11), URL `https://ektlcjoxnjlyiyzzzjob.supabase.co`. Project trống trước khi áp dụng.
* 10 migration (01–09 + `10_fk_covering_indexes`) áp dụng bằng Supabase MCP `apply_migration`, **không cần sửa file 01–09**: trigger trên `auth.users`,
  policy trên `storage.objects`, insert bucket, publication `supabase_realtime` và `REVOKE` default privileges đều chạy được với role `postgres`.
  Lưu ý: `apply_migration` ghi version = thời điểm áp dụng (`20261115063329`…), không phải timestamp trong tên file; nội dung giống hệt.
* Chạy pgTAP trên DB thật (mỗi file trong một transaction rồi `ROLLBACK`, kèm helper + `create extension pgtap` trong transaction đó nên không lưu gì):
  **399/399 pass**. Sau đó `auth.users`, `profiles`, `places`, `storage.objects` đều rỗng, không còn schema `tests` hay extension `pgtap`.
* Hai chỗ test phải chỉnh cho Supabase thật (migration không đổi):
  1. `01_schema_hardening`: bỏ `public.rls_auto_enable()` khỏi kiểm tra "mọi SECURITY DEFINER pin `search_path=''`" – hàm này do nền tảng Supabase tạo sẵn (event trigger, pin `pg_catalog`).
  2. `06_storage`: Supabase có trigger `storage.protect_delete()` chặn `DELETE` trực tiếp trên `storage.objects`; test đặt
     `set_config('storage.allow_delete_query','true',true)` (cờ mà Storage API tự đặt) để kiểm policy xoá.
* Advisor **security**: 14 WARN `authenticated_security_definer_function_executable` – đều là RPC chia sẻ/projection **cố ý** để client gọi
  (mỗi hàm tự kiểm `auth.uid()` + quyền; `anon`/`PUBLIC` không có EXECUTE; helper RLS nằm ở schema `private` không expose). Không có lỗi ERROR.
  **Performance**: 10 INFO `unindexed_foreign_keys` → đã xử lý bằng migration 10; còn INFO `unused_index` (bình thường trên DB chưa có dữ liệu).
* Chưa thử bằng client thật (PostgREST/GoTrue/Realtime end-to-end): pgTAP giả lập JWT bằng `request.jwt.claims`.

## 4. Truy vết yêu cầu → test

### ERD §6.3 (bắt buộc)
| Case | Test |
|------|------|
| Anonymous reads private Place → denied | 02 (khối anonymous: lỗi `42501`, `anon` không có GRANT) |
| Owner reads own Place/Visit/Journal | 02 "Owner reads own Places/Visits", 04 "Owner reads own Journal" |
| Active Place Viewer reads Place, no Visit | 02 khối place VIEWER |
| Place Viewer reads sibling Visit via REST → denied | 02 `[6.3][ERD-03]` (cả `select *` và theo id) |
| Visit Viewer reads shared Visit; sibling denied | 02 khối visit VIEWER |
| Journal Viewer reads linked Place only via projection | 04 (trường giới hạn, không có address/provider; `places`/`visits` trực tiếp rỗng) |
| Participant not member reads Visit → denied | 02 khối participant (erin) |
| Removed member reads resource after revocation → denied | 02, 03, 04, 05, 06 |
| Editor updates another user's Memory → denied | 03 (0 row) |
| Viewer inserts Memory → denied | 03 (`42501`) |
| Client forges author_id/owner_id → denied | 02 (Place/Visit), 03 (Memory), 04 (Journal/journal_places), 05 (audit_log) |
| User guesses Storage path → denied | 06 |

### 5 quyết định
* **D1** Editor của Place tạo Visit, `owner_id` = editor: 02 (`[D1]`, `[ERD-06]`).
* **D2** `owner_id` là nguồn sự thật, membership chỉ EDITOR/VIEWER: 01 (CHECK), 04 (không có row owner), 05 (`transfer_ownership` xoá row của owner mới, không còn OWNER trong bảng member).
* **D3** Visit owner luôn đọc được projection tối thiểu của Place (kể cả unshare/soft-delete) mà `places` RLS không mở rộng: 02 (`[D3]`), 05.
* **D4** `memories` đúng một parent (CHECK) + `journal_visit_id` không phải parent, chỉ khi parent là Journal, cùng Journal (FK ghép): 03.
* **D5** Journal member chỉ thấy Place/Visit qua projection live (không snapshot, không đọc bảng gốc): 04 (đổi tên/di chuyển → projection đổi ngay; soft-delete → biến mất).

## 5. Thiết kế chính

* **Deny by default 2 lớp**: `GRANT` (migration 09 thu hồi mặc định của Supabase, cấp lại tối thiểu: không `DELETE` trên places/visits/journals/memories,
  bảng member/`audit_log` chỉ `SELECT`, `invitations` không cấp gì) + RLS từng thao tác (migration 05).
* **Helper nằm ở schema `private`** (PostgREST không expose). Mỗi helper chỉ nhìn `auth.uid()` nên gọi bởi bất kỳ user nào cũng không lộ dữ liệu người khác.
  `authenticated` được `USAGE` schema `private` và `EXECUTE` đúng các helper mà policy dùng (test 01 kiểm tra mọi helper `can_*/is_*`).
* **Soft delete**: không có policy DELETE; xoá = `UPDATE deleted_at`. Owner vẫn thấy tombstone (để sync/khôi phục), người khác không thấy.
  Place đã xoá không cho tạo Visit mới; Memory của parent bị xoá không cascade (chỉ owner/author thấy).
* **Thời gian**: `timestamptz` (UTC) + `visits.timezone_id` được kiểm tra với `pg_timezone_names`. `created_at/updated_at` do server đóng dấu (giờ client nằm ở `visited_at`).
* **Idempotent**: PK uuid do client sinh. Retry dùng `INSERT … ON CONFLICT (id) DO NOTHING` (PostgREST `Prefer: resolution=ignore-duplicates`); insert thường trùng id → `23505`.
* **Invitation**: token 256-bit (`gen_random_bytes(32)` → 64 hex), chỉ lưu `sha256` hex; TTL ≤ 30 ngày; role EDITOR/VIEWER; ràng buộc tuỳ chọn theo `invitee_user_id` hoặc email (email phải đã xác thực);
  mời lại cùng invitee = thay thế (revoke cái cũ). `accept_invitation` khoá hàng invitation (`FOR UPDATE`) nên 2 thiết bị cùng accept chỉ 1 thành công; REMOVED/LEFT được kích hoạt lại với role mới.
* **Audit**: bảng `audit_log` append-only, chỉ ghi bởi RPC/trigger (SECURITY DEFINER). Ghi: tạo/accept/decline/revoke invitation, đổi role, remove/leave, unshare, transfer, moderation memory, xoá/khôi phục/archive.
* **Mã lỗi RPC** (PostgREST map `PTxxx` → HTTP xxx, `message` là mã ổn định): `PT401 AUTH_REQUIRED`, `PT400 INVALID_ROLE/INVALID_EXPIRY/CANNOT_INVITE_SELF/INVALID_NEW_OWNER`,
  `PT403 FORBIDDEN`, `PT404 INVITATION_NOT_FOUND/RESOURCE_NOT_FOUND/MEMBER_NOT_FOUND`, `PT409 INVITATION_USED/ALREADY_MEMBER/ALREADY_OWNER/OWNER_MUST_TRANSFER/OWNER_CANNOT_BE_REMOVED/NEW_OWNER_NOT_MEMBER/RESOURCE_UNAVAILABLE`,
  `PT410 INVITATION_EXPIRED/REVOKED/DECLINED`.
* **Cách app dùng**: CRUD Place/Visit/Memory/Journal qua bảng (RLS); mọi thao tác chia sẻ qua RPC; Journal đọc qua `rpc('journal_places_projection')`, `rpc('journal_visits_projection')`;
  Visit owner lấy toạ độ Place qua `rpc('my_visit_places')`; danh sách lời mời của owner qua `rpc('list_invitations')` (không trả `token_hash`).
* **Upload ảnh**: (1) tạo `memories` → (2) upload object `{uploader_id}/{memory_id}/{attachment_id}.{jpg|jpeg|png|heic}` → (3) insert `memory_attachments` (finalize).
  Object chưa finalize thì chưa đọc được; không có policy UPDATE nên không ghi đè cùng path.

## 6. Các điểm mơ hồ đã tự quyết (cần bạn xác nhận)

1. **Chỉ chủ Place/Visit mới được link vào Journal** (Journal Owner/Editor + là owner của Place/Visit được link). Lý do: link = công khai projection cho cả nhóm. Owner của Place/Visit luôn xem/gỡ được link của mình kể cả sau khi bị remove khỏi Journal.
2. **Visit projection trong Journal** chỉ gồm ngày giờ, timezone và Place (title/category/toạ độ) theo ERD §5.4; **không** có `note`, participants, địa chỉ. Place đã soft-delete thì Visit liên quan cũng biến khỏi projection.
3. **Chỉ Visit owner** nhận projection Place (D3); Visit Viewer/Editor không thấy Place. *v1.2: riêng `my_timeline` trả projection tối thiểu (title/category/toạ độ) cho Visit member khi Place còn hiệu lực; RLS `places` không đổi.*
4. **Dedup `provider_place_id` theo từng owner** (unique `(owner_id, provider, provider_place_id)` với row chưa xoá), không unique toàn cục.
5. **Membership có enum `OWNER` nhưng CHECK cấm** (giữ từ vựng ERD, thực thi D2).
6. **Transfer ownership**: owner mới phải là member ACTIVE; row member của owner mới bị xoá; owner cũ mặc định thành EDITOR (hoặc `NULL` = mất quyền); các invitation PENDING bị revoke.
7. **Author có thể khôi phục (`deleted_at = NULL`) memory của mình sau khi owner moderate** – chưa chặn (chưa có cờ "bị moderate").
8. **Decline một link không ràng buộc** làm chết link đó với mọi người (trạng thái DECLINED theo BRD).
9. **Hết hạn invitation**: tính từ `expires_at` lúc gọi RPC; trạng thái `EXPIRED` được lưu bởi `expire_pending_invitations()` (cần lịch pg_cron hoặc Edge Function), vì RPC raise lỗi thì không thể ghi trạng thái.
10. **Bảng `invitations` không cấp quyền cho client** (tránh lộ `token_hash`, tránh lỗi `select=*` do column-grant) → dùng `list_invitations`/`resolve_invitation`. Có policy SELECT cho owner phòng khi sau này cấp GRANT.
11. **Profile**: đọc được khi cùng Place/Visit/Journal (owner/ACTIVE member), là tác giả memory đọc được, hoặc là participant có tài khoản của Visit đọc được. Không lưu email.
12. **Memory type** dùng `NOTE`/`PHOTO` (ERD) thay cho `TEXT_NOTE` (BRD); body ≤ 2000 ký tự, NOTE bắt buộc có body. `Place.note`, favorite (v1.0) bị bỏ theo v1.1 (note → Memory; favorite là P1).
13. **Journal** bỏ `visibility`/`status` của v1.0: luôn private, trạng thái = `archived_at`. Journal archived từ chối thêm Memory/link; vẫn đọc được.
14. **Collections (P1)**, AI, GPS nền: chưa có bảng.
15. **Visit tạo trên Place chỉ cho owner = chính người tạo** (không chọn owner khác lúc insert); muốn đổi dùng `transfer_ownership`.
16. **Participant có tài khoản phải là người bạn đã nhìn thấy được** (cùng Place/Visit/Journal hoặc đã là participant): chặn việc thêm UUID bất kỳ để đọc profile / dò tài khoản. Chọn "bạn bè" bất kỳ chỉ làm được khi có friend graph (P1); hiện chỉ thêm được guest label cho người chưa chung tài nguyên.
17. **Member cũ vẫn xoá được file do mình upload** (author), nhưng không đọc/upload thêm được; parent owner xoá được mọi file (moderation).

## 7. Việc chưa làm / gợi ý tiếp theo

* Bucket `avatars` và `journal-covers` (profiles.avatar_path, journals.cover_path hiện chỉ là text) – chưa tạo policy.
* Rate limit cho `resolve/accept_invitation` (BRD yêu cầu) – cần làm ở Edge Function/API gateway; DB chỉ chống trùng và khoá hàng.
* Workflow xoá tài khoản (`profiles.id` đang `ON DELETE RESTRICT`), retention/purge, dọn object Storage mồ côi, kiểm tra nội dung/EXIF phía server.
* Kiểm tra hiệu năng policy trên dữ liệu lớn (nhiều helper là truy vấn theo từng row), và thử Realtime với RLS.

## 7. Cập nhật v1.2 (17/11/2026)

6 quyết định UI: điều hướng 5 tab; Muốn đến/Đã ghé suy ra (không có cột); chưa có Yêu thích; gợi ý người đi cùng = đồng thành viên + tên tự do; hạn lời mời 1/7/30 ngày (mặc định 7); Dòng thời gian theo `timezone_id` của từng Visit.

* Local (PostgreSQL 17.11 + pgTAP): 14 migration áp dụng sạch, **460 assertion / 8 file, 0 lỗi** (399 cũ + 61 mới).
* Supabase thật (`ektlcjoxnjlyiyzzzjob`): migration 11–14 áp dụng bằng `apply_migration` (version `20261117043509`, `20261117043518`, `20261117043519`, `20261117043706`).
  Test 01–07 chạy trong transaction rồi rollback: 36 + 80 + 54 + 69 + 112 + 45 + 61 = **457/457 pass**; không để lại dữ liệu.
* Advisor: security – chỉ thêm `authenticated_security_definer_function_executable` cho `my_timeline` (có chủ đích, như 14 RPC hiện có) và `auth_leaked_password_protection` (cài đặt Auth trên dashboard); performance – chỉ INFO `unused_index`.
* App: bản đồ `from('map_places').select()`; Dòng thời gian `rpc('my_timeline', {p_from, p_to, p_category, p_visit_id, p_limit})`; chọn người đi cùng `rpc('list_companion_suggestions', {p_query, p_limit})` rồi insert `visit_participants`.

## 8. Tìm kiếm dự phòng Overture Maps (20/11/2026)

* Bảng `public.poi_overture` (422.329 POI Việt Nam, release `2026-11-18.0`), `public.poi_overture_imports` (nhật ký import). RLS bật, `authenticated` chỉ `SELECT`, `anon` không có quyền; client không ghi được.
* RPC `public.search_pois(q, lat, lng, max_results)` – SECURITY INVOKER, `search_path` rỗng, chỉ `authenticated` được gọi. Bỏ dấu (`unaccent` + Đ→d), `pg_trgm` (GIN trên tên + địa chỉ), GiST trên `point(longitude, latitude)`; q cắt 100 ký tự, cần ≥ 3 ký tự sau chuẩn hoá, kết quả 1–20 (mặc định 10), truy vấn < 6 ký tự có vị trí chỉ tìm trong ~28 km, tối đa 10.000 ứng viên trước khi chấm điểm.
* Dung lượng: bảng ~174 MB (heap 92 + trigram 38 + GiST 27 + PK ~17), cả DB 190 MB / 500 MB (gói Free).
* Local (PostgreSQL 17.11 + pgTAP): 17 migration áp dụng sạch, **491 assertion / 9 file, 0 lỗi**. Supabase thật: 3 migration áp dụng bằng `apply_migration`; test 08 không chạy trên DB thật vì kiểm số dòng của fixture (bảng thật đã có dữ liệu).
* Cách import / làm mới hằng tháng và giấy phép: `scripts/overture/README.md`.

## 9. Nén ảnh + giới hạn Storage 2 MB (21/11/2026)

* App nén ảnh trước khi tải lên (≤ 1600 px, JPEG 0,7→0,5, bỏ EXIF/GPS); ảnh thực tế 250–470 KB.
* `memory-media`: `file_size_limit` 10 MB → 2 MB, `memory_attachments.size_bytes` ≤ 2 MB. Local: 18 migration, **492 assertion / 9 file, 0 lỗi**.

## 10. Giao diện Liquid Glass (21/11/2026)

* iOS 26 dùng Liquid Glass cho tab bar, nút nổi, ô tìm và chip trên bản đồ, panel Thêm địa điểm và sheet thấp; iOS 17–25 tự chuyển sang vật liệu mờ / nền đặc. Chi tiết: `docs/design/LIQUID_GLASS_PLAN.md`, ảnh trước/sau: `docs/screenshots/liquid-glass/`.
