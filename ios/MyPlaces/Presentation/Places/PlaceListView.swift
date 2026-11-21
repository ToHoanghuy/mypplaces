import SwiftUI

/// 03a – list of places with search, category chips, visit count, sync state.
struct PlaceListView: View {
    @Environment(Router.self) private var router
    private var store: PlacesStore { PlacesStore.shared }
    private var sync: SyncEngine { SyncEngine.shared }
    @State private var query = ""
    @State private var category: PlaceCategory?
    @State private var addSeed: PlaceSeed?
    @State private var moveTick = 0
    @AppStorage("places.sort") private var sortRaw = PlaceSort.custom.rawValue
    @AppStorage("places.reorderHintSeen") private var reorderHintSeen = false

    private var sort: PlaceSort { PlaceSort(rawValue: sortRaw) ?? .custom }
    private var canReorder: Bool {
        PlaceOrdering.canReorder(sort: sort, query: query, category: category, count: store.places.count)
    }
    private var reorderHint: String? {
        guard sort == .custom, store.places.count > 1 else { return nil }
        if !canReorder { return "Bỏ tìm kiếm và bộ lọc để sắp xếp lại" }
        return reorderHintSeen ? nil : "Nhấn giữ một địa điểm rồi kéo để sắp xếp"
    }

    var body: some View {
        Group {
            if store.hasLoaded && store.places.isEmpty {
                VStack {
                    Spacer()
                    EmptyStateView(icon: "mappin.and.ellipse", title: "Chưa có nơi nào", message: "Lưu nơi đầu tiên để bắt đầu",
                                   actionTitle: "Thêm địa điểm") {
                        addSeed = PlaceSeed(coordinate: LocationService.shared.lastLocation?.coordinate ?? MapClustering.hanoi.center)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    // Chips scroll with the content so the large title can collapse into the bar.
                    CategoryFilterRow(selection: $category)
                        .padding(.top, 4).padding(.bottom, 2)
                        .listRowInsets(EdgeInsets())
                        .plainListRow()
                    if let hint = reorderHint {
                        Label(hint, systemImage: canReorder ? "hand.draw" : "line.3.horizontal.decrease")
                            .font(.mpCaption).foregroundStyle(Theme.textTertiary)
                            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 2, trailing: 24))
                            .plainListRow()
                            .accessibilityIdentifier("places.reorderHint")
                    }
                    ForEach(filtered) { p in
                        Button { router.push(.place(p.id)) } label: { row(p) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("place.row.\(p.title)")
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                            .plainListRow()
                    }
                    .onMove(perform: canReorder ? move : nil)
                    if filtered.isEmpty && !query.isEmpty {
                        Text("Không có địa điểm phù hợp").font(.mpCallout).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                            .plainListRow()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 36 + Theme.tabInset, for: .scrollContent)
                .environment(\.defaultMinListRowHeight, 1)
                .animation(.snappy, value: filtered.map(\.id))
                .sensoryFeedback(.impact(weight: .medium), trigger: moveTick)
                .refreshable { await store.refresh(); await sync.syncNow() }
            }
        }
        .screenBackground()
        .mpTabRootTitle("Địa điểm")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm trong địa điểm của bạn")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sắp xếp", selection: $sortRaw) {
                        ForEach(PlaceSort.allCases) { s in
                            Label(s.title, systemImage: s.systemImage).tag(s.rawValue)
                        }
                    }
                    .accessibilityIdentifier("places.sort.picker")
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.mp(17, .semibold)).foregroundStyle(Theme.textPrimary)
                }
                .accessibilityIdentifier("places.sort")
                .accessibilityLabel("Sắp xếp: \(sort.title)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ToolbarIconButton(systemName: "plus", tint: Theme.accent) {
                    addSeed = PlaceSeed(coordinate: LocationService.shared.lastLocation?.coordinate ?? MapClustering.hanoi.center)
                }
                .accessibilityIdentifier("places.add")
                .accessibilityLabel("Thêm địa điểm")
            }
        }
        .task(id: AppEvents.shared.revision) { await store.refresh() }
        .fullScreenCover(item: $addSeed) { seed in
            AddPlaceView(seed: seed) { id in router.push(.place(id)) }
        }
    }

    private var filtered: [MapPlace] {
        let q = query.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return store.places
            .filter { category == nil || $0.category == category }
            .filter { q.isEmpty || $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
                || ($0.address ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) }
            .sortedForList(sort, positions: store.orderPositions)
    }

    /// Drag-to-reorder (custom mode, unfiltered list only): persist the whole visible order.
    private func move(from source: IndexSet, to destination: Int) {
        let ids = PlaceOrdering.moved(filtered.map(\.id), from: source, to: destination)
        store.setOrder(ids)
        moveTick += 1
        reorderHintSeen = true
    }

    private func row(_ p: MapPlace) -> some View {
        HStack(spacing: 14) {
            PlaceThumb(path: p.coverStoragePath, category: p.category, size: 52, corner: 12)
                .overlay(alignment: .bottomLeading) {
                    if p.isShared {
                        Image(systemName: "person.2.fill").font(.system(size: 7)).foregroundStyle(Theme.onAccent)
                            .frame(width: 16, height: 16).background(.black.opacity(0.7), in: Circle()).padding(3)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.title).font(.mp(16, .semibold)).foregroundStyle(Theme.textPrimary).mpLineLimit(large: 3)
                    CategoryDot(category: p.category)
                    if let state = sync.state(for: p.id) {
                        Badge(text: state == .failed ? "Lỗi đồng bộ" : "Chưa đồng bộ", tone: state == .failed ? Theme.danger : Theme.textSecondary)
                    }
                }
                if let a = p.address, !a.isEmpty {
                    Text(a).font(.mp(13)).foregroundStyle(Theme.textSecondary).mpLineLimit(large: 2)
                }
                Text(PlaceCopy.visitCount(p)).font(.mp(12)).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.mp(12, .semibold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

private extension Array where Element == MapPlace {
    func sortedForList(_ sort: PlaceSort, positions: [UUID: Int]) -> [MapPlace] {
        PlaceOrdering.sorted(self, by: sort, positions: positions)
    }
}

private extension View {
    func plainListRow() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}
