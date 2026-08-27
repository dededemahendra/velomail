import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct AIUnconfiguredTests {
    private func makeApp() throws -> AppViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.upsert(MailThread(id: "t0", sender: "a@x.com", snippet: "s",
                                    lastMessageDate: Date(), isUnread: false,
                                    hasAttachments: false, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m0", threadID: "t0", sender: "a@x.com",
                                 recipients: ["me@x.com"], subject: "s", date: Date(),
                                 bodyHTML: nil, bodyText: "b", isUnread: false,
                                 labelIDs: ["INBOX"]))
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true,
            // No provider, which is a supported state.
            assistant: MailAssistant(provider: nil))
        try app.start()
        return app
    }

    @Test func anAIKeystrokeIsAnswered() throws {
        // The palette hides these when no provider is configured, but the
        // chords stay bound. A key that does nothing at all reads as a broken
        // key rather than as a missing setting.
        let app = try makeApp()
        app.handle(KeyInput(.character("a")))
        app.handle(KeyInput(.character("s")))
        #expect(app.notice?.contains("AI is not set up") == true)
    }

    @Test func everyAIChordSaysIt() throws {
        for second in Array("srt") {
            let app = try makeApp()
            app.handle(KeyInput(.character("a")))
            app.handle(KeyInput(.character(second)))
            #expect(app.notice != nil, "a \(second) said nothing")
        }
    }

    @Test func theInertCommandIsNotOfferedAtAll() throws {
        // "Write a Reply" was missing from isAI, so it stayed in the palette
        // with no provider and did nothing when run.
        let app = try makeApp()
        #expect(!app.palette.commands.map(\.title).contains("Write a Reply"))
    }

    @Test func everyAssistantCommandIsTreatedAsOne() {
        for action in [MailAction.summarizeThread, .suggestReplies,
                       .triageThread, .draftReplyWithAI] {
            #expect(action.isAI, "\(action) is not counted as an AI command")
        }
    }

    @Test func runningItAnywayStillSaysSomething() throws {
        let app = try makeApp()
        app.perform(.draftReplyWithAI)
        #expect(app.notice?.contains("AI is not set up") == true)
    }

    @Test func noSelectionStaysSilent() throws {
        // That one is a state you can see for yourself.
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true,
            assistant: MailAssistant(provider: StubProvider()))
        try app.start()
        app.perform(.summarizeThread)
        #expect(app.notice == nil)
    }
}

private struct StubProvider: LLMProvider {
    var displayName: String { "stub" }
    func complete(_ request: LLMRequest) async throws -> String { "" }
}
