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
        static let undoWindow = "velomail.undoWindow"
        static let snoozeHours = "velomail.snoozeHours"
        static let morningHour = "velomail.morningHour"
        static let syncInterval = "velomail.syncInterval"
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

    /// Absent means "never set", which is not the same as zero.
    private func value<Value>(_ key: String) -> Value? {
        defaults.object(forKey: key) as? Value
    }
}
