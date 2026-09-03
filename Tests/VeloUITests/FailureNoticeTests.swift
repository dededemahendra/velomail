import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct FailureNoticeTests {
    /// The presenter refuses to touch `UNUserNotificationCenter` without a
    /// bundle identifier, which a test runner has not got. What is testable
    /// here is the bookkeeping: which failures it considers new.
    private func presenter(test: String = #function) -> NotificationPresenter {
        NotificationPresenter(defaults: scratchDefaults(test: test))
    }

    private func failure(_ id: Int64, subject: String = "Revised invoice") -> MailFailure {
        MailFailure(id: id, kind: .send, subject: subject, attempts: 5, draft: nil)
    }

    @Test func aFailureIsAnnouncedOnce() {
        // It stays in the queue until dealt with, and a fresh banner on every
        // sync tick would be a punishment rather than a warning.
        let presenter = presenter()
        #expect(presenter.newFailures(among: [failure(1)]).map(\.id) == [1])
        #expect(presenter.newFailures(among: [failure(1)]).isEmpty)
    }

    @Test func aSecondFailureIsStillAnnounced() {
        let presenter = presenter()
        _ = presenter.newFailures(among: [failure(1)])
        #expect(presenter.newFailures(among: [failure(1), failure(2)]).map(\.id) == [2])
    }

    @Test func aRetriedSendThatFailsAgainSaysSoAgain() {
        // Forgotten once it leaves the queue, so the second failure is not
        // mistaken for the one already reported.
        let presenter = presenter()
        _ = presenter.newFailures(among: [failure(1)])
        _ = presenter.newFailures(among: [])
        #expect(presenter.newFailures(among: [failure(1)]).map(\.id) == [1])
    }

    @Test func anEmptyQueueAnnouncesNothing() {
        #expect(presenter().newFailures(among: []).isEmpty)
    }

    @Test func theBannerNamesTheMessage() {
        #expect(NotificationPresenter.failureBody(failure(1)) == "Revised invoice")
    }

    @Test func aSubjectlessOneStillSaysSomething() {
        #expect(NotificationPresenter.failureBody(failure(1, subject: ""))
                == "A message could not be sent")
    }
}
