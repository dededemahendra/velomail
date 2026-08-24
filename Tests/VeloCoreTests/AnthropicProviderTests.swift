import Testing
import Foundation
@testable import VeloCore

private struct Boom: Error {}

/// Records the POST it was given and replays a scripted result.
final class RecordingHTTPClient: HTTPClient, @unchecked Sendable {
    var result: Result<(Data, HTTPURLResponse), Error>
    private(set) var lastURL: URL?
    private(set) var lastHeaders: [String: String]?
    private(set) var lastBody: Data?

    init(_ result: Result<(Data, HTTPURLResponse), Error>) { self.result = result }

    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        lastURL = url; lastHeaders = headers; lastBody = body
        return try result.get()
    }

    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        fatalError("LLM providers only POST")
    }

    var bodyJSON: [String: Any] {
        (try? JSONSerialization.jsonObject(with: lastBody ?? Data())) as? [String: Any] ?? [:]
    }
}

func httpResponse(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status,
                    httpVersion: nil, headerFields: nil)!
}

@Suite struct AnthropicProviderTests {
    private let ok = Data(#"{"content":[{"type":"text","text":"a summary"}]}"#.utf8)

    private func makeProvider(_ result: Result<(Data, HTTPURLResponse), Error>,
                              model: String = "claude-sonnet-5")
        -> (AnthropicProvider, RecordingHTTPClient) {
        let client = RecordingHTTPClient(result)
        return (AnthropicProvider(apiKey: "sk-test", model: model, httpClient: client), client)
    }

    @Test func postsToTheMessagesEndpoint() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(prompt: "hello"))

        #expect(client.lastURL?.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    @Test func sendsTheAPIKeyAndVersionHeaders() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(prompt: "hello"))

        #expect(client.lastHeaders?["x-api-key"] == "sk-test")
        #expect(client.lastHeaders?["anthropic-version"] == "2023-06-01")
        #expect(client.lastHeaders?["content-type"] == "application/json")
    }

    @Test func sendsModelMaxTokensAndTheUserMessage() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(prompt: "summarise this", maxTokens: 512))

        let body = client.bodyJSON
        #expect(body["model"] as? String == "claude-sonnet-5")
        #expect(body["max_tokens"] as? Int == 512)
        let messages = body["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
        #expect(messages?.first?["role"] as? String == "user")
        #expect(messages?.first?["content"] as? String == "summarise this")
    }

    @Test func sendsTheSystemPromptAsATopLevelField() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(system: "You are terse.", prompt: "hi"))

        // system is its own field on this API, not a message with role "system".
        #expect(client.bodyJSON["system"] as? String == "You are terse.")
    }

    @Test func omitsSystemEntirelyWhenThereIsNone() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(prompt: "hi"))

        #expect(client.bodyJSON["system"] == nil)
    }

    @Test func returnsTheTextOfTheResponse() async throws {
        let (provider, _) = makeProvider(.success((ok, httpResponse(200))))
        #expect(try await provider.complete(LLMRequest(prompt: "hi")) == "a summary")
    }

    @Test func joinsMultipleTextBlocks() async throws {
        let json = Data(#"{"content":[{"type":"text","text":"one"},{"type":"text","text":"two"}]}"#.utf8)
        let (provider, _) = makeProvider(.success((json, httpResponse(200))))
        #expect(try await provider.complete(LLMRequest(prompt: "hi")) == "onetwo")
    }

    @Test func ignoresNonTextBlocks() async throws {
        let json = Data(#"{"content":[{"type":"thinking"},{"type":"text","text":"answer"}]}"#.utf8)
        let (provider, _) = makeProvider(.success((json, httpResponse(200))))
        #expect(try await provider.complete(LLMRequest(prompt: "hi")) == "answer")
    }

    @Test func a401BecomesUnauthorized() async throws {
        let json = Data(#"{"error":{"type":"authentication_error","message":"invalid key"}}"#.utf8)
        let (provider, _) = makeProvider(.success((json, httpResponse(401))))

        await #expect(throws: LLMError.unauthorized) {
            _ = try await provider.complete(LLMRequest(prompt: "hi"))
        }
    }

    @Test func otherFailuresCarryTheServerMessage() async throws {
        let json = Data(#"{"error":{"type":"overloaded_error","message":"try later"}}"#.utf8)
        let (provider, _) = makeProvider(.success((json, httpResponse(529))))

        await #expect(throws: LLMError.server(status: 529, message: "try later")) {
            _ = try await provider.complete(LLMRequest(prompt: "hi"))
        }
    }

    @Test func aTransportFailureIsUnavailable() async throws {
        let (provider, _) = makeProvider(.failure(Boom()))

        await #expect(throws: LLMError.unavailable) {
            _ = try await provider.complete(LLMRequest(prompt: "hi"))
        }
    }

    @Test func unparseableSuccessIsMalformed() async throws {
        let (provider, _) = makeProvider(.success((Data("not json".utf8), httpResponse(200))))

        await #expect(throws: LLMError.malformedResponse) {
            _ = try await provider.complete(LLMRequest(prompt: "hi"))
        }
    }

    @Test func theBaseURLAndVersionAreOverridable() async throws {
        let client = RecordingHTTPClient(.success((ok, httpResponse(200))))
        let provider = AnthropicProvider(
            apiKey: "k", model: "m", httpClient: client,
            baseURL: URL(string: "https://proxy.internal")!, apiVersion: "2099-01-01")

        _ = try await provider.complete(LLMRequest(prompt: "hi"))

        // Providers rev faster than a mail client ships; nothing is a constant.
        #expect(client.lastURL?.absoluteString == "https://proxy.internal/v1/messages")
        #expect(client.lastHeaders?["anthropic-version"] == "2099-01-01")
    }
}
