import Testing
import Foundation
@testable import VeloUI

/// The first screen someone sees, and the only one that can leave them stuck.
///
/// It was a paragraph with bullets inside it. These pin the things that make
/// the difference between instructions and a wall of text: an order, the exact
/// strings to paste, somewhere to go, and a way out for a person who would
/// rather look before committing.
@Suite struct SetupStepsTests {
    @Test func theStepsAreNumberedInOrderFromOne() {
        #expect(Setup.steps.map(\.number) == Array(1...Setup.steps.count))
    }

    @Test func everyStepSaysWhatItIsAndWhy() {
        for step in Setup.steps {
            #expect(!step.title.isEmpty)
            #expect(!step.detail.isEmpty, "step \(step.number) has a title and no explanation")
        }
    }

    /// The values are long and exact, and nobody should be retyping them.
    @Test func theStepsThatNeedExactStringsCarryThem() {
        let snippets = Setup.steps.compactMap(\.snippet)
        #expect(snippets.contains { $0.contains("VELOMAIL_CLIENT_ID") })
        #expect(snippets.contains { $0.contains("VELOMAIL_CLIENT_SECRET") })
        #expect(snippets.contains { $0.contains("~/.config/velomail/config.json") })
    }

    /// "Create an OAuth client" is not something you can do from here, so the
    /// step has to say where.
    @Test func theStepDoneElsewhereSaysWhere() throws {
        let linked = try #require(Setup.steps.first { $0.link != nil })
        #expect(linked.link?.host?.contains("console.cloud.google.com") == true)
    }

    /// A first screen that only makes demands is a first screen people close.
    @Test func thereIsAWayToLookAroundWithoutSettingAnyOfItUp() {
        #expect(Setup.demoHint.contains("VELOMAIL_DEMO=1"))
    }

    /// The old prose had a line-continuation fault that printed
    /// "VELOMAIL_CLIENT_SECRET,         or" with the gap in it.
    @Test func noStepCarriesStrayRunsOfWhitespace() {
        for step in Setup.steps {
            for text in [step.title, step.detail] {
                #expect(!text.contains("  "), "\(step.number) has a double space: \(text)")
            }
        }
    }
}
