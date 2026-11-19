import Foundation
import Supabase
import Observation

@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    enum Phase: Equatable { case loading, signedOut, signedIn }

    private(set) var phase: Phase = .loading
    private(set) var profile: UserProfile?
    private(set) var email: String?
    private(set) var userID: UUID?

    @ObservationIgnored private var client: SupabaseClient { SupabaseService.shared.client }
    @ObservationIgnored private var listener: Task<Void, Never>?

    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                await self.handle(event: event, session: session)
            }
        }
    }

    private func handle(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            if let session {
                let changedUser = userID != session.user.id
                userID = session.user.id
                email = session.user.email
                phase = .signedIn
                if changedUser || profile == nil { await reloadProfile() }
                if changedUser {
                    SyncEngine.shared.userChanged()
                    await PlacesStore.shared.refresh()
                    await SyncEngine.shared.syncNow()
                }
            } else {
                phase = .signedOut
            }
        case .signedOut, .userDeleted:
            userID = nil; email = nil; profile = nil
            phase = .signedOut
        default:
            break
        }
    }

    func reloadProfile() async {
        guard let uid = userID else { return }
        profile = try? await MyPlacesAPI.shared.profile(uid)
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
    }

    /// Returns true when the project requires email confirmation (no session yet).
    func signUp(name: String, email: String, password: String) async throws -> Bool {
        let r = try await client.auth.signUp(
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            password: password,
            data: ["display_name": .string(name.trimmingCharacters(in: .whitespaces))]
        )
        return r.session == nil
    }

    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespaces).lowercased())
    }

    func updateDisplayName(_ name: String) async throws {
        try await MyPlacesAPI.shared.updateDisplayName(name.trimmingCharacters(in: .whitespaces))
        await reloadProfile()
    }

    func signOut() async {
        try? await client.auth.signOut()
        SyncEngine.shared.reset()
        PlacesStore.shared.reset()
        await ImageStore.shared.clear()
        userID = nil; email = nil; profile = nil
        phase = .signedOut
    }
}
