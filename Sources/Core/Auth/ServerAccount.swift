import Foundation

/// One configured Grimmory server plus the identity used against it.
/// Multi-server from day one — self-hosters routinely run a LAN address and a
/// remote one for the same library.
struct ServerAccount: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var baseURL: URL
    var username: String
    /// Server version, learned after login (`/api/v1/version` is authenticated).
    var serverVersion: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        baseURL: URL,
        username: String,
        serverVersion: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.username = username
        self.serverVersion = serverVersion
    }

    var accessTokenKey: String { "\(id.uuidString).access" }
    var refreshTokenKey: String { "\(id.uuidString).refresh" }
}

extension ServerAccount {
    /// Accepts what people actually type — "192.168.1.21:6060",
    /// "grimmory.local", "http://box:6060/" — and produces a usable base URL.
    static func normalizeBaseURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let host = components.host, !host.isEmpty
        else { return nil }

        // Strip a trailing slash so path joining stays predictable.
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
