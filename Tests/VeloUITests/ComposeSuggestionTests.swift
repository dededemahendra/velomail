import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct SilentWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct ComposeSuggestionTests {
    private func makeModel() throws -> ComposeViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let book = AddressBook(contacts: [
            .init(address: "natalie@sistercreatives.co", name: "Natalie Roberts", count: 9),
            .init(address: "nat@other.com", name: nil, count: 1),
            .init(address: "gede@sistercreatives.co", name: "Gede Mahendra", count: 4),
        ])
        return ComposeViewModel(
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com", addressBook: book)
    }

    @Test func typingOffersMatchingContacts() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "nat"

        #expect(model.suggestions.map(\.address).contains("natalie@sistercreatives.co"))
    }

    @Test func anEmptyFieldOffersNothing() throws {
        let model = try makeModel()
        model.startNew()
        #expect(model.suggestions.isEmpty)
    }

    @Test func onlyTheAddressBeingTypedIsMatched() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "gede@sistercreatives.co, nat"

        // The completed one must not keep matching itself.
        #expect(model.suggestions.allSatisfy { $0.address != "gede@sistercreatives.co" })
        #expect(model.suggestions.contains { $0.address == "natalie@sistercreatives.co" })
    }

    @Test func acceptingASuggestionCompletesTheField() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "nat"

        model.accept(.init(address: "natalie@sistercreatives.co", name: "Natalie Roberts", count: 9))

        #expect(model.to == "Natalie Roberts <natalie@sistercreatives.co>, ")
        // And stops offering, so the list does not hang around after choosing.
        #expect(model.suggestions.isEmpty)
    }

    @Test func acceptingKeepsEarlierRecipients() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "gede@sistercreatives.co, nat"

        model.accept(.init(address: "natalie@sistercreatives.co", name: "Natalie Roberts", count: 9))

        #expect(model.to == "gede@sistercreatives.co, Natalie Roberts <natalie@sistercreatives.co>, ")
    }

    @Test func aCompletedAddressStillSends() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "nat"
        model.accept(.init(address: "natalie@sistercreatives.co", name: "Natalie Roberts", count: 9))

        // The trailing separator must not become an empty recipient.
        #expect(model.canSend)
    }

    @Test func withNoAddressBookNothingIsOffered() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let model = ComposeViewModel(
            outbound: OutboundService(writer: SilentWriter(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com")
        model.startNew()
        model.to = "nat"

        #expect(model.suggestions.isEmpty)
    }

    // MARK: - Choosing without the mouse

    @Test func theFirstMatchIsHighlightedToBeginWith() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "nat"
        #expect(model.highlighted == 0)
    }

    @Test func theHighlightMovesThroughTheList() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "nat"
        model.moveHighlight(by: 1)
        #expect(model.highlighted == 1)
    }

    @Test func theHighlightWrapsRatherThanSticking() throws {
        // Holding the down arrow past the end should come back round, not stall
        // on the last row with nothing appearing to happen.
        let model = try makeModel()
        model.startNew()
        model.to = "nat"
        let last = model.suggestions.count - 1
        model.moveHighlight(by: last + 1)
        #expect(model.highlighted == 0)
        model.moveHighlight(by: -1)
        #expect(model.highlighted == last)
    }

    @Test func typingAgainReturnsToTheFirstMatch() throws {
        // The list has changed underneath, so a stale highlight would point at
        // whoever happens to sit in that row now.
        let model = try makeModel()
        model.startNew()
        model.to = "nat"
        model.moveHighlight(by: 1)
        model.to = "nata"
        #expect(model.highlighted == 0)
    }

    @Test func returnTakesTheHighlightedContact() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "ged"

        #expect(model.acceptHighlighted())
        #expect(model.to.hasPrefix("Gede Mahendra <gede@sistercreatives.co>"))
    }

    @Test func returnDoesNothingWithNoMatches() throws {
        // Otherwise the key would be swallowed and the message never sent.
        let model = try makeModel()
        model.startNew()
        model.to = "zzz"
        #expect(!model.acceptHighlighted())
    }

    @Test func acceptingClearsTheListUntilMoreIsTyped() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "ged"
        _ = model.acceptHighlighted()
        #expect(model.suggestions.isEmpty)
    }

    @Test func escapeGetsTheListOutOfTheWay() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "nat"
        model.dismissSuggestions()
        #expect(model.suggestions.isEmpty)
    }

    @Test func typingBringsTheListBack() throws {
        let model = try makeModel()
        model.startNew()
        model.to = "nat"
        model.dismissSuggestions()
        model.to = "nata"
        #expect(!model.suggestions.isEmpty)
    }
}
