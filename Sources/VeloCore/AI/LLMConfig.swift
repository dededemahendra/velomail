import Foundation

/// Which LLM the app talks to, resolved from the environment then a config file.
///
/// Absence is a supported state, not a degraded one: with nothing configured the
/// app is exactly what it was before AI existed, and the AI commands are simply
/// not offered.
public struct LLMConfig: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case none, anthropic, ollama
    }

    public let kind: Kind
    public let anthropicAPIKey: String?
    public let anthropicModel: String
    public let ollamaModel: String
    public let ollamaBaseURL: URL

    /// True only when the selected provider can actually run. Asking for
    /// Anthropic without a key resolves to *not enabled* rather than presenting
    /// as working and failing on first use.
    public var isEnabled: Bool {
        switch kind {
        case .none: return false
        case .anthropic: return anthropicAPIKey != nil
        case .ollama: return true
        }
    }

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               file: URL? = defaultConfigFile) -> LLMConfig {
        let fileValues = FileValues.load(file)

        let apiKey = nonBlank(environment["VELOMAIL_ANTHROPIC_API_KEY"]) ?? nonBlank(fileValues?.anthropicAPIKey)
        let ollamaModel = nonBlank(environment["VELOMAIL_OLLAMA_MODEL"]) ?? nonBlank(fileValues?.ollamaModel)
        let ollamaURLString = nonBlank(environment["VELOMAIL_OLLAMA_URL"]) ?? nonBlank(fileValues?.ollamaURL)

        // Explicit selection wins; an unrecognised name falls through to
        // inference rather than disabling AI on a typo.
        let requested = nonBlank(environment["VELOMAIL_LLM_PROVIDER"]) ?? nonBlank(fileValues?.provider)
        let kind: Kind
        if let requested, let explicit = Kind(rawValue: requested.lowercased()) {
            kind = explicit
        } else if apiKey != nil {
            kind = .anthropic
        } else if ollamaModel != nil || ollamaURLString != nil {
            // Deliberately not probed: launch must not block on a socket that
            // may never answer.
            kind = .ollama
        } else {
            kind = .none
        }

        return LLMConfig(
            kind: kind,
            anthropicAPIKey: apiKey,
            anthropicModel: nonBlank(environment["VELOMAIL_ANTHROPIC_MODEL"])
                ?? nonBlank(fileValues?.anthropicModel)
                ?? AnthropicProvider.defaultModel,
            ollamaModel: ollamaModel ?? OllamaProvider.defaultModel,
            ollamaBaseURL: ollamaURLString.flatMap(URL.init(string:)).flatMap(usableHost)
                ?? OllamaProvider.defaultBaseURL)
    }

    /// Builds the provider, or nil when AI is off.
    public func makeProvider(httpClient: HTTPClient) -> LLMProvider? {
        guard isEnabled else { return nil }
        switch kind {
        case .none:
            return nil
        case .anthropic:
            guard let anthropicAPIKey else { return nil }
            return AnthropicProvider(apiKey: anthropicAPIKey, model: anthropicModel, httpClient: httpClient)
        case .ollama:
            return OllamaProvider(model: ollamaModel, httpClient: httpClient, baseURL: ollamaBaseURL)
        }
    }

    /// Same file the rest of the app uses, so there is one place to look.
    public static var defaultConfigFile: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/velomail/config.json")
    }

    // MARK: - Internals

    /// `URL(string:)` accepts a bare path, which would produce a hostless URL
    /// that can never be reached.
    private static func usableHost(_ url: URL) -> URL? {
        url.host == nil ? nil : url
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private struct FileValues: Decodable {
        let provider: String?
        let anthropicAPIKey: String?
        let anthropicModel: String?
        let ollamaModel: String?
        let ollamaURL: String?

        /// A malformed file resolves to "nothing configured" rather than
        /// throwing on launch.
        static func load(_ url: URL?) -> FileValues? {
            guard let url, let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(FileValues.self, from: data)
        }
    }
}
