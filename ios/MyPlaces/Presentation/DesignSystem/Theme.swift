import SwiftUI

/// "MyPlaces Minimal" (Stitch design system assets/8094474840949808557): dark #0E0E10,
/// coral #F26A3D used sparingly, category colors only as tiny dots, photo first.
enum Theme {
    static let background = Color(hex: 0x0E0E10)
    static let surface = Color(hex: 0x1A1A1D)
    static let surfaceHigh = Color(hex: 0x232327)
    static let accent = Color(hex: 0xF26A3D)
    static let danger = Color(hex: 0xFF453A)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x8E8E93)
    static let textTertiary = Color(hex: 0x5C5C61)
    static let hairline = Color.white.opacity(0.06)
    static let border = Color.white.opacity(0.08)

    static let radius: CGFloat = 16
    static let radiusLarge: CGFloat = 24
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension PlaceCategory {
    var color: Color {
        switch self {
        case .food: return Color(hex: 0xF26A3D)
        case .cafe: return Color(hex: 0xB8825A)
        case .travel: return Color(hex: 0x4DB6E6)
        case .hotel: return Color(hex: 0x9B87E8)
        case .shopping: return Color(hex: 0xF06FA3)
        case .entertainment: return Color(hex: 0xF5C04A)
        case .other: return Color(hex: 0x8E98A3)
        }
    }
}

extension Font {
    static let mpLargeTitle = Font.system(size: 28, weight: .bold)
    static let mpTitle = Font.system(size: 22, weight: .bold)
    static let mpHeadline = Font.system(size: 17, weight: .semibold)
    static let mpBody = Font.system(size: 15)
    static let mpCallout = Font.system(size: 14)
    static let mpCaption = Font.system(size: 12)
    static let mpSection = Font.system(size: 12, weight: .semibold)
}
