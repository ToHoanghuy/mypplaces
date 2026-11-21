import UIKit
import SwiftUI
import PhotosUI

enum ImageProcessing {
    /// Picked photo bytes -> upload-ready JPEG (<= 1600 px, q 0.7→0.5, no EXIF/GPS). See `ImageCompressor`.
    static func prepare(data: Data) async -> PreparedPhoto? {
        guard let r = await ImageCompressor.compressInBackground(data) else { return nil }
        return PreparedPhoto(id: UUID(), data: r.data, width: r.width, height: r.height)
    }

    /// Synchronous variant for already-decoded images (QA sample photos).
    static func prepare(_ image: UIImage) -> PreparedPhoto? {
        guard let src = image.jpegData(compressionQuality: 0.95), let r = ImageCompressor.compress(src) else { return nil }
        return PreparedPhoto(id: UUID(), data: r.data, width: r.width, height: r.height)
    }

    static func load(_ items: [PhotosPickerItem]) async -> [PreparedPhoto] {
        var result: [PreparedPhoto] = []
        for item in items {
            // Original file bytes (HEIC/JPEG); decoding + downsampling happens off the main thread.
            if let data = try? await item.loadTransferable(type: Data.self),
               let p = await prepare(data: data) {
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
