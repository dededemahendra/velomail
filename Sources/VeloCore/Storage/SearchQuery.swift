import Foundation

/// A search, as structure rather than a string.
///
/// This is what the natural-language layer produces and what the search engine
/// consumes, which keeps the model out of the query path entirely: it
/// translates, it does not search.
public struct SearchQuery: Equatable, Sendable, Codable {
    /// Free text, matched against sender, subject and body.
    public var terms: String
    /// Substring of the sender, case-insensitive.
    public var from: String?
    public var isUnread: Bool?
    public var after: Date?
    public var before: Date?
    /// Only threads carrying a file. Read off the thread's own flag rather than
    /// the attachment table: content is fetched on demand, so a thread is known
    /// to have a file long before there is a row describing it.
    public var hasAttachment: Bool?
    /// Substring of an attachment's name, matched on its own -- for finding the
    /// document when you remember the file and not a word of the message.
    public var filename: String?

    public init(terms: String = "", from: String? = nil, isUnread: Bool? = nil,
                after: Date? = nil, before: Date? = nil,
                hasAttachment: Bool? = nil, filename: String? = nil) {
        self.terms = terms
        self.from = from
        self.isUnread = isUnread
        self.after = after
        self.before = before
        self.hasAttachment = hasAttachment
        self.filename = filename
    }

    /// True when this would match everything — used to decide whether a query is
    /// worth running at all.
    public var isEmpty: Bool {
        terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && from == nil && isUnread == nil && after == nil && before == nil
            && hasAttachment == nil && filename == nil
    }

    /// True when something narrower than free text was asked for.
    ///
    /// What distinguishes a query worth honouring exactly from one worth
    /// handing to a model to interpret.
    public var hasOperators: Bool {
        from != nil || isUnread != nil || after != nil || before != nil
            || hasAttachment != nil || filename != nil
    }

    /// What was narrowed, in words, for showing back to the person who typed it.
    ///
    /// Without this there is no way to tell whether `from:cloudflare` filtered
    /// or searched for the literal string -- and the two look identical when
    /// the answer is empty either way.
    public func filterLabels(calendar: Calendar = .current) -> [String] {
        var labels: [String] = []
        if let from { labels.append("From \(from)") }
        if let isUnread { labels.append(isUnread ? "Unread" : "Read") }
        if let after { labels.append("After \(SearchQuery.day.string(from: after))") }
        if let before { labels.append("Before \(SearchQuery.day.string(from: before))") }
        if hasAttachment == true { labels.append("Has a file") }
        if let filename { labels.append("File named \(filename)") }
        return labels
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    // MARK: - Typed queries

    /// Reads the operators people already know from other mail clients.
    ///
    /// The filtering has always been here; until now the only thing that could
    /// fill it in was the AI translator, so anyone without a provider
    /// configured got plain text and a search for the literal string
    /// "from:cloudflare".
    ///
    /// Anything that does not parse is left as words. Searching for what was
    /// typed is a worse answer than filtering, but a much better one than
    /// silently dropping it.
    public static func parse(_ text: String, now: Date = Date(),
                             calendar: Calendar = .current) -> SearchQuery {
        var query = SearchQuery()
        var words: [String] = []

        for token in tokens(of: text) {
            guard let colon = token.firstIndex(of: ":"), colon != token.startIndex else {
                words.append(token)
                continue
            }
            let name = token[token.startIndex..<colon].lowercased()
            let value = String(token[token.index(after: colon)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            // An operator with nothing after it is somebody mid-typing.
            guard !value.isEmpty else { words.append(token); continue }

            switch name {
            case "from":
                query.from = value
            case "is" where value.lowercased() == "unread":
                query.isUnread = true
            case "is" where value.lowercased() == "read":
                query.isUnread = false
            case "after":
                guard let date = date(from: value, now: now, calendar: calendar) else {
                    words.append(token); continue
                }
                query.after = date
            case "has" where ["attachment", "attachments"].contains(value.lowercased()):
                // Gmail spells it singular; enough people type the plural that
                // refusing it would just look broken.
                query.hasAttachment = true
            case "filename", "file":
                query.filename = value
            case "before":
                guard let date = date(from: value, now: now, calendar: calendar) else {
                    words.append(token); continue
                }
                query.before = date
            default:
                words.append(token)
            }
        }

        query.terms = words.joined(separator: " ")
        return query
    }

    /// Splits on spaces, except inside quotes: `from:"team tailscale"` is one
    /// sender, not a sender and a stray word.
    private static func tokens(of text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false

        for character in text {
            if character == "\"" {
                quoted.toggle()
                current.append(character)
            } else if character == " " && !quoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// A date, either written out or said the way people say it.
    private static func date(from value: String, now: Date, calendar: Calendar) -> Date? {
        switch value.lowercased() {
        case "today": return calendar.startOfDay(for: now)
        case "yesterday":
            return calendar.startOfDay(for: now.addingTimeInterval(-86_400))
        case "week": return calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))
        case "month": return calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: now))
        case "year": return calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: now))
        default: break
        }

        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
