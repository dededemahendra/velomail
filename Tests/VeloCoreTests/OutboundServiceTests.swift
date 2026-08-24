import Testing
import Foundation
import GRDB
@testable import VeloCore

/// Writer stub — B4 exercises optimistic apply only, so the writer is never called.
private struct UnusedWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        fatalError("batchModify not called during optimistic apply")
    }

    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        fatalError("send not called during optimistic apply")
    }
}

/// Scripted writer that throws when the batch contains any failing message id.
private final class ScriptedWriter: GmailWriting {
    var failingMessageIDs: Set<String>
    private(set) var batchCalls: [(ids: [String], add: [String], remove: [String])] = []

    init(failing: Set<String> = []) { self.failingMessageIDs = failing }

    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        batchCalls.append((ids, addLabelIDs, removeLabelIDs))
        if !failingMessageIDs.isDisjoint(with: Set(ids)) {
            throw AuthError.server(code: "500", description: "boom")
        }
    }

    /// Scripted send: records the raw payload, then either throws or returns
    /// `sendResult` (defaulting to a plausible created resource).
    var sendShouldFail = false
    var sendResult: GmailMessageDTO?
    private(set) var sendCalls: [(raw: String, threadID: String?)] = []

    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        sendCalls.append((raw, threadID))
        if sendShouldFail { throw AuthError.server(code: "500", description: "boom") }
        if let sendResult { return sendResult }
        return try decodeMessageDTO(#"""
        {"id":"sent1","threadId":"\#(threadID ?? "tServer")","labelIds":["SENT"],
         "internalDate":"100000","payload":{"mimeType":"text/plain","headers":[]}}
        """#)
    }
}

func decodeMessageDTO(_ json: String) throws -> GmailMessageDTO {
    try JSONDecoder().decode(GmailMessageDTO.self, from: Data(json.utf8))
}

@Suite struct OutboundServiceTests {
    private func makeContext(now: @escaping () -> Date = { Date(timeIntervalSince1970: 42) })
        throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let service = OutboundService(writer: UnusedWriter(), store: store, mutations: mutations,
                                      identity: "me@example.com", now: now, newID: counter())
        return (service, store, mutations)
    }

    /// Deterministic id source: "id1", "id2", ... so placeholder ids and
    /// Message-IDs are assertable.
    private func counter() -> () -> String {
        let box = Counter()
        return { box.next() }
    }

    private func sendPayload(_ mutation: PendingMutation) throws -> OutboundSendPayload {
        try JSONDecoder().decode(OutboundSendPayload.self, from: mutation.payload)
    }

    private func seedThread(_ store: MailStore, id: String, labels: [String], unread: Bool,
                            messageIDs: [String]) throws {
        try store.upsert(MailThread(id: id, snippet: id, lastMessageDate: Date(timeIntervalSince1970: 100),
                                    isUnread: unread, hasAttachments: false, labelIDs: labels))
        for (i, mid) in messageIDs.enumerated() {
            try store.upsert(Message(id: mid, threadID: id, sender: "x", recipients: [], subject: "",
                                     date: Date(timeIntervalSince1970: TimeInterval(i)),
                                     bodyHTML: nil, bodyText: nil, isUnread: unread, labelIDs: labels))
        }
    }

    private func payload(_ mutation: PendingMutation) throws -> OutboundMutationPayload {
        try JSONDecoder().decode(OutboundMutationPayload.self, from: mutation.payload)
    }

    @Test func archiveRemovesInboxLocallyAndEnqueues() async throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1", "m2"])

        try service.archive(threadID: "t")

        #expect(try store.inboxThreads().isEmpty)
        let pending = try mutations.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .archive)
        let p = try payload(pending[0])
        #expect(p.removeLabelIDs == ["INBOX"])
        #expect(p.addLabelIDs == [])
        #expect(p.messageIDs == ["m1", "m2"])
        #expect(p.previousMessageLabels["m1"]?.contains("INBOX") == true)
        #expect(try store.message(id: "m1")?.labelIDs.contains("INBOX") == false)   // message row updated too
    }

    @Test func markReadClearsUnreadLocallyAndEnqueues() async throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX", "UNREAD"], unread: true, messageIDs: ["m1"])

        try service.markRead(threadID: "t")

        #expect(try store.thread(id: "t")?.isUnread == false)
        let p = try payload(try mutations.pending()[0])
        #expect(p.removeLabelIDs == ["UNREAD"])
        #expect(try mutations.pending()[0].kind == .markRead)
    }

    @Test func markUnreadSetsUnreadLocallyAndEnqueues() async throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.markUnread(threadID: "t")

        #expect(try store.thread(id: "t")?.isUnread == true)
        let p = try payload(try mutations.pending()[0])
        #expect(p.addLabelIDs == ["UNREAD"])
        #expect(try mutations.pending()[0].kind == .markUnread)
    }

    @Test func archivePreservesUnreadFlag() async throws {
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX", "UNREAD"], unread: true, messageIDs: ["m1"])

        try service.archive(threadID: "t")

        let updated = try store.thread(id: "t")
        #expect(updated?.labelIDs == ["UNREAD"])
        #expect(updated?.isUnread == true)
    }

    @Test func unknownThreadIsNoOp() async throws {
        let (service, _, mutations) = try makeContext()
        try service.archive(threadID: "ghost")
        #expect(try mutations.pending().isEmpty)
    }

    @Test func optimisticApplyUpdatesMessagesSoReDerivationDoesNotResurrect() async throws {
        // Regression: markRead must update the message rows too, else a later
        // thread re-derivation (LabelDeltaApplier) resurrects UNREAD.
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX", "UNREAD"], unread: true, messageIDs: ["m1"])

        try service.markRead(threadID: "t")
        #expect(try store.message(id: "m1")?.labelIDs.contains("UNREAD") == false)

        // An unrelated incremental label delta re-derives the thread from its messages.
        try LabelDeltaApplier.apply([.init(messageID: "m1", added: ["IMPORTANT"], removed: [])], into: store)

        #expect(try store.thread(id: "t")?.isUnread == false)   // mark-read survives
    }

    @Test func createdAtUsesInjectedClock() async throws {
        let fixed = Date(timeIntervalSince1970: 777)
        let (service, store, mutations) = try makeContext(now: { fixed })
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.archive(threadID: "t")

        #expect(try mutations.pending()[0].createdAt == fixed)
    }

    // MARK: - Drain (B5)

    private func makeDrainContext(writer: ScriptedWriter)
        throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let service = OutboundService(writer: writer, store: store, mutations: mutations,
                                      identity: "me@example.com",
                                      now: { Date(timeIntervalSince1970: 1) },
                                      newID: counter())
        return (service, store, mutations)
    }

    @Test func drainSuccessModifiesEveryMessageThenDeletesRow() async throws {
        let writer = ScriptedWriter()
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1", "m2"])
        try service.archive(threadID: "t")

        try await service.drain()

        #expect(writer.batchCalls.count == 1)                 // one atomic call, not per-message
        #expect(writer.batchCalls.first?.ids == ["m1", "m2"])
        #expect(writer.batchCalls.first?.remove == ["INBOX"])
        #expect(try mutations.all().isEmpty)
        #expect(try store.inboxThreads().isEmpty)   // stays archived
    }

    @Test func drainUsesSingleAtomicBatchCallSoNoPartialApplication() async throws {
        let writer = ScriptedWriter(failing: ["m2"])   // second message fails
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1", "m2"])
        try service.archive(threadID: "t")

        try await service.drain()

        #expect(writer.batchCalls.count == 1)                 // atomic: not a per-message loop
        #expect(try store.inboxThreads().map(\.id) == ["t"])  // fully reverted, no half-applied state
        #expect(try mutations.all().first?.status == .failed)
    }

    @Test func drainFailureRevertsAndMarksFailed() async throws {
        let writer = ScriptedWriter(failing: ["m1"])
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX", "UNREAD"], unread: true, messageIDs: ["m1"])
        try service.archive(threadID: "t")

        try await service.drain()

        let reverted = try store.thread(id: "t")
        #expect(reverted?.labelIDs == ["INBOX", "UNREAD"])   // restored
        #expect(reverted?.isUnread == true)
        #expect(try store.inboxThreads().map(\.id) == ["t"])  // back in inbox
        #expect(try mutations.pending().isEmpty)
        #expect(try mutations.all().first?.status == .failed)
    }

    @Test func drainIsIdempotentAfterSuccess() async throws {
        let writer = ScriptedWriter()
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.archive(threadID: "t")

        try await service.drain()
        let callsAfterFirst = writer.batchCalls.count
        try await service.drain()

        #expect(writer.batchCalls.count == callsAfterFirst)   // no new calls
        #expect(try mutations.all().isEmpty)
    }

    @Test func drainProcessesMultipleMutations() async throws {
        let writer = ScriptedWriter()
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "a", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try seedThread(store, id: "b", labels: ["INBOX"], unread: false, messageIDs: ["m2"])
        try service.archive(threadID: "a")
        try service.archive(threadID: "b")

        try await service.drain()

        #expect(try mutations.all().isEmpty)
        #expect(try store.inboxThreads().isEmpty)
    }

    @Test func failedMutationDoesNotBlockGoodOne() async throws {
        let writer = ScriptedWriter(failing: ["m1"])
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "a", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try seedThread(store, id: "b", labels: ["INBOX"], unread: false, messageIDs: ["m2"])
        try service.archive(threadID: "a")
        try service.archive(threadID: "b")

        try await service.drain()

        #expect(try store.inboxThreads().map(\.id) == ["a"])   // a reverted, b archived
        let all = try mutations.all()
        #expect(all.count == 1)                                 // b deleted, a kept failed
        #expect(all.first?.status == .failed)
    }

    // MARK: - Send (optimistic apply)

    @Test func sendInsertsPlaceholderMessageLabelledSENTIntoExistingThread() throws {
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "Re: hi", bodyText: "yes",
                               threadID: "t", inReplyTo: "<p@x.com>", references: ["<p@x.com>"]))

        let messages = try store.messages(inThread: "t")
        #expect(messages.count == 2)
        let placeholder = try #require(messages.first { $0.id.hasPrefix("local:") })
        #expect(placeholder.labelIDs == ["SENT"])
        #expect(placeholder.sender == "me@example.com")
        #expect(placeholder.recipients == ["a@b.com"])
        #expect(placeholder.subject == "Re: hi")
        #expect(placeholder.bodyText == "yes")
        #expect(placeholder.inReplyTo == "<p@x.com>")
    }

    @Test func sendPlaceholderIsNotUnread() throws {
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        let placeholder = try #require(try store.messages(inThread: "t").first { $0.id.hasPrefix("local:") })
        #expect(placeholder.isUnread == false)
    }

    @Test func sendReDerivesThreadLabelsToIncludeSENT() throws {
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        #expect(try store.thread(id: "t")?.labelIDs == ["INBOX", "SENT"])
    }

    @Test func sendCreatesAPlaceholderThreadForANewCompose() throws {
        let (service, store, mutations) = try makeContext()

        try service.send(Draft(to: ["a@b.com"], subject: "Fresh", bodyText: "b"))

        let payload = try sendPayload(try #require(try mutations.pending().first))
        #expect(payload.createdThread == true)
        #expect(payload.threadID.hasPrefix("local:"))
        let thread = try #require(try store.thread(id: payload.threadID))
        #expect(thread.labelIDs == ["SENT"])
        #expect(try store.messages(inThread: payload.threadID).count == 1)
    }

    @Test func sendIntoAnExistingThreadDoesNotFlagCreatedThread() throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        let payload = try sendPayload(try #require(try mutations.pending().first))
        #expect(payload.createdThread == false)
        #expect(payload.threadID == "t")
    }

    @Test func sendEnqueuesASendMutationCarryingTheDraftAndPlaceholderIDs() throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        let draft = Draft(to: ["a@b.com"], cc: ["c@d.com"], subject: "s", bodyText: "b", threadID: "t")

        try service.send(draft)

        let pending = try mutations.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.kind == .send)
        let payload = try sendPayload(pending[0])
        #expect(payload.draft == draft)
        #expect(payload.placeholderMessageID.hasPrefix("local:"))
        #expect(try store.message(id: payload.placeholderMessageID) != nil)
    }

    @Test func sendStampsAMessageIDOnThePlaceholderAndThePayload() throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        let payload = try sendPayload(try #require(try mutations.pending().first))
        let placeholder = try #require(try store.message(id: payload.placeholderMessageID))
        #expect(placeholder.messageIDHeader == payload.messageID)
        // Domain comes from the sending identity, per RFC 5322.
        #expect(payload.messageID.hasSuffix("@example.com>"))
    }

    // MARK: - Drain (send)

    @Test func drainSendsRawBuiltFromTheQueuedDraft() async throws {
        let writer = ScriptedWriter()
        let (service, store, _) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.send(Draft(to: ["a@b.com"], subject: "Hello", bodyText: "hi", threadID: "t"))

        try await service.drain()

        #expect(writer.sendCalls.count == 1)
        let call = try #require(writer.sendCalls.first)
        #expect(call.threadID == "t")

        var padded = call.raw.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if padded.count % 4 > 0 { padded += String(repeating: "=", count: 4 - padded.count % 4) }
        let message = String(decoding: Data(base64Encoded: padded)!, as: UTF8.self)
        #expect(message.contains("From: me@example.com\r\n"))
        #expect(message.contains("To: a@b.com\r\n"))
        #expect(message.contains("Subject: Hello\r\n"))
        #expect(message.hasSuffix("aGk="))          // base64 of "hi"
    }

    @Test func drainReplacesPlaceholderWithTheRealMessageOnSuccess() async throws {
        let writer = ScriptedWriter()
        writer.sendResult = try decodeMessageDTO(
            #"{"id":"gmailID","threadId":"t","labelIds":["SENT"],"internalDate":"100000"}"#)
        let (service, store, _) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.send(Draft(to: ["a@b.com"], subject: "Hello", bodyText: "hi", threadID: "t"))

        try await service.drain()

        let messages = try store.messages(inThread: "t")
        #expect(messages.count == 2)
        #expect(messages.contains { $0.id == "gmailID" })
        #expect(!messages.contains { $0.id.hasPrefix("local:") })

        // The real row keeps everything the sparse send response cannot carry.
        let sent = try #require(try store.message(id: "gmailID"))
        #expect(sent.subject == "Hello")
        #expect(sent.bodyText == "hi")
        #expect(sent.recipients == ["a@b.com"])
        #expect(sent.labelIDs == ["SENT"])
        #expect(sent.messageIDHeader?.hasSuffix("@example.com>") == true)
    }

    @Test func drainRemovesTheQueueRowOnSuccessfulSend() async throws {
        let writer = ScriptedWriter()
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        try await service.drain()

        #expect(try mutations.all().isEmpty)
    }

    @Test func drainMovesTheMessageToTheServerThreadForANewCompose() async throws {
        let writer = ScriptedWriter()
        writer.sendResult = try decodeMessageDTO(
            #"{"id":"gmailID","threadId":"tServer","labelIds":["SENT"],"internalDate":"100000"}"#)
        let (service, store, _) = try makeDrainContext(writer: writer)
        try service.send(Draft(to: ["a@b.com"], subject: "Fresh", bodyText: "b"))

        try await service.drain()

        let sent = try #require(try store.message(id: "gmailID"))
        #expect(sent.threadID == "tServer")
        #expect(try store.thread(id: "tServer") != nil)
        // The invented local thread must not linger.
        #expect(try store.thread(id: "local:id3") == nil)
    }

    @Test func drainRevertsPlaceholderAndMarksFailedWhenSendFails() async throws {
        let writer = ScriptedWriter()
        writer.sendShouldFail = true
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        try await service.drain()

        #expect(try store.messages(inThread: "t").map(\.id) == ["m1"])
        #expect(try store.thread(id: "t")?.labelIDs == ["INBOX"])   // SENT re-derived away
        let all = try mutations.all()
        #expect(all.count == 1)
        #expect(all.first?.status == .failed)
    }

    @Test func drainKeepsTheDraftRecoverableAfterAFailedSend() async throws {
        let writer = ScriptedWriter()
        writer.sendShouldFail = true
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.send(Draft(to: ["a@b.com"], subject: "keep me", bodyText: "body", threadID: "t"))

        try await service.drain()

        let failed = try #require(try mutations.all().first)
        let payload = try sendPayload(failed)
        #expect(payload.draft.subject == "keep me")
        #expect(payload.draft.bodyText == "body")
    }

    @Test func drainDropsThePlaceholderThreadWhenAFailedSendCreatedIt() async throws {
        let writer = ScriptedWriter()
        writer.sendShouldFail = true
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b"))
        let threadID = try sendPayload(try #require(try mutations.pending().first)).threadID

        try await service.drain()

        #expect(try store.thread(id: threadID) == nil)
    }

    @Test func drainStillDrainsLabelMutationsAfterASendFailure() async throws {
        let writer = ScriptedWriter()
        writer.sendShouldFail = true
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))
        try service.archive(threadID: "t")

        try await service.drain()

        #expect(writer.batchCalls.count == 1)                       // archive still went out
        #expect(try store.inboxThreads().isEmpty)
        let statuses = try mutations.all().map(\.status)
        #expect(statuses == [.failed])                              // only the send remains
    }

    // MARK: - Thread invariants after a send

    @Test func sendBumpsTheThreadLastMessageDate() throws {
        let (service, store, _) = try makeContext(now: { Date(timeIntervalSince1970: 5000) })
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        // A thread you just replied to must sort to the top of a date-ordered inbox.
        #expect(try store.thread(id: "t")?.lastMessageDate == Date(timeIntervalSince1970: 5000))
    }

    @Test func drainReDerivesTheOriginalThreadWhenGmailRethreadsTheReply() async throws {
        let writer = ScriptedWriter()
        // Gmail declined the requested thread and made a new one.
        writer.sendResult = try decodeMessageDTO(
            #"{"id":"gmailID","threadId":"tOther","labelIds":["SENT"],"internalDate":"100000"}"#)
        let (service, store, _) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        try await service.drain()

        // The message left thread "t", so "t" must not keep the optimistic SENT.
        #expect(try store.thread(id: "t")?.labelIDs == ["INBOX"])
        #expect(try store.messages(inThread: "t").map(\.id) == ["m1"])
        #expect(try store.message(id: "gmailID")?.threadID == "tOther")
    }

    @Test func sendMakesTheSenderOfTheThreadTheAccountIdentity() throws {
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        // A list row shows who spoke last; after replying, that is you.
        #expect(try store.thread(id: "t")?.sender == "me@example.com")
    }

    // MARK: - Late-bound identity (I2)

    @Test func identityIsResolvedAtSendTimeNotConstructionTime() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        // The real address arrives with the first backfill, long after the
        // service is built, so it must not be captured at construction.
        var current = "placeholder@example.com"
        let service = OutboundService(writer: UnusedWriter(), store: store,
                                      mutations: MutationStore(db),
                                      identity: { current },
                                      now: { Date(timeIntervalSince1970: 1) },
                                      newID: counter())
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        current = "real@example.com"
        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        let placeholder = try #require(try store.messages(inThread: "t").first { $0.id.hasPrefix("local:") })
        #expect(placeholder.sender == "real@example.com")
        #expect(placeholder.messageIDHeader?.hasSuffix("@example.com>") == true)
    }

    @Test func theStringInitializerStillWorks() throws {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let service = OutboundService(writer: UnusedWriter(), store: store,
                                      mutations: MutationStore(db),
                                      identity: "fixed@example.com",
                                      now: { Date(timeIntervalSince1970: 1) },
                                      newID: counter())
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        #expect(try store.thread(id: "t")?.sender == "fixed@example.com")
    }

    // MARK: - Undo Send / Send Later (M2)

    @Test func anImmediateSendIsDueAtOnce() throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"))

        #expect(try mutations.pending(due: Date(timeIntervalSince1970: 42)).count == 1)
    }

    @Test func aDelayedSendIsNotDueUntilTheWindowPasses() throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"),
                         after: 10)

        // now() is fixed at 42 in this harness.
        #expect(try mutations.pending(due: Date(timeIntervalSince1970: 45)).isEmpty)
        #expect(try mutations.pending(due: Date(timeIntervalSince1970: 52)).count == 1)
    }

    @Test func sendReturnsTheMutationIdSoItCanBeUndone() throws {
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        let id = try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"),
                                  after: 10)

        #expect(id != nil)
    }

    @Test func theMessageStillAppearsImmediatelyWhileDelayed() throws {
        let (service, store, _) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])

        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"), after: 10)

        // Optimism is the point: the user sees it sent, we just hold it back.
        #expect(try store.messages(inThread: "t").contains { $0.id.hasPrefix("local:") })
    }

    @Test func cancellingRemovesTheQueuedSendAndThePlaceholder() throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        let id = try #require(try service.send(
            Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"), after: 10))

        try service.cancelSend(mutationID: id)

        #expect(try mutations.all().isEmpty)
        #expect(try store.messages(inThread: "t").map(\.id) == ["m1"])
        #expect(try store.thread(id: "t")?.labelIDs == ["INBOX"])   // SENT derived away
    }

    @Test func cancellingANewComposeAlsoRemovesTheInventedThread() throws {
        let (service, store, mutations) = try makeContext()
        let id = try #require(try service.send(
            Draft(to: ["a@b.com"], subject: "s", bodyText: "b"), after: 10))
        // A fresh compose is labelled SENT, so it is not in the inbox; the
        // invented thread id lives in the payload.
        let threadID = try sendPayload(try #require(try mutations.all().first)).threadID
        #expect(try store.thread(id: threadID) != nil)

        try service.cancelSend(mutationID: id)

        #expect(try store.thread(id: threadID) == nil)
    }

    @Test func cancellingAnUnknownIdIsANoOp() throws {
        let (service, _, _) = try makeContext()
        try service.cancelSend(mutationID: 999)
    }

    @Test func cancellingALabelMutationIsRefusedRatherThanCorrupting() throws {
        let (service, store, mutations) = try makeContext()
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.archive(threadID: "t")
        let id = try #require(try mutations.pending().first?.id)

        try service.cancelSend(mutationID: id)

        // cancelSend is for sends; decoding an archive payload as one would
        // throw, and silently deleting it would lose the archive.
        #expect(try mutations.all().count == 1)
    }

    @Test func drainSkipsASendThatIsNotYetDue() async throws {
        let writer = ScriptedWriter()
        let (service, store, mutations) = try makeDrainContext(writer: writer)
        try seedThread(store, id: "t", labels: ["INBOX"], unread: false, messageIDs: ["m1"])
        try service.send(Draft(to: ["a@b.com"], subject: "s", bodyText: "b", threadID: "t"),
                         after: 3_600)

        try await service.drain()

        #expect(writer.sendCalls.isEmpty)
        #expect(try mutations.all().count == 1)   // still queued, still waiting
    }
}

/// Mutable id counter for deterministic placeholder ids in tests.
private final class Counter {
    private var n = 0
    func next() -> String { n += 1; return "id\(n)" }
}