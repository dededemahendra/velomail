import Foundation

/// A named piece of reusable text, reached by typing its shortcut.
///
/// A *template* is not a separate concept: it is a snippet that also carries a
/// subject. Built as two types they would need two stores, two editors and two
/// insertion paths that drift; built as one, you reach a template exactly the
/// way you reach a snippet and there is nothing new to learn.
public struct Snippet: Codable, Equatable, Sendable {
    public var name: String
    /// Typed after a `;` to insert this snippet.
    public var shortcut: String
    /// Non-nil makes this a template: expanding it fills an *empty* subject too.
    public var subject: String?
    public var body: String

    public init(name: String, shortcut: String, subject: String? = nil, body: String) {
        self.name = name
        self.shortcut = shortcut
        self.subject = subject
        self.body = body
    }
}

/// The snippets and signature available to the composer.
///
/// A file rather than a table, because that is how this app already takes
/// everything else the user provides — the OAuth client id, the LLM provider,
/// the identity. It costs no migration and no editor UI, and the expansion is
/// the part that saves keystrokes every day.
public struct SnippetLibrary: Equatable, Sendable {
    /// Appended to every draft you start. A single value beside the list rather
    /// than a flagged member of it: an `isSignature` boolean would admit a
    /// "two signatures" state that then has to be forbidden, and states you can
    /// simply not represent need no forbidding.
    public let signature: String?
    public let snippets: [Snippet]

    /// Normalises on the way in, so a hand-edited file, a test and any other
    /// caller all obey the same rules.
    public init(signature: String? = nil, snippets: [Snippet] = []) {
        self.signature = Self.nonBlank(signature)

        var seen = Set<String>()
        self.snippets = snippets.compactMap { snippet in
            guard let shortcut = Self.nonBlank(snippet.shortcut),
                  Self.nonBlank(snippet.body) != nil else { return nil }
            let key = shortcut.lowercased()
            // First wins, so the file reads top-down and a duplicate lower down
            // cannot silently shadow the one above it.
            guard seen.insert(key).inserted else { return nil }
            var normalized = snippet
            normalized.shortcut = shortcut
            return normalized
        }
    }

    public static let empty = SnippetLibrary()

    public func snippet(forShortcut shortcut: String) -> Snippet? {
        guard let needle = Self.nonBlank(shortcut)?.lowercased() else { return nil }
        return snippets.first { $0.shortcut.lowercased() == needle }
    }

    /// Where a user drops their snippets.
    public static var defaultFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/velomail/snippets.json")
    }

    /// Environment first, then the file — the same order as `LLMConfig`.
    ///
    /// A missing or malformed file resolves to an empty library rather than an
    /// error: a typo in a snippets file must not stop a mail client launching.
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               file: URL? = defaultFile) -> SnippetLibrary {
        let fileValues = FileValues.load(file)
        return SnippetLibrary(
            signature: nonBlank(environment["VELOMAIL_SIGNATURE"]) ?? fileValues?.signature,
            snippets: fileValues?.snippets ?? [])
    }

    // MARK: - Internals

    private struct FileValues: Decodable {
        let signature: String?
        let snippets: [Snippet]?

        static func load(_ url: URL?) -> (signature: String?, snippets: [Snippet])? {
            guard let url, let data = try? Data(contentsOf: url),
                  let values = try? JSONDecoder().decode(FileValues.self, from: data)
            else { return nil }
            return (values.signature, values.snippets ?? [])
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
