import Foundation

/// The pre-change state and intended label change for one outbound mutation,
/// persisted in `PendingMutation.payload`. Everything needed to push the change
/// AND to revert it lives here, so `drain()` works even in a later process.
struct OutboundMutationPayload: Codable, Equatable {
    var threadID: String
    var messageIDs: [String]
    var addLabelIDs: [String]
    var removeLabelIDs: [String]
    var previousLabelIDs: [String]
    var previousIsUnread: Bool
}

/// Applies triage actions (archive, mark read/unread) optimistically to local
/// storage and enqueues a durable mutation for later push to Gmail.
public struct OutboundService {
    private let writer: GmailWriting
    private let store: MailStore
    private let mutations: MutationStore
    private let now: () -> Date

    public init(writer: GmailWriting, store: MailStore, mutations: MutationStore,
                now: @escaping () -> Date = { Date() }) {
        self.writer = writer
        self.store = store
        self.mutations = mutations
        self.now = now
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
        guard let thread = try store.thread(id: threadID) else { return }
        let messageIDs = try store.messages(inThread: threadID).map(\.id)

        var newLabels = thread.labelIDs.filter { !remove.contains($0) }
        for label in add where !newLabels.contains(label) { newLabels.append(label) }

        var updated = thread
        updated.labelIDs = newLabels
        updated.isUnread = newLabels.contains("UNREAD")
        try store.upsert(updated)

        let payload = OutboundMutationPayload(
            threadID: threadID,
            messageIDs: messageIDs,
            addLabelIDs: add,
            removeLabelIDs: remove,
            previousLabelIDs: thread.labelIDs,
            previousIsUnread: thread.isUnread)
        let encoded = try JSONEncoder().encode(payload)
        _ = try mutations.enqueue(PendingMutation(kind: kind, payload: encoded, createdAt: now(), status: .pending))
    }
}
