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

    public init(terms: String = "", from: String? = nil, isUnread: Bool? = nil,
                after: Date? = nil, before: Date? = nil) {
        self.terms = terms
        self.from = from
        self.isUnread = isUnread
        self.after = after
        self.before = before
    }

    /// True when this would match everything — used to decide whether a query is
    /// worth running at all.
    public var isEmpty: Bool {
        terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && from == nil && isUnread == nil && after == nil && before == nil
    }
}
