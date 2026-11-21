import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import MyPlaces

final class ImageCompressorTests: XCTestCase {
    /// Photo-like test image: gradients + shapes + mild per-pixel noise (so JPEG size is realistic).
    private func makeImage(width: Int, height: Int, noise: UInt8 = 12, alpha: Bool = false) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info)!
        let grad = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1), CGColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1)] as CFArray, locations: [0, 1])!
        if !alpha { ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: width, y: height), options: []) }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        for i in 0..<12 { ctx.fillEllipse(in: CGRect(x: i * width / 12, y: (i * 37) % max(1, height - 200), width: width / 10, height: width / 10)) }
        if noise > 0, let p = ctx.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) {
            var seed: UInt32 = 42
            for i in stride(from: 0, to: width * height * 4, by: 4) {
                seed = seed &* 1664525 &+ 1013904223
                let n = UInt8(truncatingIfNeeded: seed >> 24) % noise
                p[i] = p[i] &+ n; p[i + 1] = p[i + 1] &+ n; p[i + 2] = p[i + 2] &+ n
            }
        }
        return ctx.makeImage()!
    }

    private func encode(_ img: CGImage, type: UTType = .jpeg, quality: Double = 0.95, props: [CFString: Any] = [:]) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        var p = props; p[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(dest, img, p as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func properties(_ data: Data) -> [CFString: Any] {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
    }

    func testDownscalesLongestEdgeTo1600AndKeepsAspect() throws {
        let src = encode(makeImage(width: 4032, height: 3024))
        let r = try XCTUnwrap(ImageCompressor.compress(src))
        XCTAssertEqual(r.width, 1600)
        XCTAssertEqual(r.height, 1200)
        XCTAssertLessThan(r.data.count, src.count)
        XCTAssertLessThanOrEqual(r.data.count, 500_000)
        XCTAssertEqual(properties(r.data)[kCGImagePropertyPixelWidth] as? Int, 1600)
        XCTAssertEqual(r.quality, 0.7, accuracy: 0.001)
    }

    func testNeverUpscales() throws {
        let r = try XCTUnwrap(ImageCompressor.compress(encode(makeImage(width: 800, height: 600))))
        XCTAssertEqual(r.width, 800); XCTAssertEqual(r.height, 600)
    }

    func testAppliesExifOrientation() throws {
        // Stored 400x200 with orientation 6 (rotate 90° CW) -> displayed 200x400.
        let src = encode(makeImage(width: 400, height: 200), props: [kCGImagePropertyOrientation: 6])
        let r = try XCTUnwrap(ImageCompressor.compress(src))
        XCTAssertEqual(r.width, 200); XCTAssertEqual(r.height, 400)
        let o = properties(r.data)[kCGImagePropertyOrientation] as? Int
        XCTAssertTrue(o == nil || o == 1, "output must not carry a rotation flag")
    }

    func testStripsGPSAndCameraMetadata() throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 21.0285, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 105.8542, kCGImagePropertyGPSLongitudeRef: "E"]
        let tiff: [CFString: Any] = [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 14 Pro"]
        let exif: [CFString: Any] = [kCGImagePropertyExifDateTimeOriginal: "2026:11:20 10:00:00", kCGImagePropertyExifLensModel: "iPhone back camera"]
        let src = encode(makeImage(width: 2000, height: 1500), props: [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyTIFFDictionary: tiff, kCGImagePropertyExifDictionary: exif])
        XCTAssertNotNil(properties(src)[kCGImagePropertyGPSDictionary], "fixture should carry GPS")
        let out = properties(try XCTUnwrap(ImageCompressor.compress(src)).data)
        XCTAssertNil(out[kCGImagePropertyGPSDictionary])
        let outTiff = out[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNil(outTiff?[kCGImagePropertyTIFFMake]); XCTAssertNil(outTiff?[kCGImagePropertyTIFFModel])
        let outExif = out[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(outExif?[kCGImagePropertyExifDateTimeOriginal]); XCTAssertNil(outExif?[kCGImagePropertyExifLensModel])
    }

    func testStepsQualityDownForHeavyImagesButNotBelowMinimum() throws {
        // Pure high-entropy noise cannot reach 500 KB at 1600 px: quality must drop to the 0.5 floor and stop.
        let src = encode(makeImage(width: 1600, height: 1600, noise: 255), quality: 1.0)
        let r = try XCTUnwrap(ImageCompressor.compress(src))
        XCTAssertEqual(r.quality, 0.5, accuracy: 0.001)
        XCTAssertLessThan(r.data.count, src.count)
        // And a lower soft limit is honoured on a normal photo.
        var o = ImageCompressor.Options(); o.softLimitBytes = 60_000
        let r2 = try XCTUnwrap(ImageCompressor.compress(encode(makeImage(width: 3000, height: 2000)), options: o))
        XCTAssertLessThan(r2.quality, 0.7)
        XCTAssertGreaterThanOrEqual(r2.quality, 0.5 - 0.001)
    }

    func testOutputIsJPEGAndAcceptsHEICAndPNGWithAlpha() throws {
        let heic = encode(makeImage(width: 3000, height: 2000), type: .heic, quality: 0.9)
        let r = try XCTUnwrap(ImageCompressor.compress(heic))
        XCTAssertEqual(r.width, 1600)
        let src = CGImageSourceCreateWithData(r.data as CFData, nil)!
        XCTAssertEqual(CGImageSourceGetType(src) as String?, UTType.jpeg.identifier)
        let png = encode(makeImage(width: 500, height: 500, alpha: true), type: .png)
        XCTAssertNotNil(ImageCompressor.compress(png))
        XCTAssertEqual(ImageCompressor.contentType, "image/jpeg")
    }

    func testRejectsNonImageData() {
        XCTAssertNil(ImageCompressor.compress(Data("not an image".utf8)))
        XCTAssertNil(ImageCompressor.compress(Data()))
    }

    func testBackgroundVariantMatches() async throws {
        let src = encode(makeImage(width: 2400, height: 1600))
        let a = try XCTUnwrap(ImageCompressor.compress(src))
        let b = await ImageCompressor.compressInBackground(src)
        XCTAssertEqual(a, b)
    }
}
