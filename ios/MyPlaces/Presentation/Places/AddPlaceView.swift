import SwiftUI
import MapKit

/// 03b – add place: pan the map under a fixed pin (or search), name, category, address.
struct AddPlaceView: View {
    var seed: PlaceSeed
    var onSaved: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var category: PlaceCategory = .food
    @State private var address: String
    @State private var editingAddress = false
    @State private var center: CLLocationCoordinate2D
    @State private var position: MapCameraPosition
    @State private var provider: String?
    @State private var providerPlaceId: String?
    @State private var showSearch = false
    @State private var saving = false
    @State private var error: String?
    @State private var addressTouched = false
    @FocusState private var titleFocused: Bool

    init(seed: PlaceSeed, onSaved: @escaping (UUID) -> Void = { _ in }) {
        self.seed = seed
        self.onSaved = onSaved
        _title = State(initialValue: seed.title)
        _address = State(initialValue: seed.address ?? "")
        _center = State(initialValue: seed.coordinate)
        _position = State(initialValue: .region(MKCoordinateRegion(center: seed.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))))
        _provider = State(initialValue: seed.provider)
        _providerPlaceId = State(initialValue: seed.providerPlaceId)
        _addressTouched = State(initialValue: seed.address != nil)
        if let c = seed.category { _category = State(initialValue: c) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) { UserAnnotation() }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    let moved = abs(ctx.region.center.latitude - center.latitude) > 0.00002 || abs(ctx.region.center.longitude - center.longitude) > 0.00002
                    center = ctx.region.center
                    if moved { provider = nil; providerPlaceId = nil; addressTouched = false }
                    if !addressTouched { reverseGeocode() }
                }
                .ignoresSafeArea()
                .overlay(alignment: .center) { centerPin.offset(y: -170) }

            VStack {
                MPGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Text("Hủy").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 16).frame(height: 44)
                            .mpGlass(in: Capsule(), interactive: true)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button { showSearch = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Tìm hoặc chạm giữ bản đồ").lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 14).frame(height: 44)
                        .mpGlass(in: Capsule(), interactive: true)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
            }

            sheet
        }
        .screenBackground()
        .fullScreenCover(isPresented: $showSearch) {
            PlaceSearchView(region: MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)),
                            showsOwnPlaces: false) { s in
                title = title.isEmpty ? s.title : title
                if !s.title.isEmpty { title = s.title }
                address = s.address ?? address
                addressTouched = s.address != nil
                center = s.coordinate
                provider = s.provider; providerPlaceId = s.providerPlaceId
                if let c = s.category { category = c }
                position = .region(MKCoordinateRegion(center: s.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
            }
        }
        .task { if !addressTouched { reverseGeocode() } }
    }

    private var centerPin: some View {
        VStack(spacing: 0) {
            Circle().fill(Theme.accent).frame(width: 34, height: 34)
                .overlay(Circle().fill(Theme.onAccent).frame(width: 10, height: 10))
                .shadow(color: Theme.accent.opacity(0.5), radius: 10)
            Rectangle().fill(Theme.accent).frame(width: 3, height: 12)
        }
        .allowsHitTesting(false)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule().fill(Theme.textTertiary).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            TextField("", text: $title, prompt: Text("Tên địa điểm").foregroundColor(Theme.textTertiary))
                .font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.textPrimary).tint(Theme.accent)
                .focused($titleFocused)
                .accessibilityIdentifier("addplace.title")
            CategoryPicker(selection: $category, wrap: false)
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.textSecondary)
                if editingAddress {
                    TextField("", text: $address, prompt: Text("Nhập địa chỉ").foregroundColor(Theme.textTertiary))
                        .font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                        .onSubmit { editingAddress = false }
                        .onChange(of: address) { _, _ in addressTouched = true }
                } else {
                    Text(address.isEmpty ? "Đang lấy địa chỉ…" : address).font(.system(size: 15)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                }
                Spacer()
                Button(editingAddress ? "Xong" : "Sửa") { editingAddress.toggle() }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }
            PrimaryButton(title: "Lưu địa điểm", isLoading: saving, isEnabled: valid) { save() }
                .padding(.top, 8)
                .accessibilityIdentifier("addplace.save")
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
        .modifier(MapPanelFill())
    }

    /// BRD §10.1: title 1–100, address <= 500.
    private var valid: Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        return (1...100).contains(t.count) && address.count <= 500
    }

    private func reverseGeocode() {
        let loc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        Task {
            if let pm = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "vi_VN")).first,
               !addressTouched {
                address = PlaceSeed.address(pm) ?? ""
            }
        }
    }

    private func save() {
        saving = true; error = nil
        let a = address.trimmingCharacters(in: .whitespaces)
        let insert = PlaceInsert(id: UUID(), title: title.trimmingCharacters(in: .whitespaces), category: category,
                                 latitude: center.latitude, longitude: center.longitude,
                                 address: a.isEmpty ? nil : String(a.prefix(500)),
                                 provider: providerPlaceId == nil ? nil : provider,
                                 providerPlaceId: provider == nil ? nil : providerPlaceId)
        Task {
            do {
                try await PlacesStore.shared.create(insert)
                dismiss()
                onSaved(insert.id)
            } catch {
                self.error = AppError.message(error)
            }
            saving = false
        }
    }
}

/// "Đổi vị trí" (03d): choose a new coordinate by panning the map.
struct LocationPickerView: View {
    var initial: CLLocationCoordinate2D
    var onPick: (CLLocationCoordinate2D, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D

    init(initial: CLLocationCoordinate2D, onPick: @escaping (CLLocationCoordinate2D, String?) -> Void) {
        self.initial = initial; self.onPick = onPick
        _center = State(initialValue: initial)
        _position = State(initialValue: .region(MKCoordinateRegion(center: initial, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))))
    }

    var body: some View {
        ZStack {
            Map(position: $position).mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .onEnd) { center = $0.region.center }
                .ignoresSafeArea()
            Image(systemName: "mappin.circle.fill").font(.system(size: 40)).foregroundStyle(Theme.accent, Theme.textPrimary).offset(y: -20)
                .allowsHitTesting(false)
            VStack {
                ModalBar(title: "Đổi vị trí", onCancel: { dismiss() }) {
                    PillButton(title: "Xong") {
                        let c = center
                        Task {
                            let pm = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude),
                                                                                  preferredLocale: Locale(identifier: "vi_VN")).first
                            onPick(c, pm.flatMap(PlaceSeed.address))
                            dismiss()
                        }
                    }
                }
                .background(Theme.background.opacity(0.85))
                Spacer()
            }
        }
    }
}

/// Panel floating over the map. iOS 26: inset Liquid Glass panel (like Maps' sheets); earlier: solid bottom sheet.
struct MapPanelFill: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .mpGlass(in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        } else {
            content
                .background(Theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
