import Testing
import Foundation
@testable import VeloCore

private struct Boom: Error {}

@Suite struct OllamaProviderTests {
    private let ok = Data(#"{"message":{"role":"assistant","content":"local answer"},"done":true}"#.utf8)

    private func makeProvider(_ result: Result<(Data, HTTPURLResponse), Error>,
                              model: String = "llama3.2")
        -> (OllamaProvider, RecordingHTTPClient) {
        let client = RecordingHTTPClient(result)
        return (OllamaProvider(model: model, httpClient: client), client)
    }

    @Test func postsToTheLocalChatEndpoint() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(prompt: "hello"))

        #expect(client.lastURL?.absoluteString == "http://localhost:11434/api/chat")
    }

    @Test func sendsNoAPIKeyBecauseThereIsNone() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(prompt: "hello"))

        #expect(client.lastHeaders?["x-api-key"] == nil)
        #expect(client.lastHeaders?["Authorization"] == nil)
        #expect(client.lastHeaders?["content-type"] == "application/json")
    }

    @Test func disablesStreamingSoOneResponseIsOneJSONObject() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(prompt: "hello"))

        // Ollama streams newline-delimited JSON by default, which would not
        // decode as a single object.
        #expect(client.bodyJSON["stream"] as? Bool == false)
    }

    @Test func sendsTheModelAndUserMessage() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))), model: "mistral")

        _ = try await provider.complete(LLMRequest(prompt: "summarise"))

        #expect(client.bodyJSON["model"] as? String == "mistral")
        let messages = client.bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?.count == 1)
        #expect(messages?.first?["role"] as? String == "user")
        #expect(messages?.first?["content"] as? String == "summarise")
    }

    @Test func sendsTheSystemPromptAsASystemMessage() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(system: "Be terse.", prompt: "hi"))

        // Unlike the hosted API, this one takes system as a message role.
        let messages = client.bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?.count == 2)
        #expect(messages?.first?["role"] as? String == "system")
        #expect(messages?.first?["content"] as? String == "Be terse.")
        #expect(messages?.last?["role"] as? String == "user")
    }

    @Test func passesMaxTokensAndTemperatureAsOptions() async throws {
        let (provider, client) = makeProvider(.success((ok, httpResponse(200))))

        _ = try await provider.complete(LLMRequest(prompt: "hi", maxTokens: 256, temperature: 0.2))

        let options = client.bodyJSON["options"] as? [String: Any]
        #expect(options?["num_predict"] as? Int == 256)
        #expect(options?["temperature"] as? Double == 0.2)
    }

    @Test func returnsTheMessageContent() async throws {
        let (provider, _) = makeProvider(.success((ok, httpResponse(200))))
        #expect(try await provider.complete(LLMRequest(prompt: "hi")) == "local answer")
    }

    @Test func aTransportFailureIsUnavailableNotAServerError() async throws {
        let (provider, _) = makeProvider(.failure(Boom()))

        // The overwhelmingly common case: Ollama is not running.
        await #expect(throws: LLMError.unavailable) {
            _ = try await provider.complete(LLMRequest(prompt: "hi"))
        }
    }

    @Test func aMissingModelCarriesOllamasOwnMessage() async throws {
        let json = Data(#"{"error":"model 'llama3.2' not found, try pulling it first"}"#.utf8)
        let (provider, _) = makeProvider(.success((json, httpResponse(404))))

        await #expect(throws: LLMError.server(
            status: 404, message: "model 'llama3.2' not found, try pulling it first")) {
            _ = try await provider.complete(LLMRequest(prompt: "hi"))
        }
    }

    @Test func unparseableSuccessIsMalformed() async throws {
        let (provider, _) = makeProvider(.success((Data("<html>".utf8), httpResponse(200))))

        await #expect(throws: LLMError.malformedResponse) {
            _ = try await provider.complete(LLMRequest(prompt: "hi"))
        }
    }

    @Test func theHostIsOverridableForARemoteOllama() async throws {
        let client = RecordingHTTPClient(.success((ok, httpResponse(200))))
        let provider = OllamaProvider(model: "llama3.2", httpClient: client,
                                      baseURL: URL(string: "http://gpu-box.local:11434")!)

        _ = try await provider.complete(LLMRequest(prompt: "hi"))

        #expect(client.lastURL?.absoluteString == "http://gpu-box.local:11434/api/chat")
    }

    @Test func displayNameNamesTheModelSoUsersKnowWhatAnsweredThem() {
        let (provider, _) = makeProvider(.success((ok, httpResponse(200))), model: "qwen2.5")
        #expect(provider.displayName.contains("qwen2.5"))
    }
}
