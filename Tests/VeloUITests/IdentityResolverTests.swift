import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct IdentityResolverTests {
    private func store(email: String?) throws -> SyncStateStore {
        let db = try AppDatabase.makeInMemory()
        let store = SyncStateStore(db)
        try store.save(SyncState(accountID: "acct", historyId: "1",
                                 backfillComplete: true, emailAddress: email))
        return store
    }

    @Test func prefersThePersistedProfileAddress() throws {
        let resolver = IdentityResolver(syncState: try store(email: "real@example.com"),
                                        accountID: "acct", configured: "configured@example.com")
        #expect(resolver.identity() == "real@example.com")
    }

    @Test func fallsBackToTheConfiguredIdentityBeforeBackfill() throws {
        let resolver = IdentityResolver(syncState: try store(email: nil),
                                        accountID: "acct", configured: "configured@example.com")
        #expect(resolver.identity() == "configured@example.com")
    }

    @Test func fallsBackToAPlaceholderWhenNothingIsKnown() throws {
        let resolver = IdentityResolver(syncState: try store(email: nil),
                                        accountID: "acct", configured: nil)
        #expect(resolver.identity() == IdentityResolver.placeholder)
    }

    @Test func aBlankStoredAddressIsIgnored() throws {
        let resolver = IdentityResolver(syncState: try store(email: "   "),
                                        accountID: "acct", configured: "configured@example.com")
        #expect(resolver.identity() == "configured@example.com")
    }

    @Test func picksUpTheAddressOnceBackfillLandsIt() throws {
        let db = try AppDatabase.makeInMemory()
        let syncState = SyncStateStore(db)
        let resolver = IdentityResolver(syncState: syncState, accountID: "acct", configured: nil)
        #expect(resolver.identity() == IdentityResolver.placeholder)

        // Backfill completes and records the address.
        try syncState.save(SyncState(accountID: "acct", historyId: "1",
                                     backfillComplete: true, emailAddress: "real@example.com"))

        #expect(resolver.identity() == "real@example.com")
    }
}
