import Foundation
import GRDB

/// A Gmail label, as something a person can browse rather than an id.
///
/// The id is the only thing a message carries -- `Label_7` for a label someone
/// made, `CATEGORY_UPDATES` for one Gmail did -- so a name has to be fetched
/// separately or every label in the app reads as a serial number.
public struct MailLabel: Codable, FetchableRecord, PersistableRecord,
                         Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case system
        case user
    }

    public var id: String
    public var name: String
    public var kind: Kind

    public static let databaseTableName = "label"

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// Labels with a view of their own already. Listing them again would put
    /// the same mail under two names in the same sidebar.
    public static let structural: Set<String> = [
        "INBOX", "SENT", "DRAFT", "TRASH", "SPAM", "UNREAD", "STARRED", "IMPORTANT",
        "CHAT", "CATEGORY_FORUMS",
    ]

    /// The categories Gmail files bulk mail into. Primary is everything else:
    /// tagged `CATEGORY_PERSONAL`, or tagged with no category at all.
    public static let bulkCategories = [
        "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_UPDATES", "CATEGORY_FORUMS",
    ]

    /// True when this is a label worth offering as a place to look.
    public var isBrowsable: Bool { !MailLabel.structural.contains(id) }

    /// What to put on screen. Gmail's own categories arrive shouting in
    /// `CATEGORY_` form; a person's own labels are already named by a person.
    public var displayName: String {
        guard id.hasPrefix("CATEGORY_") else { return name }
        let word = id.dropFirst("CATEGORY_".count).lowercased()
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    /// Categories before a person's own labels, each group in reading order.
    /// The ones Gmail made are a fixed set and belong together.
    public static func browsableOrder(_ labels: [MailLabel]) -> [MailLabel] {
        labels.filter(\.isBrowsable).sorted { left, right in
            let leftIsCategory = left.id.hasPrefix("CATEGORY_")
            let rightIsCategory = right.id.hasPrefix("CATEGORY_")
            if leftIsCategory != rightIsCategory { return leftIsCategory }
            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
    }
}
