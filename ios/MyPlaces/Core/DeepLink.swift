import Foundation

/// `myplaces://invite/<token>` (share link), plus in-app routes used by navigation and QA:
/// `myplaces://place/<id>`, `myplaces://visit/<id>`, `myplaces://journal/<id>`, `myplaces://tab/<0-4>`.
enum DeepLink: Equatable {
    case invite(String)
    case place(UUID)
    case visit(UUID)
    case journal(UUID)
    case tab(Int)

    static func inviteURL(token: String) -> URL { URL(string: "myplaces://invite/\(token)")! }

    init?(url: URL) {
        guard url.scheme == "myplaces" else { return nil }
        let host = url.host ?? ""
        let value = url.pathComponents.filter { $0 != "/" }.first
            ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "token" || $0.name == "id" })?.value
        switch host {
        case "invite": guard let v = value, !v.isEmpty else { return nil }; self = .invite(v)
        case "place": guard let v = value.flatMap(UUID.init(uuidString:)) else { return nil }; self = .place(v)
        case "visit": guard let v = value.flatMap(UUID.init(uuidString:)) else { return nil }; self = .visit(v)
        case "journal": guard let v = value.flatMap(UUID.init(uuidString:)) else { return nil }; self = .journal(v)
        case "tab": guard let v = value.flatMap(Int.init) else { return nil }; self = .tab(v)
        default: return nil
        }
    }

    /// Accepts a pasted link or a raw token.
    static func parseInvite(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: t), case .invite(let token)? = DeepLink(url: url) { return token }
        if t.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil { return t }
        return nil
    }
}
