import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct SettingsViewModelTests {
    private func makeModel(test: String = #function) -> (SettingsViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("velo-settings-vm-\(UUID().uuidString)", isDirectory: true)
        let defaults = scratchDefaults(test: test)
        return (SettingsViewModel(store: SettingsStore(directory: directory),
                                  preferences: AppPreferences(defaults: defaults)), directory)
    }

    // MARK: - Signature

    @Test func aSignatureIsKeptWhenSaved() {
        let (model, directory) = makeModel()
        model.signature = "Warren\nLiving Legacy Forest"
        model.save()

        #expect(SettingsStore(directory: directory).snippets().signature
                == "Warren\nLiving Legacy Forest")
    }

    @Test func loadingShowsWhatIsAlreadyThere() throws {
        let (model, directory) = makeModel()
        try SettingsStore(directory: directory)
            .saveSnippets(SnippetLibrary(signature: "Existing", snippets: []))

        model.load()

        #expect(model.signature == "Existing")
    }

    // MARK: - Snippets

    @Test func aSnippetCanBeAdded() {
        let (model, _) = makeModel()
        model.addSnippet()

        #expect(model.snippets.count == 1)
    }

    @Test func aNewSnippetIsEditableRatherThanFinished() {
        // It appears with placeholder text to replace, not as a fixed row.
        let (model, _) = makeModel()
        model.addSnippet()

        #expect(!(model.snippets.first?.name.isEmpty ?? true))
        #expect(!(model.snippets.first?.shortcut.isEmpty ?? true))
    }

    @Test func aSnippetCanBeRemoved() {
        let (model, _) = makeModel()
        model.addSnippet()
        model.removeSnippet(at: 0)

        #expect(model.snippets.isEmpty)
    }

    @Test func snippetsSurviveSaving() {
        let (model, directory) = makeModel()
        model.addSnippet()
        model.snippets[0].shortcut = "thx"
        model.snippets[0].body = "Thanks so much."
        model.save()

        #expect(SettingsStore(directory: directory).snippets().snippets.map(\.shortcut) == ["thx"])
    }

    @Test func aSnippetWithNoShortcutIsNotWorthKeeping() {
        // It could never be triggered, so storing it is storing a puzzle.
        let (model, directory) = makeModel()
        model.addSnippet()
        model.snippets[0].shortcut = "   "
        model.save()

        #expect(SettingsStore(directory: directory).snippets().snippets.isEmpty)
    }

    // MARK: - Rules

    @Test func aRuleCanBeTurnedOffWithoutDeletingIt() {
        // Rules act without asking, so pausing one has to be easier than
        // rebuilding it from memory later.
        let (model, directory) = makeModel()
        model.addRule()
        model.rules[0].isEnabled = false
        model.save()

        #expect(SettingsStore(directory: directory).rules().rules.first?.isEnabled == false)
    }

    @Test func aRuleWithNothingToMatchIsNotSaved() {
        // An empty condition matches everything, and these actions are not
        // undoable in bulk.
        let (model, directory) = makeModel()
        model.addRule()
        model.rules[0].senderContains = ""
        model.save()

        #expect(SettingsStore(directory: directory).rules().rules.isEmpty)
    }

    @Test func aRuleRoundTrips() {
        let (model, directory) = makeModel()
        model.addRule()
        model.rules[0].name = "Newsletters"
        model.rules[0].senderContains = "news@"
        model.save()

        model.load()
        #expect(model.rules.map(\.senderContains) == ["news@"])
        #expect(SettingsStore(directory: directory).rules().rules.count == 1)
    }

    // MARK: - AI

    @Test func anAPIKeyIsSavedAndReadBack() {
        let (model, _) = makeModel()
        model.aiProvider = "anthropic"
        model.aiAPIKey = "sk-test"
        model.save()

        model.load()
        #expect(model.aiAPIKey == "sk-test")
    }

    @Test func savingReportsWhetherItWorked() {
        let (model, _) = makeModel()
        model.signature = "Warren"

        model.save()

        #expect(model.status == .saved)
    }

    @Test func aRefusedWriteSaysSoRatherThanLookingSaved() throws {
        let (model, directory) = makeModel()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{ not json".write(to: directory.appendingPathComponent("config.json"),
                               atomically: true, encoding: .utf8)
        model.aiAPIKey = "sk-test"

        model.save()

        #expect(model.status != .saved)
    }

    // MARK: - The choices that apply at once

    @Test func aToggleTakesEffectWithoutWaitingForDone() {
        // A switch that does nothing until a button is pressed elsewhere reads
        // as a broken switch.
        let defaults = scratchDefaults()
        let preferences = AppPreferences(defaults: defaults)
        let model = SettingsViewModel(store: SettingsStore(directory: FileManager.default
            .temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                                      preferences: preferences)

        model.loadsImages = false

        #expect(!preferences.loadsRemoteImages)
    }

    @Test func aNumberOutsideWhatTheAppAcceptsSnapsBack() {
        // Otherwise the screen shows 9999 while the app uses 60.
        let (model, _) = makeModel()
        model.undoWindow = 9_999

        #expect(model.undoWindow == 60)
    }

    @Test func theTimingSettingsLoadWhatWasSet() {
        let (model, _) = makeModel()
        model.snoozeHours = 12
        model.morningHour = 6

        model.load()

        #expect(model.snoozeHours == 12)
        #expect(model.morningHour == 6)
    }
}
