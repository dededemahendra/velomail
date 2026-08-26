import Foundation
import GRDB

/// Everyone you have corresponded with, learned from the mail already stored.
///
/// No contacts API and nothing extra persisted: every sender, recipient and Cc
/// of every synced message is already in SQLite, so the address book is a
/// derivation rather than a thing to keep in step.
public struct AddressBook: Sendable {
    public struct Contact: Equatable, Sendable {
        public let address: String
        public let name: String?
        /// How often they appear. Used for ranking, not shown.
        public let count: Int

        public init(address: String, name: String?, count: Int) {
            self.address = address
            self.name = name
            self.count = count
        }

        /// What goes in the field when picked.
        public var label: String {
            guard let name, !name.isEmpty else { return address }
            return "\(name) <\(address)>"
        }
    }

    /// Enough to choose from without becoming a wall.
    public static let maximumSuggestions = 6

    private let contacts: [Contact]

    public init(contacts: [Contact]) {
        self.contacts = contacts
    }

    public static func build(from store: MailStore, identity: String,
                             now: Date = Date(), withinDays: Int = 365) throws -> AddressBook {
        let cutoff = now.addingTimeInterval(-Double(withinDays) * 86_400)
        // Three columns rather than whole messages: the bodies are the bulk of
        // the table, and this runs on the main thread as the composer opens.
        let rows = try store.database.dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT sender, recipients, cc FROM message WHERE date >= ?
                """, arguments: [cutoff])
        }

        let mine = Draft.normalizedAddress(identity)
        var seen: [String: (name: String?, count: Int)] = [:]

        for row in rows {
            let sender: String = row["sender"] ?? ""
            let headers = [sender] + addresses(inColumn: row["recipients"])
                + addresses(inColumn: row["cc"])
            for header in headers {
                let address = Draft.normalizedAddress(header)
                guard !address.isEmpty, address != mine, address.contains("@") else { continue }

                let name = displayName(in: header)
                let existing = seen[address]
                // The richest name wins: a bare address seen once must not
                // erase a full name seen elsewhere.
                let best = [existing?.name, name].compactMap { $0 }
                    .max { $0.count < $1.count }
                seen[address] = (best, (existing?.count ?? 0) + 1)
            }
        }

        return AddressBook(contacts: seen.map {
            Contact(address: $0.key, name: $0.value.name, count: $0.value.count)
        })
    }

    /// Decodes one of the JSON address columns, treating anything unreadable as
    /// empty: a malformed row should cost its own addresses, not the whole book.
    private static func addresses(inColumn value: String?) -> [String] {
        guard let value, let data = value.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    /// Contacts matching `prefix`, best first.
    ///
    /// An empty query suggests nothing — opening the composer should not dump
    /// the whole address book at you.
    public func suggestions(for query: String) -> [Contact] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        return contacts
            .compactMap { contact -> (Contact, Int, Int)? in
                let name = (contact.name ?? "").lowercased()
                let address = contact.address.lowercased()
                // Rank 0 for something that starts with what was typed: typing
                // "nat" almost always means the person called Nat, not someone
                // whose surname happens to contain it.
                if name.hasPrefix(needle) || address.hasPrefix(needle) {
                    return (contact, 0, -contact.count)
                }
                if name.contains(needle) || address.contains(needle) {
                    return (contact, 1, -contact.count)
                }
                return nil
            }
            .sorted { ($0.1, $0.2, $0.0.address) < ($1.1, $1.2, $1.0.address) }
            .prefix(Self.maximumSuggestions)
            .map(\.0)
    }

    /// The name half of `Name <addr>`, or nil for a bare address.
    private static func displayName(in header: String) -> String? {
        guard let open = header.firstIndex(of: "<") else { return nil }
        let name = header[header.startIndex..<open]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
