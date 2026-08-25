import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct InboxViewModelTests {
    private func makeContext(threadCount: Int) throws -> (InboxViewModel, MailStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        for i in 0..<threadCount {
            let id = "t\(i)"
            try store.upsert(MailThread(id: id, snippet: "snippet \(i)",
                                        lastMessageDate: Date(timeIntervalSince1970: TimeInterval(100 - i)),
                                        isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
            try store.upsert(Message(id: "m\(i)", threadID: id, sender: "a@b.com", recipients: ["me@x.com"],
                                     subject: "subject \(i)", date: Date(timeIntervalSince1970: TimeInterval(100 - i)),
                                     bodyHTML: "<p>body \(i)</p>", bodyText: "body \(i)",
                                     isUnread: false, labelIDs: ["INBOX"]))
        }
        let outbound = OutboundService(writer: NoopWriter(), store: store, mutations: mutations,
                                       identity: "me@x.com")
        let model = InboxViewModel(store: store, outbound: outbound)
        try model.reload()
        return (model, store)
    }

    @Test func loadsThreadsNewestFirst() throws {
        let (model, _) = try makeContext(threadCount: 3)
        #expect(model.threads.map(\.id) == ["t0", "t1", "t2"])
    }

    @Test func selectsTheFirstThreadOnLoad() throws {
        let (model, _) = try makeContext(threadCount: 3)
        #expect(model.selectedThread?.id == "t0")
    }

    @Test func emptyInboxHasNoSelection() throws {
        let (model, _) = try makeContext(threadCount: 0)
        #expect(model.selectedThread == nil)
    }

    @Test func moveDownAndUpChangeTheSelectedThread() throws {
        let (model, _) = try makeContext(threadCount: 3)
        model.moveDown()
        #expect(model.selectedThread?.id == "t1")
        model.moveUp()
        #expect(model.selectedThread?.id == "t0")
    }

    @Test func archiveRemovesTheThreadAndAutoAdvances() throws {
        let (model, store) = try makeContext(threadCount: 3)

        try model.archiveSelected()

        // The next thread is now selected, which is what makes a held-down "e" sweep.
        #expect(model.threads.map(\.id) == ["t1", "t2"])
        #expect(model.selectedThread?.id == "t1")
        #expect(try store.inboxThreads().count == 2)
    }

    @Test func archivingTheLastThreadClampsSelection() throws {
        let (model, _) = try makeContext(threadCount: 2)
        model.moveDown()                       // on t1, the last

        try model.archiveSelected()

        #expect(model.selectedThread?.id == "t0")
    }

    @Test func archivingTheOnlyThreadClearsSelection() throws {
        let (model, _) = try makeContext(threadCount: 1)

        try model.archiveSelected()

        #expect(model.threads.isEmpty)
        #expect(model.selectedThread == nil)
    }

    @Test func archivingWithNoSelectionIsANoOp() throws {
        let (model, _) = try makeContext(threadCount: 0)
        try model.archiveSelected()
        #expect(model.threads.isEmpty)
    }

    @Test func reloadKeepsSelectionInRangeWhenSyncShrinksTheList() throws {
        let (model, store) = try makeContext(threadCount: 3)
        model.moveDown()
        model.moveDown()                       // index 2
        try store.deleteThread(id: "t2")
        try store.deleteThread(id: "t1")

        try model.reload()

        // Selection must clamp, not dangle past the end of the list.
        #expect(model.threads.count == 1)
        #expect(model.selectedThread?.id == "t0")
    }

    @Test func messagesForTheSelectedThreadAreExposed() throws {
        let (model, _) = try makeContext(threadCount: 2)
        #expect(model.selectedMessages.map(\.id) == ["m0"])
        model.moveDown()
        #expect(model.selectedMessages.map(\.id) == ["m1"])
    }

    // MARK: - Marks and bulk triage

    @Test func archiveWithNothingMarkedArchivesTheCursorRow() throws {
        let (model, store) = try makeContext(threadCount: 3)

        try model.archiveSelected()

        #expect(model.threads.map(\.id) == ["t1", "t2"])
        #expect(try store.inboxThreads().map(\.id) == ["t1", "t2"])
    }

    @Test func archiveArchivesEveryMarkedThread() throws {
        let (model, store) = try makeContext(threadCount: 4)
        model.toggleMark()                 // t0
        model.select(index: 2)
        model.toggleMark()                 // t2

        try model.archiveSelected()

        #expect(model.threads.map(\.id) == ["t1", "t3"])
        #expect(try store.inboxThreads().map(\.id) == ["t1", "t3"])
    }

    @Test func bulkArchiveClearsTheMarks() throws {
        let (model, _) = try makeContext(threadCount: 3)
        model.toggleMark()
        model.select(index: 2)
        model.toggleMark()

        try model.archiveSelected()

        #expect(model.markedThreadIDs.isEmpty)
    }

    @Test func bulkArchiveLeavesSelectionOnTheFirstGap() throws {
        let (model, _) = try makeContext(threadCount: 4)
        model.select(index: 1)
        model.toggleMark()                 // t1
        model.select(index: 3)
        model.toggleMark()                 // t3

        try model.archiveSelected()

        // Whatever slid up into the first gap is selected — the same rule a
        // single archive follows.
        #expect(model.selectedThread?.id == "t2")
    }

    @Test func toggleStarStarsTheCursorRowWhenNothingIsMarked() throws {
        let (model, store) = try makeContext(threadCount: 3)

        try model.toggleStarSelected()

        #expect(try store.thread(id: "t0")?.labelIDs.contains("STARRED") == true)
        #expect(try store.thread(id: "t1")?.labelIDs.contains("STARRED") == false)
        #expect(model.threads[0].labelIDs.contains("STARRED"))   // the list row updated too
    }

    @Test func toggleStarAppliesToEveryMarkedThread() throws {
        let (model, store) = try makeContext(threadCount: 3)
        model.toggleMark()                 // t0
        model.select(index: 2)
        model.toggleMark()                 // t2

        try model.toggleStarSelected()

        #expect(try store.thread(id: "t0")?.labelIDs.contains("STARRED") == true)
        #expect(try store.thread(id: "t2")?.labelIDs.contains("STARRED") == true)
        #expect(try store.thread(id: "t1")?.labelIDs.contains("STARRED") == false)

        try model.toggleStarSelected()     // all starred, so the gesture unstars

        #expect(try store.thread(id: "t0")?.labelIDs.contains("STARRED") == false)
        #expect(try store.thread(id: "t2")?.labelIDs.contains("STARRED") == false)
    }

    @Test func toggleStarOnAMixedSelectionStarsRatherThanTogglingEachIndependently() throws {
        let (model, store) = try makeContext(threadCount: 3)
        model.select(index: 1)
        try model.toggleStarSelected()     // t1 alone is starred

        model.toggleMark()                 // t1
        model.select(index: 2)
        model.toggleMark()                 // t2
        try model.toggleStarSelected()

        // Toggling each independently would leave the set *more* mixed, which
        // is never what the gesture meant.
        #expect(try store.thread(id: "t1")?.labelIDs.contains("STARRED") == true)
        #expect(try store.thread(id: "t2")?.labelIDs.contains("STARRED") == true)
    }

    @Test func markedThreadIDsReportsWhatIsMarked() throws {
        let (model, _) = try makeContext(threadCount: 3)
        model.select(index: 2)
        model.toggleMark()
        model.select(index: 0)
        model.toggleMark()

        #expect(model.markedThreadIDs == ["t0", "t2"])
        #expect(model.isMarked(index: 0))
        #expect(!model.isMarked(index: 1))
    }

    @Test func reloadClearsTheMarks() throws {
        let (model, _) = try makeContext(threadCount: 3)
        model.toggleMark()

        try model.reload()

        // Sync can move a row out from under a mark, so the marks go with it.
        #expect(model.markedThreadIDs.isEmpty)
    }

    @Test func markingReadClearsUnreadOnTheSelectedThread() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.upsert(MailThread(id: "t", snippet: "s", lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: true, hasAttachments: false, labelIDs: ["INBOX", "UNREAD"]))
        try store.upsert(Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 1),
                                 bodyHTML: nil, bodyText: "b", isUnread: true, labelIDs: ["INBOX", "UNREAD"]))
        let model = InboxViewModel(store: store,
                                   outbound: OutboundService(writer: NoopWriter(), store: store,
                                                             mutations: MutationStore(db), identity: "me@x.com"))
        try model.reload()

        try model.markSelectedRead()

        #expect(model.selectedThread?.isUnread == false)
    }
}

/// The view model never pushes to Gmail itself; the sync actor drains the queue.
private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        fatalError("unused")
    }
}
