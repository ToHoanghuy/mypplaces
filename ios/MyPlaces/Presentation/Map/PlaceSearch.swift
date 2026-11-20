import SwiftUI
import MapKit

@MainActor
@Observable
final class MapSearchModel {
    var query = ""
    var results: [MKMapItem] = []
    var isSearching = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func search(near region: MKCoordinateRegion?) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q
            req.resultTypes = [.pointOfInterest, .address]
            if let region { req.region = region }
            let res = try? await MKLocalSearch(request: req).start()
            guard !Task.isCancelled else { return }
            results = Array((res?.mapItems ?? []).prefix(15))
            isSearching = false
        }
    }
}

/// Values extracted from a MapKit result to prefill "Thêm địa điểm" (provider + id for dedup).
struct PlaceSeed: Hashable, Identifiable {
    var id = UUID()
    var title: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var provider: String?
    var providerPlaceId: String?

    init(title: String = "", coordinate: CLLocationCoordinate2D, address: String? = nil) {
        self.title = title; latitude = coordinate.latitude; longitude = coordinate.longitude; self.address = address
    }

    init(item: MKMapItem) {
        title = item.name ?? ""
        latitude = item.placemark.coordinate.latitude
        longitude = item.placemark.coordinate.longitude
        address = PlaceSeed.address(item.placemark)
        if #available(iOS 18.0, *), let ident = item.identifier?.rawValue {
            provider = "apple"; providerPlaceId = ident
        }
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    static func address(_ p: CLPlacemark) -> String? {
        let parts = [p.subThoroughfare.map { "\($0) \(p.thoroughfare ?? "")" } ?? p.thoroughfare, p.subLocality, p.locality ?? p.subAdministrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}

/// 02d – search own places + MapKit results.
struct PlaceSearchView: View {
    var region: MKCoordinateRegion?
    var showsOwnPlaces = true
    var onSelectOwn: (MapPlace) -> Void = { _ in }
    var onSelectMapItem: (PlaceSeed) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model = MapSearchModel()
    @FocusState private var focused: Bool
    private var store: PlacesStore { PlacesStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(placeholder: "Tìm địa điểm", text: $model.query, focused: $focused) { model.search(near: region) }
                    .accessibilityIdentifier("search.field")
                Button("Hủy") { dismiss() }.font(.system(size: 15)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)

            List {
                if showsOwnPlaces && !ownMatches.isEmpty {
                    Section {
                        ForEach(ownMatches) { p in
                            Button { onSelectOwn(p); dismiss() } label: {
                                HStack(spacing: 12) {
                                    PlaceThumb(path: p.coverStoragePath, category: p.category, size: 40, corner: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) { Text(p.title).font(.system(size: 15, weight: .semibold)); CategoryDot(category: p.category) }
                                        if let a = p.address { Text(a).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                                    }
                                }
                            }
                            .listRowBackground(Theme.background)
                            .accessibilityIdentifier("search.own")
                        }
                    } header: { sectionTitle("Địa điểm của bạn") }
                }
                if !model.results.isEmpty {
                    Section {
                        ForEach(model.results, id: \.self) { item in
                            Button { onSelectMapItem(PlaceSeed(item: item)); dismiss() } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.textSecondary)
                                        .frame(width: 40, height: 40).background(Theme.surface, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Địa điểm").font(.system(size: 15, weight: .semibold))
                                        if let a = PlaceSeed.address(item.placemark) {
                                            Text(a).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                        .frame(width: 28, height: 28).background(Theme.surfaceHigh, in: Circle())
                                }
                            }
                            .listRowBackground(Theme.background)
                            .accessibilityIdentifier("search.result")
                        }
                    } header: { sectionTitle("Trên bản đồ") }
                }
                if model.isSearching { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Theme.background) }
                if !model.query.isEmpty && ownMatches.isEmpty && model.results.isEmpty && !model.isSearching {
                    Text("Không tìm thấy kết quả").font(.mpCallout).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .foregroundStyle(.white)
        }
        .screenBackground()
        .onChange(of: model.query) { _, _ in model.search(near: region) }
        .onAppear { focused = true }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.mpSection).tracking(0.6).foregroundStyle(Theme.textSecondary)
    }

    private var ownMatches: [MapPlace] {
        let q = model.query.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !q.isEmpty else { return [] }
        return store.places.filter {
            $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
            || ($0.address ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
        }
    }
}
