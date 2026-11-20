import SwiftUI
import PhotosUI

/// Photo source button: system PhotosPicker, or generated photos when `-QAStubPhotos` (DEBUG).
struct PhotoPickButton<Label: View>: View {
    var maxCount: Int = 10
    var onPicked: ([PreparedPhoto]) -> Void
    @ViewBuilder var label: Label
    @State private var items: [PhotosPickerItem] = []
    @State private var seed = Int.random(in: 0..<1000)

    var body: some View {
        if QAHooks.stubPhotos {
            Button {
                #if DEBUG
                seed += 1
                if let p = ImageProcessing.samplePhoto(seed: seed) { onPicked([p]) }
                #endif
            } label: { label }
            .buttonStyle(.plain)
        } else {
            PhotosPicker(selection: $items, maxSelectionCount: max(1, maxCount), matching: .images, photoLibrary: .shared()) { label }
                .buttonStyle(.plain)
                .onChange(of: items) { _, newItems in
                    guard !newItems.isEmpty else { return }
                    Task {
                        let photos = await ImageProcessing.load(newItems)
                        onPicked(photos)
                        items = []
                    }
                }
        }
    }
}

struct PhotoTile: View {
    var photo: PreparedPhoto
    var width: CGFloat
    var height: CGFloat
    var uploading = false
    var onRemove: (() -> Void)?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let img = UIImage(data: photo.data) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: width, height: height).clipped()
            }
            if uploading {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 6) { ProgressView().tint(Theme.accent); Text("Đang tải lên…").font(.system(size: 11)).foregroundStyle(Theme.textPrimary) }
                }
            }
            if let onRemove, !uploading {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.onAccent)
                        .frame(width: 22, height: 22).background(.black.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain).padding(8)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
