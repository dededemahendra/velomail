import Foundation

/// The pre-change state and intended label change for one outbound mutation,
/// persisted in `PendingMutation.payload`. Everything needed to push the change
/// AND to revert it lives here (including each message's prior labels), so
/// `drain()` works even in a later process.
struct OutboundMutationPayload: Codable, Equatable {
    var threadID: String
    var messageIDs: [String]
    var addLabelIDs: [String]
    var removeLabelIDs: [String]
    var previousMessageLabels: [String: [String]]
}

/// The persisted payload of a queued `.send`. It carries the whole `Draft` so a
/// send survives a restart and a failed one can be re-opened, plus the ids of
/// the optimistic rows `drain()` must swap out or roll back.
struct OutboundSendPayload: Codable, Equatable {
    var draft: Draft
    /// The RFC 5322 `Message-ID` minted at enqueue time, so it is stable across
    /// a restart and identical on any later retry of the same send.
    var messageID: String
    /// The `local:`-prefixed id of the optimistically inserted message.
    var placeholderMessageID: String
    /// The thread the placeholder went into (a local id for a fresh compose).
    var threadID: String
    /// True when `send` invented the thread, so a failure must remove it too.
    var createdThread: Bool
}

/// Applies triage actions (archive, mark read/unread) optimistically to local
/// storage and enqueues a durable mutation for later push to Gmail.
public struct OutboundService: Sendable {
    private let writer: GmailWriting
    private let store: MailStore
    private let mutations: MutationStore
    private let resolveIdentity: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let newID: @Sendable () -> String

    /// - Parameters:
    ///   - identity: resolves the account's own address, used as the `From` of
    ///     anything sent. A closure rather than a value because the real
    ///     address arrives with the first backfill, long after this is built.
    ///   - newID: opaque unique-id source, injected so tests get stable ids.
    public init(writer: GmailWriting, store: MailStore, mutations: MutationStore,
                identity: @escaping @Sendable () -> String,
                now: @escaping @Sendable () -> Date = { Date() },
                newID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.writer = writer
        self.store = store
        self.mutations = mutations
        self.resolveIdentity = identity
        self.now = now
        self.newID = newID
    }

    /// Convenience for callers that genuinely know their address up front
    /// (tests, and the demo path).
    public init(writer: GmailWriting, store: MailStore, mutations: MutationStore,
                identity: String, now: @escaping @Sendable () -> Date = { Date() },
                newID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.init(writer: writer, store: store, mutations: mutations,
                  identity: { identity }, now: now, newID: newID)
    }

    /// The account's own address, resolved now rather than at construction.
    private var identity: String { resolveIdentity() }

    /// Applies a draft locally at once and queues the real send.
    ///
    /// A send has no row to mutate yet, so the optimistic apply has to invent
    /// one: a placeholder message under a `local:` id (which can never collide
    /// with a Gmail id), in the draft's thread, or in a placeholder thread when
    /// this is a fresh compose. `drain()` later swaps it for the real message or
    /// rolls it back. The draft itself is persisted in the payload, so nothing
    /// the user typed is lost if the send fails.
    /// - Parameter after: seconds to hold the message back. Non-zero gives the
    ///   undo window (or a scheduled send); the local apply still happens now.
    /// - Returns: the queued mutation's id, so it can be cancelled.
    @discardableResult
    public func send(_ draft: Draft, after delay: TimeInterval = 0) throws -> Int64? {
        let placeholderMessageID = "local:\(newID())"
        let messageID = "<\(newID())@\(identityDomain)>"
        let createdThread = draft.threadID == nil
        let threadID = draft.threadID ?? "local:\(newID())"

        if createdThread {
            try store.upsert(MailThread(id: threadID, snippet: draft.bodyText,
                                        lastMessageDate: now(), isUnread: false,
                                        hasAttachments: false, labelIDs: ["SENT"]))
        }

        try store.upsert(Message(
            id: placeholderMessageID, threadID: threadID, sender: identity,
            recipients: draft.to, cc: draft.cc, subject: draft.subject, date: now(),
            bodyHTML: draft.bodyHTML, bodyText: draft.bodyText,
            isUnread: false, labelIDs: ["SENT"],
            messageIDHeader: messageID, inReplyTo: draft.inReplyTo,
            references: draft.references))
        try deriveThread(threadID, in: store)

        let payload = OutboundSendPayload(
            draft: draft, messageID: messageID,
            placeholderMessageID: placeholderMessageID,
            threadID: threadID, createdThread: createdThread)
        return try mutations.enqueue(PendingMutation(
            kind: .send, payload: try JSONEncoder().encode(payload),
            createdAt: now(), status: .pending,
            dueAt: delay > 0 ? now().addingTimeInterval(delay) : nil)).id
    }

    /// Undoes a queued send that has not gone out: removes the optimistic rows
    /// and the queue entry.
    ///
    /// Refuses anything that is not a send. Decoding an archive payload as a
    /// send would throw, and deleting it regardless would silently lose the
    /// archive.
    public func cancelSend(mutationID: Int64) throws {
        guard let mutation = try mutations.all().first(where: { $0.id == mutationID }),
              mutation.kind == .send,
              let payload = try? JSONDecoder().decode(OutboundSendPayload.self,
                                                      from: mutation.payload) else { return }
        try rollBackSend(payload)
        try mutations.delete(id: mutationID)
    }

    // MARK: - Scheduled sends

    /// Anything not due for a good while yet.
    ///
    /// Every send waits out an undo window, so "has a dueAt" is not the same as
    /// "was scheduled". The threshold keeps the last ten seconds of ordinary
    /// sending off a screen that is meant to list deliberate choices.
    public static let scheduleThreshold: TimeInterval = 60

    /// Messages waiting for their hour, soonest first.
    public func scheduled(now moment: Date = Date()) throws -> [ScheduledSend] {
        try mutations.all()
            .filter { $0.kind == .send }
            .compactMap { mutation -> ScheduledSend? in
                guard let id = mutation.id, let dueAt = mutation.dueAt,
                      dueAt.timeIntervalSince(moment) > Self.scheduleThreshold,
                      let payload = try? JSONDecoder().decode(OutboundSendPayload.self,
                                                              from: mutation.payload)
                else { return nil }
                return ScheduledSend(id: id, draft: payload.draft, dueAt: dueAt)
            }
            .sorted { $0.dueAt < $1.dueAt }
    }

    /// Lets a scheduled message go on the next drain.
    public func sendNow(mutationID: Int64) throws {
        try mutations.clearDueAt(id: mutationID)
    }

    /// Takes a scheduled message back out of the queue and returns its draft.
    ///
    /// The optimistic copy goes with it: a message the writer decided not to
    /// send must not stay visible in the thread as though it had.
    public func unschedule(mutationID: Int64) throws -> Draft? {
        guard let mutation = try mutations.all().first(where: { $0.id == mutationID }),
              mutation.kind == .send,
              let payload = try? JSONDecoder().decode(OutboundSendPayload.self,
                                                      from: mutation.payload) else { return nil }
        try rollBackSend(payload)
        try mutations.delete(id: mutationID)
        return payload.draft
    }

    // MARK: - Failures

    /// How many pushes a mutation gets before the queue gives up on it.
    ///
    /// Shared with `GmailSync` rather than duplicated: the number that decides
    /// what stops being retried must be the number that decides what is
    /// reported, or the app goes quiet about writes it has abandoned.
    public static let maxAttempts = 3

    /// Changes that will not be retried again, described in the writer's terms.
    ///
    /// Only rows at the cap: a mutation still under it goes out on the next
    /// tick, and reporting that is crying wolf over a dropped connection.
    public func failures(maxAttempts: Int) throws -> [MailFailure] {
        try mutations.abandoned(maxAttempts: maxAttempts).compactMap(describe)
    }

    /// Hands back the draft of a failed send and clears the failure.
    ///
    /// Returns nil for anything still queued: reopening a send that is on its
    /// way would put the same message out twice.
    public func reopen(mutationID: Int64) throws -> Draft? {
        guard let mutation = try failedMutation(mutationID), mutation.kind == .send,
              let payload = try? JSONDecoder().decode(OutboundSendPayload.self,
                                                      from: mutation.payload) else { return nil }
        try mutations.delete(id: mutationID)
        return payload.draft
    }

    /// Forgets a failure. The local revert happened when the push failed, so
    /// there is nothing here to put back.
    public func dismiss(mutationID: Int64) throws {
        guard try failedMutation(mutationID) != nil else { return }
        try mutations.delete(id: mutationID)
    }

    private func failedMutation(_ id: Int64) throws -> PendingMutation? {
        try mutations.all().first { $0.id == id && $0.status == .failed }
    }

    /// Names a failed mutation by the mail it was about.
    private func describe(_ mutation: PendingMutation) -> MailFailure? {
        guard let id = mutation.id else { return nil }
        if mutation.kind == .send {
            guard let payload = try? JSONDecoder().decode(OutboundSendPayload.self,
                                                          from: mutation.payload) else { return nil }
            return MailFailure(id: id, kind: .send, subject: payload.draft.subject,
                               attempts: mutation.attempts, draft: payload.draft)
        }
        guard let payload = try? JSONDecoder().decode(OutboundMutationPayload.self,
                                                      from: mutation.payload) else { return nil }
        return MailFailure(id: id, kind: mutation.kind, subject: subject(ofThread: payload.threadID),
                           attempts: mutation.attempts, draft: nil)
    }

    /// The thread's subject, falling back to its snippet: a thread whose
    /// messages have since gone still has to be nameable.
    private func subject(ofThread threadID: String) -> String {
        if let subject = try? mailStore.messages(inThread: threadID).first?.subject,
           !subject.isEmpty {
            return subject
        }
        return (try? mailStore.thread(id: threadID))??.snippet ?? ""
    }

    /// The domain half of the sending identity, for minting a `Message-ID`.
    private var identityDomain: String {
        let address = Draft.normalizedAddress(identity)
        return address.split(separator: "@").last.map(String.init) ?? "localhost"
    }

    /// Returns failed mutations to the queue while they are under `maxAttempts`,
    /// so the next drain retries them.
    public func retryFailed(maxAttempts: Int) throws {
        try mutations.retryFailed(maxAttempts: maxAttempts)
    }

    public func archive(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .archive, add: [], remove: ["INBOX"])
    }

    public func markRead(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .markRead, add: [], remove: ["UNREAD"])
    }

    /// Hides a thread until `date`.
    ///
    /// Removing INBOX goes through the queue like any other label change, so the
    /// thread disappears on every device; the wake time stays local because
    /// Gmail has no public snooze.
    public func snooze(threadID: String, until date: Date) throws {
        guard try store.thread(id: threadID) != nil else { return }
        try enqueueLabelChange(threadID: threadID, kind: .snooze, add: [], remove: ["INBOX"])
        try store.setSnoozedUntil(date, onThread: threadID)
    }

    /// Brings a snoozed thread back now, before its time.
    ///
    /// Clears the wake time as well as restoring the label: left set, the waker
    /// would later fire on a thread already sitting in the inbox.
    public func unsnooze(threadID: String) throws {
        guard let thread = try store.thread(id: threadID), thread.snoozedUntil != nil else { return }
        try enqueueLabelChange(threadID: threadID, kind: .unsnooze, add: ["INBOX"], remove: [])
        try store.setSnoozedUntil(nil, onThread: threadID)
    }

    /// Returns any thread whose snooze has expired to the inbox.
    /// - Returns: the ids that woke.
    @discardableResult
    public func wakeSnoozed(now moment: Date) throws -> [String] {
        let due = try store.snoozedThreadsDue(now: moment)
        for thread in due {
            try enqueueLabelChange(threadID: thread.id, kind: .unsnooze, add: ["INBOX"], remove: [])
            // Cleared after re-labelling, so a failure mid-way leaves it asleep
            // rather than awake-but-unlabelled.
            try store.setSnoozedUntil(nil, onThread: thread.id)
        }
        return due.map(\.id)
    }

    /// Stars a thread. `STARRED` is a real Gmail label, so this needs no new
    /// machinery: the same queue that archives pushes it and reverts it.
    public func star(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .star, add: ["STARRED"], remove: [])
    }

    /// Sends a thread to Gmail's spam folder.
    ///
    /// One queued change, not two: SPAM on and INBOX off have to land together
    /// or a half-applied pair leaves the thread in both places.
    public func reportSpam(threadID: String) throws {
        guard try store.thread(id: threadID) != nil else { return }
        try enqueueLabelChange(threadID: threadID, kind: .label,
                               add: ["SPAM"], remove: ["INBOX"])
    }

    /// Takes a thread back out of spam.
    ///
    /// The exact reverse of `reportSpam`, as one change for the same reason:
    /// a half-applied pair would leave the thread in both places.
    public func notSpam(threadID: String) throws {
        guard try store.thread(id: threadID) != nil else { return }
        try enqueueLabelChange(threadID: threadID, kind: .label,
                               add: ["INBOX"], remove: ["SPAM"])
    }

    /// Puts a label on a thread. Nothing happens if it is already there.
    public func addLabel(_ labelID: String, toThread threadID: String) throws {
        guard let thread = try store.thread(id: threadID),
              !thread.labelIDs.contains(labelID) else { return }
        try enqueueLabelChange(threadID: threadID, kind: .label, add: [labelID], remove: [])
    }

    /// Takes a label off a thread, leaving every other label alone.
    public func removeLabel(_ labelID: String, fromThread threadID: String) throws {
        guard let thread = try store.thread(id: threadID),
              thread.labelIDs.contains(labelID) else { return }
        try enqueueLabelChange(threadID: threadID, kind: .label, add: [], remove: [labelID])
    }

    public func unstar(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .unstar, add: [], remove: ["STARRED"])
    }

    /// Moves a thread to the bin.
    ///
    /// Applies Gmail's `TRASH` alongside removing `INBOX`, so it is recoverable
    /// from any client rather than disappearing locally in a way nothing else
    /// knows about. That extra label is the whole difference from archive.
    public func trash(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .trash,
                               add: ["TRASH"], remove: ["INBOX"])
    }

    /// Puts a thread back in the inbox after an archive or a delete.
    ///
    /// Clears `TRASH` as well as restoring `INBOX`: leaving it would put the
    /// thread back in the inbox *and* the bin at the same time.
    public func unarchive(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .unarchive,
                               add: ["INBOX"], remove: ["TRASH"])
    }

    public func markUnread(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .markUnread, add: ["UNREAD"], remove: [])
    }

    // MARK: - Internals

    /// Provides `drain()` (defined in an extension) with the shared collaborators.
    var queue: MutationStore { mutations }
    var mailStore: MailStore { store }
    var gmailWriter: GmailWriting { writer }

    private func enqueueLabelChange(threadID: String, kind: MutationKind,
                                   add: [String], remove: [String]) throws {
        guard try store.thread(id: threadID) != nil else { return }
        let messages = try store.messages(inThread: threadID)

        // Apply the change to each message row (capturing prior labels for revert),
        // then re-derive the thread from its messages. This preserves the invariant
        // thread.labelIDs == union(message.labelIDs), so a later thread re-derivation
        // (LabelDeltaApplier) can't resurrect the removed label.
        var previousMessageLabels: [String: [String]] = [:]
        for var message in messages {
            previousMessageLabels[message.id] = message.labelIDs
            message.labelIDs = applyLabels(to: message.labelIDs, add: add, remove: remove)
            message.isUnread = message.labelIDs.contains("UNREAD")
            try store.upsert(message)
        }
        try deriveThread(threadID, in: store)

        let payload = OutboundMutationPayload(
            threadID: threadID,
            messageIDs: messages.map(\.id),
            addLabelIDs: add,
            removeLabelIDs: remove,
            previousMessageLabels: previousMessageLabels)
        let encoded = try JSONEncoder().encode(payload)
        _ = try mutations.enqueue(PendingMutation(kind: kind, payload: encoded, createdAt: now(), status: .pending))
    }
}

func applyLabels(to labels: [String], add: [String], remove: [String]) -> [String] {
    var result = labels.filter { !remove.contains($0) }
    for label in add where !result.contains(label) { result.append(label) }
    return result
}

/// Re-derives a thread from its messages, restoring both invariants the rest of
/// the engine relies on: `thread.labelIDs == union(message.labelIDs)` and
/// `thread.lastMessageDate == max(message.date)`. The date matters because a
/// send adds a message the thread has never seen, and an inbox ordered by date
/// would otherwise leave a thread you just replied to sitting where it was.
func deriveThread(_ threadID: String, in store: MailStore) throws {
    let messages = try store.messages(inThread: threadID)
    let (labelIDs, isUnread) = GmailMessageMapper.threadAggregate(from: messages)
    try store.updateThreadDerivedLabels(labelIDs, isUnread: isUnread, onThread: threadID)
    if let newest = messages.max(by: { $0.date < $1.date }) {
        try store.updateThreadLastMessageDate(newest.date, onThread: threadID)
        try store.updateThreadSender(newest.sender, onThread: threadID)
    }
}

extension OutboundService {
    /// Pushes every pending mutation to Gmail. For each: modify every message in
    /// the payload; on success delete the row; on API failure revert the thread
    /// to its pre-change state (from the persisted payload) and mark the mutation
    /// failed, then continue. Never rethrows an API failure; only genuine DB/decode
    /// faults propagate.
    public func drain() async throws {
        for mutation in try queue.pending(due: now()) {
            guard let id = mutation.id else { continue }
            if mutation.kind == .send {
                try await drainSend(mutation, id: id)
                continue
            }
            let payload = try JSONDecoder().decode(OutboundMutationPayload.self, from: mutation.payload)

            if payload.messageIDs.isEmpty {
                try queue.delete(id: id)   // nothing to push
                continue
            }

            var apiFailed = false
            do {
                // One atomic batch call — a multi-message change can't be half-applied.
                try await gmailWriter.batchModifyMessages(
                    ids: payload.messageIDs,
                    addLabelIDs: payload.addLabelIDs,
                    removeLabelIDs: payload.removeLabelIDs)
            } catch is AuthError {
                apiFailed = true
            }

            if apiFailed {
                try revert(payload)
                try queue.markFailed(id: id)
            } else {
                try queue.delete(id: id)
            }
        }
    }

    /// Pushes one queued send. On success the optimistic placeholder is swapped
    /// for the real message; on failure it is rolled back and the row is marked
    /// failed (the draft survives inside the payload, so nothing typed is lost).
    private func drainSend(_ mutation: PendingMutation, id: Int64) async throws {
        let payload = try JSONDecoder().decode(OutboundSendPayload.self, from: mutation.payload)
        let raw = MIMEBuilder.raw(payload.draft, from: identity,
                                  messageID: payload.messageID, date: now(),
                                  boundary: "velo-\(newID())")

        let sent: GmailMessageDTO
        do {
            sent = try await gmailWriter.sendMessage(raw: raw, threadID: payload.draft.threadID)
        } catch is AuthError {
            try rollBackSend(payload)
            try queue.markFailed(id: id)
            return
        }

        try applySent(sent, for: payload)
        try queue.delete(id: id)
    }

    /// Replaces the placeholder row with the real message. The send response is
    /// sparse (id, threadId, labels -- not `format=full`), so the durable fields
    /// come from the draft we already hold; only identity and labels come from
    /// the server.
    private func applySent(_ sent: GmailMessageDTO, for payload: OutboundSendPayload) throws {
        let draft = payload.draft
        try mailStore.deleteMessage(id: payload.placeholderMessageID)

        // Gmail assigns the thread for a fresh compose; make sure it exists
        // before the message references it, then drop the invented one.
        if try mailStore.thread(id: sent.threadId) == nil {
            try mailStore.upsert(MailThread(
                id: sent.threadId, snippet: draft.bodyText, lastMessageDate: now(),
                isUnread: false, hasAttachments: false, labelIDs: ["SENT"]))
        }

        try mailStore.upsert(Message(
            id: sent.id, threadID: sent.threadId, sender: identity,
            recipients: draft.to, cc: draft.cc, subject: draft.subject, date: now(),
            bodyHTML: draft.bodyHTML, bodyText: draft.bodyText,
            isUnread: false, labelIDs: sent.labelIds ?? ["SENT"],
            messageIDHeader: payload.messageID, inReplyTo: draft.inReplyTo,
            references: draft.references))

        // Gmail can decline the requested thread and file the message elsewhere.
        // The message has left the original thread, so that thread has to be
        // re-derived too, or it keeps the optimistic SENT label forever.
        if payload.threadID != sent.threadId {
            if payload.createdThread {
                try mailStore.deleteThread(id: payload.threadID)
            } else {
                try deriveThread(payload.threadID, in: mailStore)
            }
        }
        try deriveThread(sent.threadId, in: mailStore)
    }

    /// Undoes the optimistic apply of a failed send.
    func rollBackSend(_ payload: OutboundSendPayload) throws {
        try mailStore.deleteMessage(id: payload.placeholderMessageID)
        if payload.createdThread {
            try mailStore.deleteThread(id: payload.threadID)
        } else {
            try deriveThread(payload.threadID, in: mailStore)
        }
    }

    private func revert(_ payload: OutboundMutationPayload) throws {
        for messageID in payload.messageIDs {
            guard var message = try mailStore.message(id: messageID),
                  let previous = payload.previousMessageLabels[messageID] else { continue }
            message.labelIDs = previous
            message.isUnread = previous.contains("UNREAD")
            try mailStore.upsert(message)
        }
        try deriveThread(payload.threadID, in: mailStore)
    }
}
