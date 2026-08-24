import Foundation

/// Hosted provider, authenticated with an API key.
///
/// Base URL, API version and model are injected with defaults rather than
/// written into the request: providers rev models faster than a mail client
/// ships, and pointing at a proxy or a newer model should not need a code change.
public struct AnthropicProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let httpClient: HTTPClient
    private let baseURL: URL
    private let apiVersion: String

    public init(apiKey: String,
                model: String = AnthropicProvider.defaultModel,
                httpClient: HTTPClient,
                baseURL: URL = URL(string: "https://api.anthropic.com")!,
                apiVersion: String = "2023-06-01") {
        self.apiKey = apiKey
        self.model = model
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.apiVersion = apiVersion
    }

    /// A balance of quality and latency for short mail tasks. Overridable.
    public static let defaultModel = "claude-sonnet-5"

    public var displayName: String { "Claude (\(model))" }

    public func complete(_ request: LLMRequest) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/messages")
        let body = try JSONEncoder().encode(Request(request, model: model))

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.post(
                url: url,
                headers: ["x-api-key": apiKey,
                          "anthropic-version": apiVersion,
                          "content-type": "application/json"],
                body: body)
        } catch {
            throw LLMError.unavailable
        }

        guard (200..<300).contains(response.statusCode) else {
            throw Self.mapFailure(status: response.statusCode, data: data)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LLMError.malformedResponse
        }
        // Non-text blocks (thinking, tool use) are not something this app asks
        // for, but skipping rather than failing keeps it forward-compatible.
        return decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
    }

    // MARK: - Internals

    private static func mapFailure(status: Int, data: Data) -> LLMError {
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
        return status == 401 || status == 403 ? .unauthorized : .server(status: status, message: message)
    }

    /// `system` is a top-level field on this API, not a message with a role.
    private struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let system: String?
        let temperature: Double?
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: String
        }

        init(_ request: LLMRequest, model: String) {
            self.model = model
            self.max_tokens = request.maxTokens
            self.system = request.system
            self.temperature = request.temperature
            self.messages = [Message(role: "user", content: request.prompt)]
        }
    }

    private struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }

    private struct ErrorResponse: Decodable {
        struct Inner: Decodable { let type: String?; let message: String? }
        let error: Inner
    }
}
