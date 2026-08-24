import Foundation

/// Local provider, talking to an Ollama daemon.
///
/// This is the answer to "I do not want my mail sent to a third party". It needs
/// no key and no account; the cost is that quality is whatever model you have
/// pulled.
public struct OllamaProvider: LLMProvider {
    private let model: String
    private let httpClient: HTTPClient
    private let baseURL: URL

    public init(model: String = OllamaProvider.defaultModel,
                httpClient: HTTPClient,
                baseURL: URL = OllamaProvider.defaultBaseURL) {
        self.model = model
        self.httpClient = httpClient
        self.baseURL = baseURL
    }

    /// Where Ollama listens by default. Overridable for a remote box.
    public static let defaultBaseURL = URL(string: "http://localhost:11434")!
    /// Commonly pulled and small enough to be usable on a laptop. Override freely.
    public static let defaultModel = "llama3.2"

    public var displayName: String { "Ollama (\(model))" }

    public func complete(_ request: LLMRequest) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")
        let body = try JSONEncoder().encode(Request(request, model: model))

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.post(
                url: url, headers: ["content-type": "application/json"], body: body)
        } catch {
            // By far the most common failure here is that Ollama is not running,
            // which deserves different words than a model error.
            throw LLMError.unavailable
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw LLMError.server(status: response.statusCode, message: message)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LLMError.malformedResponse
        }
        return decoded.message.content
    }

    // MARK: - Internals

    /// Unlike the hosted API, system is a message role here, and generation
    /// limits live under `options`. `stream` must be false: the default emits
    /// newline-delimited JSON, which will not decode as one object.
    private struct Request: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options?

        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct Options: Encodable {
            let num_predict: Int?
            let temperature: Double?
        }

        init(_ request: LLMRequest, model: String) {
            self.model = model
            var messages: [Message] = []
            if let system = request.system {
                messages.append(Message(role: "system", content: system))
            }
            messages.append(Message(role: "user", content: request.prompt))
            self.messages = messages
            self.stream = false
            self.options = Options(num_predict: request.maxTokens, temperature: request.temperature)
        }
    }

    private struct Response: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }
}
