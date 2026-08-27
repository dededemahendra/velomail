import Foundation
import SwiftUI
import VeloCore

/// The search surface: a query, its results, and a cursor over them.
@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var text: String = ""
    @Published public private(set) var results: [MailThread] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var failure: String?

    private let search: SearchService
    private let translator: QueryTranslator
    /// What the last query actually narrowed on, in words.
    @Published public private(set) var filterLabels: [String] = []
    /// The last few searches, newest first. Typing the same query again from
    /// memory is the commonest thing anyone does in a search field.
    @Published public private(set) var recents: [String] = []
    /// True when the search matched more than it is willing to draw.
    ///
    /// It capped at two hundred and said nothing, so a search that found five
    /// hundred looked like a search that found two hundred.
    @Published public private(set) var truncated = false

    /// How many results a list will show. One more than this is fetched, so
    /// "there are more" is known rather than guessed at from a round number.
    public static let resultLimit = 200

    /// How many to keep. Beyond a handful the empty state becomes a wall.
    public static let recentLimit = 5
    private var cursor = SelectionCursor(count: 0)

    private let preferences: AppPreferences?

    public init(search: SearchService, translator: QueryTranslator,
                preferences: AppPreferences? = nil) {
        self.search = search
        self.translator = translator
        self.preferences = preferences
        self.recents = preferences?.recentSearches ?? []
    }

    public var selectedIndex: Int? { cursor.index }

    public var selected: MailThread? {
        guard let index = cursor.index, results.indices.contains(index) else { return nil }
        return results[index]
    }

    /// Translates the query if a model is configured, then searches.
    ///
    /// Translation happens first and separately so that with no model -- or a
    /// failing one -- the raw text is still searched rather than the whole
    /// feature going down with it.
    public func run() async {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            clearResults()
            return
        }

        isSearching = true
        defer { isSearching = false }
        failure = nil

        remember(raw)
        let query = await translator.translate(raw)
        filterLabels = query.filterLabels()
        do {
            let found = try search.search(query, limit: Self.resultLimit + 1)
            truncated = found.count > Self.resultLimit
            results = Array(found.prefix(Self.resultLimit))
        } catch {
            results = []
            truncated = false
            failure = "Search failed."
        }
        cursor = SelectionCursor(count: results.count)
    }

    public func moveDown() { cursor.moveDown() }
    public func moveUp() { cursor.moveUp() }
    public func select(index: Int) { cursor.select(index) }

    /// Puts a search back in the field and runs it.
    public func rerun(_ query: String) async {
        text = query
        await run()
    }

    /// Kept whatever the search returns: a query that found nothing is one you
    /// are most likely to want to edit and try again.
    private func remember(_ raw: String) {
        recents = RecentList.remember(raw, in: recents, limit: Self.recentLimit)
        preferences?.recentSearches = recents
    }

    public func clear() {
        text = ""
        clearResults()
    }

    private func clearResults() {
        results = []
        truncated = false
        filterLabels = []
        cursor = SelectionCursor(count: 0)
        failure = nil
    }
}
