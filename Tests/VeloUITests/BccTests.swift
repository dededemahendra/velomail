import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct BccTests {
    private func makeContext() throws -> (ComposeViewModel, MutationStore, DraftStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let drafts = DraftStore(db)
        let outbound = OutboundService(writer: SilentWriter(), store: store,
                                       mutations: mutations, identity: "me@x.com")
        return (ComposeViewModel(outbound: outbound, identity: "me@x.com", drafts: drafts),
                mutations, drafts)
    }

    private func sent(_ model: ComposeViewModel, _ mutations: MutationStore) throws -> QueuedBcc.Draft {
        try model.send()
        return try JSONDecoder().decode(
            QueuedBcc.self, from: try #require(try mutations.all().first).payload).draft
    }

    @Test func aBlindCopyReachesTheDraft() throws {
        let (model, mutations, _) = try makeContext()
        model.startNew()
        model.to = "bob@x.com"
        model.bcc = "quiet@x.com"
        model.subject = "s"

        #expect(try sent(model, mutations).bcc == ["quiet@x.com"])
    }

    @Test func severalBlindCopiesAreSplitLikeTheOtherFields() throws {
        let (model, mutations, _) = try makeContext()
        model.startNew()
        model.to = "bob@x.com"
        model.bcc = "one@x.com, Two <two@x.com>"
        model.subject = "s"

        #expect(try sent(model, mutations).bcc == ["one@x.com", "Two <two@x.com>"])
    }

    @Test func anEmptyFieldAddsNoRecipients() throws {
        let (model, mutations, _) = try makeContext()
        model.startNew()
        model.to = "bob@x.com"
        model.subject = "s"

        #expect(try sent(model, mutations).bcc.isEmpty)
    }

    @Test func aBlindCopySurvivesLeavingAndResuming() throws {
        // Losing it on resume would send the message to fewer people than the
        // writer thought, silently.
        let (model, _, _) = try makeContext()
        model.startNew()
        model.to = "bob@x.com"
        model.bcc = "quiet@x.com"
        model.autosave()

        model.startNew()
        model.resumeDraft()

        #expect(model.bcc == "quiet@x.com")
    }

    @Test func startingFreshClearsIt() throws {
        let (model, _, _) = try makeContext()
        model.bcc = "quiet@x.com"
        model.startNew()
        #expect(model.bcc.isEmpty)
    }

    @Test func aBlindCopyIsNotAddedToAReplysVisibleRecipients() throws {
        let (model, mutations, _) = try makeContext()
        model.startNew()
        model.to = "bob@x.com"
        model.cc = "cc@x.com"
        model.bcc = "quiet@x.com"
        model.subject = "s"

        let draft = try sent(model, mutations)
        #expect(draft.to == ["bob@x.com"])
        #expect(draft.cc == ["cc@x.com"])
        #expect(draft.bcc == ["quiet@x.com"])
    }
}

private struct QueuedBcc: Decodable {
    struct Draft: Decodable {
        let to: [String]
        let cc: [String]
        let bcc: [String]
    }
    let draft: Draft
}
