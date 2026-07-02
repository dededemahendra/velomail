import Testing
import Foundation
@testable import VeloCore

private final class MockHTTPClient: HTTPClient {
    var result: Result<(Data, HTTPURLResponse), Error>
    private(set) var callCount = 0

    init(_ result: Result<(Data, HTTPURLResponse), Error>) { self.result = result }

    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        return try result.get()
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
}
