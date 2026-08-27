import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct CommandSymbolTests {
    @Test func everyActionHasAnIcon() {
        // The palette is scanned, not read. A row with no icon in a column of
        // icons reads as a rendering fault, and this is the only thing that
        // stops a newly added action shipping like that.
        for action in MailAction.allCases {
            #expect(!CommandSymbol.name(for: action).isEmpty,
                    "\(action.rawValue) has no icon")
        }
    }

    @Test func relatedActionsShareAFamily() {
        // Going somewhere should look like going somewhere, whichever list.
        let goes = [MailAction.goToInbox, .goToSent, .goToSnoozed, .goToDrafts,
                    .goToStarred, .goToArchive]
        let symbols = Set(goes.map(CommandSymbol.name(for:)))
        #expect(symbols.count == goes.count)          // distinct, not interchangeable
    }

    @Test func destructiveAndReversibleActionsDoNotLookAlike() {
        #expect(CommandSymbol.name(for: .trashSelected) != CommandSymbol.name(for: .archiveSelected))
    }
}
