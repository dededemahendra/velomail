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

    private let defaults: UserDefaults
    private var isAuthorized = false
    private var hasAsked = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var announcedThrough: Date? {
        get { defaults.object(forKey: Self.markKey) as? Date }
        set { defaults.set(newValue, forKey: Self.markKey) }
    }

    /// Asks once. A refusal -- or an unsigned build that is simply not allowed
    /// to post -- is not an error: the app carries on without banners rather
    /// than apologising every sync tick.
    public func requestAuthorizationIfNeeded() async {
        guard !hasAsked else { return }
        hasAsked = true
        guard let center = Self.center else { return }
        isAuthorized = (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
    }

    public func present(_ result: MailAnnouncer.Result) {
        guard isAuthorized, let center = Self.center else { return }

        for item in result.items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.subtitle
            content.userInfo = ["threadID": item.threadID]
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

    public func setBadge(_ count: Int) {
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil
    }

    /// `UNUserNotificationCenter.current()` traps when the process has no
    /// bundle identifier, which is exactly the case in a test runner.
    private static var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }
}
