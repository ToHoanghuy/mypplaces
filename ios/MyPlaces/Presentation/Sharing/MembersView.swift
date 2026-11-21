import SwiftUI

@MainActor
@Observable
final class MembersModel {
    let target: ShareTarget
    var ownerId: UUID?
    var ownerName = ""
    var members: [MemberRow] = []
    var invitations: [InvitationRow] = []
    var loaded = false
    var error: String?
    private let api = MyPlacesAPI.shared

    init(target: ShareTarget) { self.target = target }

    var isOwner: Bool { ownerId == api.userID }

    func load() async {
        do {
            switch target.type {
            case .place: ownerId = try await api.place(target.id)?.ownerId
            case .journal: ownerId = try await api.journal(target.id)?.ownerId
            case .visit: ownerId = try await api.timelineItem(visit: target.id)?.ownerId
            }
            if let ownerId { ownerName = (try? await api.profile(ownerId).displayName) ?? "" }
            members = try await api.members(target.type, target.id)
            invitations = isOwner ? ((try? await api.listInvitations(target.type, target.id)) ?? []).filter { $0.status == .pending } : []
            error = nil
        } catch { self.error = AppError.message(error) }
        loaded = true
    }
}

/// 07b – members, roles, pending invitations, transfer ownership, stop sharing.
struct MembersView: View {
    let target: ShareTarget
    @Environment(\.dismiss) private var dismiss
    @State private var model: MembersModel
    @State private var showShare = false
    @State private var toast: String?
    @State private var confirmUnshare = false
    @State private var showTransfer = false
    @State private var confirmLeave = false

    init(target: ShareTarget) {
        self.target = target
        _model = State(initialValue: MembersModel(target: target))
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var backButton: some View {
        CircleIconButton(systemName: "chevron.left", background: Theme.surface) { dismiss() }.accessibilityIdentifier("nav.back")
    }
    private var titleText: some View {
        Text("Thành viên").font(.mpLargeTitle).foregroundStyle(Theme.textPrimary)
    }
    private var countChip: some View {
        HStack(spacing: 4) { Image(systemName: "person.2"); Text("\(model.members.count + 1) người") }
            .font(.mp(12)).foregroundStyle(Theme.textSecondary)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 10).frame(minHeight: 28).background(Theme.surface, in: Capsule())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Accessibility sizes: title gets its own row so "Thành viên" never breaks mid-word.
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { backButton; Spacer(minLength: 8); countChip }
                        titleText
                    }
                } else {
                    HStack(spacing: 12) { backButton; titleText; Spacer(minLength: 8); countChip }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        if let owner = model.ownerId {
                            memberRow(name: model.ownerName + (owner == MyPlacesAPI.shared.userID ? " (bạn)" : ""),
                                      subtitle: "Tạo \(target.type.noun)", role: .owner, userId: owner)
                        }
                        ForEach(model.members) { m in
                            Divider().overlay(Theme.hairline).padding(.leading, 64)
                            memberRow(name: (m.profile?.displayName ?? "Thành viên") + (m.userId == MyPlacesAPI.shared.userID ? " (bạn)" : ""),
                                      subtitle: "Tham gia \(VNFormat.relative(m.joinedAt).lowercased())", role: m.role, userId: m.userId)
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))

                    if !model.invitations.isEmpty {
                        Text("LỜI MỜI ĐANG CHỜ").font(.mpSection).tracking(0.6).foregroundStyle(Theme.textSecondary).padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(model.invitations) { inv in
                                HStack(spacing: 12) {
                                    Image(systemName: inv.inviteeEmailNormalized == nil ? "link" : "envelope").foregroundStyle(Theme.textSecondary)
                                        .frame(width: 40, height: 40).background(Theme.surfaceHigh, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(inv.inviteeEmailNormalized ?? "Liên kết mời").font(.mp(15, .medium)).foregroundStyle(Theme.textPrimary)
                                        Text("\(inv.role.displayName) · \(VNFormat.expiresIn(inv.expiresAt))").font(.mp(12)).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Button("Thu hồi") { act { try await MyPlacesAPI.shared.revokeInvitation(inv.id) } }
                                        .font(.mp(13, .semibold)).foregroundStyle(Theme.danger)
                                        .accessibilityIdentifier("invite.revoke")
                                }
                                .padding(12)
                            }
                        }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                    InfoNote(text: privacyNote).padding(.horizontal, 4)
                    if let e = model.error { Text(e).font(.mpCaption).foregroundStyle(Theme.danger) }
                }
                .padding(.horizontal, 20).padding(.top, 20)
            }

            VStack(spacing: 10) {
                if model.isOwner {
                    PrimaryButton(title: "Mời thêm", icon: "plus") { showShare = true }.accessibilityIdentifier("members.invite")
                    HStack(spacing: 10) {
                        Button("Chuyển quyền sở hữu") { showTransfer = true }.foregroundStyle(Theme.textSecondary)
                            .disabled(model.members.isEmpty)
                        Text("·").foregroundStyle(Theme.textTertiary)
                        Button("Ngừng chia sẻ") { confirmUnshare = true }.foregroundStyle(Theme.danger)
                            .disabled(model.members.isEmpty && model.invitations.isEmpty)
                    }
                    .font(.mp(13))
                } else if model.loaded {
                    Button("Rời \(target.type.noun)") { confirmLeave = true }
                        .font(.mp(14, .medium)).foregroundStyle(Theme.danger).padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .toast($toast)
        .task(id: AppEvents.shared.revision) { await model.load() }
        .sheet(isPresented: $showShare) { ShareSheetView(target: target) }
        .confirmationDialog("Ngừng chia sẻ?", isPresented: $confirmUnshare, titleVisibility: .visible) {
            Button("Ngừng chia sẻ", role: .destructive) { act { try await MyPlacesAPI.shared.unshare(target.type, target.id) } }
        } message: { Text("Mọi thành viên sẽ mất quyền truy cập và các lời mời đang chờ bị thu hồi.") }
        .confirmationDialog("Chuyển quyền sở hữu cho", isPresented: $showTransfer, titleVisibility: .visible) {
            ForEach(model.members) { m in
                Button(m.profile?.displayName ?? "Thành viên") {
                    act { try await MyPlacesAPI.shared.transferOwnership(target.type, target.id, to: m.userId) }
                }
            }
        } message: { Text("Bạn sẽ trở thành Biên tập viên.") }
        .confirmationDialog("Rời \(target.type.noun)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Rời", role: .destructive) {
                act(dismissAfter: true) { try await MyPlacesAPI.shared.leave(target.type, target.id); await PlacesStore.shared.refresh() }
            }
        }
    }

    private var privacyNote: String {
        switch target.type {
        case .journal: return "Chỉ thành viên mới có thể xem các bức ảnh và kỷ niệm trong nhật ký này."
        case .place: return "Thành viên thấy tên, danh mục, địa chỉ và kỷ niệm của địa điểm, không thấy lịch sử lần ghé của bạn."
        case .visit: return "Thành viên chỉ thấy lần ghé này, không thấy các lần ghé khác."
        }
    }

    @ViewBuilder
    private func memberRow(name: String, subtitle: String, role: MemberRole, userId: UUID) -> some View {
        HStack(spacing: 12) {
            Avatar(name: name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.mp(15, .semibold)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.mp(12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if model.isOwner && role != .owner {
                Menu {
                    Button { act { try await MyPlacesAPI.shared.changeRole(target.type, target.id, user: userId, role: .editor) } } label: {
                        if role == .editor { Label("Biên tập", systemImage: "checkmark") } else { Text("Biên tập") }
                    }
                    Button { act { try await MyPlacesAPI.shared.changeRole(target.type, target.id, user: userId, role: .viewer) } } label: {
                        if role == .viewer { Label("Người xem", systemImage: "checkmark") } else { Text("Người xem") }
                    }
                    Button(role: .destructive) { act { try await MyPlacesAPI.shared.removeMember(target.type, target.id, user: userId) } } label: {
                        Label("Xóa khỏi \(target.type.noun)", systemImage: "person.badge.minus")
                    }
                } label: {
                    HStack(spacing: 4) { Text(role.displayName); Image(systemName: "chevron.down").font(.mp(9)) }
                        .font(.mp(12, .medium)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10).frame(minHeight: 28).background(Theme.surfaceHigh, in: Capsule())
                }
                .accessibilityIdentifier("member.role.\(name)")
            } else {
                Badge(text: role.displayName)
            }
        }
        .padding(12)
    }

    private func act(dismissAfter: Bool = false, _ op: @escaping () async throws -> Void) {
        Task {
            do {
                try await op()
                AppEvents.shared.bump()
                if dismissAfter { dismiss() }
            } catch { toast = AppError.message(error) }
        }
    }
}
