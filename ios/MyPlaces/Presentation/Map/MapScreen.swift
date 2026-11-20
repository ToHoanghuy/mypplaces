import SwiftUI
import MapKit

/// 02a–02e: personal map with photo pins, clustering, preview, category filter, search, empty state.
struct MapScreen: View {
    @Environment(Router.self) private var router
    private var store: PlacesStore { PlacesStore.shared }
    private var events: AppEvents { AppEvents.shared }

    @State private var position: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var selectedID: UUID?
    @State private var category: PlaceCategory?
    @State private var showSearch = false
    @State private var addSeed: PlaceSeed?
    @State private var didFit = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                map(size: geo.size)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    Button { showSearch = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                            Text("Tìm địa điểm").foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                        .font(.system(size: 15))
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Theme.surface.opacity(0.92), in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.search")
                    .padding(.horizontal, 16)

                    if !store.places.isEmpty {
                        CategoryFilterRow(selection: $category, categories: presentCategories, horizontalPadding: 16)
                    }
                }
                .padding(.top, 6)

                // Right-side controls
                VStack(spacing: 14) {
                    Spacer()
                    CircleIconButton(systemName: "location", size: 40, background: Theme.surface.opacity(0.92)) { centerOnUser() }
                        .accessibilityIdentifier("map.locate")
                    if !store.places.isEmpty {
                        Button { addSeed = PlaceSeed(coordinate: seedCoordinate(preferUser: false)) } label: {
                            Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.onAccent)
                                .frame(width: 56, height: 56).background(Theme.accent, in: Circle())
                                .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("map.add")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.bottom, (store.hasLoaded && store.places.isEmpty) ? 330 : (selectedPlace == nil ? 96 : 190))

                VStack {
                    Spacer()
                    if store.hasLoaded && store.places.isEmpty {
                        emptyCard.padding(.horizontal, 12).padding(.bottom, 100)
                    } else if let p = selectedPlace {
                        Button { router.push(.place(p.id)) } label: { PlacePreviewCard(place: p) }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16).padding(.bottom, 82)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.spring(duration: 0.3), value: selectedID)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showSearch) {
            PlaceSearchView(region: region, onSelectOwn: { p in focus(on: p) }, onSelectMapItem: { seed in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { addSeed = seed }
            })
        }
        .fullScreenCover(item: $addSeed) { seed in
            AddPlaceView(seed: seed) { newID in
                selectedID = newID
                if let p = store.place(newID) { focus(on: p) }
            }
        }
        .task(id: events.revision) { await store.refresh() }
        .onAppear { LocationService.shared.requestWhenInUse() }
        .onChange(of: store.places.count) { _, _ in fitIfNeeded() }
        .onAppear { fitIfNeeded() }
    }

    // MARK: Map

    private func map(size: CGSize) -> some View {
        let clusters = MapClustering.clusters(filtered, region: region, size: size)
        return Map(position: $position, interactionModes: .all) {
            UserAnnotation()
            ForEach(clusters) { cl in
                Annotation(cl.representative.title, coordinate: cl.coordinate, anchor: .center) {
                    PlacePinView(cluster: cl, selected: cl.members.contains { $0.id == selectedID } && cl.count == 1 || cl.id == selectedID)
                        .onTapGesture { tap(cl) }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { }
        .onMapCameraChange(frequency: .onEnd) { ctx in region = ctx.region }
        .onTapGesture { selectedID = nil }
    }

    private var filtered: [MapPlace] {
        guard let category else { return store.places }
        return store.places.filter { $0.category == category }
    }

    private var presentCategories: [PlaceCategory] {
        let set = Set(store.places.map(\.category))
        return PlaceCategory.allCases.filter { set.contains($0) }
    }

    private var selectedPlace: MapPlace? { selectedID.flatMap { id in filtered.first { $0.id == id } } }

    private func tap(_ cl: PlaceCluster) {
        if cl.count == 1 {
            selectedID = cl.id
        } else if let r = MapClustering.region(fitting: cl.members.map(\.coordinate), minSpan: 0.002) {
            withAnimation { position = .region(r) }
        }
    }

    private func focus(on p: MapPlace) {
        selectedID = p.id
        withAnimation {
            position = .region(MKCoordinateRegion(center: p.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
        }
    }

    /// Where a new place starts: the visible map centre when zoomed in to street level, else the user, else Hà Nội.
    private func seedCoordinate(preferUser: Bool) -> CLLocationCoordinate2D {
        let user = LocationService.shared.lastLocation?.coordinate
        if let r = region, r.span.latitudeDelta < 0.5, !(preferUser && user != nil) { return r.center }
        return user ?? MapClustering.hanoi.center
    }

    private func centerOnUser() {
        LocationService.shared.requestWhenInUse()
        withAnimation { position = .userLocation(fallback: .region(region ?? MapClustering.hanoi)) }
    }

    private func fitIfNeeded() {
        guard !didFit else { return }
        if let r = MapClustering.region(fitting: store.places.map(\.coordinate)) {
            position = .region(r); didFit = true
        } else if store.hasLoaded {
            position = .userLocation(fallback: .region(MapClustering.hanoi))
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 18)).foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44).background(Theme.surfaceHigh, in: Circle())
            Text("Chưa có nơi nào").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.top, 4)
            Text("Lưu nơi đầu tiên để thấy nó trên bản đồ").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            PrimaryButton(title: "Thêm địa điểm", icon: "plus") {
                addSeed = PlaceSeed(coordinate: seedCoordinate(preferUser: true))
            }
            .padding(.top, 14)
            .accessibilityIdentifier("map.empty.add")
        }
        .padding(20)
        .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
