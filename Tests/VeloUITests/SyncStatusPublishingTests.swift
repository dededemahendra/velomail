import Testing
import Combine
import Foundation
import VeloCore
@testable import VeloUI

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError("unused") }
}

/// `AppHost` polls the sync engine once a second for the whole life of the
/// process and hands the answer to `setSyncStatus`. Almost every one of those
/// ticks carries the status the app already had, so republishing it repaints
/// the entire view tree -- and the thread list with it -- once a second while
/// nothing whatsoever has changed.
///
/// That is what made the list scroll itself back under the reader's hands: the
/// list follows its selection when it is redrawn, and it was being redrawn on a
/// timer. The list no longer follows a selection that has not moved, so these
/// cover the other half -- not redrawing at all when there is nothing new.
@MainActor
@Suite struct SyncStatusPublishingTests {
    private func makeApp() throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let outbound = OutboundService(writer: NoopWriter(), store: store,
                                       mutations: MutationStore(db), identity: "me@x.com")
        let app = AppViewModel(config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "cid"],
                                                         configFile: nil),
                               store: store, outbound: outbound,
                               identity: "me@x.com", isSignedIn: true)
        try app.start()
        return app
    }

    /// Counts how many times the object announces a change while `body` runs.
    private func changes(on app: AppViewModel, during body: () -> Void) -> Int {
        var count = 0
        let token = app.objectWillChange.sink { _ in count += 1 }
        body()
        token.cancel()
        return count
    }

    @Test func aStatusThatHasNotChangedIsNotRepublished() throws {
        let app = try makeApp()
        let moment = Date(timeIntervalSince1970: 1_000)
        app.setSyncStatus(.upToDate(lastSyncedAt: moment))

        // Eight ticks of the once-a-second poll with the same answer. Before
        // this, each one repainted the whole app.
        let count = changes(on: app) {
            for _ in 0..<8 { app.setSyncStatus(.upToDate(lastSyncedAt: moment)) }
        }

        #expect(count == 0)
    }

    @Test func aStatusThatHasChangedIsStillPublished() throws {
        let app = try makeApp()
        app.setSyncStatus(.syncing)

        let count = changes(on: app) {
            app.setSyncStatus(.upToDate(lastSyncedAt: Date(timeIntervalSince1970: 1_000)))
        }

        #expect(count == 1)
        #expect(app.syncStatus == .upToDate(lastSyncedAt: Date(timeIntervalSince1970: 1_000)))
    }

    @Test func aStatusCarryingANewTimeIsAChange() throws {
        let app = try makeApp()
        app.setSyncStatus(.upToDate(lastSyncedAt: Date(timeIntervalSince1970: 1_000)))

        // "Updated 10.31" has to become "Updated 10.32"; the associated value
        // is the difference and dropping it would freeze the status bar.
        let count = changes(on: app) {
            app.setSyncStatus(.upToDate(lastSyncedAt: Date(timeIntervalSince1970: 1_060)))
        }

        #expect(count == 1)
    }

    @Test func anUnchangedFailureListIsNotRepublished() throws {
        let app = try makeApp()
        app.refreshFailures()

        // Nothing has failed, and nothing failed on any of these passes either.
        let count = changes(on: app) {
            for _ in 0..<8 { app.refreshFailures() }
        }

        #expect(count == 0)
    }
}
