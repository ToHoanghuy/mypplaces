import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        ZStack {
            Theme.background.ignoresSafeArea()
            switch session.phase {
            case .loading:
                ProgressView().tint(.white)
            case .signedOut:
                AuthFlowView()
                    .transition(.opacity)
            case .signedIn:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .fullScreenCover(isPresented: Binding(
            get: { router.inviteToken != nil && session.phase == .signedIn },
            set: { if !$0 { router.inviteToken = nil } })) {
            if let token = router.inviteToken {
                InvitationView(token: token)
                    .environment(session)
                    .environment(router)
            }
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .signedOut { router.reset() }
            if phase == .signedIn { QAHooks.afterSignIn(router: router) }
        }
        .task { await QAHooks.autoSignIn(session: session) }
    }
}
