import Testing
import Foundation
@testable import VeloCore

// Opt-in: real Keychain access can prompt or flake under Command Line Tools, so
// this suite is excluded from the default `swift test` run. Enable with:
//   VELO_KEYCHAIN_TESTS=1 swift test --filter KeychainTokenStoreTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VELO_KEYCHAIN_TESTS"] == "1"))
struct KeychainTokenStoreTests {
    private func makeStore() -> KeychainTokenStore {
        // Unique service per run avoids collisions with any real stored item.
        KeychainTokenStore(service: "com.velomail.tokens.test", account: "unit-test")
    }

    @Test func saveLoadClearRoundTrips() throws {
        let store = makeStore()
        try? store.clear()

        let initial = try store.load()
        #expect(initial == nil)

        let token = TokenSet(accessToken: "a", refreshToken: "r",
                             expiresAt: Date(timeIntervalSince1970: 5000))
        try store.save(token)
        let loaded = try store.load()
        #expect(loaded == token)

        // Overwrite path (SecItemUpdate).
        let token2 = TokenSet(accessToken: "a2", refreshToken: "r2",
                              expiresAt: Date(timeIntervalSince1970: 6000))
        try store.save(token2)
        let loaded2 = try store.load()
        #expect(loaded2 == token2)

        try store.clear()
        let afterClear = try store.load()
        #expect(afterClear == nil)
    }
}
