import Testing
import Foundation
@testable import VeloCore

@Suite struct StarredArchiveTests {
    private func makeStore() throws -> MailStore { MailStore(try AppDatabase.makeInMemory()) }

    private func seed(_ store: MailStore, id: String, labels: [String],
                      at seconds: TimeInterval = 10) throws {
        try store.upsert(MailThread(id: id, sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: seconds),
                                    isUnread: false, hasAttachments: false, labelIDs: labels))
    }

    // MARK: - Starred

    @Test func starredIsWhateverCarriesTheLabel() throws {
        let store = try makeStore()
        try seed(store, id: "star", labels: ["INBOX", "STARRED"])
        try seed(store, id: "plain", labels: ["INBOX"])

        #expect(try store.starredThreads().map(\.id) == ["star"])
    }

    @Test func aStarredThreadOutsideTheInboxStillCounts() throws {
        // The point of starring is that it survives filing something away.
        let store = try makeStore()
        try seed(store, id: "filed", labels: ["STARRED"])

        #expect(try store.starredThreads().map(\.id) == ["filed"])
    }

    @Test func theNewestStarredThreadComesFirst() throws {
        let store = try makeStore()
        try seed(store, id: "old", labels: ["STARRED"], at: 10)
        try seed(store, id: "new", labels: ["STARRED"], at: 30)

        #expect(try store.starredThreads().map(\.id) == ["new", "old"])
    }

    @Test func starredIsAmongTheLabelsFetched() throws {
        // Otherwise the view works and shows only what was starred from here.
        #expect(BackfillService.backfilledLabels.contains("STARRED"))
    }

    // MARK: - Archive

    @Test func archiveIsWhatHasLeftTheInbox() throws {
        let store = try makeStore()
        try seed(store, id: "inbox", labels: ["INBOX"])
        try seed(store, id: "archived", labels: [])

        #expect(try store.archivedThreads().map(\.id) == ["archived"])
    }

    @Test func theBinIsNotTheArchive() throws {
        // Deleted mail has left the inbox too, and belongs in neither place.
        let store = try makeStore()
        try seed(store, id: "binned", labels: ["TRASH"])

        #expect(try store.archivedThreads().isEmpty)
    }

    @Test func aSentMessageIsNotArchivedMailYouFiled() throws {
        // It never was in the inbox, so calling it archived would fill the view
        // with everything ever sent.
        let store = try makeStore()
        try seed(store, id: "sent", labels: ["SENT"])

        #expect(try store.archivedThreads().isEmpty)
    }

    @Test func aSnoozedThreadIsWaitingNotFiled() throws {
        // A snooze removes INBOX, so without this every snoozed thread would
        // also appear as archived.
        let store = try makeStore()
        try seed(store, id: "later", labels: [])
        try store.setSnoozedUntil(Date(timeIntervalSince1970: 9_999_999), onThread: "later")

        #expect(try store.archivedThreads(now: Date(timeIntervalSince1970: 10)).isEmpty)
    }
}
