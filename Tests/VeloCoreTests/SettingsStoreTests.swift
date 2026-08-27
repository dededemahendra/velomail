import Testing
import Foundation
@testable import VeloCore

@Suite struct SettingsStoreTests {
    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("velo-settings-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func store(_ directory: URL) -> SettingsStore { SettingsStore(directory: directory) }

    // MARK: - Signature and snippets

    @Test func aSignatureSurvivesBeingWrittenAndReadBack() throws {
        let directory = makeDirectory()
        try store(directory).saveSnippets(
            SnippetLibrary(signature: "Warren\nLiving Legacy Forest", snippets: []))

        #expect(store(directory).snippets().signature == "Warren\nLiving Legacy Forest")
    }

    @Test func snippetsKeepTheirShortcuts() throws {
        let directory = makeDirectory()
        try store(directory).saveSnippets(SnippetLibrary(
            signature: nil,
            snippets: [Snippet(name: "Thanks", shortcut: "thx", body: "Thanks so much.")]))

        let loaded = store(directory).snippets()
        #expect(loaded.snippets.map(\.shortcut) == ["thx"])
        #expect(loaded.snippets.first?.body == "Thanks so much.")
    }

    @Test func savingSnippetsLeavesTheSignatureAlone() throws {
        // They share a file, so writing one must not blank the other.
        let directory = makeDirectory()
        let settings = store(directory)
        try settings.saveSnippets(SnippetLibrary(signature: "Warren", snippets: []))

        try settings.saveSnippets(SnippetLibrary(
            signature: settings.snippets().signature,
            snippets: [Snippet(name: "Hi", shortcut: "hi", body: "Hello")]))

        #expect(store(directory).snippets().signature == "Warren")
    }

    // MARK: - Rules

    @Test func rulesRoundTrip() throws {
        let directory = makeDirectory()
        let rule = MailRule(id: "r1", name: "Newsletters",
                            conditions: [.senderContains("news")], actions: [.archive])
        try store(directory).saveRules(RuleLibrary(rules: [rule]))

        #expect(store(directory).rules().rules.map(\.name) == ["Newsletters"])
    }

    @Test func rulesStayReadableInATextEditor() throws {
        // The point of a file is that a person can read it. Rules act without
        // asking, and one nobody can inspect is one nobody trusts.
        let directory = makeDirectory()
        try store(directory).saveRules(RuleLibrary(
            rules: [MailRule(id: "r1", name: "Newsletters",
                             conditions: [.senderContains("news")], actions: [.archive])]))

        let text = try String(contentsOf: directory.appendingPathComponent("rules.json"),
                              encoding: .utf8)
        #expect(text.contains("\n"))          // pretty-printed, not one long line
        #expect(text.contains("Newsletters"))
    }

    // MARK: - The config file, which also holds credentials

    @Test func savingAIKeepsTheOAuthCredentials() throws {
        // The same file holds the client secret. Replacing it wholesale would
        // sign the user out and lose a credential they had to fetch by hand.
        let directory = makeDirectory()
        try #"{"clientID":"abc.apps.googleusercontent.com","clientSecret":"shh"}"#
            .write(to: directory.appendingPathComponent("config.json"),
                   atomically: true, encoding: .utf8)

        try store(directory).saveAI(provider: "anthropic", model: "claude-opus-5", apiKey: "sk-1")

        let text = try String(contentsOf: directory.appendingPathComponent("config.json"),
                              encoding: .utf8)
        #expect(text.contains("shh"))
        #expect(text.contains("abc.apps.googleusercontent.com"))
        #expect(text.contains("sk-1"))
    }

    @Test func aiSettingsReadBack() throws {
        let directory = makeDirectory()
        try store(directory).saveAI(provider: "ollama", model: "llama3", apiKey: nil)

        let ai = store(directory).ai()
        #expect(ai.provider == "ollama")
        #expect(ai.model == "llama3")
    }

    @Test func clearingTheKeyRemovesIt() throws {
        let directory = makeDirectory()
        let settings = store(directory)
        try settings.saveAI(provider: "anthropic", model: "m", apiKey: "sk-1")

        try settings.saveAI(provider: "anthropic", model: "m", apiKey: "")

        #expect(settings.ai().apiKey == nil)
    }

    @Test func aMalformedConfigIsNotOverwrittenBlindly() throws {
        // Better to refuse than to throw away a file we could not understand,
        // which may hold the only copy of a credential.
        let directory = makeDirectory()
        let file = directory.appendingPathComponent("config.json")
        try "{ this is not json".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try store(directory).saveAI(provider: "x", model: "y", apiKey: "z")
        }
        #expect(try String(contentsOf: file, encoding: .utf8).contains("this is not json"))
    }

    // MARK: - Making the directory

    @Test func aFirstSaveCreatesTheFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("velo-fresh-\(UUID().uuidString)", isDirectory: true)

        try store(directory).saveSnippets(SnippetLibrary(signature: "Hi", snippets: []))

        #expect(store(directory).snippets().signature == "Hi")
    }
}
