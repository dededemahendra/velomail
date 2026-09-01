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


    // MARK: - Replying to your own message

    /// Observed live: reply-all on a message the reader had sent produced a
    /// draft addressed *to the reader*, from the reader. `to` was always
    /// `[message.sender]`, and `reply` discarded its `from` argument entirely
    /// -- the parameter was named `_` in the signature.
    ///
    /// Continuing a conversation you spoke last in means writing to the people
    /// you wrote to, not to yourself.

    @Test func replyingToYourOwnMessageWritesToThePeopleYouWroteTo() {
        let mine = parent(sender: "Me <me@example.com>",
                          recipients: ["Gede <gede@example.com>"])

        let draft = Draft.reply(to: mine, from: "me@example.com")

        #expect(draft.to == ["Gede <gede@example.com>"])
        #expect(!draft.to.contains { $0.contains("me@example.com") })
    }

    @Test func replyAllOnYourOwnMessageKeepsTheOriginalAudienceAndDropsYou() {
        let mine = parent(sender: "Me <me@example.com>",
                          recipients: ["Gede <gede@example.com>"],
                          cc: ["Warren <warren@example.com>", "me@example.com"])

        let draft = Draft.replyAll(to: mine, from: "me@example.com")

        #expect(draft.to == ["Gede <gede@example.com>"])
        #expect(draft.cc == ["Warren <warren@example.com>"])
        let everyone = draft.to + draft.cc
        #expect(!everyone.contains { $0.lowercased().contains("me@example.com") })
    }

    /// The identity is matched by bare address, so a display name on the
    /// sending header must not defeat it.
    @Test func yourOwnMessageIsRecognisedThroughADisplayName() {
        let mine = parent(sender: "\"Roberts, Me\" <me@example.com>",
                          recipients: ["Gede <gede@example.com>"])

        #expect(Draft.reply(to: mine, from: "Me <me@example.com>").to
                    == ["Gede <gede@example.com>"])
    }

    /// A message you sent to yourself as well as others. `replyAll` promises
    /// "minus the sending identity", and putting yourself back in To means
    /// receiving your own reply.
    @Test func replyAllDropsYouFromToWhenYouWereOneOfYourOwnRecipients() {
        let mine = parent(sender: "Me <me@example.com>",
                          recipients: ["me@example.com", "Gede <gede@example.com>"])

        let draft = Draft.replyAll(to: mine, from: "me@example.com")

        #expect(draft.to == ["Gede <gede@example.com>"])
        #expect(!(draft.to + draft.cc).contains { $0.lowercased().contains("me@example.com") })
    }

    /// Your own message whose `To` is empty and whose real audience is in `Cc`.
    /// The first fix guarded on `recipients.isEmpty` and fell through to the
    /// generic branch, which addresses the sender -- reintroducing exactly the
    /// bug it was written to remove.
    @Test func yourOwnMessageWithOnlyCcRecipientsStillRepliesToThem() {
        let mine = parent(sender: "Me <me@example.com>", recipients: [],
                          cc: ["Bob <bob@example.com>"])

        #expect(Draft.reply(to: mine, from: "me@example.com").to
                    == ["Bob <bob@example.com>"])
    }

    /// Your own message addressed to yourself and copied to somebody real. The
    /// `To` is non-empty, so the guard passed, but every name in it was you --
    /// and the fallback then put you back in `To` and dropped Bob from a plain
    /// reply entirely.
    @Test func yourOwnMessageToYourselfCopyingSomebodyRepliesToThem() {
        let mine = parent(sender: "Me <me@example.com>",
                          recipients: ["me@example.com"],
                          cc: ["Bob <bob@example.com>"])

        let draft = Draft.reply(to: mine, from: "me@example.com")
        #expect(draft.to == ["Bob <bob@example.com>"])

        let all = Draft.replyAll(to: mine, from: "me@example.com")
        #expect(all.to == ["Bob <bob@example.com>"])
        #expect(!(all.to + all.cc).contains { $0.lowercased().contains("me@example.com") })
    }

    /// A message you sent to nobody but yourself still has to go somewhere.
    ///
    /// Asserted on the bare address rather than the exact header: "me@example.com"
    /// and "Me <me@example.com>" are the same person, and which one a reply
    /// happens to carry is not a requirement.
    @Test func aMessageOnlyToYourselfStillRepliesToYourself() {
        let mine = parent(sender: "Me <me@example.com>", recipients: ["me@example.com"])

        let draft = Draft.reply(to: mine, from: "me@example.com")
        #expect(draft.to.map(Draft.normalizedAddress) == ["me@example.com"])
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
