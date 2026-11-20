import Foundation

/// DEBUG-only automation hooks for simulator QA (no effect in Release builds):
///  - env `QA_EMAIL` / `QA_PASSWORD`: sign in automatically when signed out
///  - env `QA_OPEN`: deep link opened after sign-in (e.g. myplaces://tab/2)
///  - arg `-QAStubPhotos`: photo buttons insert generated sample photos instead of the system picker
///  - arg `-QASignOut`: start signed out
enum QAHooks {
    static var stubPhotos: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-QAStubPhotos")
        #else
        return false
        #endif
    }

    /// `-QANoAutofill`: drop textContentType so iOS password autofill/strong-password UI does not swallow typed text in UI tests.
    static var noAutofill: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-QANoAutofill")
        #else
        return false
        #endif
    }

    static func prepare() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-QAResetLocal") {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: support.appendingPathComponent("map_places.json"))
        }
        #endif
    }

    @MainActor
    static func autoSignIn(session: SessionStore) async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if ProcessInfo.processInfo.arguments.contains("-QASignOut") {
            try? await Task.sleep(for: .milliseconds(300))
            if session.phase == .signedIn { await session.signOut() }
            return
        }
        guard let email = env["QA_EMAIL"], let password = env["QA_PASSWORD"] else { return }
        for _ in 0..<20 where session.phase == .loading { try? await Task.sleep(for: .milliseconds(150)) }
        if session.phase == .signedIn, session.email?.lowercased() != email.lowercased() {
            await session.signOut()   // switch QA account (A ↔ B) between launches
        }
        if session.phase == .signedOut { try? await session.signIn(email: email, password: password) }
        #endif
    }

    @MainActor
    static func afterSignIn(router: Router) {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["QA_OPEN"], let url = URL(string: raw), let link = DeepLink(url: url) {
            router.open(link)
        }
        #endif
    }
}
