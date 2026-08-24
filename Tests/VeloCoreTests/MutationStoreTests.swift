import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct MutationStoreTests {
    private func makeStore() throws -> MutationStore {
        MutationStore(try AppDatabase.makeInMemory())
    }

    private func mutation(_ kind: MutationKind = .archive) -> PendingMutation {
        PendingMutation(kind: kind, payload: Data("{}".utf8),
                        createdAt: Date(timeIntervalSince1970: 100), status: .pending)
    }

    @Test func enqueueReturnsRowWithID() throws {
        let store = try makeStore()
        let saved = try store.enqueue(mutation())
        #expect(saved.id != nil)
    }

    @Test func pendingReturnsOnlyPendingFIFO() throws {
        let store = try makeStore()
        let first = try store.enqueue(mutation())
        let middle = try store.enqueue(mutation())
        let third = try store.enqueue(mutation())
        try store.markFailed(id: middle.id!)

        let pending = try store.pending()
        #expect(pending.map(\.id) == [first.id, third.id])
    }

    @Test func markFailedKeepsRowInAllAsFailed() throws {
        let store = try makeStore()
        let saved = try store.enqueue(mutation())
        try store.markFailed(id: saved.id!)

        #expect(try store.pending().isEmpty)
        let all = try store.all()
        #expect(all.count == 1)
        #expect(all.first?.status == .failed)
    }

    @Test func deleteRemovesRow() throws {
        let store = try makeStore()
        let saved = try store.enqueue(mutation())
        try store.delete(id: saved.id!)
        #expect(try store.all().isEmpty)
    }

    @Test func enqueuePreservesAscendingOrder() throws {
        let store = try makeStore()
        _ = try store.enqueue(mutation())
        _ = try store.enqueue(mutation())
        _ = try store.enqueue(mutation())
        let ids = try store.pending().map { $0.id! }
        #expect(ids == ids.sorted())
    }

    @Test func markFailedAndDeleteUnknownIDAreNoOps() throws {
        let store = try makeStore()
        let saved = try store.enqueue(mutation())
        try store.markFailed(id: 999)
        try store.delete(id: 999)
        #expect(try store.all().count == 1)
        #expect(try store.all().first?.id == saved.id)
    }

    @Test func sendMutationRoundTripsThroughTheQueue() throws {
        let store = try makeStore()
        let draft = Draft(to: ["a@b.com"], subject: "hi", bodyText: "body")
        let payload = OutboundSendPayload(draft: draft, messageID: "<x@example.com>",
                                          placeholderMessageID: "local:1",
                                          threadID: "t1", createdThread: false)
        let encoded = try JSONEncoder().encode(payload)
        _ = try store.enqueue(PendingMutation(kind: .send, payload: encoded,
                                              createdAt: Date(timeIntervalSince1970: 1),
                                              status: .pending))

        let pending = try #require(try store.pending().first)
        #expect(pending.kind == .send)
        let decoded = try JSONDecoder().decode(OutboundSendPayload.self, from: pending.payload)
        #expect(decoded == payload)
        #expect(decoded.draft.subject == "hi")
    }

    // MARK: - Bounded retry (F1)

    @Test func newMutationsStartWithZeroAttempts() throws {
        let store = try makeStore()
        let saved = try store.enqueue(mutation())
        #expect(saved.attempts == 0)
    }

    @Test func markFailedIncrementsAttempts() throws {
        let store = try makeStore()
        let saved = try store.enqueue(mutation())
        let id = try #require(saved.id)

        try store.markFailed(id: id)
        #expect(try store.all().first?.attempts == 1)

        // A second failure of the same row must count again, not reset.
        try store.retryFailed(maxAttempts: 3)
        try store.markFailed(id: id)
        #expect(try store.all().first?.attempts == 2)
    }

    @Test func retryFailedRequeuesFailedMutationsUnderTheCap() throws {
        let store = try makeStore()
        let id = try #require(try store.enqueue(mutation()).id)
        try store.markFailed(id: id)
        #expect(try store.pending().isEmpty)

        try store.retryFailed(maxAttempts: 3)

        #expect(try store.pending().count == 1)
        #expect(try store.all().first?.status == .pending)
        #expect(try store.all().first?.attempts == 1)   // history preserved
    }

    @Test func retryFailedLeavesMutationsAtTheCapFailed() throws {
        let store = try makeStore()
        let id = try #require(try store.enqueue(mutation()).id)
        for _ in 0..<3 {
            try store.markFailed(id: id)
            try store.retryFailed(maxAttempts: 3)
        }

        // Third failure hits the cap, so the last retry must not requeue it.
        #expect(try store.all().first?.attempts == 3)
        #expect(try store.all().first?.status == .failed)
        #expect(try store.pending().isEmpty)
    }

    @Test func retryFailedIgnoresPendingRows() throws {
        let store = try makeStore()
        _ = try store.enqueue(mutation())

        try store.retryFailed(maxAttempts: 3)

        #expect(try store.all().first?.attempts == 0)
        #expect(try store.pending().count == 1)
    }

    // MARK: - Scheduling (M1)

    private var epoch: Date { Date(timeIntervalSince1970: 1_000) }

    @Test func mutationsWithNoDueDateAreDueImmediately() throws {
        let store = try makeStore()
        _ = try store.enqueue(mutation())
        // Archive and mark-read never schedule; they must be unaffected.
        #expect(try store.pending(due: epoch).count == 1)
    }

    @Test func aFutureMutationIsNotYetDue() throws {
        let store = try makeStore()
        _ = try store.enqueue(PendingMutation(kind: .send, payload: Data("{}".utf8),
                                              createdAt: epoch, dueAt: epoch.addingTimeInterval(10)))
        #expect(try store.pending(due: epoch).isEmpty)
    }

    @Test func aMutationBecomesDueWhenItsTimeArrives() throws {
        let store = try makeStore()
        _ = try store.enqueue(PendingMutation(kind: .send, payload: Data("{}".utf8),
                                              createdAt: epoch, dueAt: epoch.addingTimeInterval(10)))
        #expect(try store.pending(due: epoch.addingTimeInterval(10)).count == 1)
    }

    @Test func dueMutationsStillComeOutOldestFirst() throws {
        let store = try makeStore()
        let first = try store.enqueue(PendingMutation(kind: .archive, payload: Data("{}".utf8),
                                                      createdAt: epoch, dueAt: nil))
        let second = try store.enqueue(PendingMutation(kind: .send, payload: Data("{}".utf8),
                                                       createdAt: epoch, dueAt: epoch))
        #expect(try store.pending(due: epoch).map(\.id) == [first.id, second.id])
    }

    @Test func dueAtSurvivesARoundTrip() throws {
        let store = try makeStore()
        let saved = try store.enqueue(PendingMutation(kind: .send, payload: Data("{}".utf8),
                                                      createdAt: epoch, dueAt: epoch.addingTimeInterval(600)))
        #expect(try store.all().first?.dueAt == saved.dueAt)
    }
}
