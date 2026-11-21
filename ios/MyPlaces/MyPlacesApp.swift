import SwiftUI
import SwiftData

@main
struct MyPlacesApp: App {
    let container: ModelContainer
    @State private var session = SessionStore.shared
    @State private var router = Router()

    init() {
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        do {
            container = try ModelContainer(for: OutboxOperation.self)
        } catch {
            fatalError("Không thể khởi tạo bộ nhớ cục bộ: \(error)")
        }
        SyncEngine.shared.configure(container: container)
        QAHooks.prepare()
        AppFont.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
                .appAppearance()
                .tint(Theme.accent)
                .onOpenURL { url in
                    if let link = DeepLink(url: url) { router.open(link) }
                }
                .task { session.start() }
        }
        .modelContainer(container)
    }
}
