import Foundation

enum SupabaseConfig {
    static var url: URL {
        guard let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              let url = URL(string: urlString) else {
            fatalError("SUPABASE_URL not configured in Info.plist. Please copy Config.example.xcconfig to Config.xcconfig and configure it.")
        }
        return url
    }
    
    static var anonKey: String {
        guard let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String else {
            fatalError("SUPABASE_ANON_KEY not configured in Info.plist. Please copy Config.example.xcconfig to Config.xcconfig and configure it.")
        }
        return key
    }
}
