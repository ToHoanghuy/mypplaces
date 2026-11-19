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
                    if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                    Text(title).font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .shadow(color: tone == .accent ? Theme.accent.opacity(0.25) : .clear, radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var foreground: Color {
        switch tone { case .white: return Theme.background; default: return .white }
    }
    private var background: Color {
        switch tone {
        case .accent: return Theme.accent
        case .white: return .white
        case .danger: return Theme.danger
        case .surface: return Theme.surface
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
                if isLoading { ProgressView().tint(.white).scaleEffect(0.8) } else { Text(title).font(.system(size: 14, weight: .semibold)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct CircleIconButton: View {
    var systemName: String
    var size: CGFloat = 36
    var tint: Color = .white
    var background: Color = Color.black.opacity(0.45)
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    var title: String
    var category: PlaceCategory? = nil
    var selected: Bool
    var showCheck = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let category { CategoryDot(category: category) }
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                if showCheck && selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(selected ? Theme.background : .white)
            .background(selected ? Color.white : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? .clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chip.\(title)")
    }
}

/// Horizontal category filter ("Tất cả" + categories).
struct CategoryFilterRow: View {
    @Binding var selection: PlaceCategory?
    var categories: [PlaceCategory] = PlaceCategory.allCases
    var horizontalPadding: CGFloat = 20
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Tất cả", selected: selection == nil) { selection = nil }
                ForEach(categories) { c in
                    Chip(title: c.displayName, category: c, selected: selection == c) { selection = (selection == c ? nil : c) }
                }
            }
            .padding(.horizontal, horizontalPadding)
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
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
            field
                .font(.system(size: 15))
                .foregroundStyle(.white)
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
        .frame(height: 44)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
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
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(Theme.accent)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(keyboard == .emailAddress || secure ? .never : .sentences)
            .autocorrectionDisabled(keyboard == .emailAddress || secure)
            .accessibilityIdentifier(identifier ?? placeholder)
            if secure {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye" : "eye.slash").foregroundStyle(Theme.textSecondary)
                }.buttonStyle(.plain)
            }
            if let trailing { trailing }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
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
                Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Theme.background, lineWidth: size > 40 ? 0 : 1.5))
    }
    private var initials: String {
        let parts = name.split(separator: " ")
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
                Text("+\(names.count - max)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
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
                .font(uppercase ? .mpSection : .system(size: 15, weight: .semibold))
                .foregroundStyle(uppercase ? Theme.textSecondary : .white)
                .tracking(uppercase ? 0.6 : 0)
            Spacer()
            if let count {
                Text("\(count)").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8).frame(height: 20).background(Theme.surface, in: Capsule())
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
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Theme.surfaceHigh, in: Capsule())
    }
}

struct InfoNote: View {
    var text: String
    var icon = "lock"
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).padding(.top, 2)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
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
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Theme.surfaceHigh, in: Circle())
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
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
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 80)
            HStack {
                Button(cancelTitle, action: onCancel).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("modal.cancel")
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }
}

/// Lightweight toast for transient errors / confirmations.
struct ToastModifier: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                Text(message)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Theme.surfaceHigh, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
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

    func screenBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
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
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.danger)
                    .frame(width: 52, height: 52).background(Theme.danger.opacity(0.15), in: Circle())
                Text(title).font(.system(size: 19, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                PrimaryButton(title: confirmTitle, tone: .danger, isLoading: isLoading, height: 48, action: onConfirm)
                    .padding(.top, 6).accessibilityIdentifier("confirm.ok")
                Button("Hủy", action: onCancel).font(.system(size: 15, weight: .medium)).foregroundStyle(.white).padding(.vertical, 6)
            }
            .padding(22)
            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 36)
        }
    }
}
