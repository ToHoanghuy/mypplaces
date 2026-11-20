import SwiftUI

@MainActor
@Observable
final class PlaceDetailModel {
    let placeID: UUID
    var place: MapPlace?
    var visits: [Visit] = []
    var participants: [UUID: [VisitParticipant]] = [:]
    var visitPhotos: [UUID: String] = [:]
    var memories: [Memory] = []          // place memories + visit memories
    var journals: [MyPlacesAPI.JournalLink] = []
    var ownerName: String?
    var loading = true
    var notFound = false
    var error: String?

    private let api = MyPlacesAPI.shared
    init(placeID: UUID) { self.placeID = placeID }

    var role: MemberRole { place?.role ?? .viewer }
    var isOwner: Bool { place?.isOwner ?? false }

    var pendingVisits: [VisitDraftPayload] {
        SyncEngine.shared.payloads(.visitCreate, as: VisitDraftPayload.self).filter { $0.visit.placeId == placeID }
    }

    var photoMemories: [(memory: Memory, path: String)] {
        memories.flatMap { m in m.attachments.map { (m, $0.storagePath) } }
    }

    func load() async {
        if let local = PlacesStore.shared.place(placeID) { place = local }
        do {
            if let remote = try await api.mapPlace(placeID) {
                place = remote
            } else if SyncEngine.shared.state(for: placeID) != nil {
                loading = false; return          // created offline, not on the server yet
            } else {
                place = nil; notFound = true; loading = false; return
            }
            async let v = api.visits(place: placeID)
            async let pm = api.memories(.place(placeID))
            visits = try await v
            let ids = visits.map(\.id)
            async let parts = api.participants(visits: ids)
            async let vm = api.memories(visits: ids)
            let visitMemories = try await vm
            participants = Dictionary(grouping: try await parts, by: \.visitId)
            var photos: [UUID: String] = [:]
            for m in visitMemories.sorted(by: { $0.createdAt > $1.createdAt }) {
                if let vid = m.visitId, photos[vid] == nil, let a = m.attachments.first { photos[vid] = a.storagePath }
            }
            visitPhotos = photos
            memories = (try await pm) + visitMemories
            if isOwner {
                journals = ((try? await api.journalsContaining(place: placeID)) ?? []).filter { $0.journals?.deletedAt == nil && $0.journals != nil }
            } else if let owner = place?.ownerId {
                ownerName = try? await api.profile(owner).displayName
            }
            notFound = false
            error = nil
        } catch {
            if place == nil { notFound = !AppError.isNetwork(error) }
            self.error = AppError.message(error)
        }
        loading = false
    }
}

/// 03c (owner) and 07e (shared with me) place detail.
struct PlaceDetailView: View {
    let placeID: UUID
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaceDetailModel
    @State private var showLogVisit = false
    @State private var showAddMemory = false
    @State private var showEdit = false
    @State private var shareTarget: ShareTarget?
    @State private var confirmLeave = false
    @State private var toast: String?
    @State private var viewerPhoto: String?

    init(placeID: UUID) {
        self.placeID = placeID
        _model = State(initialValue: PlaceDetailModel(placeID: placeID))
    }

    var body: some View {
        Group {
            if let place = model.place {
                if place.isOwner { ownerLayout(place) } else { sharedLayout(place) }
            } else if model.notFound {
                EmptyStateView(icon: "mappin.slash", title: "Không tìm thấy địa điểm", message: "Địa điểm đã bị xóa hoặc bạn không còn quyền xem.",
                               actionTitle: nil)
            } else {
                ProgressView().tint(Theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: AppEvents.shared.revision) { await model.load() }
        .toast($toast)
        .fullScreenCover(isPresented: $showLogVisit) {
            if let p = model.place { LogVisitView(place: p) }
        }
        .fullScreenCover(isPresented: $showAddMemory) {
            if let p = model.place { AddMemoryView(parent: .place(p.id), contextLabel: "Vào: Địa điểm · \(p.title)") }
        }
        .fullScreenCover(isPresented: $showEdit) {
            if let p = model.place { EditPlaceView(place: p) { dismiss() } }
        }
        .sheet(item: $shareTarget) { t in ShareSheetView(target: t) }
        .fullScreenCover(item: Binding(get: { viewerPhoto.map { PhotoRef(path: $0) } }, set: { viewerPhoto = $0?.path })) { ref in
            PhotoViewer(path: ref.path)
        }
        .confirmationDialog("Rời địa điểm chia sẻ?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Rời địa điểm", role: .destructive) { leave() }
        } message: { Text("Bạn sẽ không còn xem được địa điểm này.") }
    }

    // MARK: Owner (03c)

    private func ownerLayout(_ p: MapPlace) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(p, height: 300, rounded: false)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) { CategoryDot(category: p.category); Text(p.category.displayName).font(.mpCaption).foregroundStyle(Theme.textSecondary) }
                        Text(p.title).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            .accessibilityIdentifier("place.title")
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse").font(.system(size: 12))
                            Text(p.address ?? "Chưa có địa chỉ").font(.system(size: 13)).lineLimit(1)
                            Badge(text: MemberRole.owner.displayName)
                            if let s = SyncEngine.shared.state(for: p.id) { Badge(text: s == .failed ? "Lỗi đồng bộ" : "Chưa đồng bộ", tone: s == .failed ? Theme.danger : Theme.textSecondary) }
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)

                    visitsSection.padding(.top, 26)
                    memoriesStrip(p).padding(.top, 26)
                    if !model.journals.isEmpty { journalsSection.padding(.top, 26) }
                    Color.clear.frame(height: 110)
                }
            }
            .ignoresSafeArea(edges: .top)

            PrimaryButton(title: "Ghi lần ghé", icon: "camera") { showLogVisit = true }
                .padding(.horizontal, 20).padding(.bottom, 8)
                .accessibilityIdentifier("place.logVisit")
        }
    }

    private var visitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Lần ghé", count: model.visits.count + model.pendingVisits.count)
            if model.visits.isEmpty && model.pendingVisits.isEmpty {
                Text("Chưa ghé · muốn đến. Ghi lần ghé đầu tiên khi bạn tới nơi.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            ForEach(model.pendingVisits, id: \.visit.id) { d in
                visitRow(date: d.visit.visitedAt, tz: d.visit.timezoneId, note: d.visit.note, photo: nil, names: d.participants.compactMap(\.displayNameSnapshot), pending: true)
            }
            ForEach(model.visits) { v in
                Button { router.push(.visit(v.id)) } label: {
                    visitRow(date: v.visitedAt, tz: v.timezoneId, note: v.note, photo: model.visitPhotos[v.id],
                             names: (model.participants[v.id] ?? []).map(\.name), pending: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("visit.row")
            }
        }
        .padding(.horizontal, 20)
    }

    private func visitRow(date: Date, tz: String, note: String?, photo: String?, names: [String], pending: Bool) -> some View {
        HStack(spacing: 12) {
            PlaceThumb(path: photo, category: model.place?.category ?? .other, size: 46, corner: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(VNFormat.weekdayDay(date, tz: VNFormat.tz(tz))).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(note?.isEmpty == false ? note! : VNFormat.time(date, tz: VNFormat.tz(tz)))
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            if pending { Badge(text: "Chưa đồng bộ") }
            else if !names.isEmpty { AvatarStack(names: names, size: 18, max: 2) }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func memoriesStrip(_ p: MapPlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Kỷ niệm", count: model.memories.count).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.photoMemories, id: \.path) { item in
                        Button { open(item.memory, path: item.path) } label: {
                            StorageImage(path: item.path, placeholderCategory: p.category)
                                .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    ForEach(model.memories.filter { $0.attachments.isEmpty }) { m in
                        Text(m.body ?? "").font(.system(size: 11)).foregroundStyle(Theme.textPrimary).lineLimit(4)
                            .padding(8).frame(width: 84, height: 84, alignment: .topLeading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if model.role.canContribute {
                        Button { showAddMemory = true } label: {
                            Image(systemName: "plus").font(.system(size: 18)).foregroundStyle(Theme.textSecondary)
                                .frame(width: 84, height: 84)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Theme.textTertiary))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("place.addMemory")
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var journalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Nhật ký")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.journals, id: \.journalId) { j in
                        Button { router.push(.journal(j.journalId)) } label: {
                            HStack(spacing: 8) {
                                StorageImage(path: j.journals?.coverPath).frame(width: 22, height: 22).clipShape(Circle())
                                Text(j.journals?.title ?? "").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.leading, 6).padding(.trailing, 12).frame(height: 36)
                            .background(Theme.surface, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Shared with me (07e)

    private func sharedLayout(_ p: MapPlace) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(p, height: 250, rounded: true).padding(.horizontal, 12).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) { CategoryDot(category: p.category); Text(p.category.displayName).font(.mpCaption).foregroundStyle(Theme.textSecondary) }
                        Text(p.title).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            .accessibilityIdentifier("place.title")
                        if let a = p.address { Text(a).font(.system(size: 14)).foregroundStyle(Theme.textSecondary) }
                        HStack(spacing: 8) {
                            Avatar(name: model.ownerName ?? "?", size: 22)
                            Image(systemName: "person.2").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            Text("\(model.ownerName ?? "Ai đó") chia sẻ với bạn").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Badge(text: p.role.displayName)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)

                    HStack {
                        Text("Kỷ niệm").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(model.memories.count) kỷ niệm").font(.mpCaption).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 20).padding(.top, 24)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(model.memories) { m in sharedMemoryTile(m, category: p.category) }
                        if p.role.canContribute {
                            Button { showAddMemory = true } label: {
                                VStack(spacing: 6) { Image(systemName: "plus"); Text("Thêm kỷ niệm").font(.mpCaption) }
                                    .foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity).frame(height: 150)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 12)

                    if !model.visits.isEmpty || p.role.canContribute {
                        visitsSection.padding(.top, 24)
                    }
                    Color.clear.frame(height: 120)
                }
            }

            VStack(spacing: 8) {
                if p.role.canContribute {
                    PrimaryButton(title: "Ghi lần ghé", icon: "camera") { showLogVisit = true }
                }
                Button("Rời địa điểm chia sẻ") { confirmLeave = true }
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(.vertical, 8)
                    .accessibilityIdentifier("place.leave")
            }
            .padding(.horizontal, 20).padding(.bottom, 4)
            .background(LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .center))
        }
    }

    private func sharedMemoryTile(_ m: Memory, category: PlaceCategory) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let a = m.attachments.first {
                StorageImage(path: a.storagePath, placeholderCategory: category)
                    .onTapGesture { viewerPhoto = a.storagePath }
            } else {
                Text(m.body ?? "").font(.system(size: 13)).foregroundStyle(Theme.textPrimary).padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.surface)
            }
            HStack(spacing: 4) {
                Avatar(name: m.author?.displayName ?? "?", size: 16)
                Text(firstName(m.author?.displayName)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.onAccent)
            }
            .padding(.horizontal, 6).frame(height: 22).background(.black.opacity(0.55), in: Capsule()).padding(8)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Shared header

    private func header(_ p: MapPlace, height: CGFloat, rounded: Bool) -> some View {
        StorageImage(path: p.coverStoragePath, placeholderCategory: p.category)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: rounded ? 28 : 0, style: .continuous))
            .overlay(alignment: .top) {
                HStack {
                    CircleIconButton(systemName: "chevron.left") { dismiss() }.accessibilityIdentifier("nav.back")
                    Spacer()
                    if p.isOwner {
                        CircleIconButton(systemName: "square.and.arrow.up") {
                            shareTarget = ShareTarget(type: .place, id: p.id, title: p.title, coverPath: p.coverStoragePath, category: p.category)
                        }
                        .accessibilityIdentifier("place.share")
                    }
                    Menu {
                        if p.isOwner {
                            Button { showEdit = true } label: { Label("Sửa địa điểm", systemImage: "pencil") }
                            Button { shareTarget = ShareTarget(type: .place, id: p.id, title: p.title, coverPath: p.coverStoragePath, category: p.category) } label: { Label("Chia sẻ", systemImage: "person.badge.plus") }
                        }
                        Button { router.push(.members(ShareTarget(type: .place, id: p.id, title: p.title, coverPath: p.coverStoragePath, category: p.category))) } label: {
                            Label("Thành viên", systemImage: "person.2")
                        }
                        if !p.isOwner {
                            Button(role: .destructive) { confirmLeave = true } label: { Label("Rời địa điểm chia sẻ", systemImage: "rectangle.portrait.and.arrow.right") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                            .frame(width: 36, height: 36).background(Color.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityIdentifier("place.more")
                }
                .padding(.horizontal, 16)
                .padding(.top, rounded ? 12 : 58)
            }
    }

    private func open(_ m: Memory, path: String) {
        if let vid = m.visitId { router.push(.visit(vid)) } else { viewerPhoto = path }
    }

    private func firstName(_ n: String?) -> String { n?.split(separator: " ").last.map(String.init) ?? "" }

    private func leave() {
        Task {
            do {
                try await MyPlacesAPI.shared.leave(.place, placeID)
                await PlacesStore.shared.refresh()
                AppEvents.shared.bump()
                dismiss()
            } catch { toast = AppError.message(error) }
        }
    }
}

struct PhotoRef: Identifiable, Hashable { var path: String; var id: String { path } }

struct PhotoViewer: View {
    var path: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            StorageImage(path: path, fill: false).ignoresSafeArea()
            CircleIconButton(systemName: "xmark") { dismiss() }.padding(16)
        }
    }
}
