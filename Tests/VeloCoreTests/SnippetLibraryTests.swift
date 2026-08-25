import Testing
import Foundation
@testable import VeloCore

@Suite struct SnippetLibraryTests {

    // MARK: - The library

    @Test func anEmptyLibraryHasNothingInIt() {
        #expect(SnippetLibrary.empty.signature == nil)
        #expect(SnippetLibrary.empty.snippets.isEmpty)
    }

    @Test func aSnippetIsFoundByItsShortcut() {
        let library = SnippetLibrary(snippets: [Snippet(name: "Thanks", shortcut: "thx", body: "Thanks.")])
        #expect(library.snippet(forShortcut: "thx")?.body == "Thanks.")
    }

    @Test func shortcutMatchingIsCaseInsensitive() {
        let library = SnippetLibrary(snippets: [Snippet(name: "Thanks", shortcut: "Thx", body: "Thanks.")])
        #expect(library.snippet(forShortcut: "THX") != nil)
        #expect(library.snippet(forShortcut: "thx") != nil)
    }

    @Test func shortcutsAreTrimmedOnConstruction() {
        // A hand-edited file is a hostile input: a trailing space in a shortcut
        // is invisible and would make the snippet unreachable forever.
        let library = SnippetLibrary(snippets: [Snippet(name: "Thanks", shortcut: "  thx  ", body: "Thanks.")])
        #expect(library.snippets.first?.shortcut == "thx")
        #expect(library.snippet(forShortcut: "thx") != nil)
    }

    @Test func aSnippetWithABlankShortcutIsDropped() {
        let library = SnippetLibrary(snippets: [
            Snippet(name: "Nameless", shortcut: "   ", body: "text"),
            Snippet(name: "Thanks", shortcut: "thx", body: "Thanks."),
        ])
        #expect(library.snippets.count == 1)
        #expect(library.snippets.first?.shortcut == "thx")
    }

    @Test func aSnippetWithABlankBodyIsDropped() {
        let library = SnippetLibrary(snippets: [Snippet(name: "Empty", shortcut: "e", body: "  \n ")])
        #expect(library.snippets.isEmpty)
    }

    @Test func theFirstOfTwoSnippetsSharingAShortcutWins() {
        // So the file reads top-down and a duplicate lower down cannot silently
        // shadow the one above it.
        let library = SnippetLibrary(snippets: [
            Snippet(name: "First", shortcut: "x", body: "one"),
            Snippet(name: "Second", shortcut: "X", body: "two"),
        ])
        #expect(library.snippets.count == 1)
        #expect(library.snippet(forShortcut: "x")?.body == "one")
    }

    @Test func aBlankSignatureIsNoSignature() {
        #expect(SnippetLibrary(signature: "   \n  ").signature == nil)
    }

    @Test func anUnknownShortcutFindsNothing() {
        let library = SnippetLibrary(snippets: [Snippet(name: "Thanks", shortcut: "thx", body: "Thanks.")])
        #expect(library.snippet(forShortcut: "nope") == nil)
    }

    @Test func aTemplateKeepsItsSubject() {
        let library = SnippetLibrary(snippets: [
            Snippet(name: "Intro", shortcut: "intro", subject: "Intro call?", body: "Does Thursday suit?"),
        ])
        #expect(library.snippet(forShortcut: "intro")?.subject == "Intro call?")
    }

    // MARK: - Resolution

    @Test func aFileWithASignatureAndSnippetsLoadsBoth() throws {
        let file = try write("""
            {"signature":"Warren\\nLiving Legacy Forest",
             "snippets":[{"name":"Thanks","shortcut":"thx","body":"Thanks so much."},
                         {"name":"Intro","shortcut":"intro","subject":"Intro call?","body":"Thursday?"}]}
            """)
        defer { try? FileManager.default.removeItem(at: file) }

        let library = SnippetLibrary.resolve(environment: [:], file: file)

        #expect(library.signature == "Warren\nLiving Legacy Forest")
        #expect(library.snippets.count == 2)
        #expect(library.snippet(forShortcut: "intro")?.subject == "Intro call?")
    }

    @Test func oneBadSnippetDoesNotCostYouTheRestOfTheFile() throws {
        // Decoding the array as a whole means a single typo silently discards
        // every snippet *and* the signature, which is exactly the failure a
        // hand-edited file is most likely to produce.
        let file = try write("""
            {"signature":"Warren",
             "snippets":[{"shortcut":"broken","body":42},
                         {"name":"Ok","shortcut":"ok","body":"Ok."}]}
            """)
        defer { try? FileManager.default.removeItem(at: file) }

        let library = SnippetLibrary.resolve(environment: [:], file: file)

        #expect(library.signature == "Warren")
        #expect(library.snippets.map(\.shortcut) == ["ok"])
    }

    @Test func aSnippetWithNoNameIsNamedAfterItsShortcut() throws {
        // The name is only ever shown to the user; not writing one should not
        // make the snippet disappear.
        let file = try write(#"{"snippets":[{"shortcut":"thx","body":"Thanks."}]}"#)
        defer { try? FileManager.default.removeItem(at: file) }

        let library = SnippetLibrary.resolve(environment: [:], file: file)

        #expect(library.snippet(forShortcut: "thx")?.name == "thx")
    }

    @Test func aMissingFileResolvesToAnEmptyLibrary() {
        let absent = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velomail-absent-\(UUID().uuidString).json")
        #expect(SnippetLibrary.resolve(environment: [:], file: absent) == .empty)
    }

    @Test func aMalformedFileResolvesToAnEmptyLibraryRatherThanThrowing() throws {
        // A typo in a snippets file must not stop a mail client launching.
        let file = try write("{ this is not json")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(SnippetLibrary.resolve(environment: [:], file: file) == .empty)
    }

    @Test func theEnvironmentSignatureOverridesTheFile() throws {
        let file = try write(#"{"signature":"from the file"}"#)
        defer { try? FileManager.default.removeItem(at: file) }

        let library = SnippetLibrary.resolve(environment: ["VELOMAIL_SIGNATURE": "from the env"],
                                             file: file)

        #expect(library.signature == "from the env")
    }

    @Test func theEnvironmentSignatureWorksWithNoFileAtAll() {
        #expect(SnippetLibrary.resolve(environment: ["VELOMAIL_SIGNATURE": "just me"],
                                       file: nil).signature == "just me")
    }

    // MARK: - Internals

    private func write(_ contents: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velomail-snippets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("snippets.json")
        try Data(contents.utf8).write(to: file)
        return file
    }
}
