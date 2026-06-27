import Testing
import Foundation
@testable import VeloCore

@Suite struct InMemoryTokenStoreTests {
    private func sampleToken() -> TokenSet {
        TokenSet(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 5000))
    }

    @Test func loadReturnsNilWhenEmpty() throws {
        let store = InMemoryTokenStore()
        let loaded = try store.load()
        #expect(loaded == nil)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = InMemoryTokenStore()
        let token = sampleToken()
        try store.save(token)
        let loaded = try store.load()
        #expect(loaded == token)
    }

    @Test func clearRemovesStoredToken() throws {
        let store = InMemoryTokenStore()
        try store.save(sampleToken())
        try store.clear()
        let loaded = try store.load()
        #expect(loaded == nil)
    }
}
