import SwiftUI
import SwiftData

@main
struct MyPlacesApp: App {
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        .modelContainer(appState.modelContainer)
    }
}
