import Foundation
import Testing
@testable import Scriptorium

@Suite("Token expiry")
struct TokenTests {
    @Test("A token with no expiry is never treated as stale")
    func noExpiry() {
        #expect(!Tokens(access: "a", refresh: nil, expiry: nil).isExpired())
    }

    @Test("A token expiring inside the leeway counts as stale")
    func withinLeeway() {
        let now = Date()
        let tokens = Tokens(access: "a", refresh: nil, expiry: now.addingTimeInterval(10))
        #expect(tokens.isExpired(now: now, leeway: 30))
    }

    @Test("A token comfortably in the future is fresh")
    func fresh() {
        let now = Date()
        let tokens = Tokens(access: "a", refresh: nil, expiry: now.addingTimeInterval(3600))
        #expect(!tokens.isExpired(now: now, leeway: 30))
    }

    @Test("Expiry comes from epoch milliseconds, not seconds")
    func expiryUnits() {
        let token = AccessToken(
            accessToken: "a",
            refreshToken: "r",
            expires: 1_787_855_520_543,
            isDefaultPassword: nil
        )
        let expiry = token.expiryDate
        #expect(expiry != nil)
        #expect(abs((expiry?.timeIntervalSince1970 ?? 0) - 1_787_855_520.543) < 0.01)
    }
}
