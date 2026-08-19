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
}
