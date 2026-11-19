import Foundation
import Supabase

/// Single shared Supabase client. Database requests use snake_case <-> camelCase conversion
/// and a tolerant date parser (PostgREST returns microsecond timestamps).
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: JSONCoding.encoder, decoder: JSONCoding.decoder),
                auth: .init(
                    storage: KeychainLocalStorage(),
                    redirectToURL: URL(string: "myplaces://auth-callback"),
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    var currentUserID: UUID? { client.auth.currentUser?.id }
}
