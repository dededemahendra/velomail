import Testing
import Foundation
@testable import VeloCore

@Suite struct SearchServiceTests {
    private func makeContext() throws -> (SearchService, MailStore) {
        let db = try AppDatabase.makeInMemory()
        return (SearchService(db), MailStore(db))
    }

    private func seed(_ store: MailStore, thread: String, message: String,
                      sender: String = "Salsa <salsa@example.com>",
                      subject: String = "Plot map",
                      body: String = "the eastern boundary needs redrawing",
                      unread: Bool = false, days: Int = 0) throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000 - Double(days) * 86_400)
        let labels = unread ? ["INBOX", "UNREAD"] : ["INBOX"]
        try store.upsert(MailThread(id: thread, sender: sender, snippet: body,
                                    lastMessageDate: date, isUnread: unread,
                                    hasAttachments: false, labelIDs: labels))
        try store.upsert(Message(id: message, threadID: thread, sender: sender,
                                 recipients: ["me@x.com"], subject: subject, date: date,
                                 bodyHTML: nil, bodyText: body, isUnread: unread,
                                 labelIDs: labels))
    }

    // MARK: - Terms

    @Test func findsAThreadByABodyWord() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1")
        #expect(try search.search(SearchQuery(terms: "boundary")).map(\.id) == ["t1"])
    }

    @Test func findsAThreadBySubject() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1")
        #expect(try search.search(SearchQuery(terms: "plot")).map(\.id) == ["t1"])
    }

    @Test func findsAThreadBySender() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1")
        #expect(try search.search(SearchQuery(terms: "salsa")).map(\.id) == ["t1"])
    }

    @Test func matchingIsStemmedSoMeetingFindsMeet() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1", body: "we are meeting on Friday")
        #expect(try search.search(SearchQuery(terms: "meet")).map(\.id) == ["t1"])
    }

    @Test func allTermsMustMatch() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1", body: "alpha beta")
        try seed(store, thread: "t2", message: "m2", body: "alpha gamma")
        #expect(try search.search(SearchQuery(terms: "alpha beta")).map(\.id) == ["t1"])
    }

    @Test func noMatchReturnsNothing() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1")
        #expect(try search.search(SearchQuery(terms: "zebra")).isEmpty)
    }

    @Test func ftsMetacharactersDoNotBlowUp() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1")
        // A stray quote or star in a search box is a syntax error in raw FTS5.
        for nasty in ["\"", "boundary\"", "*", "AND", "NEAR(", "^ boundary"] {
            _ = try search.search(SearchQuery(terms: nasty))
        }
    }

    @Test func anEmptyQueryReturnsRecentThreadsRatherThanNothing() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1", days: 1)
        try seed(store, thread: "t2", message: "m2", days: 0)
        // An empty search box should show something, newest first.
        #expect(try search.search(SearchQuery(terms: "")).map(\.id) == ["t2", "t1"])
    }

    // MARK: - Threads, not messages

    @Test func aThreadAppearsOnceEvenWhenSeveralMessagesMatch() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1", body: "boundary one")
        try store.upsert(Message(id: "m2", threadID: "t1", sender: "x@y.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 1),
                                 bodyHTML: nil, bodyText: "boundary two", isUnread: false,
                                 labelIDs: ["INBOX"]))
        #expect(try search.search(SearchQuery(terms: "boundary")).map(\.id) == ["t1"])
    }

    @Test func resultsAreNewestFirst() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "old", message: "m1", body: "boundary", days: 5)
        try seed(store, thread: "new", message: "m2", body: "boundary", days: 0)
        #expect(try search.search(SearchQuery(terms: "boundary")).map(\.id) == ["new", "old"])
    }

    @Test func theLimitIsRespected() throws {
        let (search, store) = try makeContext()
        for i in 0..<5 { try seed(store, thread: "t\(i)", message: "m\(i)", body: "boundary", days: i) }
        #expect(try search.search(SearchQuery(terms: "boundary"), limit: 2).count == 2)
    }

    // MARK: - Filters

    @Test func fromNarrowsBySender() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1", sender: "Salsa <salsa@example.com>", body: "map")
        try seed(store, thread: "t2", message: "m2", sender: "Warren <warren@example.com>", body: "map")

        #expect(try search.search(SearchQuery(terms: "map", from: "warren")).map(\.id) == ["t2"])
    }

    @Test func fromWorksWithoutAnyTerms() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1", sender: "Salsa <salsa@example.com>")
        try seed(store, thread: "t2", message: "m2", sender: "Warren <warren@example.com>")

        #expect(try search.search(SearchQuery(terms: "", from: "salsa")).map(\.id) == ["t1"])
    }

    @Test func unreadNarrowsToUnreadThreads() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "t1", message: "m1", body: "map", unread: true)
        try seed(store, thread: "t2", message: "m2", body: "map", unread: false)

        #expect(try search.search(SearchQuery(terms: "map", isUnread: true)).map(\.id) == ["t1"])
    }

    @Test func dateRangeNarrowsResults() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "recent", message: "m1", body: "map", days: 1)
        try seed(store, thread: "ancient", message: "m2", body: "map", days: 30)

        let cutoff = Date(timeIntervalSince1970: 1_700_000_000 - 7 * 86_400)
        #expect(try search.search(SearchQuery(terms: "map", after: cutoff)).map(\.id) == ["recent"])
    }

    @Test func beforeExcludesNewerThreads() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "recent", message: "m1", body: "map", days: 1)
        try seed(store, thread: "ancient", message: "m2", body: "map", days: 30)

        let cutoff = Date(timeIntervalSince1970: 1_700_000_000 - 7 * 86_400)
        #expect(try search.search(SearchQuery(terms: "map", before: cutoff)).map(\.id) == ["ancient"])
    }

    @Test func filtersCombine() throws {
        let (search, store) = try makeContext()
        try seed(store, thread: "wanted", message: "m1", sender: "Salsa <salsa@example.com>",
                 body: "map", unread: true, days: 1)
        try seed(store, thread: "wrongSender", message: "m2", sender: "Warren <w@example.com>",
                 body: "map", unread: true, days: 1)
        try seed(store, thread: "wrongRead", message: "m3", sender: "Salsa <salsa@example.com>",
                 body: "map", unread: false, days: 1)

        let results = try search.search(SearchQuery(terms: "map", from: "salsa", isUnread: true))
        #expect(results.map(\.id) == ["wanted"])
    }
}
