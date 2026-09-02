import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

/// "Sync now" existed only in the command palette: no key, and nothing to
/// click. The poll loop backs off further after every failure, so the only way
/// to make it try again was to quit the app.
@MainActor
@Suite struct SyncButtonTests {
    private func makeApp(canSync: Bool) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let outbound = OutboundService(writer: Quiet(), store: store,
                                       mutations: MutationStore(db), identity: "me@x.com")
        let config = AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil)
        let app = canSync
            ? AppViewModel(config: config, store: store, outbound: outbound,
                           identity: "me@x.com", isSignedIn: true, syncNow: { })
            : AppViewModel(config: config, store: store, outbound: outbound,
                           identity: "me@x.com", isSignedIn: true)
        try app.start()
        return app
    }

    @Test func thereIsSomethingToPressWhenThereIsAnAccountBehindIt() throws {
        #expect(try makeApp(canSync: true).canSyncByHand)
    }

    /// A button that does nothing when pressed is worse than no button. Demo
    /// mode has no engine, and `syncMailNow` returns immediately.
    @Test func nothingIsOfferedWhenThereIsNoEngine() throws {
        #expect(try makeApp(canSync: false).canSyncByHand == false)
    }

    @Test func pressingItSaysSomethingHappened() async throws {
        let app = try makeApp(canSync: true)
        await app.syncMailNow()
        #expect(app.notice == "Up to date")
    }

    /// A failed pass can leave the list looking untouched, so the press has to
    /// be confirmed either way -- otherwise it reads as a dead button.
    @Test func aFailedPassStillConfirmsThePress() async throws {
        struct Boom: Error {}
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, syncNow: { throw Boom() })
        try app.start()

        await app.syncMailNow()

        #expect(app.notice == "Could not reach Gmail")
    }
}
