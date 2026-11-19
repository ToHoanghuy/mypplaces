import SwiftUI

/// 04d – add a memory (NOTE or PHOTO) to exactly one parent (Place / Visit / Journal, ERD-05).
struct AddMemoryView: View {
    var parent: MemoryParent
    var contextLabel: String
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PreparedPhoto] = []
    @State private var text = ""
    @State private var posting = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModalBar(title: "Kỷ niệm", onCancel: { dismiss() }) {
                PillButton(title: "Đăng", isLoading: posting, isEnabled: canPost) { post() }
                    .accessibilityIdentifier("memory.post")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                        Text(contextLabel).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    .padding(.horizontal, 12).frame(height: 28).background(Theme.surface, in: Capsule())

                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos) { p in
                                    PhotoTile(photo: p, width: 140, height: 140, uploading: posting) { photos.removeAll { $0.id == p.id } }
                                }
                            }
                        }
                    }
                    TextField("", text: $text, prompt: Text("Viết vài dòng…").foregroundColor(Theme.textTertiary), axis: .vertical)
                        .font(.system(size: 17)).foregroundStyle(.white).tint(Theme.accent)
                        .lineLimit(3...12).focused($focused)
                        .accessibilityIdentifier("memory.text")
                    if text.count > 1800 {
                        Text("\(text.count)/2000").font(.mpCaption).foregroundStyle(text.count > 2000 ? Theme.danger : Theme.textSecondary)
                    }
                    if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    PhotoPickButton(maxCount: 10 - photos.count, onPicked: { photos.append(contentsOf: $0) }) {
                        HStack(spacing: 6) { Image(systemName: "photo.on.rectangle"); Text("Thư viện") }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 36).background(Theme.surface, in: Capsule())
                    }
                    .accessibilityIdentifier("memory.library")
                    Image(systemName: "camera").font(.system(size: 14)).foregroundStyle(UIImagePickerController.isSourceTypeAvailable(.camera) ? .white : Theme.textTertiary)
                        .frame(width: 36, height: 36).background(Theme.surface, in: Circle())
                }
                InfoNote(text: visibilityNote)
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
        }
        .screenBackground()
        .onAppear { focused = true }
    }

    private var visibilityNote: String {
        switch parent {
        case .place: return "Hiển thị với người có quyền xem địa điểm này"
        case .visit: return "Hiển thị với người có quyền xem lần ghé này"
        case .journal: return "Hiển thị với thành viên của nhật ký này"
        }
    }

    private var canPost: Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!t.isEmpty || !photos.isEmpty) && text.count <= 2000
    }

    private func post() {
        posting = true; error = nil
        Task {
            do {
                try await MyPlacesAPI.shared.createMemory(parent: parent, body: text, photos: photos)
                AppEvents.shared.bump()
                await PlacesStore.shared.refresh()
                dismiss()
            } catch {
                self.error = AppError.message(error)
            }
            posting = false
        }
    }
}
