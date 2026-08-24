import Foundation

/// Turns "emails from natalie last week about the open day" into a `SearchQuery`.
///
/// A translator, not a search engine: the model sees the query string and
/// nothing else. No mail content is ever in the prompt, which makes this fast,
/// private, and safe to run against a hosted provider even when the mailbox
/// itself should stay local.
///
/// It also degrades to being useless rather than broken: anything it cannot
/// parse becomes plain search terms, which is what a search box would have done.
public struct QueryTranslator: Sendable {
    private let assistant: MailAssistant
    private let now: @Sendable () -> Date

    public init(assistant: MailAssistant, now: @escaping @Sendable () -> Date = { Date() }) {
        self.assistant = assistant
        self.now = now
    }

    public func translate(_ text: String) async -> SearchQuery {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchQuery() }
        guard assistant.isAvailable else { return SearchQuery(terms: trimmed) }

        do {
            let raw = try await assistant.translateQuery(trimmed, today: isoDay(now()))
            guard let translated = Self.parse(raw), !translated.isEmpty else {
                // A translation that searches for nothing is worse than none at
                // all: it matches everything. Seen against a real model, which
                // reduced the plain query "plot map" to {}.
                return SearchQuery(terms: trimmed)
            }
            return translated
        } catch {
            return SearchQuery(terms: trimmed)
        }
    }

    // MARK: - Parsing

    /// Models wrap JSON in code fences and pad it with prose, so this extracts
    /// the first balanced object rather than assuming the response is clean.
    static func parse(_ raw: String) -> SearchQuery? {
        guard let json = firstJSONObject(in: raw),
              let decoded = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else {
            return nil
        }
        return SearchQuery(
            terms: decoded.terms ?? "",
            from: nonBlank(decoded.from),
            isUnread: decoded.isUnread,
            after: decoded.after.flatMap(day(from:)),
            before: decoded.before.flatMap(day(from:)))
    }

    /// Scans for a balanced `{...}`, so nested objects do not truncate it.
    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = start
        while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private struct Payload: Decodable {
        let terms: String?
        let from: String?
        let isUnread: Bool?
        let after: String?
        let before: String?
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func day(from string: String) -> Date? { dayFormatter.date(from: string) }
    private func isoDay(_ date: Date) -> String { Self.dayFormatter.string(from: date) }
}
