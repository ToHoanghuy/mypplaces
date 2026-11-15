import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()
    
    let client: SupabaseClient
    
    private init() {
        self.client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
    
    var currentUserID: UUID? {
        try? client.auth.session.user.id
    }
    
    var isAuthenticated: Bool {
        (try? client.auth.session) != nil
    }
}
