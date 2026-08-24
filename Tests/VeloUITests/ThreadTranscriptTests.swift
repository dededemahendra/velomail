import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct ThreadTranscriptTests {
    private func messages(_ ids: [String], thread: String = "t") -> [Message] {
        ids.enumerated().map { index, id in
            Message(id: id, threadID: thread, sender: "a@b.com", recipients: [],
                    subject: "s", date: Date(timeIntervalSince1970: TimeInterval(index)),
                    bodyHTML: nil, bodyText: "body \(id)", isUnread: false, labelIDs: [])
        }
    }

    @Test func theNewestMessageStartsExpanded() {
        var transcript = ThreadTranscript()
        transcript.sync(threadID: "t", messages: messages(["m1", "m2", "m3"]))
        #expect(transcript.isExpanded("m3"))
    }

    @Test func olderMessagesStartCollapsed() {
        var transcript = ThreadTranscript()
        transcript.sync(threadID: "t", messages: messages(["m1", "m2", "m3"]))
        #expect(!transcript.isExpanded("m1"))
        #expect(!transcript.isExpanded("m2"))
    }

    @Test func aSingleMessageThreadIsExpanded() {
        var transcript = ThreadTranscript()
        transcript.sync(threadID: "t", messages: messages(["only"]))
        #expect(transcript.isExpanded("only"))
    }

    @Test func togglingExpandsAndCollapses() {
        var transcript = ThreadTranscript()
        transcript.sync(threadID: "t", messages: messages(["m1", "m2"]))

        transcript.toggle("m1")
        #expect(transcript.isExpanded("m1"))
        transcript.toggle("m1")
        #expect(!transcript.isExpanded("m1"))
    }

    @Test func changingThreadResetsExpansion() {
        var transcript = ThreadTranscript()
        transcript.sync(threadID: "t", messages: messages(["m1", "m2"]))
        transcript.toggle("m1")

        transcript.sync(threadID: "other", messages: messages(["n1", "n2"], thread: "other"))

        // Expansion must not leak from the previous conversation.
        #expect(!transcript.isExpanded("m1"))
        #expect(transcript.isExpanded("n2"))
    }

    @Test func resyncingTheSameThreadKeepsWhatTheUserOpened() {
        var transcript = ThreadTranscript()
        transcript.sync(threadID: "t", messages: messages(["m1", "m2"]))
        transcript.toggle("m1")

        // Background sync repaints the same thread; the user's expansion stays.
        transcript.sync(threadID: "t", messages: messages(["m1", "m2"]))

        #expect(transcript.isExpanded("m1"))
    }

    @Test func anEmptyThreadExpandsNothing() {
        var transcript = ThreadTranscript()
        transcript.sync(threadID: "t", messages: [])
        #expect(!transcript.isExpanded("anything"))
    }

    @Test func aNewMessageArrivingInTheOpenThreadExpands() {
        var transcript = ThreadTranscript()
        transcript.sync(threadID: "t", messages: messages(["m1", "m2"]))

        // A reply lands while the thread is open; it is what you want to read.
        transcript.sync(threadID: "t", messages: messages(["m1", "m2", "m3"]))

        #expect(transcript.isExpanded("m3"))
    }
}
