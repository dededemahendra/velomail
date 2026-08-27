import Foundation

/// One mailbox the app knows about.
public struct Account: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// Learned from Gmail's profile on first sync, so it is absent until then.
    public var address: String?

    public init(id: String, address: String? = nil) {
        self.id = id
        self.address = address
    }

    /// What to call it before it has said who it is.
    public var displayName: String { address ?? "Not signed in" }

    /// The id the app has always used. Kept so a mailbox already on disk is
    /// not orphaned the moment a second account is added.
    public static let primaryID = "primary"

    /// One database per account rather than an account column on every table.
    /// Accounts share nothing, so the cheapest way to keep them apart is to
    /// keep them apart.
    public static func databaseName(for id: String) -> String {
        id == primaryID ? "velomail.sqlite" : "velomail-\(id).sqlite"
    }

    /// Likewise for tokens: one Keychain entry each, and the first keeps the
    /// name it was already stored under.
    public static func keychainAccount(for id: String) -> String {
        id == primaryID ? "default" : id
    }
}

/// The accounts and which one is open.
///
/// Deliberately small and outside the database: which mailboxes exist is not a
/// fact about any one mailbox, and putting it inside one would make the first
/// account special in a way that shows up everywhere.
public final class AccountList {
    private static let accountsKey = "velomail.accounts"
    private static let currentKey = "velomail.currentAccount"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every account, the primary first. A fresh install has one waiting to be
    /// signed into rather than none: the app has always had somewhere to put
    /// mail, and calling that "no accounts" makes a first launch a special case
    /// in every caller.
    public var accounts: [Account] {
        guard let data = defaults.data(forKey: Self.accountsKey),
              let stored = try? JSONDecoder().decode([Account].self, from: data),
              !stored.isEmpty else {
            return [Account(id: Account.primaryID)]
        }
        return stored
    }

    public var current: String {
        let id = defaults.string(forKey: Self.currentKey) ?? Account.primaryID
        return accounts.contains { $0.id == id } ? id : Account.primaryID
    }

    /// Adds an account and switches to it, which is why one is added.
    @discardableResult
    public func add() -> String {
        let id = UUID().uuidString.prefix(8).lowercased()
        save(accounts + [Account(id: String(id))])
        switchTo(String(id))
        return String(id)
    }

    /// Ignores an id it does not know: staying where you are beats opening an
    /// empty mailbox.
    public func switchTo(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        defaults.set(id, forKey: Self.currentKey)
    }

    public func setAddress(_ address: String, on id: String) {
        var updated = accounts
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].address = address
        save(updated)
    }

    /// Removes an account, unless it is the only one: an app with no mailbox
    /// has nothing to show.
    public func remove(_ id: String) {
        let remaining = accounts.filter { $0.id != id }
        guard !remaining.isEmpty else { return }
        save(remaining)
        if current == id { switchTo(remaining[0].id) }
    }

    private func save(_ accounts: [Account]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: Self.accountsKey)
    }
}
