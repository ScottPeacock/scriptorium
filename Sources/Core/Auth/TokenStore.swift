import Foundation

struct Tokens: Sendable, Equatable {
    var access: String
    var refresh: String?
    var expiry: Date?

    /// Treat a token as stale slightly before it actually expires, so a request
    /// doesn't set off mid-flight.
    func isExpired(now: Date = .now, leeway: TimeInterval = 30) -> Bool {
        guard let expiry else { return false }
        return now.addingTimeInterval(leeway) >= expiry
    }
}

/// Keychain-backed token storage for one account.
actor TokenStore {
    private let account: ServerAccount
    private let keychain: Keychain
    private var cached: Tokens?

    init(account: ServerAccount, keychain: Keychain = Keychain()) {
        self.account = account
        self.keychain = keychain
    }

    func load() -> Tokens? {
        if let cached {
            return cached
        }
        guard let access = keychain.get(account.accessTokenKey) else { return nil }
        let tokens = Tokens(
            access: access,
            refresh: keychain.get(account.refreshTokenKey),
            expiry: nil
        )
        cached = tokens
        return tokens
    }

    func store(_ token: AccessToken) throws {
        let tokens = Tokens(
            access: token.accessToken,
            refresh: token.refreshToken ?? cached?.refresh,
            expiry: token.expiryDate
        )
        try keychain.set(tokens.access, for: account.accessTokenKey)
        if let refresh = tokens.refresh {
            try keychain.set(refresh, for: account.refreshTokenKey)
        }
        cached = tokens
    }

    func clear() {
        keychain.remove(account.accessTokenKey)
        keychain.remove(account.refreshTokenKey)
        cached = nil
    }
}
