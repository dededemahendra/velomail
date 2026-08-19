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
public struct OutboundService {
    private let writer: GmailWriting
    private let store: MailStore
    private let mutations: MutationStore
    private let identity: String
    private let now: () -> Date
    private let newID: () -> String

    /// - Parameters:
    ///   - identity: the account's own address, used as the `From` of anything sent.
    ///   - newID: opaque unique-id source, injected so tests get stable ids.
    public init(writer: GmailWriting, store: MailStore, mutations: MutationStore,
                identity: String, now: @escaping () -> Date = { Date() },
                newID: @escaping () -> String = { UUID().uuidString }) {
        self.writer = writer
        self.store = store
        self.mutations = mutations
        self.identity = identity
        self.now = now
        self.newID = newID
    }

    /// Applies a draft locally at once and queues the real send.
    ///
    /// A send has no row to mutate yet, so the optimistic apply has to invent
    /// one: a placeholder message under a `local:` id (which can never collide
    /// with a Gmail id), in the draft's thread, or in a placeholder thread when
    /// this is a fresh compose. `drain()` later swaps it for the real message or
    /// rolls it back. The draft itself is persisted in the payload, so nothing
    /// the user typed is lost if the send fails.
    public func send(_ draft: Draft) throws {
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
        _ = try mutations.enqueue(PendingMutation(
            kind: .send, payload: try JSONEncoder().encode(payload),
            createdAt: now(), status: .pending))
    }

    /// The domain half of the sending identity, for minting a `Message-ID`.
    private var identityDomain: String {
        let address = Draft.normalizedAddress(identity)
        return address.split(separator: "@").last.map(String.init) ?? "localhost"
    }

    public func archive(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .archive, add: [], remove: ["INBOX"])
    }

    public func markRead(threadID: String) throws {
        try enqueueLabelChange(threadID: threadID, kind: .markRead, add: [], remove: ["UNREAD"])
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

func deriveThread(_ threadID: String, in store: MailStore) throws {
    let messages = try store.messages(inThread: threadID)
    let (labelIDs, isUnread) = GmailMessageMapper.threadAggregate(from: messages)
    try store.updateThreadDerivedLabels(labelIDs, isUnread: isUnread, onThread: threadID)
}

extension OutboundService {
    /// Pushes every pending mutation to Gmail. For each: modify every message in
    /// the payload; on success delete the row; on API failure revert the thread
    /// to its pre-change state (from the persisted payload) and mark the mutation
    /// failed, then continue. Never rethrows an API failure; only genuine DB/decode
    /// faults propagate.
    public func drain() async throws {
        for mutation in try queue.pending() {
            guard let id = mutation.id else { continue }
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
