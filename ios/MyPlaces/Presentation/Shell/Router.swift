import SwiftUI
import Observation

enum AppTab: Int, CaseIterable {
    case map, places, timeline, journals, profile

    var icon: String {
        switch self {
        case .map: return "map"
        case .places: return "list.bullet"
        case .timeline: return "clock"
        case .journals: return "book"
        case .profile: return "person"
        }
    }
    var title: String {
        switch self {
        case .map: return "Bản đồ"
        case .places: return "Địa điểm"
        case .timeline: return "Dòng thời gian"
        case .journals: return "Nhật ký"
        case .profile: return "Cá nhân"
        }
    }
}

enum Route: Hashable {
    case place(UUID)
    case visit(UUID)
    case journal(UUID)
    case members(ShareTarget)
    case archivedJournals
    case sync
}

@MainActor
@Observable
final class Router {
    var tab: AppTab = .map
    var mapPath: [Route] = []
    var placesPath: [Route] = []
    var timelinePath: [Route] = []
    var journalsPath: [Route] = []
    var profilePath: [Route] = []
    /// Invitation token waiting to be shown (07c) — kept until the user is signed in.
    var inviteToken: String?

    func push(_ route: Route) {
        switch tab {
        case .map: mapPath.append(route)
        case .places: placesPath.append(route)
        case .timeline: timelinePath.append(route)
        case .journals: journalsPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func open(_ link: DeepLink) {
        switch link {
        case .invite(let token): inviteToken = token
        case .tab(let i): tab = AppTab(rawValue: i) ?? .map
        case .place(let id): tab = .places; placesPath = [.place(id)]
        case .visit(let id): tab = .timeline; timelinePath = [.visit(id)]
        case .journal(let id): tab = .journals; journalsPath = [.journal(id)]
        }
    }

    /// After accepting an invitation, jump to the shared resource.
    func show(_ type: ResourceType, _ id: UUID) {
        switch type {
        case .place: open(.place(id))
        case .visit: open(.visit(id))
        case .journal: open(.journal(id))
        }
    }

    func reset() {
        tab = .map
        mapPath = []; placesPath = []; timelinePath = []; journalsPath = []; profilePath = []
    }
}

extension View {
    /// Registers every pushable screen on a NavigationStack.
    func appRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
            switch route {
            case .place(let id): PlaceDetailView(placeID: id)
            case .visit(let id): VisitDetailView(visitID: id)
            case .journal(let id): JournalDetailView(journalID: id)
            case .members(let target): MembersView(target: target)
            case .archivedJournals: JournalListView(archivedOnly: true)
            case .sync: SyncView()
            }
            }
            .toolbar(.hidden, for: .tabBar)   // detail screens stay full-bleed (Locket-like)
        }
    }
}
