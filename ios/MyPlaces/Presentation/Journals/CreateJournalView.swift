import SwiftUI

/// 06b – create journal (private until someone is invited, BRULE-JR-02/03/04).
struct CreateJournalView: View {
    var onCreated: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var cover: PreparedPhoto?
    @State private var title = ""
    @State private var description = ""
    @State private var start: Date?
    @State private var end: Date?
    @State private var editing: DateField?
    @State private var saving = false
    @State private var error: String?

    enum DateField: Identifiable { case start, end; var id: Int { self == .start ? 0 : 1 } }

    var body: some View {
        VStack(spacing: 0) {
            ModalBar(title: "", onCancel: { dismiss() }) {
                PillButton(title: "Tạo", isLoading: saving, isEnabled: valid) { create() }
                    .accessibilityIdentifier("journal.create")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PhotoPickButton(maxCount: 1, onPicked: { cover = $0.first }) {
                        ZStack {
                            if let cover, let img = UIImage(data: cover.data) {
                                Image(uiImage: img).resizable().scaledToFill().frame(height: 210).clipped()
                            } else {
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [6])).foregroundStyle(Theme.textTertiary)
                                VStack(spacing: 10) {
                                    Image(systemName: "photo.badge.plus").font(.system(size: 18)).foregroundStyle(Theme.textSecondary)
                                        .frame(width: 44, height: 44).background(Theme.surfaceHigh, in: Circle())
                                    Text("Thêm ảnh bìa").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .frame(height: 210).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                    .accessibilityIdentifier("journal.cover")

                    TextField("", text: $title, prompt: Text("Tiêu đề nhật ký").foregroundColor(Theme.textTertiary))
                        .font(.system(size: 26, weight: .bold)).foregroundStyle(.white).tint(Theme.accent)
                        .accessibilityIdentifier("journal.title")
                    TextField("", text: $description, prompt: Text("Mô tả (tùy chọn)").foregroundColor(Theme.textTertiary), axis: .vertical)
                        .font(.system(size: 15)).foregroundStyle(.white).tint(Theme.accent).lineLimit(1...5)

                    HStack(spacing: 10) {
                        datePill(icon: "calendar", text: start.map { "Từ \(VNFormat.numeric($0))" } ?? "Từ ngày") { editing = .start }
                        datePill(icon: "calendar.badge.clock", text: end.map { "Đến \(VNFormat.numeric($0))" } ?? "Đến ngày") { editing = .end }
                    }
                    if let s = start, let e = end, e < s {
                        Text("Ngày kết thúc phải sau ngày bắt đầu").font(.mpCaption).foregroundStyle(Theme.danger)
                    }
                    InfoNote(text: "Riêng tư – chỉ bạn xem được cho đến khi mời")
                    if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .screenBackground()
        .sheet(item: $editing) { field in
            VStack {
                DatePicker("", selection: Binding(
                    get: { (field == .start ? start : end) ?? Date() },
                    set: { if field == .start { start = $0 } else { end = $0 } }), displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden().tint(Theme.accent)
                    .environment(\.locale, Locale(identifier: "vi_VN"))
                HStack {
                    Button("Xóa ngày") { if field == .start { start = nil } else { end = nil }; editing = nil }.foregroundStyle(Theme.textSecondary)
                    Spacer()
                    PillButton(title: "Xong") {
                        if field == .start, start == nil { start = Date() }
                        if field == .end, end == nil { end = Date() }
                        editing = nil
                    }
                }
            }
            .padding(20)
            .presentationDetents([.medium])
            .presentationBackground(Theme.surface)
        }
    }

    private func datePill(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 12)); Text(text).font(.system(size: 13)) }
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private var valid: Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        if let s = start, let e = end, e < s { return false }
        return (1...120).contains(t.count) && description.count <= 2000
    }

    private func dayString(_ d: Date?) -> String? {
        guard let d else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private func create() {
        saving = true; error = nil
        let id = UUID()
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await MyPlacesAPI.shared.insertJournal(JournalInsert(id: id, title: title.trimmingCharacters(in: .whitespaces),
                    description: desc.isEmpty ? nil : desc, startDate: dayString(start), endDate: dayString(end)))
                if let cover {
                    // Cover = photo memory of the journal (bucket policy needs a memory parent; members can read it).
                    let memoryId = UUID()
                    try await MyPlacesAPI.shared.createMemory(parent: .journal(id), body: nil, photos: [cover], memoryId: memoryId)
                    let path = "\(MyPlacesAPI.shared.userID!.uuidString.lowercased())/\(memoryId.uuidString.lowercased())/\(cover.id.uuidString.lowercased()).jpg"
                    try await MyPlacesAPI.shared.setJournalCover(id, path: path)
                }
                AppEvents.shared.bump()
                dismiss()
                onCreated(id)
            } catch { self.error = AppError.message(error) }
            saving = false
        }
    }
}
