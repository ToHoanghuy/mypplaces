import SwiftUI

@MainActor
@Observable
final class JournalListModel {
    var journals: [Journal] = []
    var memberships: [MyPlacesAPI.MemberCount] = []
    var loaded = false
    var error: String?

    func load() async {
        do {
            async let j = MyPlacesAPI.shared.journals()
            async let m = MyPlacesAPI.shared.journalMemberships()
            journals = try await j
            memberships = (try? await m) ?? []
            error = nil
        } catch { self.error = AppError.message(error) }
        loaded = true
    }

    func role(_ j: Journal) -> MemberRole {
        if j.ownerId == MyPlacesAPI.shared.userID { return .owner }
        return memberships.first { $0.journalId == j.id && $0.userId == MyPlacesAPI.shared.userID }?.role ?? .viewer
    }

    func memberCount(_ j: Journal) -> Int { memberships.filter { $0.journalId == j.id }.count }

    func badge(_ j: Journal) -> (icon: String, text: String) {
        let r = role(j)
        if r != .owner { return ("person.2", "Được chia sẻ · \(r.displayName)") }
        let n = memberCount(j)
        return n == 0 ? ("lock", "Riêng tư") : ("person.2", "Chủ sở hữu · \(n + 1) người")
    }
}

/// 06a – journals list (+ archived list).
struct JournalListView: View {
    var archivedOnly = false
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var model = JournalListModel()
    @State private var showCreate = false

    var body: some View {
        VStack(spacing: 0) {
            if model.loaded && visible.isEmpty {
                Spacer()
                EmptyStateView(icon: "book", title: archivedOnly ? "Không có nhật ký lưu trữ" : "Chưa có nhật ký",
                               message: archivedOnly ? "Nhật ký đã lưu trữ sẽ hiện ở đây." : "Gom các địa điểm và lần ghé của một chuyến đi vào một nhật ký.",
                               actionTitle: archivedOnly ? nil : "Tạo nhật ký") { showCreate = true }
                Spacer()
                if !archivedOnly && archivedCount > 0 { archivedRow.padding(.horizontal, 20).padding(.bottom, 26 + Theme.tabInset) }
            } else if !model.loaded {
                Spacer(); ProgressView().tint(Theme.textPrimary); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visible) { j in
                            Button { router.push(.journal(j.id)) } label: { card(j) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("journal.card.\(j.title)")
                        }
                        if !archivedOnly && archivedCount > 0 { archivedRow.padding(.top, 8) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 36 + Theme.tabInset)
                }
                .refreshable { await model.load() }
            }
        }
        .screenBackground()
        .mpTabRootTitle(archivedOnly ? "Đã lưu trữ" : "Nhật ký")
        .toolbar {
            if !archivedOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarIconButton(systemName: "plus") { showCreate = true }
                        .accessibilityIdentifier("journals.add")
                        .accessibilityLabel("Tạo nhật ký")
                }
            }
        }
        .task(id: AppEvents.shared.revision) { await model.load() }
        .fullScreenCover(isPresented: $showCreate) {
            CreateJournalView { id in router.push(.journal(id)) }
        }
    }

    private var visible: [Journal] { model.journals.filter { $0.isArchived == archivedOnly } }
    private var archivedCount: Int { model.journals.filter(\.isArchived).count }

    private var archivedRow: some View {
        Button { router.push(.archivedJournals) } label: {
            HStack {
                Text("Đã lưu trữ (\(archivedCount))").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func card(_ j: Journal) -> some View {
        let badge = model.badge(j)
        return ZStack(alignment: .bottomLeading) {
            StorageImage(path: j.coverPath)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(j.title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let r = j.dateRange { Text(r).font(.system(size: 12)).foregroundStyle(Theme.textPrimary.opacity(0.75)) }
            }
            .padding(16)
            .onPhoto()
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                Image(systemName: badge.icon).font(.system(size: 10))
                Text(badge.text).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.onAccent).padding(.horizontal, 10).frame(height: 24)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(12)
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

/// Pick a journal I can contribute to (used by "Thêm vào nhật ký" from a visit).
struct JournalPickerSheet: View {
    var onPick: (Journal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model = JournalListModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thêm vào nhật ký").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.top, 24)
            let list = model.journals.filter { !$0.isArchived && model.role($0).canContribute }
            if model.loaded && list.isEmpty {
                Text("Bạn chưa có nhật ký nào có thể thêm.").font(.mpCallout).foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(list) { j in
                        Button { onPick(j); dismiss() } label: {
                            HStack(spacing: 12) {
                                StorageImage(path: j.coverPath).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading) {
                                    Text(j.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                    if let r = j.dateRange { Text(r).font(.mpCaption).foregroundStyle(Theme.textSecondary) }
                                }
                                Spacer()
                            }
                            .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .task { await model.load() }
    }
}
