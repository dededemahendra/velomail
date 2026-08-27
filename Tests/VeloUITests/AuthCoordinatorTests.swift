import Testing
import Foundation
import VeloCore
@testable import VeloUI

/// Counts Keychain reads. On macOS a Keychain read can block on an
/// authorisation prompt, so where it happens matters.
private final class CountingTokenStore: TokenStore, @unchecked Sendable {
    private(set) var loadCount = 0
    private var stored: TokenSet?
    init(_ initial: TokenSet?) { stored = initial }
    func load() throws -> TokenSet? { loadCount += 1; return stored }
    func save(_ tokenSet: TokenSet) throws { stored = tokenSet }
    func clear() throws { stored = nil }
}

private struct DeadClient: HTTPClient {
    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        throw AuthError.invalidResponse
    }
    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        throw AuthError.invalidResponse
    }
}

@MainActor
@Suite struct AuthCoordinatorTests {
    private func makeCoordinator(_ store: CountingTokenStore) -> AuthCoordinator {
        let config = AuthConfig.gmail(clientID: "cid")
        return AuthCoordinator(config: config,
                               tokenService: TokenService(config: config, httpClient: DeadClient()),
                               tokenStore: store)
    }

    @Test func constructionNeverTouchesTheKeychain() {
        let store = CountingTokenStore(TokenSet(accessToken: "at", refreshToken: "rt",
                                                expiresAt: Date(timeIntervalSince1970: 10_000_000_000)))

        _ = makeCoordinator(store)

        // A Keychain read here blocks the main thread before the window is
        // created -- and if the app's signature changed, it blocks on a prompt
        // that never appears, so the app launches and shows nothing at all.
        #expect(store.loadCount == 0)
    }

    @Test func stateStartsSignedOutUntilRestored() {
        let store = CountingTokenStore(TokenSet(accessToken: "at", refreshToken: "rt",
                                                expiresAt: Date(timeIntervalSince1970: 10_000_000_000)))
        #expect(makeCoordinator(store).state == .signedOut)
    }

    @Test func restoringFindsAStoredSession() async {
        let store = CountingTokenStore(TokenSet(accessToken: "at", refreshToken: "rt",
                                                expiresAt: Date(timeIntervalSince1970: 10_000_000_000)))
        let coordinator = makeCoordinator(store)

        await coordinator.restoreState()

        #expect(coordinator.state == .signedIn)
        #expect(store.loadCount == 1)
    }

    @Test func restoringWithNoStoredSessionStaysSignedOut() async {
        let store = CountingTokenStore(nil)
        let coordinator = makeCoordinator(store)

        await coordinator.restoreState()

        #expect(coordinator.state == .signedOut)
    }

    @Test func signingOutClearsTheStore() async {
        let store = CountingTokenStore(TokenSet(accessToken: "at", refreshToken: "rt",
                                                expiresAt: Date(timeIntervalSince1970: 10_000_000_000)))
        let coordinator = makeCoordinator(store)
        await coordinator.restoreState()

        coordinator.signOut()

        #expect(coordinator.state == .signedOut)
    }

    @Test func aStateChangeIsReported() async {
        let store = CountingTokenStore(TokenSet(accessToken: "at", refreshToken: "rt",
                                                expiresAt: Date(timeIntervalSince1970: 10_000_000_000)))
        let coordinator = makeCoordinator(store)
        var seen: [AuthCoordinator.AuthState] = []
        coordinator.onStateChange = { seen.append($0) }

        await coordinator.restoreState()

        #expect(seen == [.signedIn])
    }
}
