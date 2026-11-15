import Foundation
import Combine

@Observable
final class AuthViewModel {
    var email = ""
    var password = ""
    var displayName = ""
    var isLoading = false
    var errorMessage: String?
    var showError = false
    
    private let authRepository: AuthRepository
    
    init(authRepository: AuthRepository = AppState.shared.authRepository) {
        self.authRepository = authRepository
    }
    
    func signIn() async {
        guard !email.isEmpty, !password.isEmpty else {
            showError(message: "Vui lòng nhập email và mật khẩu")
            return
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            try await authRepository.signInWithEmail(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password
            )
            await MainActor.run {
                isLoading = false
                clearForm()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                showError(message: error.localizedDescription)
            }
        }
    }
    
    func signInWithMagicLink() async {
        guard !email.isEmpty else {
            showError(message: "Vui lòng nhập email")
            return
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            try await authRepository.signInWithMagicLink(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
            await MainActor.run {
                isLoading = false
                showError(message: "Đã gửi link đăng nhập đến email của bạn")
            }
        } catch {
            await MainActor.run {
                isLoading = false
                showError(message: error.localizedDescription)
            }
        }
    }
    
    func signUp() async {
        guard !email.isEmpty, !password.isEmpty, !displayName.isEmpty else {
            showError(message: "Vui lòng điền đầy đủ thông tin")
            return
        }
        
        guard password.count >= 6 else {
            showError(message: "Mật khẩu phải có ít nhất 6 ký tự")
            return
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            try await authRepository.signUpWithEmail(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await MainActor.run {
                isLoading = false
                clearForm()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                showError(message: error.localizedDescription)
            }
        }
    }
    
    func signOut() async {
        do {
            try await authRepository.signOut()
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    
    func resetPassword() async {
        guard !email.isEmpty else {
            showError(message: "Vui lòng nhập email")
            return
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            try await authRepository.resetPassword(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
            await MainActor.run {
                isLoading = false
                showError(message: "Đã gửi email đặt lại mật khẩu")
            }
        } catch {
            await MainActor.run {
                isLoading = false
                showError(message: error.localizedDescription)
            }
        }
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    private func clearForm() {
        email = ""
        password = ""
        displayName = ""
        errorMessage = nil
        showError = false
    }
}
