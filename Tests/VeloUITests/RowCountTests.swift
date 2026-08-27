import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct RowCountTests {
    @Test func aThreadOfOneSaysNothingAboutItsLength() {
        #expect(MailFormatting.threadCount(1) == nil)
    }

    @Test func alongerThreadSaysHowLong() {
        // A twelve-message thread and a one-message thread looked identical.
        #expect(MailFormatting.threadCount(12) == "12")
    }

    @Test func mailWrittenToYouAloneIsMarked() {
        // Not the same object as mail copied to forty, and the list gave no
        // way to tell them apart.
        #expect(MailFormatting.isToYouAlone(recipientCount: 1))
        #expect(!MailFormatting.isToYouAlone(recipientCount: 8))
    }

    @Test func aThreadWithNoRecipientsRecordedIsNotClaimedAsDirect() {
        // Zero is "we do not know", not "nobody": rows written before the
        // column existed default to it.
        #expect(!MailFormatting.isToYouAlone(recipientCount: 0))
    }

    @Test func aListenerHearsBothFacts() {
        let thread = MailThread(id: "t", sender: "a@b.com", snippet: "hi",
                                lastMessageDate: Date(), isUnread: true, hasAttachments: false,
                                labelIDs: [], messageCount: 4, recipientCount: 1)
        let spoken = MailFormatting.rowDescription(thread, name: "Peta", date: "17.28")
        #expect(spoken.contains("4 messages"))
        #expect(spoken.contains("to you only"))
    }

    @Test func aQuietRowSaysNeither() {
        let thread = MailThread(id: "t", sender: "a@b.com", snippet: "hi",
                                lastMessageDate: Date(), isUnread: false, hasAttachments: false,
                                labelIDs: [], messageCount: 1, recipientCount: 9)
        let spoken = MailFormatting.rowDescription(thread, name: "Peta", date: "17.28")
        #expect(!spoken.contains("messages"))
        #expect(!spoken.contains("to you only"))
    }
}
