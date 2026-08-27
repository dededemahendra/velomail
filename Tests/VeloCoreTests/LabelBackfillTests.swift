import Testing
import Foundation
@testable import VeloCore

@Suite struct LabelBackfillTests {
    private func makeStore() throws -> (SyncStateStore, AppDatabase) {
        let db = try AppDatabase.makeInMemory()
        return (SyncStateStore(db), db)
    }

    // MARK: - Remembering which labels are done

    @Test func aFreshAccountHasBackfilledNothing() throws {
        let (store, _) = try makeStore()
        try store.save(SyncState(accountID: "a", historyId: "1", backfillComplete: false))

        #expect(try store.load(accountID: "a")?.backfilledLabels == [])
    }

    @Test func labelsSurviveARoundTrip() throws {
        let (store, _) = try makeStore()
        try store.save(SyncState(accountID: "a", historyId: "1", backfillComplete: true,
                                 backfilledLabels: ["INBOX", "SENT"]))

        #expect(try store.load(accountID: "a")?.backfilledLabels == ["INBOX", "SENT"])
    }

    @Test func anAccountBackfilledBeforeLabelsWereTrackedCountsAsInboxOnly() throws {
        // The real case this exists for: a mailbox synced before SENT was
        // added. Treating its old `backfillComplete` as "everything is done"
        // is what left the Sent list empty with no way to fill it.
        let (store, db) = try makeStore()
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO syncState (accountID, historyId, backfillComplete)
                VALUES ('a', '99', 1)
                """)
        }

        #expect(try store.load(accountID: "a")?.backfilledLabels == ["INBOX"])
    }

    @Test func anAccountThatNeverBackfilledClaimsNoLabels() throws {
        let (store, db) = try makeStore()
        try db.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO syncState (accountID, historyId, backfillComplete)
                VALUES ('a', NULL, 0)
                """)
        }

        #expect(try store.load(accountID: "a")?.backfilledLabels == [])
    }

    // MARK: - What still needs doing

    @Test func aLabelAddedToTheAppLaterIsStillOutstanding() throws {
        let state = SyncState(accountID: "a", historyId: "1", backfillComplete: true,
                              backfilledLabels: ["INBOX"])

        #expect(state.labelsNeedingBackfill(of: ["INBOX", "SENT"]) == ["SENT"])
    }

    @Test func nothingIsOutstandingWhenEveryLabelIsDone() throws {
        let state = SyncState(accountID: "a", historyId: "1", backfillComplete: true,
                              backfilledLabels: ["INBOX", "SENT"])

        #expect(state.labelsNeedingBackfill(of: ["INBOX", "SENT"]).isEmpty)
    }

    @Test func theOrderFollowsTheAppNotTheStore() throws {
        // Inbox first, so the list the writer is looking at fills first.
        let state = SyncState(accountID: "a", historyId: "1", backfillComplete: false,
                              backfilledLabels: [])

        #expect(state.labelsNeedingBackfill(of: ["INBOX", "SENT", "STARRED"])
                == ["INBOX", "SENT", "STARRED"])
    }
}
