import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct ThreadViewTests {
    private func message(_ id: String, listUnsubscribe: String? = nil) -> Message {
        Message(id: id, threadID: "t", sender: "news@example.com", recipients: [],
                subject: "Weekly", date: Date(timeIntervalSince1970: 0),
                bodyHTML: nil, bodyText: "news", isUnread: false, labelIDs: [],
                listUnsubscribe: listUnsubscribe)
    }

    @Test func aThreadWithAnUnsubscribeHeaderOffersTheAffordance() {
        #expect(ThreadView.canUnsubscribe(from: [message("m", listUnsubscribe: "<mailto:l@x.com>")]))
    }

    @Test func ordinaryMailOffersNothing() {
        // A button that is always there and usually does nothing is worse than
        // no button.
        #expect(!ThreadView.canUnsubscribe(from: [message("m")]))
    }

    @Test func anyMessageInTheThreadIsEnough() {
        #expect(ThreadView.canUnsubscribe(from: [message("old"),
                                                 message("new", listUnsubscribe: "<mailto:l@x.com>")]))
    }

    @Test func aHeaderWithNothingUsableOffersNothing() {
        // Parsed, not merely present: a header we cannot act on must not put a
        // button on screen that does nothing when pressed.
        #expect(!ThreadView.canUnsubscribe(from: [message("m", listUnsubscribe: "<ftp://x/u>")]))
    }

    @Test func anEmptyThreadOffersNothing() {
        #expect(!ThreadView.canUnsubscribe(from: []))
    }
}
