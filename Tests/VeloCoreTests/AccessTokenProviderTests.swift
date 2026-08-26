import Testing
import Foundation
@testable import VeloCore

private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    var result: Result<(Data, HTTPURLResponse), Error>
    private(set) var callCount = 0

    init(_ result: Result<(Data, HTTPURLResponse), Error>) { self.result = result }

    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        return try result.get()
    }

    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        fatalError("get not used by AccessTokenProvider")
    }
}

private func http(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://oauth2.googleapis.com/token")!,
                    statusCode: status, httpVersion: nil, headerFields: nil)!
}

private let fixedNow = Date(timeIntervalSince1970: 10_000)

private func makeProvider(
    stored: TokenSet?,
    refreshResult: Result<(Data, HTTPURLResponse), Error> = .success((Data(), http(200)))
) throws -> (AccessTokenProvider, MockHTTPClient, InMemoryTokenStore) {
    let store = InMemoryTokenStore()
    if let stored { try store.save(stored) }
    let client = MockHTTPClient(refreshResult)
    let service = TokenService(config: .gmail(clientID: "cid", redirectURI: "com.velomail:/oauth"),
                               httpClient: client, now: { fixedNow })
    let provider = AccessTokenProvider(store: store, service: service, now: { fixedNow })
    return (provider, client, store)
}

/// Counts Keychain reads, which are the thing being optimised.
private final class CountingTokenStore: TokenStore, @unchecked Sendable {
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private var stored: TokenSet?

    init(_ initial: TokenSet?) { stored = initial }

    func load() throws -> TokenSet? { loadCount += 1; return stored }
    func save(_ tokenSet: TokenSet) throws { saveCount += 1; stored = tokenSet }
    func clear() throws { stored = nil }
}

/// A service that must never be reached — the token is valid, so no refresh.
private func unusedService() -> TokenService {
    TokenService(config: .gmail(clientID: "c"),
                 httpClient: MockHTTPClient(.failure(NSError(domain: "unused", code: 0))))
}

@Suite struct AccessTokenProviderTests {
    private func token(access: String, refresh: String?, expiresAt: Date) -> TokenSet {
        TokenSet(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    @Test func returnsStoredTokenWhenNotExpiredWithoutRefreshing() async throws {
        let fresh = token(access: "fresh-at", refresh: "rt", expiresAt: fixedNow.addingTimeInterval(3600))
        let (provider, client, _) = try makeProvider(stored: fresh)

        let value = try await provider.validAccessToken()

        #expect(value == "fresh-at")
        #expect(client.callCount == 0)
    }

    @Test func refreshesAndPersistsWhenExpired() async throws {
        let expired = token(access: "old-at", refresh: "rt", expiresAt: fixedNow.addingTimeInterval(-10))
        let json = Data(#"{"access_token":"new-at","expires_in":3600}"#.utf8)
        let (provider, client, store) = try makeProvider(stored: expired, refreshResult: .success((json, http(200))))

        let value = try await provider.validAccessToken()

        #expect(value == "new-at")
        #expect(client.callCount == 1)
        let saved = try store.load()
        #expect(saved?.accessToken == "new-at")
        #expect(saved?.refreshToken == "rt")   // reused when refresh response omits it
        #expect(saved?.expiresAt == fixedNow.addingTimeInterval(3600))
    }

    @Test func throwsMissingRefreshTokenWhenStoreEmpty() async throws {
        let (provider, client, _) = try makeProvider(stored: nil)

        await #expect(throws: AuthError.missingRefreshToken) {
            _ = try await provider.validAccessToken()
        }
        #expect(client.callCount == 0)
    }

    @Test func throwsMissingRefreshTokenWhenExpiredAndNoRefreshToken() async throws {
        let expired = token(access: "old-at", refresh: nil, expiresAt: fixedNow.addingTimeInterval(-10))
        let (provider, client, _) = try makeProvider(stored: expired)

        await #expect(throws: AuthError.missingRefreshToken) {
            _ = try await provider.validAccessToken()
        }
        #expect(client.callCount == 0)
    }

    // MARK: - Not hitting the Keychain per request

    @Test func aValidTokenIsReadFromTheKeychainOnce() async throws {
        let store = CountingTokenStore(TokenSet(accessToken: "at", refreshToken: "rt",
                                                expiresAt: Date(timeIntervalSince1970: 10_000)))
        let provider = AccessTokenProvider(store: store, service: unusedService(),
                                           now: { Date(timeIntervalSince1970: 0) })

        for _ in 0..<50 { _ = try await provider.validAccessToken() }

        // A backfill makes one call per message. Reading the Keychain 500 times
        // for a token valid for an hour is where the time was going.
        #expect(store.loadCount == 1)
    }

    @Test func theCachedTokenIsTheOneReturned() async throws {
        let store = CountingTokenStore(TokenSet(accessToken: "at", refreshToken: "rt",
                                                expiresAt: Date(timeIntervalSince1970: 10_000)))
        let provider = AccessTokenProvider(store: store, service: unusedService(),
                                           now: { Date(timeIntervalSince1970: 0) })

        _ = try await provider.validAccessToken()
        #expect(try await provider.validAccessToken() == "at")
    }

    @Test func anExpiredCachedTokenIsNotServed() async throws {
        // Cached, then time passes: the cache must not outlive the token.
        let expiring = TokenSet(accessToken: "old", refreshToken: "rt",
                                expiresAt: Date(timeIntervalSince1970: 100))
        let store = CountingTokenStore(expiring)
        var clock = Date(timeIntervalSince1970: 0)
        let refreshed = Data(#"{"access_token":"new","expires_in":3600}"#.utf8)
        let client = MockHTTPClient(.success((refreshed, HTTPURLResponse(
            url: URL(string: "https://oauth2.googleapis.com/token")!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!)))
        let provider = AccessTokenProvider(
            store: store,
            service: TokenService(config: .gmail(clientID: "c"), httpClient: client, now: { clock }),
            now: { clock })

        #expect(try await provider.validAccessToken() == "old")
        clock = Date(timeIntervalSince1970: 10_000)
        #expect(try await provider.validAccessToken() == "new")
        #expect(store.saveCount == 1)
    }

    @Test func aRefreshedTokenIsCachedToo() async throws {
        let store = CountingTokenStore(TokenSet(accessToken: "old", refreshToken: "rt",
                                                expiresAt: Date(timeIntervalSince1970: 100)))
        let refreshed = Data(#"{"access_token":"new","expires_in":3600}"#.utf8)
        let client = MockHTTPClient(.success((refreshed, HTTPURLResponse(
            url: URL(string: "https://oauth2.googleapis.com/token")!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!)))
        let clock = Date(timeIntervalSince1970: 10_000)
        let provider = AccessTokenProvider(
            store: store,
            service: TokenService(config: .gmail(clientID: "c"), httpClient: client, now: { clock }),
            now: { clock })

        for _ in 0..<10 { _ = try await provider.validAccessToken() }

        // One refresh, not ten.
        #expect(store.saveCount == 1)
    }
}
