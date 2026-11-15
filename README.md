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
