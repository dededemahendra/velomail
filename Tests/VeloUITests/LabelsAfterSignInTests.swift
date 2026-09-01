import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

/// Labels were read once, in `start()`, behind a guard that requires being
/// signed in already. Since the Keychain read moved off the main actor so the
/// window could draw, that guard is false on essentially every launch: the app
/// starts signed out, `start()` returns early, authorisation resolves a moment
/// later, and `setSignedIn(true)` reloads the inbox and nothing else.
///
/// The result was silent. Mail arrived, the list filled, and `labels` stayed
/// empty for the whole session -- so no label chip on any row, nothing to
/// browse under `g l`, and no "Remove from ..." in the palette. Confirmed on
/// the running app by logging what each row was handed: `labels=[]`, every row.
@MainActor
@Suite struct LabelsAfterSignInTests {
    private func makeApp(signedIn: Bool) throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.replaceLabels([
            MailLabel(id: "CATEGORY_UPDATES", name: "CATEGORY_UPDATES", kind: .system),
            MailLabel(id: "Label_7", name: "Clients", kind: .user),
            MailLabel(id: "INBOX", name: "INBOX", kind: .system),
        ])
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: signedIn)
        try app.start()
        return app
    }

    @Test func signingInAfterLaunchLoadsTheLabels() throws {
        let app = try makeApp(signedIn: false)
        #expect(app.labels.isEmpty, "nothing to read before sign-in")

        app.setSignedIn(true)

        #expect(app.labels.map(\.displayName).sorted() == ["Clients", "Updates"])
    }

    /// The other two things `start()` does once it can show mail.
    @Test func signingInAlsoPicksUpFailuresAndTheImagePreference() throws {
        let app = try makeApp(signedIn: false)
        app.setSignedIn(true)

        #expect(app.route == .list)
        #expect(app.alwaysLoadsImages == app.preferences.loadsRemoteImages)
    }

    /// An app that was signed in at launch keeps working as it did.
    @Test func launchingAlreadySignedInStillLoadsThem() throws {
        let app = try makeApp(signedIn: true)
        #expect(app.labels.map(\.displayName).sorted() == ["Clients", "Updates"])
    }

    /// Signing out and back in must not leave them stale or doubled.
    @Test func signingOutAndBackInLeavesOneCopy() throws {
        let app = try makeApp(signedIn: true)
        app.setSignedIn(false)
        app.setSignedIn(true)

        #expect(app.labels.map(\.displayName).sorted() == ["Clients", "Updates"])
    }
}
