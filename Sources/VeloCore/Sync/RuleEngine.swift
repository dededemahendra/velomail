import Foundation

/// Decides what rules want done with a message.
///
/// Pure: it produces actions and performs none of them. What actually happens is
/// the caller's business, which keeps the matching — the part that is easy to
/// get subtly wrong and expensive to get wrong on a real mailbox — testable on
/// its own.
public struct RuleEngine: Sendable {
    private let rules: [MailRule]

    public init(rules: [MailRule]) {
        // Ordered once here so evaluation is deterministic regardless of how the
        // file listed them.
        self.rules = rules.filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    /// Every action the matching rules ask for, in rule order, without
    /// duplicates.
    public func actions(for message: Message, hasAttachment: Bool = false) -> [RuleAction] {
        var seen = Set<RuleAction>()
        var ordered: [RuleAction] = []
        for rule in rules where matches(rule, message, hasAttachment) {
            for action in rule.actions where !seen.contains(action) {
                seen.insert(action)
                ordered.append(action)
            }
        }
        return ordered
    }

    /// True when a rule asked for this message never to be seen — checked
    /// separately so notifications can be suppressed without re-deriving the
    /// whole action list.
    public func isBlocked(_ message: Message, hasAttachment: Bool = false) -> Bool {
        actions(for: message, hasAttachment: hasAttachment).contains(.block)
    }

    // MARK: - Matching

    private func matches(_ rule: MailRule, _ message: Message, _ hasAttachment: Bool) -> Bool {
        // A rule with no conditions matches nothing. The alternative reading --
        // "matches everything" -- would let an empty rule archive an inbox.
        guard !rule.conditions.isEmpty else { return false }

        let results = rule.conditions.map { satisfies($0, message, hasAttachment) }
        return rule.matchAll ? results.allSatisfy { $0 } : results.contains(true)
    }

    private func satisfies(_ condition: RuleCondition, _ message: Message,
                           _ hasAttachment: Bool) -> Bool {
        switch condition {
        case let .senderContains(text):
            return contains(message.sender, text)
        case let .subjectContains(text):
            return contains(message.subject, text)
        case let .bodyContains(text):
            return contains(message.bodyText ?? message.bodyHTML ?? "", text)
        case .isUnread:
            return message.isUnread
        case .hasAttachment:
            return hasAttachment
        }
    }

    private func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        return haystack.range(of: needle, options: .caseInsensitive) != nil
    }
}
