import Foundation

/// The user's rules, read from a file.
///
/// A file rather than a table, deliberately: rules act *without asking*, and a
/// rule engine whose rules are invisible inside a database is one nobody trusts.
/// The user can read, edit and delete them in a text editor.
public struct RuleLibrary: Equatable, Sendable {
    public let rules: [MailRule]

    public init(rules: [MailRule]) {
        self.rules = rules
    }

    public static let empty = RuleLibrary(rules: [])

    public static var defaultFile: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/velomail/rules.json")
    }

    /// Reads the file, or yields no rules.
    ///
    /// A malformed file fails **closed** — no rules at all. These actions cannot
    /// be undone in bulk, so guessing at a half-parsed file would be worse than
    /// doing nothing.
    public static func load(from url: URL? = defaultFile) -> RuleLibrary {
        guard let url,
              let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([MailRule].self, from: data) else {
            return .empty
        }
        return RuleLibrary(rules: rules)
    }
}
