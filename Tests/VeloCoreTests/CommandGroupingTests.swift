import Testing
import Foundation
@testable import VeloCore

@Suite struct CommandGroupingTests {
    private let registry = CommandRegistry.v1

    // MARK: - Groups

    @Test func everyCommandKnowsWhereItBelongs() {
        // Fifty commands in one flat column is a list nobody reads to the end
        // of. The default is `.mailbox`, so an unassigned one hides rather
        // than announcing itself -- this is the check that finds it.
        let stray = registry.commands.filter { $0.group == .mailbox }.map(\.title)
        #expect(stray.allSatisfy {
            ["Load older mail", "Sync now", "Open in Gmail", "Export thread",
             "Analytics", "Toggle remote images"].contains($0)
        }, "ungrouped: \(stray)")
    }

    @Test func theObviousOnesLandWhereYouWouldLook() {
        func group(_ title: String) -> CommandGroup? {
            registry.commands.first { $0.title == title }?.group
        }
        #expect(group("Archive") == .triage)
        #expect(group("Reply") == .write)
        #expect(group("Go to Sent") == .navigate)
        #expect(group("Settings") == .app)
        #expect(group("Summarise Thread") == .assistant)
    }

    // MARK: - Recents

    @Test func whatYouJustRanComesBackToTheTop() {
        let listed = registry.matches("", recents: [.showAnalytics, .reportSpam])
        #expect(listed.first?.action == .showAnalytics)
        #expect(listed.dropFirst().first?.action == .reportSpam)
    }

    @Test func nothingIsListedTwice() {
        let listed = registry.matches("", recents: [.archiveSelected])
        #expect(listed.filter { $0.action == .archiveSelected }.count == 1)
        #expect(listed.count == registry.commands.count)
    }

    @Test func typingBeatsRecency() {
        // Someone who has typed something knows what they are after, and
        // reordering by yesterday would move the answer out from under them.
        let listed = registry.matches("archive", recents: [.showAnalytics])
        #expect(listed.first?.title == "Archive")
    }

    @Test func aGroupIsNotScatteredDownTheList() {
        // Registration order left one group's commands strewn among the
        // others, so a heading covered whatever followed it rather than the
        // group it named.
        let listed = registry.matches("", recents: [])
        let order = listed.map(\.group)
        let firstSeen = order.enumerated().reduce(into: [CommandGroup: Int]()) { seen, pair in
            if seen[pair.element] == nil { seen[pair.element] = pair.offset }
        }
        for (index, group) in order.enumerated() {
            let start = firstSeen[group]!
            let run = order[start...].prefix { $0 == group }
            #expect(index < start + run.count,
                    "\(group) reappears at \(index) after its run ended")
        }
    }

    @Test func browsingLosesNothingFromTheCatalogue() {
        let listed = registry.matches("", recents: [])
        #expect(listed.count == registry.commands.count)
        #expect(Set(listed.map(\.title)) == Set(registry.commands.map(\.title)))
    }

    @Test func recentsStillLeadAndTheRestStayGrouped() {
        let listed = registry.matches("", recents: [.showAnalytics])
        #expect(listed.first?.action == .showAnalytics)
        #expect(listed.dropFirst().first?.group == .triage)
    }

    // MARK: - Remembering

    @Test func theNewestIsFirst() {
        let after = CommandRegistry.remember(.reply, in: [.archiveSelected])
        #expect(after == [.reply, .archiveSelected])
    }

    @Test func runningSomethingTwiceDoesNotListItTwice() {
        let after = CommandRegistry.remember(.reply, in: [.archiveSelected, .reply])
        #expect(after == [.reply, .archiveSelected])
    }

    @Test func itStopsBeingAShortcutIfItGrowsForever() {
        var recents: [MailAction] = []
        for action in [MailAction.reply, .forward, .compose, .send, .undo, .toggleStar] {
            recents = CommandRegistry.remember(action, in: recents)
        }
        #expect(recents.count == CommandRegistry.recentLimit)
        #expect(recents.first == .toggleStar)
    }
}
