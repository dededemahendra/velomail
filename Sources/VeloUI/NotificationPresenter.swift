import Foundation
import AppKit
import UserNotifications
import VeloCore

/// Posts banners and keeps the Dock badge current.
///
/// Deliberately thin: the decision about *what* to announce is `MailAnnouncer`'s
/// and is tested there. This forwards, and degrades quietly when it cannot.
@MainActor
public final class NotificationPresenter {
    /// Where the high-water mark lives.
    ///
    /// `UserDefaults`, not SQLite: "which banners has this Mac already shown" is
    /// a property of the installation, not of the mailbox. It should not sync,
    /// and it should not survive a database rebuild.
    private static let markKey = "VeloMailAnnouncedThrough"

    /// Which mailbox the marks belong to.
    ///
    /// The mark was kept under one key for the whole app, which with more than
    /// one account is a shared clock: whichever mailbox synced last pushed it
    /// to its own newest message, and everything in every other mailbox was
    /// then older than it and could never be announced again. A mark is a fact
    /// about a mailbox.
    public var accountID: String = Account.primaryID

    /// What a banner offers besides being clicked.
    ///
    /// Two, not five: a notification is read in a glance on the way past, and
    /// a row of buttons is a decision you did not ask to make.
    enum Action {
        static let category = "velomail.newMail"
        static let archive = "velomail.archive"
        static let markRead = "velomail.markRead"
    }

    /// How far the notification centre has got with the question.
    private enum Authorization { case unasked, asking, granted, refused }

    private let defaults: UserDefaults
    private var authorization: Authorization = .unasked
    private var isAuthorized: Bool { authorization == .granted }

    /// Whether the centre has answered yet -- granted, refused, or not there at
    /// all. Only "still asking" is unsettled.
    public var isAuthorizationSettled: Bool {
        switch authorization {
        case .unasked, .asking: false
        case .granted, .refused: true
        }
    }
    /// Kept alive here: `UNUserNotificationCenter` holds its delegate weakly,
    /// and a delegate that is collected takes every click with it.
    private var relay: Relay?
    /// Which failures have already been announced, so a message that will not
    /// send does not post a fresh banner on every sync tick.
    private var announcedFailures: Set<Int64> = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Wires up what happens when someone actually uses a banner.
    ///
    /// Without this the `threadID` on every notification was written and never
    /// read: clicking one focused the app and left you wherever you already
    /// were.
    ///
    /// - Parameters:
    ///   - open: put the reader on this thread.
    ///   - archive: file it without opening anything.
    ///   - markRead: clear it without opening anything.
    public func handleActions(open: @escaping (String) -> Void,
                              archive: @escaping (String) -> Void,
                              markRead: @escaping (String) -> Void,
                              openFailures: @escaping () -> Void = {}) {
        guard let center = Self.center else { return }
        let relay = Relay(open: open, archive: archive, markRead: markRead,
                          openFailures: openFailures)
        self.relay = relay
        center.delegate = relay
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Action.category,
                actions: [
                    UNNotificationAction(identifier: Action.archive, title: "Archive",
                                         options: []),
                    UNNotificationAction(identifier: Action.markRead, title: "Mark read",
                                         options: []),
                ],
                intentIdentifiers: [], options: [])
        ])
    }

    public var announcedThrough: Date? {
        // The primary mailbox keeps the unsuffixed key it was already stored
        // under, so the one account most people have does not get a fresh mark
        // and a silent first sync after this change.
        get { defaults.object(forKey: markKeyForAccount) as? Date }
        set { defaults.set(newValue, forKey: markKeyForAccount) }
    }

    private var markKeyForAccount: String {
        accountID == Account.primaryID ? Self.markKey : "\(Self.markKey).\(accountID)"
    }

    /// Asks once. A refusal -- or an unsigned build that is simply not allowed
    /// to post -- is not an error: the app carries on without banners rather
    /// than apologising every sync tick.
    public func requestAuthorizationIfNeeded() async {
        guard authorization == .unasked else { return }
        authorization = .asking
        // No bundle identifier means no centre to ask, which is an answer: this
        // process is never going to post anything.
        guard let center = Self.center else { authorization = .refused; return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
        authorization = granted ? .granted : .refused
    }

    /// Says what is new and records that it was said.
    ///
    /// The two halves are here together because they must not come apart. They
    /// did: the inbox observation delivers its first value immediately, which
    /// on launch is while `requestAuthorizationIfNeeded` is still suspended on
    /// its await, and the announce that ran in that window showed nothing --
    /// `present` bails when it is not yet authorised -- and advanced the mark
    /// anyway. Every launch silently ate the batch of mail that had arrived
    /// while the app was closed, which is the batch worth having.
    ///
    /// So nothing is consumed until the centre has answered. A refusal counts
    /// as an answer: if banners are never coming, the mark should keep up
    /// rather than bank a backlog to dump the day permission is granted.
    public func announce(_ result: MailAnnouncer.Result) {
        guard isAuthorizationSettled else { return }
        present(result)
        announcedThrough = result.highWaterMark
    }

    public func present(_ result: MailAnnouncer.Result) {
        guard isAuthorized, let center = Self.center else { return }

        for item in result.items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.subtitle
            content.userInfo = ["threadID": item.threadID]
            content.categoryIdentifier = Action.category
            // Grouped by thread, so twelve alerts from one conversation stack
            // into one entry in Notification Centre instead of twelve.
            content.threadIdentifier = item.threadID
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil))
        }

        if result.additionalCount > 0 {
            let content = UNMutableNotificationContent()
            content.title = "Velo Mail"
            content.body = "and \(result.additionalCount) more"
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil))
        }
    }

    /// Says that a message did not go.
    ///
    /// A failed send only ever appeared as a banner inside the app, so writing
    /// something, pressing send and switching away meant finding out hours
    /// later. This is the one thing a mail client must not be quiet about.
    ///
    /// Announced once per failure: it stays in the queue until dealt with, and
    /// a fresh banner on every sync tick would be a punishment rather than a
    /// warning.
    public func present(failures: [MailFailure]) {
        let fresh = newFailures(among: failures)
        guard isAuthorized, let center = Self.center else { return }
        for failure in fresh {
            let content = UNMutableNotificationContent()
            content.title = "Message not sent"
            content.body = Self.failureBody(failure)
            // Louder than new mail on purpose: this one needs a hand.
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["failureID": failure.id]
            center.add(UNNotificationRequest(identifier: "failure-\(failure.id)",
                                             content: content, trigger: nil))
        }
    }

    /// The failures not yet announced, marking them as announced.
    ///
    /// Separate from posting so the rule is testable: a test runner has no
    /// bundle identifier and so no notification centre to post to.
    func newFailures(among failures: [MailFailure]) -> [MailFailure] {
        // Forget the ones that are gone first, so a retried send that fails
        // again says so rather than being taken for the one already reported.
        announcedFailures.formIntersection(Set(failures.map(\.id)))
        let fresh = failures.filter { !announcedFailures.contains($0.id) }
        announcedFailures.formUnion(fresh.map(\.id))
        return fresh
    }

    static func failureBody(_ failure: MailFailure) -> String {
        failure.subject.isEmpty ? "A message could not be sent" : failure.subject
    }

    public func setBadge(_ count: Int) {
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    /// Turns a tap into a call, and keeps banners visible while the app is
    /// frontmost.
    ///
    /// macOS suppresses a banner by default when its own app is in front,
    /// which for a mail client is precisely when new mail matters -- you are
    /// looking at the inbox and it silently does not appear.
    private final class Relay: NSObject, UNUserNotificationCenterDelegate {
        private let open: (String) -> Void
        private let archive: (String) -> Void
        private let markRead: (String) -> Void
        private let openFailures: () -> Void

        init(open: @escaping (String) -> Void,
             archive: @escaping (String) -> Void,
             markRead: @escaping (String) -> Void,
             openFailures: @escaping () -> Void) {
            self.open = open
            self.archive = archive
            self.markRead = markRead
            self.openFailures = openFailures
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
            [.banner, .badge]
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            let userInfo = response.notification.request.content.userInfo
            // A failed send has no thread to open; it wants the queue.
            if userInfo["failureID"] != nil {
                await MainActor.run { self.openFailures() }
                return
            }
            // The "and 3 more" summary carries no thread, and there is no one
            // thread it could sensibly open.
            guard let threadID = userInfo["threadID"] as? String else { return }
            let action = response.actionIdentifier
            await MainActor.run {
                switch action {
                case Action.archive: self.archive(threadID)
                case Action.markRead: self.markRead(threadID)
                case UNNotificationDismissActionIdentifier: break
                default: self.open(threadID)
                }
            }
        }
    }

    /// `UNUserNotificationCenter.current()` traps when the process has no
    /// bundle identifier, which is exactly the case in a test runner.
    private static var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }
}
