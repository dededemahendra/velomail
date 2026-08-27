import Foundation

/// The choices the app makes on the reader's behalf, and how to change them.
///
/// Every default is what the app already did, so nobody's client changes
/// behaviour the day a settings window appears. Every setter clamps: these are
/// numbers a person types, and a few of them can make the app useless if taken
/// literally.
public final class AppPreferences: @unchecked Sendable {
    private enum Key {
        /// Kept from when image loading was the only preference there was.
        /// Someone who turned blocking on meant it.
        static let blockImages = "velomail.blockRemoteImages"
        static let notifications = "velomail.showsNotifications"
        static let recentCommands = "velomail.recentCommands"
        static let undoWindow = "velomail.undoWindow"
        static let snoozeHours = "velomail.snoozeHours"
        static let morningHour = "velomail.morningHour"
        static let syncInterval = "velomail.syncInterval"
        static let repliesToEveryone = "velomail.repliesToEveryone"
        static let quotesByDefault = "velomail.quotesByDefault"
        static let warnsAboutAttachments = "velomail.warnsAboutAttachments"
        static let recipientLimit = "velomail.recipientLimit"
        static let opensAt = "velomail.opensAt"
        static let marksReadAfter = "velomail.marksReadAfter"
        static let newestFirst = "velomail.newestFirstInThread"
        static let previewLines = "velomail.previewLines"
        static let compactList = "velomail.compactList"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Reading

    public var loadsRemoteImages: Bool {
        get { !defaults.bool(forKey: Key.blockImages) }
        set { defaults.set(!newValue, forKey: Key.blockImages) }
    }

    public var showsNotifications: Bool {
        get { value(Key.notifications) ?? true }
        set { defaults.set(newValue, forKey: Key.notifications) }
    }

    // MARK: - Timing

    /// How long a send can be taken back.
    ///
    /// Floored because zero means a send that cannot be undone, which is the
    /// one thing the window exists for; capped because mail sitting unsent for
    /// an hour is mail the writer believes has gone.
    public var undoWindow: TimeInterval {
        get { value(Key.undoWindow) ?? 10 }
        set { defaults.set(min(max(newValue, 3), 60), forKey: Key.undoWindow) }
    }

    /// What `h` means.
    public var snoozeHours: Double {
        get { value(Key.snoozeHours) ?? 4 }
        set { defaults.set(min(max(newValue, 1), 72), forKey: Key.snoozeHours) }
    }

    /// When "tomorrow" and "next week" wake up, and when a scheduled send goes.
    public var morningHour: Int {
        get { value(Key.morningHour) ?? 9 }
        set { defaults.set(min(max(newValue, 0), 23), forKey: Key.morningHour) }
    }

    /// Floored so a mistyped number cannot turn the app into something that
    /// hammers Gmail once a second and gets the account rate-limited.
    public var syncInterval: TimeInterval {
        get { value(Key.syncInterval) ?? 60 }
        set { defaults.set(min(max(newValue, 15), 3_600), forKey: Key.syncInterval) }
    }

    // MARK: - Composing

    /// Whether `r` answers everyone rather than just the sender.
    ///
    /// Off by default: replying to more people than intended is the harder
    /// mistake to take back, and Shift+R is right there.
    public var repliesToEveryone: Bool {
        get { value(Key.repliesToEveryone) ?? false }
        set { defaults.set(newValue, forKey: Key.repliesToEveryone) }
    }

    /// Whether a reply carries the message it answers.
    public var quotesByDefault: Bool {
        get { value(Key.quotesByDefault) ?? true }
        set { defaults.set(newValue, forKey: Key.quotesByDefault) }
    }

    public var warnsAboutAttachments: Bool {
        get { value(Key.warnsAboutAttachments) ?? true }
        set { defaults.set(newValue, forKey: Key.warnsAboutAttachments) }
    }

    /// Above how many recipients to ask first. Zero never asks.
    public var recipientLimit: Int {
        get { value(Key.recipientLimit) ?? 0 }
        set { defaults.set(max(0, min(newValue, 500)), forKey: Key.recipientLimit) }
    }

    // MARK: - Reading

    /// Which list the app opens on.
    public var opensAt: String {
        get { value(Key.opensAt) ?? "inbox" }
        set { defaults.set(newValue, forKey: Key.opensAt) }
    }

    /// Seconds a thread stays open before it counts as read. Negative never
    /// marks it, which is what someone triaging a busy inbox wants.
    public var marksReadAfter: TimeInterval {
        get { value(Key.marksReadAfter) ?? 0 }
        set { defaults.set(min(max(newValue, -1), 30), forKey: Key.marksReadAfter) }
    }

    // MARK: - Display

    /// Whether a thread reads newest first.
    ///
    /// Oldest first by default, because that is the order a conversation
    /// happened in and the order every other client shows it.
    public var newestFirstInThread: Bool {
        get { value(Key.newestFirst) ?? false }
        set { defaults.set(newValue, forKey: Key.newestFirst) }
    }

    /// How many lines of a message to show in the list. Two make prose easier
    /// to triage and alerts no easier at all, so this is worth asking.
    public var previewLines: Int {
        get { value(Key.previewLines) ?? 1 }
        set { defaults.set(min(max(newValue, 0), 3), forKey: Key.previewLines) }
    }

    /// Raw values of the commands last run from the palette, newest first.
    /// Stored rather than session-only: what you reach for does not reset
    /// because you quit the app.
    public var recentCommands: [String] {
        get { value(Key.recentCommands) ?? [] }
        set { defaults.set(newValue, forKey: Key.recentCommands) }
    }

    public var compactList: Bool {
        get { value(Key.compactList) ?? false }
        set { defaults.set(newValue, forKey: Key.compactList) }
    }

    /// The height a list row wants, given the two settings that decide it.
    /// Kept here so the list and anything measuring it cannot disagree.
    public var listRowHeight: CGFloat {
        let base: CGFloat = compactList ? 34 : 44
        return base + CGFloat(previewLines) * (compactList ? 15 : 20)
    }

    /// Absent means "never set", which is not the same as zero.
    private func value<Value>(_ key: String) -> Value? {
        defaults.object(forKey: key) as? Value
    }
}
