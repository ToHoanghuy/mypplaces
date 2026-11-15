import Foundation
import Supabase
import Combine

final class AuthRepository: ObservableObject {
    @Published var currentUser: UserProfile?
    @Published var isAuthenticated = false
    
    private let supabase: SupabaseClient
    private var cancellables = Set<AnyCancellable>()
    
    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
        Task {
            await restoreSession()
        }
    }
    
    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            await MainActor.run {
                self.isAuthenticated = true
            }
            await fetchProfile(userID: session.user.id)
        } catch {
            await MainActor.run {
                self.isAuthenticated = false
                self.currentUser = nil
            }
        }
    }
    
    func signInWithEmail(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(
            email: email,
            password: password
        )
        await MainActor.run {
            self.isAuthenticated = true
        }
        await fetchProfile(userID: session.user.id)
    }
    
    func signInWithMagicLink(email: String) async throws {
        try await supabase.auth.signInWithOTP(
            email: email
        )
    }
    
    func signUpWithEmail(email: String, password: String, displayName: String) async throws {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password
        )
        
        guard let userID = response.user?.id else {
            throw AuthError.signUpFailed
        }
        
        try await createProfile(userID: userID, displayName: displayName)
        
        await MainActor.run {
            self.isAuthenticated = true
        }
    }
    
    func signOut() async throws {
        try await supabase.auth.signOut()
        await MainActor.run {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }
    
    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }
    
    private func fetchProfile(userID: UUID) async {
        do {
            let profile: UserProfile = try await supabase.database
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            
            await MainActor.run {
                self.currentUser = profile
            }
        } catch {
            print("Failed to fetch profile: \(error)")
        }
    }
    
    private func createProfile(userID: UUID, displayName: String) async throws {
        let profile: [String: Any] = [
            "id": userID.uuidString,
            "display_name": displayName,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        try await supabase.database
            .from("profiles")
            .insert(profile)
            .execute()
    }
    
    func updateProfile(displayName: String? = nil, avatarPath: String? = nil) async throws {
        guard let userID = currentUser?.id else {
            throw AuthError.notAuthenticated
        }
        
        var updates: [String: Any] = [
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let displayName = displayName {
            updates["display_name"] = displayName
        }
        
        if let avatarPath = avatarPath {
            updates["avatar_path"] = avatarPath
        }
        
        try await supabase.database
            .from("profiles")
            .update(updates)
            .eq("id", value: userID.uuidString)
            .execute()
        
        await fetchProfile(userID: userID)
    }
}

enum AuthError: LocalizedError {
    case notAuthenticated
    case signUpFailed
    case profileCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Bạn chưa đăng nhập"
        case .signUpFailed:
            return "Đăng ký không thành công"
        case .profileCreationFailed:
            return "Không thể tạo profile"
        }
    }
}
