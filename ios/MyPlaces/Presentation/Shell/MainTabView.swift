import SwiftUI

struct MainTabView: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                SystemTabs()
            } else {
                LegacyTabs()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await SyncEngine.shared.syncNow(); await PlacesStore.shared.refresh() } }
        }
    }

    @ViewBuilder fileprivate static func root(_ tab: AppTab, router: Router) -> some View {
        @Bindable var router = router
        switch tab {
        case .map: NavigationStack(path: $router.mapPath) { MapScreen().appRoutes() }
        case .places: NavigationStack(path: $router.placesPath) { PlaceListView().appRoutes() }
        case .timeline: NavigationStack(path: $router.timelinePath) { TimelineView().appRoutes() }
        case .journals: NavigationStack(path: $router.journalsPath) { JournalListView().appRoutes() }
        case .profile: NavigationStack(path: $router.profilePath) { ProfileView().appRoutes() }
        }
    }
}

/// iOS 26: system TabView – Liquid Glass tab bar, minimizes while scrolling down, keeps each tab's state.
/// Detail screens hide it (`appRoutes` → `.toolbar(.hidden, for: .tabBar)`), as before.
@available(iOS 26.0, *)
private struct SystemTabs: View {
    @Environment(Router.self) private var router
    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    MainTabView.root(tab, router: router)
                }
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .tint(Theme.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// iOS 17–25: one stack at a time + floating tab bar drawn by the app (material glass look).
private struct LegacyTabs: View {
    @Environment(Router.self) private var router
    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            MainTabView.root(router.tab, router: router)
            if showsTabBar {
                FloatingTabBar(selection: $router.tab)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
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
                            .foregroundStyle(selection == tab ? Theme.textPrimary : Theme.textSecondary)
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
        .mpGlass(in: Capsule())
    }
}
