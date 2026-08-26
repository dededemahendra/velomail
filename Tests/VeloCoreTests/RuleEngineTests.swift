import Testing
import Foundation
@testable import VeloCore

private func message(from sender: String = "News <noreply@news.example.com>",
                     subject: String = "Weekly digest",
                     body: String = "Seven stories on regeneration",
                     unread: Bool = true) -> Message {
    Message(id: "m", threadID: "t", sender: sender, recipients: ["me@x.com"],
            subject: subject, date: Date(timeIntervalSince1970: 1),
            bodyHTML: nil, bodyText: body, isUnread: unread,
            labelIDs: unread ? ["INBOX", "UNREAD"] : ["INBOX"])
}

private func rule(_ name: String = "r",
                  _ conditions: [RuleCondition],
                  _ actions: [RuleAction],
                  matchAll: Bool = true,
                  enabled: Bool = true) -> MailRule {
    MailRule(id: name, name: name, isEnabled: enabled, order: 0,
             matchAll: matchAll, conditions: conditions, actions: actions)
}

@Suite struct RuleEngineTests {
    // MARK: - Conditions

    @Test func senderMatchingIsSubstringAndCaseInsensitive() {
        let engine = RuleEngine(rules: [rule("vip", [.senderContains("NOREPLY")], [.archive])])
        #expect(engine.actions(for: message()) == [.archive])
    }

    @Test func aSenderThatDoesNotMatchYieldsNothing() {
        let engine = RuleEngine(rules: [rule("vip", [.senderContains("alice")], [.archive])])
        #expect(engine.actions(for: message()).isEmpty)
    }

    @Test func subjectAndBodyMatch() {
        #expect(RuleEngine(rules: [rule("s", [.subjectContains("digest")], [.star])])
                    .actions(for: message()) == [.star])
        #expect(RuleEngine(rules: [rule("b", [.bodyContains("regeneration")], [.star])])
                    .actions(for: message()) == [.star])
    }

    @Test func unreadAndAttachmentConditions() {
        #expect(RuleEngine(rules: [rule("u", [.isUnread], [.star])])
                    .actions(for: message()) == [.star])
        #expect(RuleEngine(rules: [rule("u", [.isUnread], [.star])])
                    .actions(for: message(unread: false)).isEmpty)
    }

    // MARK: - Combining

    @Test func matchAllRequiresEveryCondition() {
        let all = rule("a", [.senderContains("noreply"), .subjectContains("invoice")],
                       [.archive], matchAll: true)
        #expect(RuleEngine(rules: [all]).actions(for: message()).isEmpty)
    }

    @Test func matchAnyNeedsOnlyOne() {
        let any = rule("a", [.senderContains("noreply"), .subjectContains("invoice")],
                       [.archive], matchAll: false)
        #expect(RuleEngine(rules: [any]).actions(for: message()) == [.archive])
    }

    @Test func aRuleWithNoConditionsNeverMatches() {
        // Otherwise an empty rule silently archives the entire inbox.
        #expect(RuleEngine(rules: [rule("empty", [], [.archive])]).actions(for: message()).isEmpty)
    }

    @Test func disabledRulesDoNothing() {
        let off = rule("off", [.senderContains("noreply")], [.archive], enabled: false)
        #expect(RuleEngine(rules: [off]).actions(for: message()).isEmpty)
    }

    // MARK: - Several rules

    @Test func everyMatchingRuleContributes() {
        let engine = RuleEngine(rules: [
            rule("a", [.senderContains("noreply")], [.archive]),
            rule("b", [.subjectContains("digest")], [.star]),
        ])
        #expect(Set(engine.actions(for: message())) == [.archive, .star])
    }

    @Test func duplicateActionsAppearOnce() {
        let engine = RuleEngine(rules: [
            rule("a", [.senderContains("noreply")], [.archive]),
            rule("b", [.subjectContains("digest")], [.archive]),
        ])
        #expect(engine.actions(for: message()) == [.archive])
    }

    @Test func rulesAreEvaluatedInOrder() {
        let engine = RuleEngine(rules: [
            MailRule(id: "second", name: "second", isEnabled: true, order: 2,
                     matchAll: true, conditions: [.isUnread], actions: [.star]),
            MailRule(id: "first", name: "first", isEnabled: true, order: 1,
                     matchAll: true, conditions: [.isUnread], actions: [.archive]),
        ])
        #expect(engine.actions(for: message()) == [.archive, .star])
    }

    // MARK: - The primitives the roadmap items are built from

    @Test func vipIsARuleThatMarksImportant() {
        let vip = rule("vip", [.senderContains("natalie@sistercreatives.co")], [.markImportant])
        let fromNatalie = message(from: "Natalie <natalie@sistercreatives.co>")
        #expect(RuleEngine(rules: [vip]).actions(for: fromNatalie) == [.markImportant])
    }

    @Test func blockingIsARuleThatArchivesAndSilences() {
        let engine = RuleEngine(rules: [rule("block", [.senderContains("noreply")], [.block])])
        #expect(engine.actions(for: message()) == [.block])
        #expect(engine.isBlocked(message()))
    }

    @Test func anUnblockedSenderIsNotSilenced() {
        let engine = RuleEngine(rules: [rule("block", [.senderContains("spammer")], [.block])])
        #expect(!engine.isBlocked(message()))
    }

    @Test func noRulesMeansNothingHappens() {
        #expect(RuleEngine(rules: []).actions(for: message()).isEmpty)
        #expect(!RuleEngine(rules: []).isBlocked(message()))
    }
}
