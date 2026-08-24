import Testing
import Foundation
@testable import VeloCore

@Suite struct LLMConfigTests {
    private func resolve(_ env: [String: String]) -> LLMConfig {
        LLMConfig.resolve(environment: env, file: nil)
    }

    // MARK: - Inference

    @Test func nothingConfiguredMeansNoProvider() {
        let config = resolve([:])
        #expect(config.kind == .none)
        #expect(!config.isEnabled)
    }

    @Test func anAPIKeyAloneSelectsTheHostedProvider() {
        let config = resolve(["VELOMAIL_ANTHROPIC_API_KEY": "sk-1"])
        #expect(config.kind == .anthropic)
        #expect(config.isEnabled)
    }

    @Test func anOllamaModelAloneSelectsTheLocalProvider() {
        #expect(resolve(["VELOMAIL_OLLAMA_MODEL": "llama3.2"]).kind == .ollama)
    }

    @Test func anOllamaURLAloneAlsoSelectsTheLocalProvider() {
        #expect(resolve(["VELOMAIL_OLLAMA_URL": "http://localhost:11434"]).kind == .ollama)
    }

    @Test func aKeyWinsOverOllamaWhenBothArePresent() {
        let config = resolve(["VELOMAIL_ANTHROPIC_API_KEY": "sk-1",
                              "VELOMAIL_OLLAMA_MODEL": "llama3.2"])
        #expect(config.kind == .anthropic)
    }

    // MARK: - Explicit selection

    @Test func anExplicitProviderOverridesInference() {
        let config = resolve(["VELOMAIL_LLM_PROVIDER": "ollama",
                              "VELOMAIL_ANTHROPIC_API_KEY": "sk-1"])
        #expect(config.kind == .ollama)
    }

    @Test func explicitNoneDisablesAIEvenWithAKeyPresent() {
        let config = resolve(["VELOMAIL_LLM_PROVIDER": "none",
                              "VELOMAIL_ANTHROPIC_API_KEY": "sk-1"])
        #expect(config.kind == .none)
    }

    @Test func anUnknownProviderNameFallsBackToInferenceRatherThanFailing() {
        let config = resolve(["VELOMAIL_LLM_PROVIDER": "gpt-9",
                              "VELOMAIL_ANTHROPIC_API_KEY": "sk-1"])
        #expect(config.kind == .anthropic)
    }

    @Test func theProviderNameIsCaseInsensitive() {
        #expect(resolve(["VELOMAIL_LLM_PROVIDER": "Ollama"]).kind == .ollama)
    }

    @Test func requestingAnthropicWithoutAKeyIsNotEnabled() {
        // Asking for a provider that cannot work must not present as working.
        let config = resolve(["VELOMAIL_LLM_PROVIDER": "anthropic"])
        #expect(!config.isEnabled)
    }

    // MARK: - Values

    @Test func modelsFallBackToDocumentedDefaults() {
        #expect(resolve(["VELOMAIL_ANTHROPIC_API_KEY": "k"]).anthropicModel
                == AnthropicProvider.defaultModel)
        #expect(resolve(["VELOMAIL_OLLAMA_MODEL": ""]).ollamaModel == OllamaProvider.defaultModel)
    }

    @Test func modelsAreOverridable() {
        #expect(resolve(["VELOMAIL_ANTHROPIC_API_KEY": "k",
                         "VELOMAIL_ANTHROPIC_MODEL": "claude-haiku-4-5-20251001"]).anthropicModel
                == "claude-haiku-4-5-20251001")
        #expect(resolve(["VELOMAIL_OLLAMA_MODEL": "qwen2.5"]).ollamaModel == "qwen2.5")
    }

    @Test func aMalformedOllamaURLFallsBackToTheDefault() {
        let config = resolve(["VELOMAIL_OLLAMA_URL": "not a url at all"])
        #expect(config.ollamaBaseURL == OllamaProvider.defaultBaseURL)
    }

    @Test func blankValuesAreTreatedAsAbsent() {
        #expect(resolve(["VELOMAIL_ANTHROPIC_API_KEY": "   "]).kind == .none)
    }

    // MARK: - Factory

    @Test func makeProviderReturnsNilWhenDisabled() {
        #expect(resolve([:]).makeProvider(httpClient: URLSessionHTTPClient()) == nil)
    }

    @Test func makeProviderBuildsTheSelectedProvider() throws {
        let hosted = resolve(["VELOMAIL_ANTHROPIC_API_KEY": "k", "VELOMAIL_ANTHROPIC_MODEL": "m1"])
            .makeProvider(httpClient: URLSessionHTTPClient())
        #expect(hosted?.displayName.contains("m1") == true)

        let local = resolve(["VELOMAIL_OLLAMA_MODEL": "m2"])
            .makeProvider(httpClient: URLSessionHTTPClient())
        #expect(local?.displayName.contains("m2") == true)
    }

    // MARK: - File

    @Test func theConfigFileSuppliesValuesToo() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velomail-llm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.json")
        try Data(#"{"anthropicAPIKey":"sk-file","anthropicModel":"m-file"}"#.utf8).write(to: file)

        let config = LLMConfig.resolve(environment: [:], file: file)

        #expect(config.kind == .anthropic)
        #expect(config.anthropicModel == "m-file")
    }

    @Test func theEnvironmentWinsOverTheFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velomail-llm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.json")
        try Data(#"{"anthropicModel":"m-file"}"#.utf8).write(to: file)

        let config = LLMConfig.resolve(
            environment: ["VELOMAIL_ANTHROPIC_API_KEY": "k", "VELOMAIL_ANTHROPIC_MODEL": "m-env"],
            file: file)

        #expect(config.anthropicModel == "m-env")
    }
}
