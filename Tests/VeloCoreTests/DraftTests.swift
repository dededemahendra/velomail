import Testing
import Foundation
@testable import VeloCore

private func parent(
    sender: String = "Alice <alice@example.com>",
    recipients: [String] = ["me@example.com"],
    cc: [String] = [],
    subject: String = "Lunch",
    messageID: String? = "<parent@mail.example.com>",
    references: [String] = []
) -> Message {
    Message(id: "m1", threadID: "t1", sender: sender, recipients: recipients,
            cc: cc, subject: subject, date: Date(timeIntervalSince1970: 100),
            bodyHTML: nil, bodyText: "hi", isUnread: false, labelIDs: ["INBOX"],
            messageIDHeader: messageID, inReplyTo: nil, references: references)
}

@Suite struct DraftTests {
    @Test func replyAddressesTheSenderAndKeepsTheThread() {
        let draft = Draft.reply(to: parent(), from: "me@example.com")
        #expect(draft.to == ["Alice <alice@example.com>"])
        #expect(draft.cc == [])
        #expect(draft.threadID == "t1")
    }

    @Test func replyPrefixesSubjectWithRe() {
        #expect(Draft.reply(to: parent(subject: "Lunch"), from: "me@example.com").subject == "Re: Lunch")
    }

    @Test func replyDoesNotDoublePrefixAnExistingRe() {
        #expect(Draft.reply(to: parent(subject: "Re: Lunch"), from: "me@example.com").subject == "Re: Lunch")
        #expect(Draft.reply(to: parent(subject: "RE: Lunch"), from: "me@example.com").subject == "RE: Lunch")
    }

    @Test func replyChainsReferencesFromParent() {
        let draft = Draft.reply(
            to: parent(messageID: "<parent@x.com>", references: ["<root@x.com>"]),
            from: "me@example.com")
        #expect(draft.inReplyTo == "<parent@x.com>")
        #expect(draft.references == ["<root@x.com>", "<parent@x.com>"])
    }

    @Test func replyToMessageWithoutMessageIDLeavesInReplyToNil() {
        let draft = Draft.reply(to: parent(messageID: nil), from: "me@example.com")
        #expect(draft.inReplyTo == nil)
        #expect(draft.references == [])
    }

    @Test func replyAllCarriesOtherRecipientsToCcExcludingSelf() {
        let draft = Draft.replyAll(
            to: parent(recipients: ["me@example.com", "Bob <bob@example.com>"],
                       cc: ["carol@example.com"]),
            from: "me@example.com")
        #expect(draft.to == ["Alice <alice@example.com>"])
        #expect(draft.cc == ["Bob <bob@example.com>", "carol@example.com"])
    }

    @Test func replyAllExcludesSelfEvenWhenHeaderCarriesADisplayName() {
        let draft = Draft.replyAll(
            to: parent(recipients: ["Me Myself <ME@Example.com>", "bob@example.com"]),
            from: "me@example.com")
        #expect(draft.cc == ["bob@example.com"])
    }

    @Test func replyAllDoesNotRepeatTheSenderInCc() {
        let draft = Draft.replyAll(
            to: parent(sender: "alice@example.com", recipients: ["me@example.com", "alice@example.com"]),
            from: "me@example.com")
        #expect(draft.to == ["alice@example.com"])
        #expect(draft.cc == [])
    }

    @Test func newComposeHasNoThreadOrReplyHeaders() {
        let draft = Draft(to: ["a@b.com"], subject: "Hello", bodyText: "hi")
        #expect(draft.threadID == nil)
        #expect(draft.inReplyTo == nil)
        #expect(draft.references == [])
        #expect(draft.bcc == [])
    }

    @Test func quotingIsOptInAndOffByDefault() {
        // The engine should not impose composition policy on every caller.
        #expect(Draft.reply(to: parent(), from: "me@example.com").bodyText == "")
    }

    @Test func replyCanQuoteTheParent() {
        let draft = Draft.reply(to: parent(), from: "me@example.com",
                                bodyText: "Sure.", quoting: true)
        #expect(draft.bodyText.hasPrefix("Sure."))
        #expect(draft.bodyText.contains("wrote:"))
        #expect(draft.bodyText.contains("> hi"))
    }

    @Test func replyAllCanQuoteTheParentToo() {
        let draft = Draft.replyAll(to: parent(), from: "me@example.com", quoting: true)
        #expect(draft.bodyText.contains("wrote:"))
    }

    @Test func quotingAlsoBuildsAnHTMLBodyWhenTheParentHasOne() {
        let html = Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                           subject: "s", date: Date(timeIntervalSince1970: 100),
                           bodyHTML: "<p>rich</p>", bodyText: "rich",
                           isUnread: false, labelIDs: [], messageIDHeader: "<p@x>")
        let draft = Draft.reply(to: html, from: "me@example.com", bodyText: "ok", quoting: true)
        #expect(draft.bodyHTML?.contains("<blockquote") == true)
        #expect(draft.bodyHTML?.contains("<p>rich</p>") == true)
    }
}
