import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if appState.authRepository.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState.shared)
}
