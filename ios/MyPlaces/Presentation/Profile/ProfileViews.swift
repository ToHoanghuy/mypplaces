import SwiftUI
import Photos
import CoreLocation

/// 08a – profile.
struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    private var sync: SyncEngine { SyncEngine.shared }
    @State private var showEdit = false
    @State private var showInvite = false
    @State private var confirmSignOut = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Cá nhân").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                HStack { Spacer()
                    Button { router.push(.sync) } label: { Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(.white) }
                        .accessibilityIdentifier("profile.settings")
                }
            }
            .padding(.horizontal, 20).frame(height: 52)

            ScrollView {
                VStack(spacing: 10) {
                    Avatar(name: session.profile?.displayName ?? "?", path: session.profile?.avatarPath, size: 96)
                        .overlay(Circle().stroke(Theme.border, lineWidth: 2))
                        .padding(.top, 20)
                    Text(session.profile?.displayName ?? " ").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                        .accessibilityIdentifier("profile.name")
                    Text(session.email ?? "").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    Button { showEdit = true } label: {
                        Text("Sửa hồ sơ").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 30).overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.edit")

                    VStack(spacing: 0) {
                        row(icon: "location", title: "Quyền vị trí & ảnh") { router.push(.sync) }
                        Divider().overlay(Theme.hairline).padding(.leading, 48)
                        row(icon: "arrow.triangle.2.circlepath", title: "Đồng bộ", value: syncValue, valueIcon: sync.pendingCount == 0 ? "checkmark" : nil) { router.push(.sync) }
                            .accessibilityIdentifier("profile.sync")
                        Divider().overlay(Theme.hairline).padding(.leading, 48)
                        row(icon: "link", title: "Nhập liên kết mời") { showInvite = true }
                            .accessibilityIdentifier("profile.enterInvite")
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                    .padding(.top, 30)

                    Button { confirmSignOut = true } label: {
                        Text("Đăng xuất").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .accessibilityIdentifier("profile.signout")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showEdit) { EditProfileView() }
        .sheet(isPresented: $showInvite) { EnterInviteSheet().presentationDetents([.medium]) }
        .confirmationDialog("Đăng xuất khỏi MyPlaces?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) { Task { await session.signOut() } }
        } message: {
            if sync.pendingCount > 0 { Text("Còn \(sync.pendingCount) thay đổi chưa đồng bộ. Chúng sẽ được gửi khi bạn đăng nhập lại.") }
        }
        .task { await session.reloadProfile() }
    }

    private var syncValue: String {
        if sync.isSyncing { return "Đang đồng bộ…" }
        if sync.hasFailures { return "Có lỗi" }
        return sync.pendingCount == 0 ? "Đã đồng bộ" : "\(sync.pendingCount) thay đổi chờ"
    }

    private func row(icon: String, title: String, value: String? = nil, valueIcon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.textSecondary).frame(width: 20)
                Text(title).font(.system(size: 15)).foregroundStyle(.white)
                Spacer()
                if let value { Text(value).font(.system(size: 13)).foregroundStyle(Theme.textSecondary) }
                if let valueIcon { Image(systemName: valueIcon).font(.system(size: 11)).foregroundStyle(Theme.textSecondary) }
                else { Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary) }
            }
            .padding(.horizontal, 16).frame(height: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 08b – edit profile (display_name 1–40; email read-only).
struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    @State private var error: String?
    @State private var avatarInfo = false

    var body: some View {
        VStack(spacing: 0) {
            ModalBar(title: "Hồ sơ", onCancel: { dismiss() }) {
                PillButton(title: "Lưu", isLoading: saving, isEnabled: valid) { save() }.accessibilityIdentifier("profile.save")
            }
            VStack(spacing: 14) {
                Button { avatarInfo = true } label: {
                    VStack(spacing: 10) {
                        Avatar(name: name.isEmpty ? "?" : name, path: session.profile?.avatarPath, size: 120)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera").font(.system(size: 13)).foregroundStyle(.white)
                                    .frame(width: 34, height: 34).background(Theme.surfaceHigh, in: Circle())
                                    .overlay(Circle().stroke(Theme.background, lineWidth: 3))
                            }
                        Text("Đổi ảnh").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tên hiển thị").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    HStack {
                        TextField("", text: $name, prompt: Text("Nhập tên").foregroundColor(Theme.textTertiary))
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(.white).tint(Theme.accent)
                            .accessibilityIdentifier("profile.nameField")
                        Text("\(name.trimmingCharacters(in: .whitespaces).count)/40").font(.system(size: 12))
                            .foregroundStyle(name.count > 40 ? Theme.danger : Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Email").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Text(session.email ?? "").font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Image(systemName: "lock").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .screenBackground()
        .onAppear { name = session.profile?.displayName ?? "" }
        .alert("Ảnh đại diện", isPresented: $avatarInfo) { Button("OK", role: .cancel) {} } message: {
            Text("Tính năng đổi ảnh đại diện sẽ có trong bản cập nhật sau.")
        }
    }

    private var valid: Bool { (1...40).contains(name.trimmingCharacters(in: .whitespaces).count) }

    private func save() {
        saving = true; error = nil
        Task {
            do { try await session.updateDisplayName(name); dismiss() }
            catch { self.error = AppError.message(error) }
            saving = false
        }
    }
}

/// 08c – sync queue + permissions.
struct SyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var sync: SyncEngine { SyncEngine.shared }
    private var location: LocationService { LocationService.shared }
    @State private var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CircleIconButton(systemName: "chevron.left", background: Theme.surface) { dismiss() }.accessibilityIdentifier("nav.back")
                Text("Đồng bộ").font(.mpLargeTitle).foregroundStyle(.white)
            }
            .padding(.horizontal, 20).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: sync.pendingCount == 0 ? "checkmark.icloud" : "arrow.triangle.2.circlepath.icloud")
                                .font(.system(size: 18)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    if sync.pendingCount > 0 { Circle().fill(Theme.accent).frame(width: 9, height: 9).offset(x: 2, y: -2) }
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sync.pendingCount == 0 ? "Đã đồng bộ" : "\(sync.pendingCount) thay đổi chưa đồng bộ")
                                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                    .accessibilityIdentifier("sync.status")
                                Text(lastLine).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if sync.pendingCount > 0 {
                            Divider().overlay(Theme.hairline)
                            HStack { Spacer()
                                Button { Task { await sync.retryFailed() } } label: {
                                    Group { if sync.isSyncing { ProgressView().tint(.white) } else { Text("Thử lại") } }
                                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 18).frame(height: 36).background(Theme.accent, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("sync.retry")
                            }
                        }
                    }
                    .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))

                    if !sync.items.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(sync.items) { item in
                                HStack {
                                    Text(item.label).font(.system(size: 14)).foregroundStyle(.white).lineLimit(1)
                                    Spacer()
                                    Text(item.state == .failed ? "Lỗi – thử lại" : (sync.isSyncing ? "Đang gửi" : "Đang chờ"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(item.state == .failed ? Theme.accent : Theme.textSecondary)
                                        .padding(.horizontal, 8).frame(height: 24)
                                        .background(item.state == .failed ? Theme.accent.opacity(0.15) : Theme.surfaceHigh, in: Capsule())
                                }
                                .padding(.horizontal, 16).frame(height: 54)
                                .contextMenu {
                                    if let e = item.errorMessage { Text(e) }
                                    Button("Bỏ thay đổi này", role: .destructive) { sync.discard(item.id) }
                                }
                                if item.id != sync.items.last?.id { Divider().overlay(Theme.hairline) }
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                    }

                    Text("Quyền truy cập").font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(.top, 10).padding(.leading, 4)
                    VStack(spacing: 0) {
                        permRow(icon: "location", title: "Vị trí", value: location.statusText) {
                            if location.authorization == .notDetermined { location.requestWhenInUse() } else { openSettings() }
                        }
                        Divider().overlay(Theme.hairline).padding(.leading, 48)
                        permRow(icon: "photo.on.rectangle", title: "Ảnh", value: photoText) {
                            if photoStatus == .notDetermined {
                                PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in DispatchQueue.main.async { photoStatus = s } }
                            } else { openSettings() }
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                    InfoNote(text: "Thay đổi được lưu trên máy trước và tự gửi lên khi có mạng.", icon: "info.circle").padding(.horizontal, 4)
                }
                .padding(.horizontal, 20).padding(.top, 20)
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var lastLine: String {
        if !sync.isOnline { return "Đang ngoại tuyến" }
        guard let d = sync.lastSyncedAt else { return "Chưa đồng bộ lần nào" }
        return "Lần cuối: \(VNFormat.time(d))"
    }

    private var photoText: String {
        switch photoStatus {
        case .authorized: return "Toàn bộ ảnh"
        case .limited: return "Đã chọn ảnh"
        case .denied, .restricted: return "Đã tắt"
        default: return "Hỏi khi chọn ảnh"
        }
    }

    private func openSettings() { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }

    private func permRow(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.white).frame(width: 20)
                Text(title).font(.system(size: 15)).foregroundStyle(.white)
                Spacer()
                Text(value).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16).frame(height: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
