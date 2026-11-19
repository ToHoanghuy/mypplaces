import UIKit
import SwiftUI
import PhotosUI

enum ImageProcessing {
    /// Downscales to <= 2048px and encodes JPEG (bucket accepts jpeg/png/heic, max 10 MB).
    static func prepare(_ image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.82) -> PreparedPhoto? {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        var q = quality
        var data = rendered.jpegData(compressionQuality: q)
        while let d = data, d.count > 9_500_000, q > 0.3 {
            q -= 0.15
            data = rendered.jpegData(compressionQuality: q)
        }
        guard let data else { return nil }
        return PreparedPhoto(id: UUID(), data: data, width: Int(target.width), height: Int(target.height))
    }

    static func load(_ items: [PhotosPickerItem]) async -> [PreparedPhoto] {
        var result: [PreparedPhoto] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data),
               let p = prepare(img) {
                result.append(p)
            }
        }
        return result
    }

    #if DEBUG
    /// Deterministic sample photo for UI tests (`-QAStubPhotos`), so flows can be automated
    /// without driving the out-of-process system photo picker.
    static func samplePhoto(seed: Int) -> PreparedPhoto? {
        let palettes: [[UIColor]] = [
            [UIColor(red: 0.95, green: 0.42, blue: 0.24, alpha: 1), UIColor(red: 0.25, green: 0.12, blue: 0.08, alpha: 1)],
            [UIColor(red: 0.30, green: 0.71, blue: 0.90, alpha: 1), UIColor(red: 0.05, green: 0.10, blue: 0.20, alpha: 1)],
            [UIColor(red: 0.96, green: 0.75, blue: 0.29, alpha: 1), UIColor(red: 0.20, green: 0.15, blue: 0.05, alpha: 1)],
            [UIColor(red: 0.61, green: 0.53, blue: 0.91, alpha: 1), UIColor(red: 0.08, green: 0.06, blue: 0.18, alpha: 1)],
        ]
        let colors = palettes[abs(seed) % palettes.count]
        let size = CGSize(width: 1200, height: 1200)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.white.withAlphaComponent(0.85).setFill()
            cg.fillEllipse(in: CGRect(x: 420, y: 380, width: 360, height: 360))
            let text = "MyPlaces #\(seed)" as NSString
            text.draw(at: CGPoint(x: 80, y: 1060), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 64), .foregroundColor: UIColor.white])
        }
        return prepare(img)
    }
    #endif
}
