import SwiftUI
import UIKit

/// App appearance (extra feature beyond BRD v1.2): automatic by time of day, always light, or always dark.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Tự động theo giờ"
        case .light: return "Sáng"
        case .dark: return "Tối"
        }
    }
}

enum AppearanceKeys {
    static let mode = "appearance.mode"
    /// Minutes after local midnight.
    static let lightStart = "appearance.lightStart"
    static let darkStart = "appearance.darkStart"
    static let defaultLightStart = 6 * 60   // 06:00
    static let defaultDarkStart = 18 * 60   // 18:00
}

/// Pure schedule logic (unit-tested).
enum ThemeSchedule {
    /// Light when the local time is in [lightStart, darkStart); the window may wrap past midnight.
    /// Equal start times mean "always light".
    static func isLight(minuteOfDay m: Int, lightStart: Int, darkStart: Int) -> Bool {
        let m = ((m % 1440) + 1440) % 1440
        if lightStart == darkStart { return true }
        if lightStart < darkStart { return m >= lightStart && m < darkStart }
        return m >= lightStart || m < darkStart
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func scheme(mode: AppearanceMode, now: Date, lightStart: Int, darkStart: Int, calendar: Calendar = .current) -> ColorScheme {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .auto: return isLight(minuteOfDay: minuteOfDay(now, calendar: calendar), lightStart: lightStart, darkStart: darkStart) ? .light : .dark
        }
    }

    /// The next moment (strictly after `now`) at which the automatic scheme flips.
    static func nextBoundary(after now: Date, lightStart: Int, darkStart: Int, calendar: Calendar = .current) -> Date? {
        guard lightStart != darkStart else { return nil }
        let startOfDay = calendar.startOfDay(for: now)
        var best: Date?
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else { continue }
            for minutes in [lightStart, darkStart] {
                guard let d = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day), d > now else { continue }
                if best == nil || d < best! { best = d }
            }
        }
        return best
    }

    static func label(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}

/// Applies the chosen appearance at the app root (status bar, sheets, keyboard and MapKit follow
/// `preferredColorScheme`) and flips automatically at the next boundary while the app is open.
struct AppearanceRoot: ViewModifier {
    @AppStorage(AppearanceKeys.mode) private var modeRaw = AppearanceMode.auto.rawValue
    @AppStorage(AppearanceKeys.lightStart) private var lightStart = AppearanceKeys.defaultLightStart
    @AppStorage(AppearanceKeys.darkStart) private var darkStart = AppearanceKeys.defaultDarkStart
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    private var mode: AppearanceMode { AppearanceMode(rawValue: modeRaw) ?? .auto }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(ThemeSchedule.scheme(mode: mode, now: now, lightStart: lightStart, darkStart: darkStart))
            .task(id: "\(modeRaw)|\(lightStart)|\(darkStart)|\(now.timeIntervalSince1970)") {
                guard mode == .auto, let next = ThemeSchedule.nextBoundary(after: Date(), lightStart: lightStart, darkStart: darkStart) else { return }
                let wait = max(1, next.timeIntervalSinceNow + 0.5)
                try? await Task.sleep(for: .seconds(wait))
                if !Task.isCancelled { now = Date() }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in now = Date() }
    }
}

extension View {
    func appAppearance() -> some View { modifier(AppearanceRoot()) }
}
