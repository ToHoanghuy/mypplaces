import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MapView(modelContext: modelContext)
                .tabItem {
                    Label("Bản đồ", systemImage: "map")
                }
                .tag(0)
            
            PlaceListView(modelContext: modelContext)
                .tabItem {
                    Label("Địa điểm", systemImage: "list.bullet")
                }
                .tag(1)
            
            JournalListView()
                .tabItem {
                    Label("Hành trình", systemImage: "book")
                }
                .tag(2)
            
            ProfileView()
                .tabItem {
                    Label("Cá nhân", systemImage: "person")
                }
                .tag(3)
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(AppState.shared.modelContainer)
}
