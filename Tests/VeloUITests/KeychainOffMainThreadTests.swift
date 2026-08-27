import Testing
import Foundation
import VeloCore
@testable import VeloUI

/// Records where its Keychain read actually ran.
private final class WatchingTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _ranOnMain: Bool?
    private let token: TokenSet?
    /// How long the read takes, standing in for a Keychain prompt.
    private let delay: TimeInterval

    init(token: TokenSet?, delay: TimeInterval = 0) {
        self.token = token
        self.delay = delay
    }

    var ranOnMain: Bool? {
        lock.lock(); defer { lock.unlock() }
        return _ranOnMain
    }

    func load() throws -> TokenSet? {
        lock.lock(); _ranOnMain = Thread.isMainThread; lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return token
    }

    func save(_ tokenSet: TokenSet) throws {}
    func clear() throws {}
}

@MainActor
@Suite struct KeychainOffMainThreadTests {
    private func makeCoordinator(_ store: TokenStore) -> AuthCoordinator {
        let config = AuthConfig.gmail(clientID: "cid")
        return AuthCoordinator(config: config,
                               tokenService: TokenService(config: config, httpClient: DeadClient()),
                               tokenStore: store)
    }

    private var token: TokenSet {
        TokenSet(accessToken: "a", refreshToken: "r",
                 expiresAt: Date(timeIntervalSince1970: 9_999_999_999))
    }

    @Test func theKeychainIsNotReadOnTheMainThread() async {
        // This is the whole bug: a Keychain read blocks on an authorisation
        // prompt whenever the app's signature changes, which an ad-hoc build
        // does on every rebuild. On the main thread that happens before SwiftUI
        // has drawn, so the app launches to a Dock icon and no window at all.
        let store = WatchingTokenStore(token: token)
        let coordinator = makeCoordinator(store)

        await coordinator.restoreState()

        #expect(store.ranOnMain == false)
    }

    @Test func aStoredSessionStillSignsYouIn() async {
        let coordinator = makeCoordinator(WatchingTokenStore(token: token))

        await coordinator.restoreState()

        #expect(coordinator.state == .signedIn)
    }

    @Test func noStoredSessionLeavesYouSignedOut() async {
        let coordinator = makeCoordinator(WatchingTokenStore(token: nil))

        await coordinator.restoreState()

        #expect(coordinator.state == .signedOut)
    }

    @Test func aSlowReadDoesNotHoldUpTheMainActor() async {
        // The window has to be able to draw while the prompt is on screen.
        let store = WatchingTokenStore(token: token, delay: 0.4)
        let coordinator = makeCoordinator(store)

        let restoring = Task { await coordinator.restoreState() }
        // If the read were blocking the main actor, this could not run first.
        var drewFirst = false
        await MainActor.run { drewFirst = true }

        await restoring.value
        #expect(drewFirst)
        #expect(coordinator.state == .signedIn)
    }
}

private struct DeadClient: HTTPClient {
    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        throw AuthError.invalidResponse
    }
    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        throw AuthError.invalidResponse
    }
}
