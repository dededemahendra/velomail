import Foundation
import VeloCore

/// Answers "what is this account's address?" every time it is asked, rather
/// than once at launch.
///
/// The authoritative answer comes from Gmail's own profile and only arrives
/// with the first backfill, so this is deliberately a live lookup: the app is
/// built before the answer exists.
public struct IdentityResolver: Sendable {
    /// Used only before the first backfill and only when nothing is configured.
    /// It is still wrong as a `From`, but it survives seconds, not sessions.
    public static let placeholder = "me@localhost"

    private let syncState: SyncStateStore
    private let accountID: String
    private let configured: String?

    public init(syncState: SyncStateStore, accountID: String, configured: String?) {
        self.syncState = syncState
        self.accountID = accountID
        self.configured = configured
    }

    /// Gmail's answer, then the configured override, then a placeholder.
    public func identity() -> String {
        if let stored = nonBlank(try? syncState.load(accountID: accountID)?.emailAddress) {
            return stored
        }
        return nonBlank(configured) ?? Self.placeholder
    }

    private func nonBlank(_ value: String??) -> String? {
        guard let value = value ?? nil else { return nil }
        return nonBlank(value)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
