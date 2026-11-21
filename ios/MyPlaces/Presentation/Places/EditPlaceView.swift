import SwiftUI
import MapKit

/// 03d – edit place (owner only, FR-PL-06) + 03e delete confirmation (soft delete, FR-PL-07).
struct EditPlaceView: View {
    var place: MapPlace
    var onDeleted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: PlaceCategory
    @State private var address: String
    @State private var coordinate: CLLocationCoordinate2D
    @State private var saving = false
    @State private var error: String?
    @State private var showPicker = false
    @State private var confirmDelete = false
    @State private var usage: (visits: Int, journals: Int)?
    @State private var deleting = false

    init(place: MapPlace, onDeleted: @escaping () -> Void = {}) {
        self.place = place
        self.onDeleted = onDeleted
        _title = State(initialValue: place.title)
        _category = State(initialValue: place.category)
        _address = State(initialValue: place.address ?? "")
        _coordinate = State(initialValue: place.coordinate)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ModalBar(title: "Sửa địa điểm", onCancel: { dismiss() }) {
                    PillButton(title: "Lưu", isLoading: saving, isEnabled: valid) { save() }
                        .accessibilityIdentifier("editplace.save")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Map(position: .constant(.region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))))) {
                            Annotation("", coordinate: coordinate) {
                                Circle().fill(Theme.accent).frame(width: 26, height: 26)
                                    .overlay(Circle().fill(Theme.textPrimary).frame(width: 8, height: 8))
                            }
                        }
                        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                        .allowsHitTesting(false)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Button { showPicker = true } label: {
                                HStack(spacing: 6) { Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.accent); Text("Đổi vị trí") }
                                    .font(.mp(12, .semibold)).foregroundStyle(Theme.onAccent)
                                    .padding(.horizontal, 12).frame(minHeight: 30).background(.black.opacity(0.7), in: Capsule())
                            }
                            .buttonStyle(.plain).padding(10)
                        }

                        label("Tên địa điểm")
                        InputField(placeholder: "Nhập tên địa điểm", text: $title, identifier: "editplace.title")
                        label("Danh mục")
                        CategoryPicker(selection: $category)
                        label("Địa chỉ")
                        InputField(placeholder: "Nhập địa chỉ", text: $address, identifier: "editplace.address")
                        if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }

                        Button { askDelete() } label: {
                            Text("Xóa địa điểm").font(.mp(15, .semibold)).foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity).padding(.vertical, 20)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 40)
                        .accessibilityIdentifier("editplace.delete")
                    }
                    .padding(.horizontal, 20)
                }
            }
            if confirmDelete {
                ConfirmCard(icon: "trash", title: "Xóa \(place.title)?", message: deleteMessage, confirmTitle: "Xóa", isLoading: deleting,
                            onConfirm: delete, onCancel: { confirmDelete = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: confirmDelete)
        .screenBackground()
        .sheet(isPresented: $showPicker) {
            LocationPickerView(initial: coordinate) { c, a in
                coordinate = c
                if let a { address = a }
            }
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.mp(13)).foregroundStyle(Theme.textSecondary).padding(.leading, 6).padding(.bottom, -8)
    }

    private var valid: Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        return (1...100).contains(t.count) && address.count <= 500
    }

    private var deleteMessage: String {
        guard let usage else { return "Địa điểm sẽ bị ẩn khỏi bản đồ và nhật ký." }
        var parts: [String] = []
        if usage.visits > 0 { parts.append("có \(usage.visits) lần ghé") }
        if usage.journals > 0 { parts.append("nằm trong \(usage.journals) nhật ký") }
        let head = parts.isEmpty ? "" : "Địa điểm \(parts.joined(separator: " và ")). "
        return head + "Địa điểm sẽ bị ẩn khỏi bản đồ và nhật ký."
    }

    private func askDelete() {
        confirmDelete = true
        Task { usage = try? await MyPlacesAPI.shared.placeUsage(place.id) }
    }

    private func save() {
        saving = true; error = nil
        let a = address.trimmingCharacters(in: .whitespaces)
        let update = PlaceUpdate(title: title.trimmingCharacters(in: .whitespaces), category: category,
                                 latitude: coordinate.latitude, longitude: coordinate.longitude, address: a.isEmpty ? nil : a)
        Task {
            do { try await PlacesStore.shared.update(place.id, update); dismiss() }
            catch { self.error = AppError.message(error) }
            saving = false
        }
    }

    private func delete() {
        deleting = true
        Task {
            do {
                try await PlacesStore.shared.delete(place.id, title: place.title)
                dismiss()
                onDeleted()
            } catch { self.error = AppError.message(error); confirmDelete = false }
            deleting = false
        }
    }
}
