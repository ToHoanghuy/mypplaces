import SwiftUI

struct CategoryDot: View {
    var category: PlaceCategory
    var size: CGFloat = 6
    var body: some View { Circle().fill(category.color).frame(width: size, height: size) }
}

enum ButtonTone { case accent, white, danger, surface }

struct PrimaryButton: View {
    var title: String
    var icon: String? = nil
    var tone: ButtonTone = .accent
    var isLoading = false
    var isEnabled = true
    var height: CGFloat = 52
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else {
                    if let icon { Image(systemName: icon).font(.mp(15, .semibold)) }
                    Text(title).font(.mp(16, .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(foreground)
            .modifier(PrimaryFill(tone: tone, color: background))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var foreground: Color {
        switch tone {
        case .white: return Theme.background
        case .surface: return Theme.textPrimary
        default: return Theme.onAccent
        }
    }
    private var background: Color {
        switch tone {
        case .accent: return Theme.accent
        case .white: return Theme.textPrimary
        case .danger: return Theme.danger
        case .surface: return Theme.surface
        }
    }
}

/// iOS 26: tinted, interactive Liquid Glass for accent/danger/surface CTAs; solid capsule otherwise.
private struct PrimaryFill: ViewModifier {
    var tone: ButtonTone
    var color: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), tone != .white {
            content.mpGlass(in: Capsule(), interactive: true, tint: tone == .surface ? nil : color)
        } else {
            content
                .background(color, in: Capsule())
                .shadow(color: tone == .accent ? Theme.accent.opacity(0.25) : .clear, radius: 14, y: 6)
        }
    }
}

/// Small coral capsule used in nav bars ("Lưu", "Đăng", "Tạo").
struct PillButton: View {
    var title: String
    var isLoading = false
    var isEnabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if isLoading { ProgressView().tint(Theme.onAccent).scaleEffect(0.8) } else { Text(title).font(.mp(14, .semibold)) }
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16)
            .frame(minHeight: 34)
            .modifier(PrimaryFill(tone: .accent, color: Theme.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct CircleIconButton: View {
    var systemName: String
    var size: CGFloat = 36
    /// nil = white on the photo scrim (default) or primary text on a themed background.
    var tint: Color? = nil
    /// nil = translucent black scrim, used over photos and maps in both themes.
    var background: Color? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            CircleIconLabel(systemName: systemName, size: size, tint: tint, background: background)
        }
        .buttonStyle(.plain)
    }
}

/// The visual of `CircleIconButton`, for `Menu` labels ("…" menus on photo headers).
struct CircleIconLabel: View {
    var systemName: String
    var size: CGFloat = 36
    var tint: Color? = nil
    var background: Color? = nil
    var body: some View {
        if #available(iOS 26.0, *) {
            // Floating control: Liquid Glass adapts to the photo / map / background behind it.
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint ?? Color.primary)
                .frame(width: size, height: size)
                .mpGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        } else {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint ?? (background == nil ? Theme.onAccent : Theme.textPrimary))
                .frame(width: size, height: size)
                .background(background ?? Color.black.opacity(0.45), in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
        }
    }
}

/// Round coral action floating over content (map "+"). iOS 26: tinted interactive glass.
struct FloatingActionButton: View {
    var systemName: String
    var size: CGFloat = 56
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            if #available(iOS 26.0, *) {
                Image(systemName: systemName).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(width: size, height: size)
                    .mpGlass(in: Circle(), interactive: true, tint: Theme.accent)
                    .contentShape(Circle())
            } else {
                Image(systemName: systemName).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .frame(width: size, height: size).background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 6)
            }
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    var title: String
    var category: PlaceCategory? = nil
    var selected: Bool
    var showCheck = false
    /// Chips floating over the map use glass; chips inside forms/lists stay solid (content).
    var floating = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let category { CategoryDot(category: category) }
                Text(title).font(.mp(13, selected ? .semibold : .medium))
                if showCheck && selected { Image(systemName: "checkmark").font(.mp(10, .bold)) }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
            .modifier(ChipFill(selected: selected, floating: floating))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chip.\(title)")
    }
}

private struct ChipFill: ViewModifier {
    var selected: Bool
    var floating: Bool
    func body(content: Content) -> some View {
        if floating && !selected {
            content.mpGlass(in: Capsule(), interactive: true)
        } else {
            content
                .background(selected ? Theme.textPrimary : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Theme.border, lineWidth: 1))
        }
    }
}

/// Horizontal category filter ("Tất cả" + categories).
struct CategoryFilterRow: View {
    @Binding var selection: PlaceCategory?
    var categories: [PlaceCategory] = PlaceCategory.allCases
    var horizontalPadding: CGFloat = 20
    var floating = false
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            MPGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Chip(title: "Tất cả", selected: selection == nil, floating: floating) { selection = nil }
                    ForEach(categories) { c in
                        Chip(title: c.displayName, category: c, selected: selection == c, floating: floating) { selection = (selection == c ? nil : c) }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, floating ? 6 : 0)
            }
        }
    }
}

/// Wrapping category picker used in forms (03b, 03d).
struct CategoryPicker: View {
    @Binding var selection: PlaceCategory
    var wrap = true
    var body: some View {
        if wrap {
            FlowLayout(spacing: 8) {
                ForEach(PlaceCategory.allCases) { c in
                    Chip(title: c.displayName, category: c, selected: selection == c) { selection = c }
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlaceCategory.allCases) { c in
                        Chip(title: c.displayName, category: c, selected: selection == c) { selection = c }
                    }
                }
            }
        }
    }
}

struct SearchField: View {
    var placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding? = nil
    /// Floating (over map / at the top of a full-screen search) = glass; inline in a list = solid.
    var floating = false
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.mp(15)).foregroundStyle(Theme.textSecondary)
            field
                .font(.mp(15))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .modifier(SearchFill(floating: floating))
    }

    private struct SearchFill: ViewModifier {
        var floating: Bool
        func body(content: Content) -> some View {
            if floating {
                content.mpGlass(in: Capsule())
            } else {
                content.background(Theme.surface, in: Capsule()).overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    @ViewBuilder private var field: some View {
        let tf = TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.textSecondary))
        if let focused { tf.focused(focused) } else { tf }
    }
}

/// Rounded dark input (auth / forms).
struct InputField: View {
    var placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var leadingIcon: String? = nil
    var trailing: AnyView? = nil
    var identifier: String? = nil
    @State private var reveal = false

    var body: some View {
        HStack(spacing: 10) {
            if let leadingIcon { Image(systemName: leadingIcon).foregroundStyle(Theme.textSecondary) }
            Group {
                if secure && !reveal {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.textSecondary))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.textSecondary))
                }
            }
            .font(.mp(15))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .keyboardType(keyboard)
            .textContentType(QAHooks.noAutofill ? nil : contentType)
            .textInputAutocapitalization(keyboard == .emailAddress || secure ? .never : .sentences)
            .autocorrectionDisabled(keyboard == .emailAddress || secure)
            .accessibilityIdentifier(identifier ?? placeholder)
            if secure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye" : "eye.slash").foregroundStyle(Theme.textSecondary)
                }.buttonStyle(.plain)
                .accessibilityLabel(reveal ? "Ẩn mật khẩu" : "Hiện mật khẩu")
                .accessibilityIdentifier("\(identifier ?? placeholder).reveal")
            }
            if let trailing { trailing }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct Avatar: View {
    var name: String
    var path: String? = nil
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle().fill(Theme.surfaceHigh)
            if let path {
                StorageImage(path: path).clipShape(Circle())
            } else {
                Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Theme.background, lineWidth: size > 40 ? 0 : 1.5))
    }
    private var initials: String {
        // Vietnamese given name is the last word; skip suffixes like "(bạn)".
        let parts = name.split(separator: " ").filter { $0.first?.isLetter == true }
        guard let last = parts.last?.first else { return "?" }
        return String(last).uppercased()
    }
}

struct AvatarStack: View {
    var names: [String]
    var size: CGFloat = 22
    var max: Int = 3
    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(max).enumerated()), id: \.offset) { _, n in Avatar(name: n, size: size) }
            if names.count > max {
                Text("+\(names.count - max)").font(.mp(10, .semibold)).foregroundStyle(Theme.textPrimary)
                    .padding(.leading, size * 0.4)
            }
        }
    }
}

struct SectionHeader: View {
    var title: String
    var count: Int? = nil
    var uppercase = false
    var body: some View {
        HStack {
            Text(uppercase ? title.uppercased() : title)
                .font(uppercase ? .mpSection : .mp(15, .semibold))
                .foregroundStyle(uppercase ? Theme.textSecondary : Theme.textPrimary)
                .tracking(uppercase ? 0.6 : 0)
            Spacer()
            if let count {
                Text("\(count)").font(.mp(12, .medium)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8).frame(minHeight: 20).background(Theme.surface, in: Capsule())
            }
        }
    }
}

struct Badge: View {
    var text: String
    var icon: String? = nil
    var tone: Color = Theme.textSecondary
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.mp(9, .semibold)) }
            Text(text).font(.mp(11, .medium))
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 8)
        .frame(minHeight: 20)
        .background(Theme.surfaceHigh, in: Capsule())
    }
}

struct InfoNote: View {
    var text: String
    var icon = "lock"
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.mp(11)).padding(.top, 2)
            Text(text).font(.mp(12)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textSecondary)
    }
}

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.textPrimary)
                .frame(width: 48, height: 48).background(Theme.surfaceHigh, in: Circle())
            Text(title).font(.mp(18, .bold)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.mpCallout).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, icon: "plus", action: action).padding(.top, 10)
            }
        }
        .padding(24)
    }
}

/// Simple wrap layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height); maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }
}

/// Text bar used by modal forms: "Hủy  ·  Title  ·  [Action]".
struct ModalBar<Trailing: View>: View {
    var title: String
    var cancelTitle = "Hủy"
    var onCancel: () -> Void
    @ViewBuilder var trailing: Trailing
    var body: some View {
        ZStack {
            Text(title).font(.mp(16, .semibold)).foregroundStyle(Theme.textPrimary).mpLineLimit(large: 2).padding(.horizontal, 80)
            HStack {
                Button(action: onCancel) {
                    Text(cancelTitle).font(.mp(15, .medium)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14).frame(minHeight: 34)
                        .mpGlass(in: Capsule(), interactive: true)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("modal.cancel")
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
    }
}

/// Lightweight toast for transient errors / confirmations.
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                Text(message)
                    .font(.mp(14, .medium)).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .mpGlass(in: Capsule())
                    .padding(.top, 8).padding(.horizontal, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { self.message = nil }
                    }
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(.spring(duration: 0.3), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }

    /// Screen fill; tapping empty background also dismisses the keyboard (multi-line fields have no return-to-dismiss).
    func screenBackground() -> some View {
        self.background(
            Theme.background.ignoresSafeArea()
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
    }
}

/// Centered confirmation card on a dimmed backdrop (03e).
struct ConfirmCard: View {
    var icon: String
    var title: String
    var message: String
    var confirmTitle: String
    var isLoading = false
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.danger)
                    .frame(width: 52, height: 52).background(Theme.danger.opacity(0.15), in: Circle())
                Text(title).font(.mp(19, .bold)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                Text(message).font(.mp(13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                PrimaryButton(title: confirmTitle, tone: .danger, isLoading: isLoading, height: 48, action: onConfirm)
                    .padding(.top, 6).accessibilityIdentifier("confirm.ok")
                Button("Hủy", action: onCancel).font(.mp(15, .medium)).foregroundStyle(Theme.textPrimary).padding(.vertical, 6)
            }
            .padding(22)
            .modifier(AlertFill())
            .padding(.horizontal, 36)
        }
    }
}

/// iOS 26 alerts are glass; earlier keep the solid elevated card.
private struct AlertFill: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.mpGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        } else {
            content.background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}
