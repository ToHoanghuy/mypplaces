import SwiftUI

@MainActor
@Observable
final class VisitDetailModel {
    let visitID: UUID
    var item: TimelineItem?
    var participants: [VisitParticipant] = []
    var memories: [Memory] = []
    var loading = true
    var notFound = false
    var error: String?
    private let api = MyPlacesAPI.shared

    init(visitID: UUID) { self.visitID = visitID }

    var photos: [String] { memories.flatMap { $0.attachments.map(\.storagePath) } }
    var role: MemberRole { item?.myRole ?? .viewer }

    func load() async {
        do {
            item = try await api.timelineItem(visit: visitID)
            if item == nil {
                notFound = SyncEngine.shared.state(for: visitID) == nil
                loading = false
                return
            }
            async let p = api.participants(visit: visitID)
            async let m = api.memories(.visit(visitID))
            participants = try await p
            memories = try await m
            notFound = false
        } catch {
            self.error = AppError.message(error)
        }
        loading = false
    }
}

/// 04c – visit detail: photos, time in the visit's own timezone, note, companions, memories.
struct VisitDetailView: View {
    let visitID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State private var model: VisitDetailModel
    @State private var page = 0
    @State private var showAddMemory = false
    @State private var shareTarget: ShareTarget?
    @State private var showJournalPicker = false
    @State private var confirmDelete = false
    @State private var confirmLeave = false
    @State private var toast: String?

    init(visitID: UUID) {
        self.visitID = visitID
        _model = State(initialValue: VisitDetailModel(visitID: visitID))
    }

    var body: some View {
        Group {
            if let item = model.item { content(item) }
            else if model.notFound {
                VStack { backBar; Spacer()
                    EmptyStateView(icon: "clock.badge.xmark", title: "Không tìm thấy lần ghé", message: "Lần ghé đã bị xóa hoặc bạn không còn quyền xem.")
                    Spacer() }
            } else if !model.loading {
                VStack { backBar; Spacer()
                    EmptyStateView(icon: "arrow.triangle.2.circlepath", title: "Đang chờ đồng bộ", message: "Lần ghé sẽ hiện đầy đủ khi đồng bộ xong.")
                    Spacer() }
            } else { ProgressView().tint(Theme.textPrimary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: AppEvents.shared.revision) { await model.load() }
        .toast($toast)
        .fullScreenCover(isPresented: $showAddMemory) {
            if let item = model.item {
                AddMemoryView(parent: .visit(visitID), contextLabel: "Vào: Lần ghé · \(VNFormat.dayMonth(item.visitedAt, tz: VNFormat.tz(item.timezoneId))) · \(item.title)")
            }
        }
        .sheet(item: $shareTarget) { ShareSheetView(target: $0) }
        .sheet(isPresented: $showJournalPicker) {
            JournalPickerSheet { journal in
                Task {
                    do {
                        try await MyPlacesAPI.shared.linkVisits([JournalVisitInsert(journalId: journal.id, visitId: visitID, sortOrder: 0)])
                        toast = "Đã thêm vào \(journal.title)"
                        AppEvents.shared.bump()
                    } catch { toast = AppError.isDuplicate(error) ? "Lần ghé đã có trong nhật ký" : AppError.message(error) }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.background)
        }
        .confirmationDialog("Xóa lần ghé này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xóa lần ghé", role: .destructive) { delete() }
        } message: { Text("Lần ghé sẽ bị ẩn khỏi dòng thời gian và nhật ký.") }
        .confirmationDialog("Rời lần ghé chia sẻ?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Rời", role: .destructive) { leave() }
        }
    }

    private var backBar: some View {
        HStack { CircleIconButton(systemName: "chevron.left", background: Theme.surface) { dismiss() }; Spacer() }.padding(16)
    }

    private func content(_ item: TimelineItem) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroCard(item).padding(.horizontal, 8)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("KỶ NIỆM").font(.mpSection).tracking(0.6).foregroundStyle(Theme.textSecondary)
                        let notes = model.memories.filter { ($0.body ?? "").isEmpty == false }
                        if notes.isEmpty {
                            Text("Chưa có kỷ niệm nào. Thêm vài dòng hoặc ảnh để nhớ lần ghé này.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(notes) { m in memoryRow(m) }
                    }
                    .padding(.horizontal, 20).padding(.top, 22)
                    Color.clear.frame(height: 110)
                }
            }
            HStack(spacing: 12) {
                if item.myRole.canContribute {
                    PrimaryButton(title: "Thêm kỷ niệm", icon: "plus") { showAddMemory = true }
                        .accessibilityIdentifier("visit.addMemory")
                }
                if item.myRole == .owner {
                    CircleIconButton(systemName: "square.and.arrow.up", size: 52, background: Theme.surface) {
                        shareTarget = ShareTarget(type: .visit, id: visitID, title: "\(item.title) · \(VNFormat.dayMonth(item.visitedAt, tz: VNFormat.tz(item.timezoneId)))",
                                                  coverPath: item.coverStoragePath, category: item.placeCategory)
                    }
                    .accessibilityIdentifier("visit.share")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    private func heroCard(_ item: TimelineItem) -> some View {
        let photos = model.photos
        return ZStack(alignment: .bottomLeading) {
            if photos.isEmpty {
                PlaceholderArt(category: item.placeCategory)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, path in
                        StorageImage(path: path, placeholderCategory: item.placeCategory).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if item.placeAvailable { router.push(.place(item.placeId)) }
                } label: {
                    HStack(spacing: 6) {
                        if let c = item.placeCategory { CategoryDot(category: c) }
                        Text(item.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.onAccent.opacity(0.9))
                    }
                    .padding(.horizontal, 10).frame(height: 24).background(.black.opacity(0.4), in: Capsule())
                }
                .buttonStyle(.plain)
                Text("\(VNFormat.weekdayDay(item.local)) · \(VNFormat.time(item.local))")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("visit.date")
                HStack(alignment: .bottom) {
                    if let note = item.note, !note.isEmpty {
                        Text(note).font(.system(size: 14)).foregroundStyle(Theme.textPrimary.opacity(0.9)).lineLimit(3)
                    }
                    Spacer()
                    if !model.participants.isEmpty { AvatarStack(names: model.participants.map(\.name), size: 24, max: 2) }
                }
                if !model.participants.isEmpty {
                    Text("Cùng " + model.participants.map(\.name).joined(separator: ", "))
                        .font(.system(size: 12)).foregroundStyle(Theme.textPrimary.opacity(0.7)).lineLimit(1)
                }
            }
            .padding(18)
        }
        .frame(height: 470)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onPhoto()
        .overlay(alignment: .top) {
            HStack {
                CircleIconButton(systemName: "chevron.left") { dismiss() }.accessibilityIdentifier("nav.back")
                Spacer()
                if photos.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<min(photos.count, 8), id: \.self) { i in
                            Capsule().fill(i == page ? Theme.textPrimary : Theme.textPrimary.opacity(0.4)).frame(width: i == page ? 14 : 5, height: 5)
                        }
                    }
                }
                Spacer()
                Menu {
                    if item.myRole == .owner {
                        Button { shareTarget = ShareTarget(type: .visit, id: visitID, title: item.title, coverPath: item.coverStoragePath, category: item.placeCategory) } label: { Label("Chia sẻ lần ghé", systemImage: "person.badge.plus") }
                        Button { showJournalPicker = true } label: { Label("Thêm vào nhật ký", systemImage: "book") }
                    }
                    Button { router.push(.members(ShareTarget(type: .visit, id: visitID, title: item.title, coverPath: item.coverStoragePath, category: item.placeCategory))) } label: { Label("Thành viên", systemImage: "person.2") }
                    if item.myRole == .owner {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Xóa lần ghé", systemImage: "trash") }
                    } else {
                        Button(role: .destructive) { confirmLeave = true } label: { Label("Rời lần ghé", systemImage: "rectangle.portrait.and.arrow.right") }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .frame(width: 36, height: 36).background(Color.black.opacity(0.45), in: Circle())
                }
                .accessibilityIdentifier("visit.more")
            }
            .padding(14)
        }
    }

    private func memoryRow(_ m: Memory) -> some View {
        let isMe = m.authorId == MyPlacesAPI.shared.userID
        return HStack(alignment: .top, spacing: 12) {
            Avatar(name: m.author?.displayName ?? "?", path: m.author?.avatarPath, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isMe ? "Bạn" : (m.author?.displayName ?? "Thành viên")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(VNFormat.relative(m.createdAt)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Text(m.body ?? "").font(.system(size: 14)).foregroundStyle(Theme.textPrimary.opacity(0.9))
                if !m.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(m.attachments.prefix(3)) { a in
                            StorageImage(path: a.storagePath).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
    }

    private func delete() {
        Task {
            do { try await MyPlacesAPI.shared.softDeleteVisit(visitID); AppEvents.shared.bump(); await PlacesStore.shared.refresh(); dismiss() }
            catch { toast = AppError.message(error) }
        }
    }

    private func leave() {
        Task {
            do { try await MyPlacesAPI.shared.leave(.visit, visitID); AppEvents.shared.bump(); dismiss() }
            catch { toast = AppError.message(error) }
        }
    }
}
