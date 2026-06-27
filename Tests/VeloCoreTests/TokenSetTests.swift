import Testing
import Foundation
@testable import VeloCore

@Suite struct TokenSetTests {
    @Test func isExpiredFalseWellBeforeExpiry() {
        let now = Date(timeIntervalSince1970: 1000)
        let token = TokenSet(accessToken: "a", refreshToken: nil,
                             expiresAt: Date(timeIntervalSince1970: 5000))
        #expect(token.isExpired(now: now) == false)
    }

    @Test func isExpiredTrueAfterExpiry() {
        let now = Date(timeIntervalSince1970: 6000)
        let token = TokenSet(accessToken: "a", refreshToken: nil,
                             expiresAt: Date(timeIntervalSince1970: 5000))
        #expect(token.isExpired(now: now) == true)
    }

    @Test func isExpiredTrueWithinSkewWindow() {
        let now = Date(timeIntervalSince1970: 4970) // 30s before expiry, skew 60s
        let token = TokenSet(accessToken: "a", refreshToken: nil,
                             expiresAt: Date(timeIntervalSince1970: 5000))
        #expect(token.isExpired(now: now, skew: 60) == true)
    }

    @Test func codableRoundTrips() throws {
        let token = TokenSet(accessToken: "a", refreshToken: "r",
                             expiresAt: Date(timeIntervalSince1970: 5000))
        let data = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(TokenSet.self, from: data)
        #expect(decoded == token)
    }
}
