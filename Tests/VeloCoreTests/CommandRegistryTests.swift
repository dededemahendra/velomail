import Testing
@testable import VeloCore

@Suite struct CommandRegistryTests {
    private let registry = CommandRegistry.v1

    private func titles(_ query: String) -> [String] {
        registry.matches(query).map(\.title)
    }

    @Test func emptyQueryReturnsEveryCommandInRegistrationOrder() {
        #expect(registry.matches("") == registry.commands)
    }

    @Test func matchesAPlainPrefix() {
        #expect(titles("arch").contains("Archive"))
    }

    @Test func matchesASubsequenceNotJustAPrefix() {
        // Letters in order, gaps allowed — how every palette behaves.
        #expect(titles("gti").contains("Go to Inbox"))
        #expect(titles("cmps").contains("Compose"))
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(titles("ARCH").contains("Archive"))
    }

    @Test func matchingIgnoresSpacesInTheQuery() {
        #expect(titles("go to in").contains("Go to Inbox"))
    }

    @Test func noMatchReturnsEmpty() {
        #expect(registry.matches("zzzz").isEmpty)
    }

    @Test func lettersOutOfOrderDoNotMatch() {
        #expect(!titles("ihcra").contains("Archive"))
    }

    @Test func prefixMatchesOutrankLaterMatches() {
        let registry = CommandRegistry(commands: [
            Command(title: "Mark Read", action: .openCommandPalette),
            Command(title: "Reply", action: .reply),
        ])
        // "re" is a prefix of Reply but starts at index 5 of "Mark Read".
        #expect(registry.matches("re").map(\.title) == ["Reply", "Mark Read"])
    }

    @Test func shorterTitleWinsATie() {
        let registry = CommandRegistry(commands: [
            Command(title: "Reply All", action: .reply),
            Command(title: "Reply", action: .reply),
        ])
        #expect(registry.matches("rep").map(\.title) == ["Reply", "Reply All"])
    }

    @Test func starIsInThePalette() {
        #expect(registry.commands.contains { $0.action == .toggleStar })
        #expect(titles("star").contains("Star"))
    }

    @Test func selectIsInThePalette() {
        #expect(registry.commands.contains { $0.action == .toggleMark })
    }

    @Test func unsubscribeIsInThePalette() {
        #expect(registry.commands.contains { $0.action == .unsubscribe })
        #expect(titles("unsub").contains("Unsubscribe"))
    }

    @Test func everyV1ActionIsReachableFromThePalette() {
        // The palette is the discoverability net for the keymap, so nothing
        // should be keyboard-only.
        let reachable = Set(registry.commands.map(\.action))
        #expect(reachable == Set(MailAction.allCases))
    }
}
