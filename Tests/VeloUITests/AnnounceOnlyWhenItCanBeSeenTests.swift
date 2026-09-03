import Testing
import Foundation
@testable import VeloUI
@testable import VeloCore

/// The launch-time batch of new mail was being eaten.
///
/// `observeInbox` delivers its first value immediately, which happens while
/// `requestAuthorizationIfNeeded` is still suspended on its await. The announce
/// that ran in that window presented nothing -- `present` bails when it is not
/// yet authorised -- and then advanced the high-water mark anyway. The mail was
/// marked as announced without ever being shown, and the next pass had nothing
/// left to say.
///
/// It is the worst batch to lose: everything that arrived while the app was
/// closed, every launch.
@MainActor @Suite struct AnnounceOnlyWhenItCanBeSeenTests {
    private func presenter(test: String = #function) -> NotificationPresenter {
        NotificationPresenter(defaults: scratchDefaults(test: test))
    }

    private func result(at date: Date) -> MailAnnouncer.Result {
        MailAnnouncer.Result(
            items: [.init(title: "Alice", subtitle: "Lunch?", threadID: "t1")],
            additionalCount: 0,
            highWaterMark: date)
    }

    @Test func nothingIsConsumedBeforeTheCentreHasAnswered() {
        let presenter = presenter()
        let start = Date(timeIntervalSince1970: 1_000)
        presenter.announcedThrough = start

        presenter.announce(result(at: start.addingTimeInterval(60)))

        #expect(presenter.announcedThrough == start,
                "mail was marked as announced while the app still could not post")
    }

    @Test func theMarkAdvancesOnceItHas() async {
        let presenter = presenter()
        let start = Date(timeIntervalSince1970: 1_000)
        presenter.announcedThrough = start
        // In a test runner there is no notification centre, so this settles as
        // a refusal -- which is still an answer, and still lets the app move on.
        await presenter.requestAuthorizationIfNeeded()

        let later = start.addingTimeInterval(60)
        presenter.announce(result(at: later))

        #expect(presenter.announcedThrough == later)
    }

    @Test func anUnaskedPresenterIsNotSettledAndAnAskedOneIs() async {
        let presenter = presenter()
        #expect(!presenter.isAuthorizationSettled)
        await presenter.requestAuthorizationIfNeeded()
        #expect(presenter.isAuthorizationSettled)
    }
}
