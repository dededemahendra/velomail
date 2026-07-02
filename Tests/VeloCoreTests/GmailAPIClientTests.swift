import Testing
import Foundation
@testable import VeloCore

private struct Unused: Error {}

private final class MockHTTPClient: HTTPClient {
    var getResult: Result<(Data, HTTPURLResponse), Error>
    private(set) var lastGetURL: URL?
    private(set) var lastGetHeaders: [String: String]?

    init(get: Result<(Data, HTTPURLResponse), Error>) { self.getResult = get }

    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        lastGetURL = url
        lastGetHeaders = headers
        return try getResult.get()
    }

    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        fatalError("post not used by GmailAPIClient")
    }
}

private func http(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://gmail.googleapis.com/")!,
                    statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func makeClient(_ getResult: Result<(Data, HTTPURLResponse), Error>) throws -> (GmailAPIClient, MockHTTPClient) {
    let store = InMemoryTokenStore()
    try store.save(TokenSet(accessToken: "tok", refreshToken: "rt",
                            expiresAt: Date(timeIntervalSince1970: 10_000_000_000)))
    let providerClient = MockHTTPClient(get: .failure(Unused()))
    let service = TokenService(config: .gmail(clientID: "c", redirectURI: "r"), httpClient: providerClient)
    let provider = AccessTokenProvider(store: store, service: service, now: { Date(timeIntervalSince1970: 0) })
    let httpClient = MockHTTPClient(get: getResult)
    let api = GmailAPIClient(httpClient: httpClient, tokenProvider: provider)
    return (api, httpClient)
}

@Suite struct GmailAPIClientTests {
    @Test func listParsesIDsAndNextPageTokenAndAttachesBearer() async throws {
        let json = Data(#"{"messages":[{"id":"m1","threadId":"t1"},{"id":"m2","threadId":"t2"}],"nextPageToken":"next"}"#.utf8)
        let (api, client) = try makeClient(.success((json, http(200))))

        let result = try await api.listInboxMessageIDs(pageToken: nil)

        #expect(result.ids == ["m1", "m2"])
        #expect(result.nextPageToken == "next")
        #expect(client.lastGetHeaders?["Authorization"] == "Bearer tok")
        let query = client.lastGetURL?.query ?? ""
        #expect(query.contains("labelIds=INBOX"))
    }

    @Test func listPassesPageTokenWhenProvided() async throws {
        let json = Data(#"{"messages":[]}"#.utf8)
        let (api, client) = try makeClient(.success((json, http(200))))

        let result = try await api.listInboxMessageIDs(pageToken: "page-2")

        #expect(result.ids == [])
        #expect(result.nextPageToken == nil)
        #expect((client.lastGetURL?.query ?? "").contains("pageToken=page-2"))
    }

    @Test func getMessageParsesDTOAndRequestsFullFormat() async throws {
        let json = Data(#"{"id":"m1","threadId":"t1","labelIds":["INBOX"],"snippet":"s","internalDate":"1000"}"#.utf8)
        let (api, client) = try makeClient(.success((json, http(200))))

        let dto = try await api.getMessage(id: "m1")

        #expect(dto.id == "m1")
        #expect(dto.threadId == "t1")
        let url = client.lastGetURL?.absoluteString ?? ""
        #expect(url.contains("/messages/m1"))
        #expect((client.lastGetURL?.query ?? "").contains("format=full"))
    }

    @Test func nonSuccessMapsToServerError() async throws {
        let json = Data(#"{"error":{"code":401,"message":"Invalid Credentials","status":"UNAUTHENTICATED"}}"#.utf8)
        let (api, _) = try makeClient(.success((json, http(401))))

        await #expect(throws: AuthError.server(code: "UNAUTHENTICATED", description: "Invalid Credentials")) {
            _ = try await api.getMessage(id: "x")
        }
    }
}
