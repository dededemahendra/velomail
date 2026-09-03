import Testing
import Foundation
@testable import VeloUI

/// Reported as notifications not working. They were not: nothing was ever new
/// enough to announce.
///
/// The high-water mark -- the date past which mail counts as new -- was kept
/// under one key for the whole app. With more than one mailbox that is a shared
/// clock: whichever account synced last pushed the mark to its newest message,
/// and every message in every *other* account was then older than it. On the
/// real machine the mark stood at 2026-09-03 03:19 while the open account's
/// newest mail was 2026-09-01 02:11, so nothing in it could ever qualify again.
///
/// A mark is a fact about a mailbox, not about the app.
@MainActor
@Suite struct AnnouncementMarkTests {
    private func presenter(_ account: String, _ defaults: UserDefaults) -> NotificationPresenter {
        let presenter = NotificationPresenter(defaults: defaults)
        presenter.accountID = account
        return presenter
    }

    @Test func eachMailboxKeepsItsOwnMark() {
        let defaults = UserDefaults(suiteName: "velo.mark.\(UUID())")!
        let busy = presenter("busy", defaults)
        let quiet = presenter("quiet", defaults)

        busy.announcedThrough = Date(timeIntervalSince1970: 2_000_000)

        #expect(quiet.announcedThrough == nil,
                "one mailbox syncing silenced another")
    }

    @Test func aMarkSurvivesSwitchingAwayAndBack() {
        let defaults = UserDefaults(suiteName: "velo.mark.\(UUID())")!
        let moment = Date(timeIntervalSince1970: 1_500_000)
        presenter("a", defaults).announcedThrough = moment
        presenter("b", defaults).announcedThrough = Date(timeIntervalSince1970: 9_000_000)

        #expect(presenter("a", defaults).announcedThrough == moment)
    }

    /// A mailbox with no mark yet is a first run, and `MailAnnouncer` is
    /// deliberately silent on those -- so a fresh mark per account cannot
    /// produce a burst of banners for mail that arrived while you were away.
    @Test func aMailboxWithNoMarkYetStartsWithoutOne() {
        let defaults = UserDefaults(suiteName: "velo.mark.\(UUID())")!
        #expect(presenter("new", defaults).announcedThrough == nil)
    }
}
