import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct SyncStateStoreTests {
    private func makeStore() throws -> SyncStateStore {
        SyncStateStore(try AppDatabase.makeInMemory())
    }

    @Test func loadReturnsNilForUnknownAccount() throws {
        let store = try makeStore()
        let loaded = try store.load(accountID: "acct-1")
        #expect(loaded == nil)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = try makeStore()
        let state = SyncState(accountID: "acct-1", historyId: "1000", backfillComplete: true)

        try store.save(state)
        let loaded = try store.load(accountID: "acct-1")

        #expect(loaded == state)
    }

    @Test func saveUpdatesHistoryIdForExistingAccount() throws {
        let store = try makeStore()
        try store.save(SyncState(accountID: "acct-1", historyId: "1000", backfillComplete: true))

        try store.save(SyncState(accountID: "acct-1", historyId: "2000", backfillComplete: true))
        let loaded = try store.load(accountID: "acct-1")

        #expect(loaded?.historyId == "2000")
    }
}
