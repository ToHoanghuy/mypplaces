import SwiftUI
import UIKit

/// "MyPlaces Minimal" (Stitch design system assets/8094474840949808557).
/// Dark (#0E0E10, original look) and Light (white) palettes; coral #F26A3D used sparingly,
/// category colors only as tiny dots, photo first.
/// Every token is a dynamic color resolved from the current `colorScheme`, so the whole app
/// follows `AppearanceSettings` (applied with `preferredColorScheme` at the root).
enum Theme {
    /// Extra bottom room for the custom floating tab bar (iOS < 26). On iOS 26 the system tab bar
    /// is part of the safe area, so tab roots need no manual clearance.
    static var tabInset: CGFloat {
        if #available(iOS 26.0, *) { return 0 }
        return 74
    }

    static let background = Color(light: 0xFFFFFF, dark: 0x0E0E10)
    static let surface = Color(light: 0xF2F2F4, dark: 0x1A1A1D)
    static let surfaceHigh = Color(light: 0xE7E7EB, dark: 0x232327)
    static let accent = Color(light: 0xE85D2F, dark: 0xF26A3D)
    static let danger = Color(light: 0xE0362C, dark: 0xFF453A)
    static let textPrimary = Color(light: 0x111113, dark: 0xFFFFFF)
    static let textSecondary = Color(light: 0x6C6C72, dark: 0x8E8E93)
    static let textTertiary = Color(light: 0xA3A3AA, dark: 0x5C5C61)
    static let hairline = Color(light: 0x000000, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.06)
    static let border = Color(light: 0x000000, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.08)
    /// Soft drop shadow for floating elements (tab bar, cards over the map).
    static let shadow = Color(light: 0x000000, lightAlpha: 0.12, dark: 0x000000, darkAlpha: 0.45)
    /// Content drawn on accent fills, photos or black scrims: always white in both themes.
    static let onAccent = Color.white

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

    /// Dynamic color resolved per light/dark trait.
    init(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension View {
    /// Content laid over a photo / dark gradient keeps the dark palette (white text) in both themes.
    func onPhoto() -> some View { environment(\.colorScheme, .dark) }
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
