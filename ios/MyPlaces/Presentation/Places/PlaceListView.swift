import SwiftUI

/// 03a – list of places with search, category chips, visit count, sync state.
struct PlaceListView: View {
    @Environment(Router.self) private var router
    private var store: PlacesStore { PlacesStore.shared }
    private var sync: SyncEngine { SyncEngine.shared }
    @State private var query = ""
    @State private var category: PlaceCategory?
    @State private var addSeed: PlaceSeed?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Địa điểm").font(.mpLargeTitle).foregroundStyle(Theme.textPrimary)
                Spacer()
                CircleIconButton(systemName: "plus", tint: Theme.accent, background: Theme.surface) {
                    addSeed = PlaceSeed(coordinate: LocationService.shared.lastLocation?.coordinate ?? MapClustering.hanoi.center)
                }
                .accessibilityIdentifier("places.add")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)

            SearchField(placeholder: "Tìm trong địa điểm của bạn", text: $query).padding(.horizontal, 20)
            CategoryFilterRow(selection: $category).padding(.vertical, 12)

            if store.hasLoaded && store.places.isEmpty {
                Spacer()
                EmptyStateView(icon: "mappin.and.ellipse", title: "Chưa có nơi nào", message: "Lưu nơi đầu tiên để bắt đầu",
                               actionTitle: "Thêm địa điểm") {
                    addSeed = PlaceSeed(coordinate: LocationService.shared.lastLocation?.coordinate ?? MapClustering.hanoi.center)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { p in
                            Button { router.push(.place(p.id)) } label: { row(p) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("place.row.\(p.title)")
                        }
                        if !filtered.isEmpty || !query.isEmpty {
                            if filtered.isEmpty {
                                Text("Không có địa điểm phù hợp").font(.mpCallout).foregroundStyle(Theme.textSecondary).padding(.top, 40)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36 + Theme.tabInset)
                }
                .refreshable { await store.refresh(); await sync.syncNow() }
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
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
            .sorted { ($0.lastVisitedAt ?? $0.updatedAt ?? .distantPast) > ($1.lastVisitedAt ?? $1.updatedAt ?? .distantPast) }
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
                    Text(p.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    CategoryDot(category: p.category)
                    if let state = sync.state(for: p.id) {
                        Badge(text: state == .failed ? "Lỗi đồng bộ" : "Chưa đồng bộ", tone: state == .failed ? Theme.danger : Theme.textSecondary)
                    }
                }
                if let a = p.address, !a.isEmpty {
                    Text(a).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Text(PlaceCopy.visitCount(p)).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}
