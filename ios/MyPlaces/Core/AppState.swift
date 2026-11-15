import Foundation
import SwiftData
import SwiftUI

final class AppState: ObservableObject {
    static let shared = AppState()
    
    let modelContainer: ModelContainer
    let authRepository: AuthRepository
    
    @Published var isAuthenticated = false
    
    private init() {
        do {
            let schema = Schema([
                LocalPlace.self,
                OutboxOperation.self
            ])
            
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [config]
            )
            
            self.authRepository = AuthRepository()
            
            Task { @MainActor in
                self.isAuthenticated = self.authRepository.isAuthenticated
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
