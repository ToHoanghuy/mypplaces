import SwiftUI

/// Liquid Glass layer of the design system (docs/design/LIQUID_GLASS_PLAN.md).
///
/// Use ONLY for the navigation / controls layer that floats over content (buttons over photos or the map,
/// floating search fields, toolbars, toasts, map panels). Content cards keep solid `Theme.surface`.
/// iOS 26: native `glassEffect` / glass button styles (the system handles Reduce Transparency & Increase Contrast).
/// iOS 17–25: `.ultraThinMaterial` + hairline; Reduce Transparency → solid `Theme.surface`.

// MARK: - Surface

struct MPGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var interactive: Bool
    var tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background {
                    if reduceTransparency {
                        shape.fill(tint ?? Theme.surfaceHigh)
                    } else {
                        shape.fill(.ultraThinMaterial)
                        if let tint { shape.fill(tint.opacity(0.85)) }
                    }
                }
                .overlay(shape.stroke(Theme.border, lineWidth: 0.5))
                .shadow(color: Theme.shadow.opacity(0.6), radius: 12, y: 4)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension View {
    /// Floating glass surface (controls layer only, never content cards).
    func mpGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(MPGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }

    func mpGlass(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(MPGlassModifier(shape: Capsule(), interactive: interactive, tint: tint))
    }
}

/// Groups nearby glass elements so they blend/morph instead of stacking (iOS 26 `GlassEffectContainer`).
struct MPGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Buttons

/// Neutral glass button (secondary floating actions).
struct MPGlassButtonStyle: ButtonStyle {
    var shape: AnyShape = AnyShape(Capsule())
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .mpGlass(in: shape)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Accent-filled glass button for the one primary action of a screen.
struct MPProminentButtonStyle: ButtonStyle {
    var shape: AnyShape = AnyShape(Capsule())
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(shape.fill(Theme.accent))
            .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: Theme.accent.opacity(0.25), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension View {
    /// `.buttonStyle(.glass)` on iOS 26; material fallback earlier. Label provides its own padding/frame.
    @ViewBuilder func mpGlassButton() -> some View {
        if #available(iOS 26.0, *) { buttonStyle(.glass) } else { buttonStyle(MPGlassButtonStyle()) }
    }

    /// `.buttonStyle(.glassProminent)` tinted coral on iOS 26; solid coral capsule earlier.
    @ViewBuilder func mpProminentButton() -> some View {
        if #available(iOS 26.0, *) { buttonStyle(.glassProminent).tint(Theme.accent) } else { buttonStyle(MPProminentButtonStyle()) }
    }
}

// MARK: - System adoption helpers (no-ops before iOS 26)

extension View {
    /// Soft fade of content under floating top controls.
    @ViewBuilder func mpScrollEdgeSoft() -> some View {
        if #available(iOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: .top) } else { self }
    }

    /// Extends a hero image under the floating controls / safe area.
    @ViewBuilder func mpBackgroundExtension() -> some View {
        if #available(iOS 26.0, *) { backgroundExtensionEffect() } else { self }
    }
}

// MARK: - Sheets
extension View {
    /// Partial-height sheets get the system Liquid Glass sheet on iOS 26; earlier versions use a solid colour + corner radius.
    @ViewBuilder func mpSheetBackground(_ fallback: Color, cornerRadius: CGFloat? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else if let cornerRadius {
            self.presentationBackground(fallback).presentationCornerRadius(cornerRadius)
        } else {
            self.presentationBackground(fallback)
        }
    }

    /// Content of a partial-height sheet: transparent on iOS 26 so the glass shows, solid screen background earlier.
    @ViewBuilder func mpSheetContentBackground() -> some View {
        if #available(iOS 26.0, *) { self } else { self.screenBackground() }
    }
}
