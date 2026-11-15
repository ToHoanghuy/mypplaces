import SwiftUI

struct EditPlaceView: View {
    let place: Place
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var title: String
    @State private var category: PlaceCategory
    @State private var address: String
    @State private var note: String
    @State private var visitedAt: Date?
    @State private var hasVisitedDate: Bool
    
    init(place: Place) {
        self.place = place
        _title = State(initialValue: place.title)
        _category = State(initialValue: place.category)
        _address = State(initialValue: place.address ?? "")
        _note = State(initialValue: place.note ?? "")
        _visitedAt = State(initialValue: place.visitedAt ?? Date())
        _hasVisitedDate = State(initialValue: place.visitedAt != nil)
    }
    
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
                    
                    Text(String(format: "%.6f, %.6f", place.latitude, place.longitude))
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
                            selection: Binding(
                                get: { visitedAt ?? Date() },
                                set: { visitedAt = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .navigationTitle("Sửa địa điểm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveChanges()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveChanges() {
        var updatedPlace = place
        updatedPlace.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedPlace.category = category
        updatedPlace.address = address.isEmpty ? nil : address
        updatedPlace.note = note.isEmpty ? nil : note
        updatedPlace.visitedAt = hasVisitedDate ? visitedAt : nil
        updatedPlace.updatedAt = Date()
        
        Task {
            let repository = PlaceRepository(modelContext: modelContext)
            try? await repository.updatePlace(updatedPlace)
            await MainActor.run {
                dismiss()
            }
        }
    }
}
