import Foundation

/// Reads and writes the files that configure the app.
///
/// The same files a person can open in a text editor, not a second source of
/// truth beside them. Rules act without asking and are deliberately inspectable;
/// a settings window that wrote somewhere else would take that away and leave
/// two places to disagree.
public struct SettingsStore: Sendable {
    public enum Failure: Error, Equatable {
        /// The file exists and could not be understood. Refusing beats
        /// overwriting: it may hold the only copy of a credential.
        case unreadableConfig
    }

    private let directory: URL

    public init(directory: URL = SettingsStore.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/velomail")
    }

    private var snippetsFile: URL { directory.appendingPathComponent("snippets.json") }
    private var rulesFile: URL { directory.appendingPathComponent("rules.json") }
    private var configFile: URL { directory.appendingPathComponent("config.json") }

    // MARK: - Signature and snippets

    public func snippets() -> SnippetLibrary {
        SnippetLibrary.resolve(environment: [:], file: snippetsFile)
    }

    public func saveSnippets(_ library: SnippetLibrary) throws {
        try write(StoredSnippets(signature: library.signature, snippets: library.snippets),
                  to: snippetsFile)
    }

    // MARK: - Rules

    public func rules() -> RuleLibrary { RuleLibrary.load(from: rulesFile) }

    public func saveRules(_ library: RuleLibrary) throws {
        try write(library.rules, to: rulesFile)
    }

    // MARK: - AI

    public struct AISettings: Equatable, Sendable {
        public var provider: String?
        public var model: String?
        public var apiKey: String?

        public init(provider: String?, model: String?, apiKey: String?) {
            self.provider = provider
            self.model = model
            self.apiKey = apiKey
        }
    }

    public func ai() -> AISettings {
        let values = (try? configValues()) ?? [:]
        return AISettings(provider: values["llmProvider"] as? String,
                          model: values["llmModel"] as? String,
                          apiKey: values["llmAPIKey"] as? String)
    }

    /// Merges into the config file rather than replacing it.
    ///
    /// That file also holds the OAuth client id and secret. Writing it whole
    /// would sign the user out and lose a credential they had to fetch by hand.
    public func saveAI(provider: String?, model: String?, apiKey: String?) throws {
        var values = try configValues()
        set("llmProvider", provider, in: &values)
        set("llmModel", model, in: &values)
        set("llmAPIKey", apiKey, in: &values)
        try writeJSON(values, to: configFile)
    }

    // MARK: - Internals

    /// The config file as a dictionary, or empty when there is no file yet.
    /// A file that exists and will not parse is an error, never an empty start.
    private func configValues() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configFile.path) else { return [:] }
        guard let data = try? Data(contentsOf: configFile),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableConfig
        }
        return values
    }

    /// An empty value clears the key rather than storing an empty string, so
    /// "no key configured" and "the key is blank" cannot drift apart.
    private func set(_ key: String, _ value: String?, in values: inout [String: Any]) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            values[key] = trimmed
        } else {
            values.removeValue(forKey: key)
        }
    }

    private struct StoredSnippets: Encodable {
        let signature: String?
        let snippets: [Snippet]
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        // Readable on purpose: these are files people open.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try makeDirectory()
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func writeJSON(_ values: [String: Any], to url: URL) throws {
        try makeDirectory()
        let data = try JSONSerialization.data(withJSONObject: values,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func makeDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
