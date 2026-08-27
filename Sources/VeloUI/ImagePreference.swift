import Foundation

/// Whether to fetch the pictures a message points at.
///
/// Loads by default. Blocking is the more private choice -- a remote image is
/// how a sender learns their message was opened, by whom and when -- but a mail
/// client that shows most messages with holes in them is not being private so
/// much as broken, and the reader can turn it on knowingly.
///
/// Stored as the *blocked* flag so the default falls out of `UserDefaults`
/// returning false for a key nobody has set.
public final class ImagePreference {
    private static let key = "velomail.blockRemoteImages"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var alwaysLoads: Bool {
        get { !defaults.bool(forKey: Self.key) }
        set { defaults.set(!newValue, forKey: Self.key) }
    }

    /// Flips the setting and reports what it became, so a caller can say so.
    @discardableResult
    public func toggle() -> Bool {
        alwaysLoads.toggle()
        return alwaysLoads
    }
}
