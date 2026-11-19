import SwiftUI

enum AuthRoute: Hashable { case signIn, signUp, forgot }

/// 01a–01d. Guest only sees the intro and auth screens (BRD §4.1, DEC-01).
struct AuthFlowView: View {
    @State private var path: [AuthRoute] = []
    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(path: $path)
                .navigationDestination(for: AuthRoute.self) { r in
                    switch r {
                    case .signIn: SignInView(path: $path)
                    case .signUp: SignUpView(path: $path)
                    case .forgot: ForgotPasswordView(path: $path)
                    }
                }
        }
    }
}

struct HeroPhoto: View {
    var caption: String? = "Phố cổ Hà Nội"
    var height: CGFloat
    var body: some View {
        Image("Hero").resizable().scaledToFill()
            .frame(height: height).frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let caption {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                        Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(12)
                }
            }
    }
}

struct AuthHeader: View {
    var title: String
    var subtitle: String? = nil
    var centerTitle: String? = nil
    var onBack: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let centerTitle { Text(centerTitle).font(.system(size: 16, weight: .bold)).foregroundStyle(.white) }
                HStack { CircleIconButton(systemName: "chevron.left", background: Theme.surface, action: onBack); Spacer() }
            }
            .padding(.bottom, 8)
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            if let subtitle { Text(subtitle).font(.mpCaption).foregroundStyle(Theme.textSecondary) }
        }
    }
}

struct WelcomeView: View {
    @Binding var path: [AuthRoute]
    var body: some View {
        VStack(spacing: 0) {
            Text("MyPlaces").font(.system(size: 17, weight: .bold)).foregroundStyle(.white).padding(.top, 8)
            HeroPhoto(caption: nil, height: 400).padding(.top, 14)
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                Text("MYPLACES").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textSecondary)
                Text("Nơi chốn là kỷ niệm").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                Text("Lưu nơi bạn đã đến, từng lần ghé và người đi cùng.")
                    .font(.system(size: 14)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                HStack(spacing: 5) {
                    Capsule().fill(Theme.accent).frame(width: 16, height: 4)
                    Circle().fill(Theme.textTertiary).frame(width: 4, height: 4)
                    Circle().fill(Theme.textTertiary).frame(width: 4, height: 4)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 20)
            PrimaryButton(title: "Tạo tài khoản") { path.append(.signUp) }
                .accessibilityIdentifier("welcome.signup")
            Button("Tôi đã có tài khoản") { path.append(.signIn) }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .padding(.vertical, 16)
                .accessibilityIdentifier("welcome.signin")
        }
        .padding(.horizontal, 14)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SignInView: View {
    @Binding var path: [AuthRoute]
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(title: "Đăng nhập") { path.removeLast() }
                HeroPhoto(height: 220).padding(.top, 28)
                VStack(spacing: 12) {
                    InputField(placeholder: "Email của bạn", text: $email, keyboard: .emailAddress, contentType: .username, identifier: "signin.email")
                    InputField(placeholder: "Mật khẩu", text: $password, secure: true, contentType: .password, identifier: "signin.password")
                    HStack {
                        Spacer()
                        Button("Quên mật khẩu?") { path.append(.forgot) }.font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger).frame(maxWidth: .infinity, alignment: .leading) }
                    PrimaryButton(title: "Đăng nhập", isLoading: loading, isEnabled: valid) { submit() }
                        .padding(.top, 6).accessibilityIdentifier("signin.submit")
                    HStack(spacing: 4) {
                        Text("Chưa có tài khoản?").foregroundStyle(Theme.textSecondary)
                        Button("Đăng ký") { path = [.signUp] }.foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                    .font(.system(size: 13)).padding(.top, 12)
                }
                .padding(.top, 36)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var valid: Bool { email.contains("@") && !password.isEmpty }

    private func submit() {
        loading = true; error = nil
        Task {
            do { try await session.signIn(email: email, password: password) }
            catch { self.error = AppError.message(error) }
            loading = false
        }
    }
}

struct SignUpView: View {
    @Binding var path: [AuthRoute]
    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    @State private var confirmSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(title: "Tạo tài khoản", subtitle: "Lưu giữ khoảnh khắc và địa điểm thân quen của bạn") { path.removeLast() }
                HeroPhoto(height: 160).padding(.top, 16)
                VStack(alignment: .leading, spacing: 12) {
                    InputField(placeholder: "Tên hiển thị", text: $name, contentType: .name, identifier: "signup.name")
                    InputField(placeholder: "Email", text: $email, keyboard: .emailAddress, contentType: .username, identifier: "signup.email")
                    InputField(placeholder: "Mật khẩu", text: $password, secure: true, contentType: .newPassword, identifier: "signup.password")
                    Text("Tối thiểu 8 ký tự").font(.system(size: 11)).foregroundStyle(password.isEmpty || password.count >= 8 ? Theme.textSecondary : Theme.danger)
                        .padding(.leading, 12)
                    if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger) }
                    if confirmSent {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "envelope").foregroundStyle(Theme.accent)
                            Text("Đã gửi email xác nhận tới \(email). Hãy mở liên kết trong email rồi đăng nhập.")
                                .font(.system(size: 13)).foregroundStyle(.white)
                        }
                        .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }
                    PrimaryButton(title: "Đăng ký", isLoading: loading, isEnabled: valid) { submit() }
                        .padding(.top, 8).accessibilityIdentifier("signup.submit")
                    HStack(spacing: 4) {
                        Text("Đã có tài khoản?").foregroundStyle(Theme.textSecondary)
                        Button("Đăng nhập") { path = [.signIn] }.foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                    .font(.system(size: 13)).frame(maxWidth: .infinity).padding(.top, 20)
                }
                .padding(.top, 36)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    /// FR-AU-05: display name 1–40; password >= 8 (BRD §10.1).
    private var valid: Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        return (1...40).contains(n.count) && email.contains("@") && password.count >= 8
    }

    private func submit() {
        loading = true; error = nil
        Task {
            do { confirmSent = try await session.signUp(name: name, email: email, password: password) }
            catch { self.error = AppError.message(error) }
            loading = false
        }
    }
}

struct ForgotPasswordView: View {
    @Binding var path: [AuthRoute]
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var sent = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AuthHeader(title: "Đặt lại mật khẩu", subtitle: "Nhận liên kết an toàn để khôi phục tài khoản", centerTitle: "MyPlaces") { path.removeLast() }
                HeroPhoto(height: 150).padding(.top, 16)
                if sent {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope").font(.system(size: 14)).foregroundStyle(Theme.accent)
                            .frame(width: 32, height: 32).background(Theme.accent.opacity(0.15), in: Circle())
                        Text("Đã gửi liên kết đặt lại mật khẩu tới email của bạn.").font(.system(size: 13)).foregroundStyle(.white)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.top, 16)
                }
                Text("Email đã đăng ký").font(.mpCaption).foregroundStyle(Theme.textSecondary).padding(.top, 20).padding(.leading, 8)
                InputField(placeholder: "Email", text: $email, keyboard: .emailAddress, contentType: .username, leadingIcon: "at",
                           trailing: email.contains("@") ? AnyView(Image(systemName: "checkmark.circle").foregroundStyle(.green)) : nil,
                           identifier: "forgot.email")
                    .padding(.top, 8)
                if let error { Text(error).font(.mpCaption).foregroundStyle(Theme.danger).padding(.top, 8) }
                PrimaryButton(title: sent ? "Gửi lại liên kết" : "Gửi liên kết", isLoading: loading, isEnabled: email.contains("@")) { submit() }
                    .padding(.top, 60)
                Button("Quay lại đăng nhập") { path = [.signIn] }
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .padding(.horizontal, 20)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func submit() {
        loading = true; error = nil
        Task {
            do { try await session.sendPasswordReset(email: email); sent = true }
            catch { self.error = AppError.message(error) }
            loading = false
        }
    }
}
