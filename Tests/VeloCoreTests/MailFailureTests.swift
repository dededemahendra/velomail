import Testing
import Foundation
@testable import VeloCore

/// A writer that refuses everything, so a mutation can be driven to the cap.
private final class RefusingWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        throw AuthError.server(code: "500", description: "boom")
    }
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        throw AuthError.server(code: "500", description: "boom")
    }
}

@Suite struct MailFailureTests {
    private func makeContext() throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let service = OutboundService(writer: RefusingWriter(), store: store, mutations: mutations,
                                      identity: "me@example.com",
                                      now: { Date(timeIntervalSince1970: 1) })
        return (service, store, mutations)
    }

    private func seedThread(_ store: MailStore, id: String) throws {
        try store.upsert(MailThread(id: id, sender: "Alice <alice@x.com>", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))
        try store.upsert(Message(id: "m-\(id)", threadID: id, sender: "Alice <alice@x.com>",
                                 recipients: ["me@example.com"], subject: "Lunch on Sunday",
                                 date: Date(timeIntervalSince1970: 1), bodyHTML: nil,
                                 bodyText: "b", isUnread: false, labelIDs: ["INBOX"]))
    }


    // MARK: - What counts as given up on

    @Test func aMutationUnderTheCapIsNotAFailureYet() async throws {
        // It will be retried on the next tick, so telling the user now would be
        // crying wolf over a dropped connection.
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t")
        try service.archive(threadID: "t")
        try await service.drain()

        #expect(try service.failures(maxAttempts: 3).isEmpty)
        #expect(try mutations.all().first?.attempts == 1)
    }

    @Test func aMutationAtTheCapIsAFailure() async throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t")
        try service.archive(threadID: "t")
        for _ in 0..<3 {
            try await service.drain()
            try mutations.retryFailed(maxAttempts: 3)
        }

        #expect(try service.failures(maxAttempts: 3).count == 1)
    }

    // MARK: - What it says

    @Test func aFailedSendNamesItsSubject() async throws {
        let (service, _, mutations) = try makeContext()
        let draft = Draft(to: ["bob@x.com"], subject: "Lunch on Sunday", bodyText: "1pm?")
        _ = try service.send(draft, after: 0)
        for _ in 0..<3 {
            try await service.drain()
            try mutations.retryFailed(maxAttempts: 3)
        }

        let failure = try #require(try service.failures(maxAttempts: 3).first)
        #expect(failure.kind == .send)
        #expect(failure.summary == "Not sent: Lunch on Sunday")
    }

    @Test func aFailedSendKeepsTheDraftSoItCanBeReopened() async throws {
        let (service, _, mutations) = try makeContext()
        let draft = Draft(to: ["bob@x.com"], subject: "Lunch on Sunday", bodyText: "1pm?")
        _ = try service.send(draft, after: 0)
        for _ in 0..<3 {
            try await service.drain()
            try mutations.retryFailed(maxAttempts: 3)
        }

        let failure = try #require(try service.failures(maxAttempts: 3).first)
        #expect(failure.draft?.subject == "Lunch on Sunday")
        #expect(failure.draft?.bodyText == "1pm?")
    }

    @Test func aFailedArchiveSaysTheThreadCameBack() async throws {
        // drain() already reverted it, so the honest message is that nothing
        // was lost, not that something must now be fixed.
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t")
        try service.archive(threadID: "t")
        for _ in 0..<3 {
            try await service.drain()
            try mutations.retryFailed(maxAttempts: 3)
        }

        let failure = try #require(try service.failures(maxAttempts: 3).first)
        #expect(failure.kind == .archive)
        #expect(failure.summary == "Could not archive: Lunch on Sunday")
    }

    // MARK: - Clearing it

    @Test func reopeningHandsBackTheDraftAndClearsTheFailure() async throws {
        let (service, _, mutations) = try makeContext()
        _ = try service.send(Draft(to: ["bob@x.com"], subject: "Lunch", bodyText: "1pm?"), after: 0)
        for _ in 0..<3 {
            try await service.drain()
            try mutations.retryFailed(maxAttempts: 3)
        }
        let failure = try #require(try service.failures(maxAttempts: 3).first)

        let draft = try service.reopen(mutationID: failure.id)

        #expect(draft?.subject == "Lunch")
        #expect(try service.failures(maxAttempts: 3).isEmpty)
        #expect(try mutations.all().isEmpty)
    }

    @Test func dismissingClearsTheFailureWithoutTouchingTheMail() async throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t")
        try service.archive(threadID: "t")
        for _ in 0..<3 {
            try await service.drain()
            try mutations.retryFailed(maxAttempts: 3)
        }
        let failure = try #require(try service.failures(maxAttempts: 3).first)

        try service.dismiss(mutationID: failure.id)

        #expect(try service.failures(maxAttempts: 3).isEmpty)
        #expect(try mutations.all().isEmpty)
        // The revert already happened when the push failed; dismissing must not
        // undo the revert and archive it a second time.
        #expect(try store.inboxThreads().map(\.id) == ["t"])
    }

    @Test func aStillPendingMutationIsNeverReopened() async throws {
        // Reopening a send that is still on its way would send it twice.
        let (service, _, _) = try makeContext()
        let queued = try #require(try service.send(
            Draft(to: ["bob@x.com"], subject: "Lunch", bodyText: "?"), after: 600))

        #expect(try service.reopen(mutationID: queued) == nil)
    }
}
