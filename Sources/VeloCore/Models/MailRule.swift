import Foundation

/// What a rule looks for. Substring matching, not regex: it is what people
/// actually write, and a bad regex is a support problem rather than a feature.
public enum RuleCondition: Codable, Equatable, Sendable, Hashable {
    case senderContains(String)
    case subjectContains(String)
    case bodyContains(String)
    case isUnread
    case hasAttachment
}

/// What a rule does. Every one of these routes through `OutboundService`, so a
/// rule-driven archive is optimistic, synced and revertible exactly like a
/// manual one.
public enum RuleAction: String, Codable, Equatable, Sendable, Hashable {
    case archive
    case star
    case markRead
    /// The VIP effect.
    case markImportant
    /// Archive, mark read, and never notify. Announcing something the user asked
    /// never to see would be worse than not having the feature.
    case block
}

/// One "when a message looks like this, do that".
///
/// Filters, rules, auto-sorting, VIP, blocking and spam are all this type with
/// different conditions — six roadmap items, one mechanism, one set of bugs.
public struct MailRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var order: Int
    /// AND across conditions when true, OR when false.
    public var matchAll: Bool
    public var conditions: [RuleCondition]
    public var actions: [RuleAction]

    public init(id: String, name: String, isEnabled: Bool = true, order: Int = 0,
                matchAll: Bool = true, conditions: [RuleCondition], actions: [RuleAction]) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.order = order
        self.matchAll = matchAll
        self.conditions = conditions
        self.actions = actions
    }
}
