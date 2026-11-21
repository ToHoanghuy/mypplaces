import SwiftUI
import MapKit

@MainActor
@Observable
final class JournalDetailModel {
    let journalID: UUID
    var journal: Journal?
    var role: MemberRole = .viewer
    var members: [MemberRow] = []
    var ownerName = ""
    var places: [JournalPlaceItem] = []
    var visits: [JournalVisitItem] = []
    var memories: [Memory] = []
    var loaded = false
    var notFound = false
    var error: String?
    private let api = MyPlacesAPI.shared

    init(journalID: UUID) { self.journalID = journalID }

    func load() async {
        do {
            guard let j = try await api.journal(journalID) else { notFound = true; loaded = true; return }
            journal = j
            async let m = api.members(.journal, journalID)
            async let p = api.journalPlaces(journalID)
            async let v = api.journalVisits(journalID)
            async let mem = api.memories(.journal(journalID))
            members = (try? await m) ?? []
            places = try await p
            visits = try await v
            memories = ((try? await mem) ?? []).filter { m in !m.attachments.contains { $0.storagePath == j.coverPath } }
            let uid = api.userID
            if j.ownerId == uid { role = .owner } else { role = members.first { $0.userId == uid }?.role ?? .viewer }
            ownerName = (try? await api.profile(j.ownerId).displayName) ?? ""
            notFound = false
            error = nil
        } catch { self.error = AppError.message(error) }
        loaded = true
    }

    func name(of user: UUID) -> String {
        if user == api.userID { return SessionStore.shared.profile?.displayName ?? "Bạn" }
        if user == journal?.ownerId { return ownerName }
        return members.first { $0.userId == user }?.profile?.displayName ?? "Thành viên"
    }

    var allPeople: [String] { [ownerName] + members.compactMap { $0.profile?.displayName } }

    /// Visits grouped by local day (visit timezone) then places without a visit grouped by link day.
    var timelineSections: [(title: String, rows: [JournalRow])] {
        var result: [(String, [JournalRow])] = []
        for v in visits {
            let tz = VNFormat.tz(v.timezoneId)
            let title = VNFormat.weekdayDay(v.visitedAt, tz: tz).uppercased()
            let row = JournalRow.visit(v)
            if let i = result.firstIndex(where: { $0.0 == title }) { result[i].1.append(row) } else { result.append((title, [row])) }
        }
        let visitPlaceIDs = Set(visits.map(\.placeId))
        for p in places where !visitPlaceIDs.contains(p.placeId) {
            let title = "NGÀY THÊM \(VNFormat.dayMonth(p.linkedAt).uppercased())"
            if let i = result.firstIndex(where: { $0.0 == title }) { result[i].1.append(.place(p)) } else { result.append((title, [.place(p)])) }
        }
        return result
    }

    /// Ordered stops for the journal map (06d).
    var stops: [JournalRow] {
        let visitPlaceIDs = Set(visits.map(\.placeId))
        return visits.map(JournalRow.visit) + places.filter { !visitPlaceIDs.contains($0.placeId) }.map(JournalRow.place)
    }
}

enum JournalRow: Identifiable, Hashable {
    case visit(JournalVisitItem)
    case place(JournalPlaceItem)
    var id: UUID { switch self { case .visit(let v): return v.id; case .place(let p): return p.id } }
    var placeId: UUID { switch self { case .visit(let v): return v.placeId; case .place(let p): return p.placeId } }
    var title: String { switch self { case .visit(let v): return v.placeTitle; case .place(let p): return p.title } }
    var category: PlaceCategory { switch self { case .visit(let v): return v.placeCategory; case .place(let p): return p.category } }
    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .visit(let v): return .init(latitude: v.latitude, longitude: v.longitude)
        case .place(let p): return .init(latitude: p.latitude, longitude: p.longitude)
        }
    }
    var addedBy: UUID { switch self { case .visit(let v): return v.addedBy; case .place(let p): return p.addedBy } }
    var subtitle: String {
        switch self {
        case .visit(let v): return VNFormat.time(v.visitedAt, tz: VNFormat.tz(v.timezoneId))
        case .place: return "Chưa xếp giờ"
        }
    }
    var dateLine: String {
        switch self {
        case .visit(let v): let tz = VNFormat.tz(v.timezoneId); return "\(VNFormat.dayMonth(v.visitedAt, tz: tz)) · \(VNFormat.time(v.visitedAt, tz: tz))"
        case .place(let p): return "Thêm \(VNFormat.dayMonth(p.linkedAt))"
        }
    }
}

/// 06c (timeline tab) + 06d (map tab).
struct JournalDetailView: View {
    let journalID: UUID
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var model: JournalDetailModel
    @State private var tab = 0
    @State private var showAdd = false
    @State private var showAddMemory = false
    @State private var shareTarget: ShareTarget?
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var toast: String?

    init(journalID: UUID) {
        self.journalID = journalID
        _model = State(initialValue: JournalDetailModel(journalID: journalID))
    }

    var body: some View {
        Group {
            if let j = model.journal {
                if tab == 0 { timelineLayout(j) } else { mapLayout(j) }
            } else if model.notFound {
                VStack {
                    HStack { CircleIconButton(systemName: "chevron.left", background: Theme.surface) { dismiss() }; Spacer() }.padding(16)
                    Spacer()
                    EmptyStateView(icon: "book.closed", title: "Không tìm thấy nhật ký", message: "Nhật ký đã bị xóa hoặc bạn không còn là thành viên.")
                    Spacer()
                }
            } else { ProgressView().tint(Theme.textPrimary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: AppEvents.shared.revision) { await model.load() }
        .toast($toast)
        .fullScreenCover(isPresented: $showAdd) {
            if let j = model.journal { AddToJournalView(journal: j, existingPlaces: Set(model.places.map(\.placeId)), existingVisits: Set(model.visits.map(\.visitId))) }
        }
        .fullScreenCover(isPresented: $showAddMemory) {
            if let j = model.journal { AddMemoryView(parent: .journal(j.id), contextLabel: "Vào: Nhật ký · \(j.title)") }
        }
        .sheet(item: $shareTarget) { ShareSheetView(target: $0) }
        .confirmationDialog("Rời nhật ký?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Rời nhật ký", role: .destructive) { run(dismissAfter: true) { try await MyPlacesAPI.shared.leave(.journal, journalID) } }
        }
        .confirmationDialog("Xóa nhật ký?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xóa nhật ký", role: .destructive) { run(dismissAfter: true) { try await MyPlacesAPI.shared.softDeleteJournal(journalID) } }
        } message: { Text("Địa điểm và lần ghé vẫn được giữ nguyên.") }
    }

    private var target: ShareTarget? {
        model.journal.map { ShareTarget(type: .journal, id: $0.id, title: $0.title, coverPath: $0.coverPath, category: nil) }
    }

    private func moreMenu(_ j: Journal) -> some View {
        Menu {
            if model.role == .owner && !j.isArchived {
                Button { shareTarget = target } label: { Label("Mời thành viên", systemImage: "person.badge.plus") }
            }
            if let t = target { Button { router.push(.members(t)) } label: { Label("Thành viên", systemImage: "person.2") } }
            if model.role.canContribute && !j.isArchived {
                Button { showAddMemory = true } label: { Label("Thêm ghi chú", systemImage: "square.and.pencil") }
            }
            if model.role == .owner {
                Button { run { try await MyPlacesAPI.shared.setJournalArchived(journalID, archived: !j.isArchived) } } label: {
                    Label(j.isArchived ? "Bỏ lưu trữ" : "Lưu trữ", systemImage: "archivebox")
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Xóa nhật ký", systemImage: "trash") }
            } else {
                Button(role: .destructive) { confirmLeave = true } label: { Label("Rời nhật ký", systemImage: "rectangle.portrait.and.arrow.right") }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onAccent)
                .frame(width: 36, height: 36).background(Color.black.opacity(0.45), in: Circle())
        }
        .accessibilityIdentifier("journal.more")
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Array(["Dòng thời gian", "Bản đồ"].enumerated()), id: \.offset) { i, t in
                Button { withAnimation(.easeInOut(duration: 0.2)) { tab = i } } label: {
                    Text(t).font(.system(size: 13, weight: tab == i ? .semibold : .regular))
                        .foregroundStyle(tab == i ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(tab == i ? Theme.surfaceHigh : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("journal.tab.\(i)")
            }
        }
        .padding(3).background(Theme.surface, in: Capsule())
    }

    // MARK: 06c

    private func timelineLayout(_ j: Journal) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        StorageImage(path: j.coverPath)
                        LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                if let r = j.dateRange { Text(r) }
                                if !model.members.isEmpty { Text("·"); Image(systemName: "person.2") }
                                if j.isArchived { Text("· Đã lưu trữ") }
                            }
                            .font(.system(size: 12)).foregroundStyle(Theme.textPrimary.opacity(0.75))
                            Text(j.title).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                .accessibilityIdentifier("journal.title.label")
                            HStack(spacing: 6) {
                                AvatarStack(names: model.allPeople, size: 24, max: 4)
                                if model.role == .owner && !j.isArchived {
                                    Button { shareTarget = target } label: {
                                        Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                            .frame(width: 24, height: 24).overlay(Circle().stroke(Theme.border))
                                    }.buttonStyle(.plain)
                                    .accessibilityIdentifier("journal.invite")
                                }
                            }
                        }
                        .padding(20)
                    }
                    .frame(height: 340)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
                    .overlay(alignment: .top) {
                        HStack { CircleIconButton(systemName: "chevron.left") { dismiss() }.accessibilityIdentifier("nav.back"); Spacer(); moreMenu(j) }
                            .padding(.horizontal, 16).padding(.top, 58)
                    }

                    segmented.padding(.horizontal, 20).padding(.top, 14)

                    if model.timelineSections.isEmpty {
                        Text(model.role.canContribute ? "Chưa có địa điểm nào. Bấm + để thêm địa điểm hoặc lần ghé." : "Nhật ký chưa có địa điểm nào.")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(20)
                    }
                    ForEach(model.timelineSections, id: \.title) { s in
                        Text(s.title).font(.mpSection).tracking(0.5).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
                        ForEach(s.rows) { row in rowView(row).padding(.horizontal, 20).padding(.bottom, 8) }
                    }

                    if !model.memories.isEmpty || model.role.canContribute {
                        HStack {
                            Text("Kỷ niệm & ghi chú").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if model.role.canContribute && !j.isArchived {
                                Button { showAddMemory = true } label: { Image(systemName: "plus").foregroundStyle(Theme.textSecondary) }
                                    .accessibilityIdentifier("journal.addNote")
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 8)
                        ForEach(model.memories) { m in
                            HStack(alignment: .top, spacing: 10) {
                                Avatar(name: m.author?.displayName ?? "?", size: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(m.authorId == MyPlacesAPI.shared.userID ? "Bạn" : (m.author?.displayName ?? "")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                        Text(VNFormat.relative(m.createdAt)).font(.mpCaption).foregroundStyle(Theme.textSecondary)
                                    }
                                    if let b = m.body { Text(b).font(.system(size: 14)).foregroundStyle(Theme.textPrimary.opacity(0.9)) }
                                    if let a = m.attachments.first {
                                        StorageImage(path: a.storagePath).frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                            }
                            .padding(.horizontal, 20).padding(.bottom, 12)
                        }
                    }
                    Color.clear.frame(height: 100)
                }
            }
            .ignoresSafeArea(edges: .top)

            if model.role.canContribute && !j.isArchived {
                FloatingActionButton(systemName: "plus") { showAdd = true }
                .padding(20)
                .accessibilityIdentifier("journal.add")
            }
        }
    }

    private func rowView(_ row: JournalRow) -> some View {
        let own = PlacesStore.shared.place(row.placeId)
        return Button {
            switch row {
            case .visit(let v): router.push(.visit(v.visitId))
            case .place(let p): if own != nil { router.push(.place(p.placeId)) }
            }
        } label: {
            HStack(spacing: 12) {
                PlaceThumb(path: own?.coverStoragePath, category: row.category, size: 48, corner: 12)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) { CategoryDot(category: row.category); Text(row.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary) }
                    HStack(spacing: 6) {
                        Text(row.subtitle)
                        Text("•")
                        Avatar(name: model.name(of: row.addedBy), size: 16)
                        Text(model.name(of: row.addedBy).split(separator: " ").last.map(String.init) ?? "")
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journal.row.\(row.title)")
    }

    // MARK: 06d

    private func mapLayout(_ j: Journal) -> some View {
        let stops = model.stops
        return ZStack {
            Map(initialPosition: MapClustering.region(fitting: stops.map(\.coordinate)).map(MapCameraPosition.region) ?? .automatic) {
                if stops.count > 1 {
                    MapPolyline(coordinates: stops.map(\.coordinate))
                        .stroke(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                }
                ForEach(Array(stops.enumerated()), id: \.element.id) { i, stop in
                    Annotation(stop.title, coordinate: stop.coordinate, anchor: .bottom) {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topLeading) {
                                PlaceThumb(path: PlacesStore.shared.place(stop.placeId)?.coverStoragePath, category: stop.category, size: 40, corner: 20)
                                    .overlay(Circle().stroke(Theme.onAccent, lineWidth: 2))
                                Text("\(i + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.background)
                                    .frame(width: 18, height: 18).background(Theme.textPrimary, in: Circle()).offset(x: -6, y: -6)
                            }
                            Text(stop.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.6), in: Capsule())
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    CircleIconButton(systemName: "chevron.left") { dismiss() }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(j.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(j.dateRange ?? "") · \(stops.count) địa điểm").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    moreMenu(j)
                }
                segmented.frame(width: 220)
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(stops) { stop in
                            HStack(spacing: 10) {
                                PlaceThumb(path: PlacesStore.shared.place(stop.placeId)?.coverStoragePath, category: stop.category, size: 52, corner: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) { CategoryDot(category: stop.category); Text(stop.category.displayName).font(.system(size: 11)).foregroundStyle(Theme.textSecondary) }
                                    Text(stop.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                    Text(stop.dateLine).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .padding(10).frame(width: 230, alignment: .leading)
                            .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
    }

    private func run(dismissAfter: Bool = false, _ op: @escaping () async throws -> Void) {
        Task {
            do {
                try await op()
                AppEvents.shared.bump()
                if dismissAfter { dismiss() }
            } catch { toast = AppError.message(error) }
        }
    }
}
