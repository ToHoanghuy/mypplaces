import SwiftUI

/// 07c – accept / decline an invitation, 07d – invalid (expired / revoked / used / not for me).
struct InvitationView: View {
    let token: String
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var preview: InvitationPreview?
    @State private var failure: String?
    @State private var failureCode: String?
    @State private var working = false
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if preview != nil { Text("Lời mời tham gia").font(.system(size: 13)).foregroundStyle(Theme.textSecondary) }
                HStack { CircleIconButton(systemName: "xmark", size: 34, background: Theme.surface) { close() }; Spacer() }
            }
            .padding(.horizontal, 20).padding(.top, 10)

            if let preview { card(preview) }
            else if failure != nil { invalid }
            else { Spacer(); ProgressView().tint(Theme.textPrimary); Spacer() }
        }
        .screenBackground()
        .task { await resolve() }
    }

    private func card(_ p: InvitationPreview) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if let c = p.resourceCoverPath { StorageImage(path: c) } else {
                        LinearGradient(colors: [Theme.accent.opacity(0.5), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: icon(p.resourceType)).font(.system(size: 40)).foregroundStyle(Theme.textPrimary.opacity(0.8))
                    }
                }
                .frame(height: 190).clipped()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Avatar(name: p.inviterDisplayName ?? "?", size: 22)
                        Text(p.inviterDisplayName ?? "Ai đó").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        + Text(" mời bạn vào \(p.resourceType.noun)").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    Text(title(p)).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("invite.title")
                    Badge(text: "Quyền: \(p.role.displayName)", icon: p.role == .editor ? "pencil" : "eye", tone: Theme.textPrimary)
                    Text(p.role == .editor ? "Bạn có thể xem và thêm kỷ niệm." : "Bạn có thể xem nhưng không chỉnh sửa.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    Text("Lời mời \(VNFormat.expiresIn(p.expiresAt))").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                .padding(18)
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 20)
            Spacer()
            if let actionError { Text(actionError).font(.mpCaption).foregroundStyle(Theme.danger).padding(.bottom, 8) }
            PrimaryButton(title: "Chấp nhận", isLoading: working) { accept() }
                .padding(.horizontal, 20)
                .accessibilityIdentifier("invite.accept")
            Button("Từ chối") { decline() }.font(.system(size: 14)).foregroundStyle(Theme.textSecondary).padding(.vertical, 16)
                .accessibilityIdentifier("invite.decline")
        }
    }

    private var invalid: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: failureCode == "INVITATION_EXPIRED" ? "hourglass" : "link.badge.plus")
                .font(.system(size: 26)).foregroundStyle(Theme.textPrimary)
                .frame(width: 64, height: 64).background(Theme.surfaceHigh, in: Circle())
            Text(failure ?? "").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                .accessibilityIdentifier("invite.invalid")
            Text(failureCode == "FORBIDDEN" ? "Lời mời này dành cho một tài khoản khác. Hãy đăng nhập đúng email được mời." : "Hãy nhờ người mời gửi lại liên kết mới.")
                .font(.system(size: 14)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: "Về trang chính", tone: .white) { close() }
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    private func icon(_ t: ResourceType) -> String {
        switch t { case .place: return "mappin.and.ellipse"; case .visit: return "clock"; case .journal: return "book" }
    }

    private func title(_ p: InvitationPreview) -> String {
        if let t = p.resourceTitle { return t }
        if let d = p.resourceVisitedAt { return "Lần ghé \(VNFormat.weekdayDay(d))" }
        return "Lời mời"
    }

    private func resolve() async {
        do { preview = try await MyPlacesAPI.shared.resolveInvitation(token: token) }
        catch { fail(error) }
    }

    private func fail(_ error: Error) {
        failureCode = AppError.code(error)
        switch failureCode {
        case "INVITATION_EXPIRED": failure = "Lời mời đã hết hạn"
        case "INVITATION_REVOKED": failure = "Lời mời đã bị thu hồi"
        case "INVITATION_DECLINED": failure = "Lời mời đã bị từ chối"
        case "INVITATION_USED", "ALREADY_MEMBER": failure = "Lời mời đã được sử dụng"
        case "FORBIDDEN": failure = "Lời mời không dành cho bạn"
        case "ALREADY_OWNER": failure = "Bạn đã là chủ sở hữu"
        case "RESOURCE_NOT_FOUND": failure = "Nội dung không còn tồn tại"
        default: failure = AppError.isNetwork(error) ? "Không có kết nối mạng" : "Không tìm thấy lời mời"
        }
        preview = nil
    }

    private func accept() {
        working = true; actionError = nil
        Task {
            do {
                let r = try await MyPlacesAPI.shared.acceptInvitation(token: token)
                await PlacesStore.shared.refresh()
                AppEvents.shared.bump()
                router.inviteToken = nil
                router.show(r.resourceType, r.resourceId)
            } catch {
                if AppError.isNetwork(error) { actionError = AppError.message(error) } else { fail(error) }
            }
            working = false
        }
    }

    private func decline() {
        Task {
            try? await MyPlacesAPI.shared.declineInvitation(token: token)
            close()
        }
    }

    private func close() { router.inviteToken = nil; dismiss() }
}

/// Paste an invitation link (custom-scheme links are not always tappable in chat apps).
struct EnterInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nhập liên kết mời").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.top, 24)
            Text("Dán liên kết myplaces://invite/… bạn nhận được.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            InputField(placeholder: "myplaces://invite/…", text: $text, keyboard: .URL, leadingIcon: "link", identifier: "invite.input")
            HStack {
                Button("Dán") { text = UIPasteboard.general.string ?? text }.foregroundStyle(Theme.accent)
                Spacer()
            }
            Spacer()
            PrimaryButton(title: "Mở lời mời", isEnabled: DeepLink.parseInvite(text) != nil) {
                if let token = DeepLink.parseInvite(text) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.inviteToken = token }
                }
            }
            .accessibilityIdentifier("invite.open")
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .screenBackground()
    }
}
