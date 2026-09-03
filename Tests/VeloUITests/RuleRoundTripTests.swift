import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct RuleRoundTripTests {
    private func scratch() -> (SettingsStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo-rt-\(UUID().uuidString)")
        return (SettingsStore(directory: dir), dir)
    }

    /// Writes `rules`, opens Settings, presses Done, and returns what survived.
    private func throughSettings(_ rules: [MailRule], test: String = #function) throws -> [MailRule] {
        let (store, dir) = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.saveRules(RuleLibrary(rules: rules))

        let model = SettingsViewModel(store: store, preferences: AppPreferences(
            defaults: scratchDefaults(test: test)))
        model.save()
        return store.rules().rules
    }

    @Test func aBlockingRuleStillBlocksAfterOpeningSettings() throws {
        // The editor knows only "archives", so a block rule came back with no
        // actions at all -- it stayed in the list and quietly stopped working,
        // and mail the reader asked never to see came back with no sign why.
        let blocked = MailRule(id: "b", name: "Block spam",
                               conditions: [.senderContains("spam@x.com")],
                               actions: [.block])
        let after = try throughSettings([blocked])
        let survivor = try #require(after.first)
        #expect(survivor.actions.contains(.block))
    }

    @Test func aSubjectRuleIsNotDeleted() throws {
        // The editor has no field for it, so senderContains was empty, and an
        // empty sender means "not saveable" -- the rule vanished.
        let subject = MailRule(id: "s", name: "Invoices",
                               conditions: [.subjectContains("invoice")],
                               actions: [.star])
        let after = try throughSettings([subject])
        let survivor = try #require(after.first)
        #expect(survivor.conditions == [.subjectContains("invoice")])
    }

    @Test func extraActionsSurvive() throws {
        let rule = MailRule(id: "m", name: "VIP",
                            conditions: [.senderContains("peta@")],
                            actions: [.star, .markImportant])
        let after = try throughSettings([rule])
        let survivor = try #require(after.first)
        #expect(Set(survivor.actions) == Set([.star, .markImportant]))
    }

    @Test func matchAllAndOrderSurvive() throws {
        let rule = MailRule(id: "o", name: "Two conditions", order: 7, matchAll: false,
                            conditions: [.senderContains("a@x.com"), .hasAttachment],
                            actions: [.archive])
        let after = try throughSettings([rule])
        let survivor = try #require(after.first)
        #expect(survivor.order == 7)
        #expect(survivor.matchAll == false)
        #expect(survivor.conditions.contains(.hasAttachment))
    }

    @Test func theEditorStillEditsWhatItOwns() throws {
        // Preserving the rest must not stop the fields it does show from working.
        let (store, dir) = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.saveRules(RuleLibrary(rules: [
            MailRule(id: "e", name: "Old name", conditions: [.senderContains("old@x.com")],
                     actions: [.archive])
        ]))
        let model = SettingsViewModel(store: store, preferences: AppPreferences(
            defaults: scratchDefaults()))
        model.rules[0].name = "New name"
        model.rules[0].senderContains = "new@x.com"
        model.rules[0].isEnabled = false
        model.save()

        let after = store.rules().rules
        #expect(after[0].name == "New name")
        #expect(after[0].conditions.contains(.senderContains("new@x.com")))
        #expect(!after[0].conditions.contains(.senderContains("old@x.com")))
        #expect(after[0].isEnabled == false)
    }

    @Test func turningArchivingOffLeavesTheOtherActions() throws {
        let (store, dir) = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.saveRules(RuleLibrary(rules: [
            MailRule(id: "a", name: "Both", conditions: [.senderContains("a@x.com")],
                     actions: [.archive, .star])
        ]))
        let model = SettingsViewModel(store: store, preferences: AppPreferences(
            defaults: scratchDefaults()))
        model.rules[0].archives = false
        model.save()

        let after = store.rules().rules
        #expect(!after[0].actions.contains(.archive))
        #expect(after[0].actions.contains(.star))
    }

    @Test func aRuleTheEditorAddedStillWorks() throws {
        let (store, dir) = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = SettingsViewModel(store: store, preferences: AppPreferences(
            defaults: scratchDefaults()))
        model.addRule()
        model.rules[0].senderContains = "noise@x.com"
        model.save()

        let after = store.rules().rules
        #expect(after.count == 1)
        #expect(after[0].actions == [.archive])
    }

    @Test func aRuleWithNothingToMatchIsStillRefused() throws {
        // A rule that matches everything and archives is not a rule.
        let (store, dir) = scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = SettingsViewModel(store: store, preferences: AppPreferences(
            defaults: scratchDefaults()))
        model.addRule()
        model.rules[0].senderContains = "   "
        model.save()

        #expect(store.rules().rules.isEmpty)
    }
}
