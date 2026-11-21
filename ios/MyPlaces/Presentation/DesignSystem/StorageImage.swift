import SwiftUI

/// Private media image (signed URL + cache). Falls back to a soft placeholder.
struct StorageImage: View {
    var path: String?
    var placeholderCategory: PlaceCategory? = nil
    var fill = true
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                } else {
                    PlaceholderArt(category: placeholderCategory)
                }
            }
        }
        .task(id: path) {
            guard let path else { image = nil; return }
            if let c = ImageStore.shared.cached(path) { image = c; return }
            image = await ImageStore.shared.image(for: path)
        }
    }
}

struct PlaceholderArt: View {
    var category: PlaceCategory?
    var body: some View {
        ZStack {
            LinearGradient(colors: [(category?.color ?? Theme.surfaceHigh).opacity(0.35), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let category {
                Image(systemName: category.icon).font(.mp(18, .medium)).foregroundStyle(category.color.opacity(0.9))
            }
        }
    }
}

/// Rounded thumbnail of a place (cover photo or category placeholder).
struct PlaceThumb: View {
    var path: String?
    var category: PlaceCategory
    var size: CGFloat = 52
    var corner: CGFloat = 12
    var body: some View {
        StorageImage(path: path, placeholderCategory: category)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
