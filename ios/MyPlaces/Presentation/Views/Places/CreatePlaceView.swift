import SwiftUI
import MapKit

struct CreatePlaceView: View {
    let coordinate: CLLocationCoordinate2D
    let onSave: (Place) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category: PlaceCategory = .other
    @State private var address = ""
    @State private var note = ""
    @State private var visitedAt = Date()
    @State private var hasVisitedDate = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên địa điểm", text: $title)
                    
                    Picker("Danh mục", selection: $category) {
                        ForEach(PlaceCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                }
                
                Section {
                    TextField("Địa chỉ", text: $address)
                    
                    Text(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section {
                    TextField("Ghi chú", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Toggle("Đã ghé thăm", isOn: $hasVisitedDate)
                    
                    if hasVisitedDate {
                        DatePicker(
                            "Ngày ghé thăm",
                            selection: $visitedAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationTitle("Thêm địa điểm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        savePlace()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func savePlace() {
        guard let userID = SupabaseService.shared.currentUserID else { return }
        
        let place = Place(
            ownerID: userID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: address.isEmpty ? nil : address,
            note: note.isEmpty ? nil : note,
            visitedAt: hasVisitedDate ? visitedAt : nil
        )
        
        onSave(place)
        dismiss()
    }
}
