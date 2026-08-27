import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct RowAccessibilityTests {
    private func thread(sender: String = "Peta Bilston",
                        snippet: String = "Covenant paperwork",
                        unread: Bool = false, attachments: Bool = false,
                        starred: Bool = false) -> MailThread {
        MailThread(id: "t", sender: sender, snippet: snippet,
                   lastMessageDate: Date(timeIntervalSince1970: 1_787_000_000),
                   isUnread: unread, hasAttachments: attachments,
                   labelIDs: starred ? ["STARRED"] : [])
    }

    private func spoken(_ thread: MailThread, name: String = "Peta Bilston",
                        date: String = "18 Aug") -> String {
        MailFormatting.rowDescription(thread, name: name, date: date)
    }

    // MARK: - What a row says out loud

    @Test func aRowNamesWhoItIsFromAndWhatItSays() {
        // Read as one sentence rather than four unlabelled fields, which is
        // what a stack of text views is without this.
        let description = spoken(thread())
        #expect(description.contains("Peta Bilston"))
        #expect(description.contains("Covenant paperwork"))
        #expect(description.contains("18 Aug"))
    }

    @Test func unreadIsSaidFirst() {
        // It is the thing that decides whether to keep listening.
        #expect(spoken(thread(unread: true)).hasPrefix("Unread"))
    }

    @Test func aReadMessageDoesNotAnnounceThat() {
        // Saying "read" on every row is noise on the great majority of them.
        #expect(!spoken(thread()).lowercased().contains("read,"))
    }

    @Test func anAttachmentIsMentioned() {
        // It is drawn as a paperclip, which says nothing at all out loud.
        #expect(spoken(thread(attachments: true)).contains("attachment"))
    }

    @Test func aStarIsMentioned() {
        #expect(spoken(thread(starred: true)).lowercased().contains("starred"))
    }

    @Test func anOrdinaryRowMentionsNeither() {
        let description = spoken(thread())
        #expect(!description.contains("attachment"))
        #expect(!description.lowercased().contains("starred"))
    }

    @Test func everythingAtOnceStillReadsAsASentence() {
        let description = spoken(thread(unread: true, attachments: true, starred: true))
        #expect(description ==
                "Unread, starred, from Peta Bilston, Covenant paperwork, has attachment, 18 Aug")
    }

    @Test func theNameGivenIsTheOneUsed() {
        // In Sent the row is about the recipient, and it should be read that way.
        #expect(spoken(thread(), name: "Bob").contains("from Bob"))
    }
}
