import Testing
import Foundation
@testable import VeloCore

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        fatalError("nothing should be pushed before it is due")
    }
}

@Suite struct ScheduledSendTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeContext() throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let service = OutboundService(writer: Quiet(), store: store, mutations: mutations,
                                      identity: "me@x.com", now: { self.now })
        return (service, store, mutations)
    }

    private func draft(_ subject: String) -> Draft {
        Draft(to: ["bob@x.com"], subject: subject, bodyText: "b")
    }

    // MARK: - Listing

    @Test func aScheduledSendIsListed() throws {
        let (service, _, _) = try makeContext()
        _ = try service.send(draft("Tomorrow's note"), after: 86_400)

        let waiting = try service.scheduled(now: now)
        #expect(waiting.count == 1)
        #expect(waiting.first?.draft.subject == "Tomorrow's note")
        #expect(waiting.first?.dueAt == now.addingTimeInterval(86_400))
    }

    @Test func anUndoWindowIsNotASchedule() throws {
        // Every send sits in the queue for ten seconds so it can be taken back.
        // Listing those as "scheduled" would fill the screen with every message
        // the writer just sent.
        let (service, _, _) = try makeContext()
        _ = try service.send(draft("Just sent"), after: 10)

        #expect(try service.scheduled(now: now).isEmpty)
    }

    @Test func soonestFirst() throws {
        let (service, _, _) = try makeContext()
        _ = try service.send(draft("Next week"), after: 7 * 86_400)
        _ = try service.send(draft("Tomorrow"), after: 86_400)

        #expect(try service.scheduled(now: now).map(\.draft.subject) == ["Tomorrow", "Next week"])
    }

    @Test func aSendAlreadyDueIsNoLongerWaiting() throws {
        let (service, _, _) = try makeContext()
        _ = try service.send(draft("Due"), after: 86_400)

        #expect(try service.scheduled(now: now.addingTimeInterval(90_000)).isEmpty)
    }

    // MARK: - Nothing goes early

    @Test func drainLeavesAScheduledSendAlone() async throws {
        // The writer fixture fatalErrors on send, so this passing at all is the
        // proof: nothing was pushed.
        let (service, _, mutations) = try makeContext()
        _ = try service.send(draft("Tomorrow"), after: 86_400)

        try await service.drain()

        #expect(try mutations.all().count == 1)
    }

    // MARK: - Changing your mind

    @Test func aScheduledSendCanGoNow() throws {
        let (service, _, _) = try makeContext()
        _ = try service.send(draft("Tomorrow"), after: 86_400)
        let waiting = try #require(try service.scheduled(now: now).first)

        try service.sendNow(mutationID: waiting.id)

        #expect(try service.scheduled(now: now).isEmpty)
        #expect(try service.failures(maxAttempts: 3).isEmpty)
    }

    @Test func unschedulingHandsTheDraftBack() throws {
        // The words are not lost: they go back to the composer to be edited or
        // dropped, exactly like reopening a send that failed.
        let (service, _, mutations) = try makeContext()
        _ = try service.send(draft("Second thoughts"), after: 86_400)
        let waiting = try #require(try service.scheduled(now: now).first)

        let returned = try service.unschedule(mutationID: waiting.id)

        #expect(returned?.subject == "Second thoughts")
        #expect(try mutations.all().isEmpty)
    }

    @Test func unschedulingTakesBackTheLocalCopy() throws {
        // A scheduled send shows optimistically in the thread. Cancelling has
        // to remove it, or the writer sees a message they decided not to send.
        let (service, store, _) = try makeContext()
        _ = try service.send(draft("Second thoughts"), after: 86_400)
        let waiting = try #require(try service.scheduled(now: now).first)

        _ = try service.unschedule(mutationID: waiting.id)

        #expect(try store.sentThreads().isEmpty)
    }

    @Test func unschedulingSomethingUnknownIsHarmless() throws {
        let (service, _, _) = try makeContext()
        #expect(try service.unschedule(mutationID: 999) == nil)
    }
}
