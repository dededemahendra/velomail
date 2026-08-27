import Foundation
import SwiftUI
import VeloCore

/// What the settings window is editing.
///
/// Editable copies rather than the stored types: a half-typed shortcut or a
/// rule with nothing in its condition yet has to be a legal thing to be looking
/// at, and neither is a legal thing to save.
@MainActor
public final class SettingsViewModel: ObservableObject {
    public enum Status: Equatable {
        case idle
        case saved
        case failed(String)
    }

    /// A snippet while it is being typed.
    public struct EditableSnippet: Identifiable, Equatable {
        public let id = UUID()
        public var name: String
        public var shortcut: String
        public var subject: String
        public var body: String
    }

    /// A rule while it is being typed. One condition, because a window that can
    /// express everything the engine can would be a rule editor rather than a
    /// settings pane -- and the file is still there for the rest.
    public struct EditableRule: Identifiable, Equatable {
        public let id: String
        public var name: String
        public var isEnabled: Bool
        public var senderContains: String
        public var archives: Bool
    }

    @Published public var signature = ""
    @Published public var snippets: [EditableSnippet] = []
    @Published public var rules: [EditableRule] = []
    @Published public var aiProvider = ""
    @Published public var aiModel = ""
    @Published public var aiAPIKey = ""
    @Published public private(set) var status: Status = .idle

    /// Written straight through rather than on save: these are single values a
    /// person flips, and a toggle that waits for a Done button reads as broken.
    @Published public var loadsImages = true { didSet { preferences.loadsRemoteImages = loadsImages } }
    @Published public var showsNotifications = true {
        didSet { preferences.showsNotifications = showsNotifications }
    }
    @Published public var undoWindow: Double = 10 {
        didSet {
            preferences.undoWindow = undoWindow
            // Read back so a value outside what the app will accept snaps to
            // what it actually stored rather than lying on screen.
            if preferences.undoWindow != undoWindow { undoWindow = preferences.undoWindow }
        }
    }
    @Published public var snoozeHours: Double = 4 {
        didSet {
            preferences.snoozeHours = snoozeHours
            if preferences.snoozeHours != snoozeHours { snoozeHours = preferences.snoozeHours }
        }
    }
    @Published public var morningHour: Int = 9 { didSet { preferences.morningHour = morningHour } }
    @Published public var syncMinutes: Double = 1 {
        didSet { preferences.syncInterval = syncMinutes * 60 }
    }

    private let store: SettingsStore
    private let preferences: AppPreferences

    public init(store: SettingsStore = SettingsStore(),
                preferences: AppPreferences = AppPreferences()) {
        self.store = store
        self.preferences = preferences
        load()
    }

    public func load() {
        let library = store.snippets()
        signature = library.signature ?? ""
        snippets = library.snippets.map {
            EditableSnippet(name: $0.name, shortcut: $0.shortcut,
                            subject: $0.subject ?? "", body: $0.body)
        }
        rules = store.rules().rules.map { rule in
            EditableRule(id: rule.id, name: rule.name, isEnabled: rule.isEnabled,
                         senderContains: rule.conditions.compactMap(\.senderText).first ?? "",
                         archives: rule.actions.contains(.archive))
        }
        loadsImages = preferences.loadsRemoteImages
        showsNotifications = preferences.showsNotifications
        undoWindow = preferences.undoWindow
        snoozeHours = preferences.snoozeHours
        morningHour = preferences.morningHour
        syncMinutes = preferences.syncInterval / 60
        let ai = store.ai()
        aiProvider = ai.provider ?? ""
        aiModel = ai.model ?? ""
        aiAPIKey = ai.apiKey ?? ""
        status = .idle
    }

    /// Adds a row already filled in, because an empty one gives the writer
    /// nothing to replace and no idea what belongs there.
    public func addSnippet() {
        snippets.append(EditableSnippet(name: "New snippet", shortcut: "new",
                                        subject: "", body: ""))
    }

    public func removeSnippet(at index: Int) {
        guard snippets.indices.contains(index) else { return }
        snippets.remove(at: index)
    }

    public func addRule() {
        rules.append(EditableRule(id: UUID().uuidString, name: "New rule",
                                  isEnabled: true, senderContains: "example.com",
                                  archives: true))
    }

    public func removeRule(at index: Int) {
        guard rules.indices.contains(index) else { return }
        rules.remove(at: index)
    }

    /// Writes everything, and says which part refused if one did.
    public func save() {
        do {
            try store.saveSnippets(SnippetLibrary(
                signature: signature.isEmpty ? nil : signature,
                snippets: snippets.compactMap(\.saveable)))
            try store.saveRules(RuleLibrary(rules: rules.compactMap(\.saveable)))
            try store.saveAI(provider: aiProvider, model: aiModel, apiKey: aiAPIKey)
            status = .saved
        } catch {
            status = .failed("Could not write settings. Check ~/.config/velomail.")
        }
    }
}

private extension SettingsViewModel.EditableSnippet {
    /// A snippet with no shortcut could never be triggered, so storing it is
    /// storing a puzzle.
    var saveable: Snippet? {
        let trimmed = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Snippet(name: name, shortcut: trimmed,
                       subject: subject.isEmpty ? nil : subject, body: body)
    }
}

private extension SettingsViewModel.EditableRule {
    /// A rule with nothing to match matches everything, and these actions are
    /// not undoable in bulk.
    var saveable: MailRule? {
        let trimmed = senderContains.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return MailRule(id: id, name: name, isEnabled: isEnabled,
                        conditions: [.senderContains(trimmed)],
                        actions: archives ? [.archive] : [])
    }
}

private extension RuleCondition {
    var senderText: String? {
        if case let .senderContains(text) = self { return text }
        return nil
    }
}
