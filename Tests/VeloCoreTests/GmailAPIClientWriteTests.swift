import Testing
import Foundation
@testable import VeloCore

private struct Boom: Error {}

private final class PostMockHTTPClient: HTTPClient {
    var postResult: Result<(Data, HTTPURLResponse), Error>
    private(set) var lastPostURL: URL?
    private(set) var lastPostHeaders: [String: String]?
    private(set) var lastPostBody: Data?

    init(post: Result<(Data, HTTPURLResponse), Error>) { self.postResult = post }

    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        lastPostURL = url
        lastPostHeaders = headers
        lastPostBody = body
        return try postResult.get()
    }

    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        fatalError("get not used by write tests")
    }
}

private struct DecodedModifyBody: Decodable, Equatable {
    let addLabelIds: [String]
    let removeLabelIds: [String]
}

private func http(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://gmail.googleapis.com/")!,
                    statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func makeClient(_ postResult: Result<(Data, HTTPURLResponse), Error>) throws
    -> (GmailAPIClient, PostMockHTTPClient) {
    let store = InMemoryTokenStore()
    try store.save(TokenSet(accessToken: "tok", refreshToken: "rt",
                            expiresAt: Date(timeIntervalSince1970: 10_000_000_000)))
    let providerClient = PostMockHTTPClient(post: .failure(Boom()))
    let service = TokenService(config: .gmail(clientID: "c", redirectURI: "r"), httpClient: providerClient)
    let provider = AccessTokenProvider(store: store, service: service, now: { Date(timeIntervalSince1970: 0) })
    let httpClient = PostMockHTTPClient(post: postResult)
    let api = GmailAPIClient(httpClient: httpClient, tokenProvider: provider)
    return (api, httpClient)
}

@Suite struct GmailAPIClientWriteTests {
    @Test func modifyMessageSendsLabelsToModifyEndpoint() async throws {
        let responseJSON = Data(#"{"id":"m1","threadId":"t1","labelIds":["UNREAD"]}"#.utf8)
        let (api, client) = try makeClient(.success((responseJSON, http(200))))

        let dto = try await api.modifyMessage(id: "m1", addLabelIDs: [], removeLabelIDs: ["INBOX"])

        #expect(dto.id == "m1")
        #expect((client.lastPostURL?.path ?? "").hasSuffix("/messages/m1/modify"))
        let body = try #require(client.lastPostBody)
        let decoded = try JSONDecoder().decode(DecodedModifyBody.self, from: body)
        #expect(decoded == DecodedModifyBody(addLabelIds: [], removeLabelIds: ["INBOX"]))
    }

    @Test func modifyMessageAttachesBearerAndJSONContentType() async throws {
        let responseJSON = Data(#"{"id":"m1","threadId":"t1","labelIds":[]}"#.utf8)
        let (api, client) = try makeClient(.success((responseJSON, http(200))))

        _ = try await api.modifyMessage(id: "m1", addLabelIDs: ["STARRED"], removeLabelIDs: [])

        #expect(client.lastPostHeaders?["Authorization"] == "Bearer tok")
        #expect(client.lastPostHeaders?["Content-Type"] == "application/json")
    }

    @Test func modifyMessageParsesUpdatedResource() async throws {
        let responseJSON = Data(#"{"id":"m9","threadId":"t9","labelIds":["UNREAD"]}"#.utf8)
        let (api, _) = try makeClient(.success((responseJSON, http(200))))

        let dto = try await api.modifyMessage(id: "m9", addLabelIDs: [], removeLabelIDs: ["INBOX"])

        #expect(dto.id == "m9")
        #expect(dto.labelIds == ["UNREAD"])   // INBOX omitted in response
    }

    @Test func modifyMessageNonSuccessMapsToServerError() async throws {
        let json = Data(#"{"error":{"code":403,"message":"nope","status":"PERMISSION_DENIED"}}"#.utf8)
        let (api, _) = try makeClient(.success((json, http(403))))

        await #expect(throws: AuthError.server(code: "PERMISSION_DENIED", description: "nope")) {
            _ = try await api.modifyMessage(id: "m1", addLabelIDs: [], removeLabelIDs: ["INBOX"])
        }
    }

    @Test func modifyMessageTransportFailureMapsToNetworkError() async throws {
        let (api, _) = try makeClient(.failure(Boom()))

        await #expect(throws: AuthError.network(NSError(domain: "", code: 0))) {
            _ = try await api.modifyMessage(id: "m1", addLabelIDs: [], removeLabelIDs: ["INBOX"])
        }
    }
}
