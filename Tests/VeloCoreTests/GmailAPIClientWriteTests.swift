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

private struct DecodedSendBody: Decodable, Equatable {
    let raw: String
    let threadId: String?
}

private func http(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://gmail.googleapis.com/")!,
                    statusCode: status, httpVersion: nil, headerFields: nil)!
}

private struct DecodedBatchModifyBody: Decodable, Equatable {
    let ids: [String]
    let addLabelIds: [String]
    let removeLabelIds: [String]
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
    // MARK: - batchModify

    /// These were five tests of `modifyMessage`, which nothing but they ever
    /// called: production has always gone through `batchModifyMessages`, and
    /// that had no test against the real client at all -- every other reference
    /// to it in the suite is a stub conforming to `GmailWriting`. Deleting the
    /// dead method would have taken the only coverage of this POST path with
    /// it, so they were pointed at the live one instead.
    ///
    /// It returns 204 with no body, so there is no decoded resource to check;
    /// what is left is the request it builds and the errors it maps.

    @Test func batchModifySendsIDsAndLabelsToTheBatchEndpoint() async throws {
        let (api, client) = try makeClient(.success((Data(), http(204))))

        try await api.batchModifyMessages(ids: ["m1", "m2"], addLabelIDs: [],
                                          removeLabelIDs: ["INBOX"])

        #expect((client.lastPostURL?.path ?? "").hasSuffix("/messages/batchModify"))
        let body = try #require(client.lastPostBody)
        let decoded = try JSONDecoder().decode(DecodedBatchModifyBody.self, from: body)
        #expect(decoded == DecodedBatchModifyBody(ids: ["m1", "m2"], addLabelIds: [],
                                                  removeLabelIds: ["INBOX"]))
    }

    @Test func batchModifyAttachesBearerAndJSONContentType() async throws {
        let (api, client) = try makeClient(.success((Data(), http(204))))

        try await api.batchModifyMessages(ids: ["m1"], addLabelIDs: ["STARRED"],
                                          removeLabelIDs: [])

        #expect(client.lastPostHeaders?["Authorization"] == "Bearer tok")
        #expect(client.lastPostHeaders?["Content-Type"] == "application/json")
    }

    /// The success case has an empty body. Decoding one anyway would fail on
    /// every archive.
    @Test func batchModifyAcceptsAnEmptyBodyOnSuccess() async throws {
        let (api, _) = try makeClient(.success((Data(), http(204))))

        try await api.batchModifyMessages(ids: ["m1"], addLabelIDs: [], removeLabelIDs: ["INBOX"])
    }

    @Test func batchModifyNonSuccessMapsToServerError() async throws {
        let json = Data(#"{"error":{"code":403,"message":"nope","status":"PERMISSION_DENIED"}}"#.utf8)
        let (api, _) = try makeClient(.success((json, http(403))))

        await #expect(throws: AuthError.server(code: "PERMISSION_DENIED", description: "nope")) {
            try await api.batchModifyMessages(ids: ["m1"], addLabelIDs: [],
                                              removeLabelIDs: ["INBOX"])
        }
    }

    @Test func batchModifyTransportFailureMapsToNetworkError() async throws {
        let (api, _) = try makeClient(.failure(Boom()))

        await #expect(throws: AuthError.network(NSError(domain: "", code: 0))) {
            try await api.batchModifyMessages(ids: ["m1"], addLabelIDs: [],
                                              removeLabelIDs: ["INBOX"])
        }
    }

    @Test func sendMessagePOSTsRawAndThreadIDToSendEndpoint() async throws {
        let responseJSON = Data(#"{"id":"sent1","threadId":"t1","labelIds":["SENT"]}"#.utf8)
        let (api, client) = try makeClient(.success((responseJSON, http(200))))

        _ = try await api.sendMessage(raw: "cmF3LWJ5dGVz", threadID: "t1")

        #expect((client.lastPostURL?.path ?? "").hasSuffix("/messages/send"))
        let body = try #require(client.lastPostBody)
        let decoded = try JSONDecoder().decode(DecodedSendBody.self, from: body)
        #expect(decoded == DecodedSendBody(raw: "cmF3LWJ5dGVz", threadId: "t1"))
    }

    @Test func sendMessageOmitsThreadIDForANewCompose() async throws {
        let responseJSON = Data(#"{"id":"sent1","threadId":"tNew","labelIds":["SENT"]}"#.utf8)
        let (api, client) = try makeClient(.success((responseJSON, http(200))))

        _ = try await api.sendMessage(raw: "cmF3", threadID: nil)

        let body = try #require(client.lastPostBody)
        let decoded = try JSONDecoder().decode(DecodedSendBody.self, from: body)
        #expect(decoded.threadId == nil)
        // The key must be absent, not null: Gmail rejects an explicit null threadId.
        #expect(!String(decoding: body, as: UTF8.self).contains("threadId"))
    }

    @Test func sendMessageDecodesReturnedMessageResource() async throws {
        let responseJSON = Data(#"{"id":"sent9","threadId":"t9","labelIds":["SENT"]}"#.utf8)
        let (api, _) = try makeClient(.success((responseJSON, http(200))))

        let dto = try await api.sendMessage(raw: "cmF3", threadID: "t9")

        #expect(dto.id == "sent9")
        #expect(dto.threadId == "t9")
        #expect(dto.labelIds == ["SENT"])
    }

    @Test func sendMessageNonSuccessMapsToServerError() async throws {
        let json = Data(#"{"error":{"code":400,"message":"bad raw","status":"INVALID_ARGUMENT"}}"#.utf8)
        let (api, _) = try makeClient(.success((json, http(400))))

        await #expect(throws: AuthError.server(code: "INVALID_ARGUMENT", description: "bad raw")) {
            _ = try await api.sendMessage(raw: "cmF3", threadID: nil)
        }
    }
}
