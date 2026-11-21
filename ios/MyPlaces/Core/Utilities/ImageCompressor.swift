import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Client-side photo compression before upload to Storage.
///
/// - Downsamples with ImageIO (`CGImageSourceCreateThumbnailAtIndex`) so the full-resolution bitmap is never
///   decoded: memory stays proportional to the 1600 px output, not the 12–48 MP original.
/// - Applies the EXIF orientation (`…WithTransform`) and re-encodes from pixels only, so EXIF/GPS/TIFF/maker
///   metadata is dropped (privacy: no location or device info leaks through shared photos).
/// - JPEG quality 0.7; if the result is still above `softLimitBytes`, quality steps down to `minQuality`.
/// - Never upscales. Pure, synchronous and thread-safe: call `compressInBackground` from UI code.
enum ImageCompressor {
    struct Options: Sendable {
        var maxDimension: Int = 1600
        var quality: Double = 0.7
        var minQuality: Double = 0.5
        var qualityStep: Double = 0.1
        var softLimitBytes: Int = 500_000
    }

    struct Result: Sendable, Equatable {
        var data: Data
        var width: Int
        var height: Int
        var quality: Double
    }

    static let contentType = "image/jpeg"
    static let fileExtension = "jpg"

    /// Compresses encoded image bytes (JPEG, HEIC, PNG, …). Returns nil if the data is not a decodable image.
    static func compress(_ data: Data, options: Options = Options()) -> Result? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(w, h)
        guard longest > 0 else { return nil }
        let target = min(options.maxDimension, longest)   // never upscale
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // bake EXIF orientation into pixels
            kCGImageSourceThumbnailMaxPixelSize: target,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else { return nil }
        if hasAlpha(image), let flat = flattenOnWhite(image) { image = flat }   // JPEG has no alpha
        return encode(image, options: options)
    }

    /// Same as `compress`, off the calling actor (keeps the main thread free while picking photos).
    static func compressInBackground(_ data: Data, options: Options = Options()) async -> Result? {
        await Task.detached(priority: .userInitiated) { compress(data, options: options) }.value
    }

    // MARK: Private

    private static func encode(_ image: CGImage, options: Options) -> Result? {
        var q = options.quality
        var best: Data?
        while true {
            guard let d = jpeg(image, quality: q) else { return nil }
            best = d
            if d.count <= options.softLimitBytes || q - options.qualityStep < options.minQuality - 0.0001 { break }
            q = (q - options.qualityStep).rounded(toPlaces: 2)
        }
        guard let data = best else { return nil }
        return Result(data: data, width: image.width, height: image.height, quality: q)
    }

    /// Pixels only: no properties dictionary is passed, so no EXIF/GPS/TIFF metadata is written.
    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast: return true
        default: return false
        }
    }

    private static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space.model == .rgb ? space : CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}

private extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let m = pow(10, Double(p)); return (self * m).rounded() / m
    }
}
