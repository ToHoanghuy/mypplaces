import SwiftUI

/// 07a – invite by link (optionally bound to an email), role Viewer/Editor, expiry 1/7/30 days (default 7).
struct ShareSheetView: View {
    var target: ShareTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var role: MemberRole = .viewer
    @State private var email = ""
    @State private var ttl = 7
    @State private var creating = false
    @State private var error: String?
    @State private var created: CreatedInvitation?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Text("Chia sẻ \(target.type.noun)").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                HStack {
                    CircleIconButton(systemName: "xmark", size: 32, background: Theme.surface) { dismiss() }
                    Spacer()
                    Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { router.push(.members(target)) } } label: {
                        Image(systemName: "person.2").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                            .frame(width: 32, height: 32).background(Theme.surface, in: Circle())
                    }
                    .accessibilityIdentifier("share.members")
                }
            }
            .padding(.top, 20)

            HStack(spacing: 12) {
                PlaceThumb(path: target.coverPath, category: target.category ?? .other, size: 48, corner: 12)
                Text(target.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                if let c = target.category { CategoryDot(category: c) }
                Spacer()
            }
            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))

            if let created { result(created) } else { form }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .screenBackground()
        .presentationDetents([.large])
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quyền").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            roleRow(.viewer, title: "Người xem – Chỉ xem")
            roleRow(.editor, title: "Biên tập – Thêm kỷ niệm")
            InputField(placeholder: "Email (tùy chọn)", text: $email, keyboard: .emailAddress, leadingIcon: "envelope", identifier: "share.email")
            Text("Hết hạn sau").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ForEach([1, 7, 30], id: \.self) { d in
                    Button { ttl = d } label: {
                        Text("\(d) ngày").font(.system(size: 14, weight: ttl == d ? .semibold : .regular))
                            .foregroundStyle(ttl == d ? Theme.background : Theme.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(ttl == d ? Theme.textPrimary : Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("share.ttl.\(d)")
                }
            }
            InfoNote(text: scopeNote)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }
            Spacer()
            PrimaryButton(title: "Tạo liên kết mời", icon: "link", isLoading: creating) { create() }
                .accessibilityIdentifier("share.create")
        }
    }

    private func result(_ inv: CreatedInvitation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Đã tạo liên kết mời · \(role.displayName) · \(VNFormat.expiresIn(inv.expiresAt))")
                    .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            }
            Text(inv.link.absoluteString).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                .lineLimit(2).truncationMode(.middle)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("share.link")
            if !email.isEmpty { InfoNote(text: "Chỉ tài khoản có email \(email.lowercased()) mới mở được liên kết này.", icon: "envelope") }
            Spacer()
            ShareLink(item: inv.link, message: Text("Mời bạn xem \(target.type.noun) “\(target.title)” trên MyPlaces")) {
                HStack { Image(systemName: "square.and.arrow.up"); Text("Gửi liên kết") }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 52).background(Theme.accent, in: Capsule())
            }
            Button {
                UIPasteboard.general.string = inv.link.absoluteString
                copied = true
            } label: {
                Text(copied ? "Đã sao chép" : "Sao chép liên kết").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("share.copy")
        }
    }

    private var scopeNote: String {
        switch target.type {
        case .place: return "Được chia sẻ: tên, danh mục, địa chỉ, kỷ niệm của địa điểm. Không chia sẻ: lịch sử lần ghé."
        case .visit: return "Được chia sẻ: thời gian, ghi chú, người đi cùng và kỷ niệm của lần ghé này. Không chia sẻ: các lần ghé khác."
        case .journal: return "Được chia sẻ: các địa điểm, lần ghé đã thêm và kỷ niệm trong nhật ký. Không chia sẻ: địa chỉ và các lần ghé khác."
        }
    }

    private func roleRow(_ r: MemberRole, title: String) -> some View {
        Button { role = r } label: {
            HStack {
                Text(title).font(.system(size: 15)).foregroundStyle(role == r ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
                Image(systemName: role == r ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(role == r ? Theme.accent : Theme.textTertiary)
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(role == r ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("share.role.\(r.rawValue)")
    }

    private func create() {
        creating = true; error = nil
        Task {
            do {
                created = try await MyPlacesAPI.shared.createInvitation(target.type, target.id, role: role, email: email, ttlDays: ttl)
                AppEvents.shared.bump()
            } catch { self.error = AppError.message(error) }
            creating = false
        }
    }
}
