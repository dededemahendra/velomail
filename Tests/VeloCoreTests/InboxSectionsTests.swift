import Testing
import Foundation
@testable import VeloCore

@Suite struct InboxSectionsTests {
    private func thread(_ id: String, labels: [String] = ["INBOX"], at seconds: TimeInterval = 0) -> MailThread {
        MailThread(id: id, snippet: id, lastMessageDate: Date(timeIntervalSince1970: seconds),
                   isUnread: false, hasAttachments: false, labelIDs: labels)
    }

    @Test func starredThreadsGoToImportant() {
        let sections = InboxSections.split([thread("a", labels: ["INBOX", "STARRED"]), thread("b")])

        #expect(sections.first?.title == "Important")
        #expect(sections.first?.threads.map(\.id) == ["a"])
    }

    @Test func gmailsImportantLabelAlsoCounts() {
        // Importance comes from Gmail, not from a heuristic we invent.
        let sections = InboxSections.split([thread("a", labels: ["INBOX", "IMPORTANT"]), thread("b")])

        #expect(sections.first?.threads.map(\.id) == ["a"])
    }

    @Test func aThreadThatIsBothAppearsOnlyOnce() {
        let sections = InboxSections.split([thread("a", labels: ["INBOX", "STARRED", "IMPORTANT"])])

        #expect(sections.count == 1)
        #expect(sections[0].threads.map(\.id) == ["a"])
    }

    @Test func everythingElseGoesToOther() {
        let sections = InboxSections.split([thread("a", labels: ["INBOX", "STARRED"]),
                                            thread("b"), thread("c")])

        #expect(sections.map(\.title) == ["Important", "Other"])
        #expect(sections[1].threads.map(\.id) == ["b", "c"])
    }

    @Test func orderWithinASectionIsPreserved() {
        let sections = InboxSections.split([thread("a", labels: ["INBOX", "STARRED"]),
                                            thread("b"),
                                            thread("c", labels: ["INBOX", "IMPORTANT"]),
                                            thread("d")])

        // The inbox is already newest-first; grouping must not re-sort inside a
        // group as well as between groups.
        #expect(sections[0].threads.map(\.id) == ["a", "c"])
        #expect(sections[1].threads.map(\.id) == ["b", "d"])
    }

    @Test func flattenedSectionsAreTheCursorOrder() {
        let threads = [thread("a"), thread("b", labels: ["INBOX", "STARRED"]), thread("c")]

        let flattened = InboxSections.split(threads).flatMap(\.threads)

        // The sections concatenate back into one flat display order, so the
        // cursor stays flat and j/k cross a boundary without knowing one exists.
        #expect(flattened.map(\.id) == ["b", "a", "c"])
        #expect(flattened.count == threads.count)
        #expect(InboxSections.ordered(threads).map(\.id) == ["b", "a", "c"])
    }

    @Test func orderingIsIdempotentSoTheFlatListIsStable() {
        let threads = [thread("a"), thread("b", labels: ["INBOX", "STARRED"]), thread("c")]
        let once = InboxSections.ordered(threads)

        // The view model stores the ordered list, so splitting it again must not
        // move anything, or the cursor index and the row on screen would drift.
        #expect(InboxSections.ordered(once).map(\.id) == once.map(\.id))
    }

    @Test func anEmptySectionIsOmitted() {
        let sections = InboxSections.split([thread("a", labels: ["INBOX", "STARRED"])])

        // A mailbox with nothing unimportant is not shown an empty "Other".
        #expect(sections.map(\.title) == ["Important"])
    }

    @Test func noThreadsGivesNoSections() {
        #expect(InboxSections.split([]).isEmpty)
    }

    @Test func aFlatInboxWithNothingImportantIsOneSection() {
        let sections = InboxSections.split([thread("a"), thread("b")])

        // Looks like the flat list it was before, which is the point.
        #expect(sections.map(\.title) == ["Other"])
        #expect(sections[0].threads.map(\.id) == ["a", "b"])
    }
}
