import Foundation

/// One completion request. Deliberately small: every AI feature in this app is
/// "here is some mail, do one thing to it", and a richer shape would be surface
/// with no caller.
public struct LLMRequest: Equatable, Sendable {
    public var system: String?
    public var prompt: String
    public var maxTokens: Int
    public var temperature: Double?

    public init(system: String? = nil, prompt: String,
                maxTokens: Int = 1024, temperature: Double? = nil) {
        self.system = system
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

/// What can go wrong, reduced to the cases a caller can actually act on.
public enum LLMError: Error, Equatable {
    /// No provider configured. The feature should not be offered at all.
    case notConfigured
    /// The API key was rejected.
    case unauthorized
    /// Nothing answered. Separate from `server` because the common local case --
    /// "Ollama is not running" -- needs different words than "the model errored".
    case unavailable
    case server(status: Int, message: String?)
    case malformedResponse
}

/// Somewhere a prompt can be sent. Two ship: a hosted API and a local runtime.
///
/// The protocol exists so mail content can stay on the machine if the user wants
/// it to -- that choice is the whole reason this is pluggable rather than a
/// single hardcoded client.
public protocol LLMProvider: Sendable {
    /// Shown in settings and errors, e.g. "Claude (claude-sonnet-5)".
    var displayName: String { get }
    func complete(_ request: LLMRequest) async throws -> String
}
