import SwiftUI

struct MainTabView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            Group {
                switch router.tab {
                case .map:
                    NavigationStack(path: $router.mapPath) { MapScreen().appRoutes() }
                case .places:
                    NavigationStack(path: $router.placesPath) { PlaceListView().appRoutes() }
                case .timeline:
                    NavigationStack(path: $router.timelinePath) { TimelineView().appRoutes() }
                case .journals:
                    NavigationStack(path: $router.journalsPath) { JournalListView().appRoutes() }
                case .profile:
                    NavigationStack(path: $router.profilePath) { ProfileView().appRoutes() }
                }
            }
            if showsTabBar {
                FloatingTabBar(selection: $router.tab)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await SyncEngine.shared.syncNow(); await PlacesStore.shared.refresh() } }
        }
    }

    /// Tab bar only on tab roots (Locket-like: detail screens are full-bleed).
    private var showsTabBar: Bool {
        switch router.tab {
        case .map: return router.mapPath.isEmpty
        case .places: return router.placesPath.isEmpty
        case .timeline: return router.timelinePath.isEmpty
        case .journals: return router.journalsPath.isEmpty
        case .profile: return router.profilePath.isEmpty
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? .white : Theme.textSecondary)
                        Circle().fill(selection == tab ? Theme.accent : .clear).frame(width: 4, height: 4)
                    }
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Theme.surface.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}
