import SwiftUI
import UIKit

/// App typography (BRD v1.2: Inter). Every font is `Font.custom(_:size:relativeTo:)`, so all text follows
/// the system text size (Dynamic Type) live. SF Symbols stay SF: an `Image(systemName:)` with an Inter font
/// just takes its point size and weight from it, so icons next to text grow together with the text.
/// Inter 4.1 static TTFs (Regular/Medium/SemiBold/Bold), subset to Latin + Vietnamese, OFL 1.1
/// (`Resources/Fonts/Inter-OFL.txt`).
enum AppFont {
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }

    /// The Dynamic Type curve a design size scales along (Apple's default sizes at "Large").
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: return .largeTitle
        case 26..<30: return .title
        case 21..<26: return .title2
        case 19..<21: return .title3
        case 17..<19: return .body
        case 16..<17: return .callout
        case 15..<16: return .subheadline
        case 13..<15: return .footnote
        case 12..<13: return .caption
        default: return .caption2
        }
    }

    static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }

    /// Scaled UIKit font (navigation bar titles, tab bar labels, search field).
    static func uiFont(_ size: CGFloat, _ weight: Font.Weight = .regular, style: UIFont.TextStyle? = nil) -> UIFont {
        let base = UIFont(name: name(for: weight), size: size) ?? .systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: style ?? uiTextStyle(textStyle(for: size))).scaledFont(for: base)
    }

    /// Inter on navigation bars (large + inline titles), tab bar labels and search fields. Only fonts are set –
    /// no bar backgrounds – so the iOS 26 Liquid Glass bars keep their system look.
    static func configureAppearance() {
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: uiFont(34, .bold, style: .largeTitle)]
        nav.titleTextAttributes = [.font: uiFont(17, .semibold, style: .headline)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: uiFont(17, .regular, style: .body)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: uiFont(10, .medium, style: .caption2)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: uiFont(10, .semibold, style: .caption2)], for: .selected)
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font = uiFont(17, .regular, style: .body)
    }
}

extension Font {
    /// Inter at a design size (pt at the default text size); scales with Dynamic Type.
    static func mp(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(for: weight), size: size, relativeTo: AppFont.textStyle(for: size))
    }

    // Semantic tokens.
    static let mpLargeTitle = Font.mp(28, .bold)
    static let mpTitle = Font.mp(22, .bold)
    static let mpTitle3 = Font.mp(20, .semibold)
    static let mpHeadline = Font.mp(17, .semibold)
    static let mpBody = Font.mp(15)
    static let mpCallout = Font.mp(14)
    static let mpSubheadline = Font.mp(13)
    static let mpFootnote = Font.mp(13)
    static let mpCaption = Font.mp(12)
    static let mpCaption2 = Font.mp(11)
    static let mpSection = Font.mp(12, .semibold)
}

/// One line at normal sizes, more lines at XXXL and accessibility sizes so critical text wraps instead of truncating.
private struct AdaptiveLineLimit: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    let normal: Int
    let large: Int
    func body(content: Content) -> some View { content.lineLimit(size >= .xxxLarge ? large : normal) }
}

extension View {
    func mpLineLimit(_ normal: Int = 1, large: Int = 3) -> some View { modifier(AdaptiveLineLimit(normal: normal, large: large)) }
}
