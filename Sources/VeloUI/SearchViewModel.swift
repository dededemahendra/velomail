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
    private var cursor = SelectionCursor(count: 0)

    public init(search: SearchService, translator: QueryTranslator) {
        self.search = search
        self.translator = translator
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

        let query = await translator.translate(raw)
        do {
            results = try search.search(query)
        } catch {
            results = []
            failure = "Search failed."
        }
        cursor = SelectionCursor(count: results.count)
    }

    public func moveDown() { cursor.moveDown() }
    public func moveUp() { cursor.moveUp() }
    public func select(index: Int) { cursor.select(index) }

    public func clear() {
        text = ""
        clearResults()
    }

    private func clearResults() {
        results = []
        cursor = SelectionCursor(count: 0)
        failure = nil
    }
}
