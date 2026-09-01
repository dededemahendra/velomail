import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

/// Clicking an address in a message opened whatever the system considers the
/// default mail client. In a mail client that is a strange thing to do: the
/// composer is already in front of the reader.
@MainActor
@Suite struct ComposeFromMailtoTests {
    private func makeApp() throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true)
        try app.start()
        return app
    }

    private func link(_ address: String) throws -> MailtoLink {
        try #require(URL(string: address).flatMap(MailtoLink.init(url:)))
    }

    @Test func followingAMailtoOpensTheComposerAddressedToThem() throws {
        let app = try makeApp()

        app.startMessage(from: try link("mailto:peta@wellingtondam.org.au"))

        #expect(app.route == .compose)
        #expect(app.compose.to == "peta@wellingtondam.org.au")
    }

    /// An unsubscribe link is routinely `mailto:leave@list?subject=unsubscribe`,
    /// and a message sent without that subject does nothing at all.
    @Test func theSubjectAndBodyComeWithIt() throws {
        let app = try makeApp()

        app.startMessage(from: try link("mailto:list@x.com?subject=unsubscribe&body=remove%20me"))

        #expect(app.compose.subject == "unsubscribe")
        #expect(app.compose.body == "remove me")
    }

    @Test func severalRecipientsAndACcAreCarried() throws {
        let app = try makeApp()

        app.startMessage(from: try link("mailto:a@x.com,b@y.com?cc=c@z.com"))

        #expect(app.compose.to == "a@x.com, b@y.com")
        #expect(app.compose.cc == "c@z.com")
    }

    /// `mailto:?subject=...` carries no recipient and is still worth opening --
    /// the reader fills in who.
    @Test func aLinkWithNoRecipientStillOpensTheComposer() throws {
        let app = try makeApp()

        app.startMessage(from: try link("mailto:?subject=Look%20at%20this"))

        #expect(app.route == .compose)
        #expect(app.compose.to.isEmpty)
        #expect(app.compose.subject == "Look at this")
    }

    /// It must not quietly continue whatever was half-written before.
    @Test func itStartsAFreshMessageRatherThanEditingTheLastOne() throws {
        let app = try makeApp()
        app.compose.startNew()
        app.compose.to = "someone-else@x.com"
        app.compose.subject = "Half written"

        app.startMessage(from: try link("mailto:new@x.com"))

        #expect(app.compose.to == "new@x.com")
        #expect(app.compose.subject.isEmpty)
    }
}
