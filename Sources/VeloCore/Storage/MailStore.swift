import Foundation
import GRDB

public final class MailStore: Sendable {
    /// Exposed so search can build its own reader over the same store rather
    /// than threading an AppDatabase through every caller.
    public let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func upsert(_ thread: MailThread) throws {
        try database.dbQueue.write { try thread.save($0) }
    }

    public func upsert(_ message: Message) throws {
        try database.dbQueue.write { try message.save($0) }
    }

    /// The canonical inbox query: threads labeled INBOX and not sleeping,
    /// newest first.
    private static func inboxRequest(now: Date = Date()) -> QueryInterfaceRequest<MailThread> {
        MailThread
            .filter(sql: "labelIDs LIKE ?", arguments: ["%\"INBOX\"%"])
            .filter(sql: "snoozedUntil IS NULL OR snoozedUntil <= ?", arguments: [now])
            .order(sql: "lastMessageDate DESC")
    }

    public func inboxThreads(now: Date = Date()) throws -> [MailThread] {
        try database.dbQueue.read { try Self.inboxRequest(now: now).fetchAll($0) }
    }

    /// Threads carrying Gmail's own `SENT` label, newest first.
    ///
    /// Not filtered by snooze: a snooze says when something should come back to
    /// the inbox and has nothing to say about what you have already sent. A
    /// replied-to conversation carries both labels and appears in both places,
    /// exactly as it does in Gmail.
    public func sentThreads() throws -> [MailThread] {
        try database.dbQueue.read { db in
            try MailThread
                .filter(sql: "labelIDs LIKE ?", arguments: ["%\"SENT\"%"])
                .order(sql: "lastMessageDate DESC")
                .fetchAll(db)
        }
    }

    /// Threads carrying Gmail's own `STARRED` label, newest first.
    ///
    /// Not restricted to the inbox: the point of starring something is that it
    /// survives filing the thread away.
    public func starredThreads() throws -> [MailThread] {
        try database.dbQueue.read { db in
            try MailThread
                .filter(sql: "labelIDs LIKE ?", arguments: ["%\"STARRED\"%"])
                .order(sql: "lastMessageDate DESC")
                .fetchAll(db)
        }
    }

    /// Threads filed away: out of the inbox, but not binned, not merely sent,
    /// and not simply waiting to come back.
    ///
    /// Archiving in Gmail is the absence of a label rather than the presence of
    /// one, so this is defined by what a thread is *not*. Each exclusion earns
    /// its place: the bin and the snooze pile both leave the inbox too, and a
    /// sent message was never in it, so without them this view would be
    /// everything that ever happened.
    public func archivedThreads(now: Date = Date()) throws -> [MailThread] {
        try database.dbQueue.read { db in
            try MailThread
                .filter(sql: """
                    labelIDs NOT LIKE '%"INBOX"%'
                    AND labelIDs NOT LIKE '%"TRASH"%'
                    AND labelIDs NOT LIKE '%"SENT"%'
                    AND (snoozedUntil IS NULL OR snoozedUntil <= ?)
                    """, arguments: [now])
                .order(sql: "lastMessageDate DESC")
                .fetchAll(db)
        }
    }

    /// Threads waiting to come back, soonest first.
    ///
    /// Ordered by wake time rather than arrival: this list answers "what is
    /// coming back and when", so that is the order to read it in. A thread past
    /// its wake time is excluded -- it belongs to the inbox again, and showing
    /// it in both places would double-count it.
    public func snoozedThreads(now: Date = Date()) throws -> [MailThread] {
        try database.dbQueue.read { db in
            try MailThread
                .filter(sql: "snoozedUntil IS NOT NULL AND snoozedUntil > ?", arguments: [now])
                .order(sql: "snoozedUntil ASC")
                .fetchAll(db)
        }
    }

    /// Threads whose snooze has expired.
    public func snoozedThreadsDue(now: Date) throws -> [MailThread] {
        try database.dbQueue.read { db in
            try MailThread
                .filter(sql: "snoozedUntil IS NOT NULL AND snoozedUntil <= ?", arguments: [now])
                .fetchAll(db)
        }
    }

    public func setSnoozedUntil(_ date: Date?, onThread threadID: String) throws {
        try database.dbQueue.write { db in
            guard var thread = try MailThread.fetchOne(db, key: threadID) else { return }
            thread.snoozedUntil = date
            try thread.update(db)
        }
    }

    public func thread(id: String) throws -> MailThread? {
        try database.dbQueue.read { try MailThread.fetchOne($0, key: id) }
    }

    public func messages(inThread threadID: String) throws -> [Message] {
        try database.dbQueue.read { db in
            try Message
                .filter(Column("threadID") == threadID)
                .order(Column("date").asc)
                .fetchAll(db)
        }
    }

    public func message(id: String) throws -> Message? {
        try database.dbQueue.read { try Message.fetchOne($0, key: id) }
    }

    /// Sets a thread's aggregate `labelIDs` + `isUnread`, preserving all other
    /// fields. No-op if the thread does not exist.
    /// The newest inbox messages, for deciding what to announce. Capped because
    /// the announcer only ever looks at what arrived since a mark.
    public func recentInboxMessages(limit: Int = 100) throws -> [Message] {
        try database.dbQueue.read { db in
            try Message
                .filter(sql: "labelIDs LIKE ?", arguments: ["%\"INBOX\"%"])
                .order(sql: "date DESC")
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func upsert(_ attachment: MailAttachment) throws {
        try database.dbQueue.write { try attachment.save($0) }
    }

    /// A message's files, by filename so the order does not wander between
    /// reads.
    public func attachments(forMessage messageID: String) throws -> [MailAttachment] {
        try database.dbQueue.read { db in
            try MailAttachment
                .filter(Column("messageID") == messageID)
                .order(Column("filename").asc)
                .fetchAll(db)
        }
    }

    public func deleteMessage(id: String) throws {
        _ = try database.dbQueue.write { db in
            try Message.deleteOne(db, key: id)
        }
    }

    /// Deletes a thread. Its messages go with it via the schema's
    /// `onDelete: .cascade` foreign key.
    public func deleteThread(id: String) throws {
        _ = try database.dbQueue.write { db in
            try MailThread.deleteOne(db, key: id)
        }
    }

    /// Sets the thread's displayed sender (the newest message's).
    public func updateThreadSender(_ sender: String, onThread threadID: String) throws {
        try database.dbQueue.write { db in
            guard var thread = try MailThread.fetchOne(db, key: threadID) else { return }
            thread.sender = sender
            try thread.update(db)
        }
    }

    /// Sets a thread's newest-message timestamp. Kept separate from
    /// `updateThreadDerivedLabels` because a label delta never moves the date.
    public func updateThreadLastMessageDate(_ date: Date, onThread threadID: String) throws {
        try database.dbQueue.write { db in
            guard var thread = try MailThread.fetchOne(db, key: threadID) else { return }
            thread.lastMessageDate = date
            try thread.update(db)
        }
    }

    public func updateThreadDerivedLabels(_ labelIDs: [String], isUnread: Bool, onThread threadID: String) throws {
        try database.dbQueue.write { db in
            guard var thread = try MailThread.fetchOne(db, key: threadID) else { return }
            thread.labelIDs = labelIDs
            thread.isUnread = isUnread
            try thread.update(db)
        }
    }

    public func setLabels(_ labelIDs: [String], onThread threadID: String) throws {
        try database.dbQueue.write { db in
            guard var thread = try MailThread.fetchOne(db, key: threadID) else { return }
            thread.labelIDs = labelIDs
            try thread.update(db)
        }
    }

    /// Observes the inbox and calls `onChange` with the current threads immediately,
    /// then again on every relevant database change.
    ///
    /// - Important: Uses GRDB `.immediate` scheduling, which **must be started on the
    ///   main thread** — calling this off the main thread traps. The returned
    ///   cancellable must be retained by the caller to keep the observation alive.
    public func observeInboxThreads(
        onChange: @escaping ([MailThread]) -> Void
    ) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { try Self.inboxRequest().fetchAll($0) }
        return observation.start(
            in: database.dbQueue,
            scheduling: .immediate,
            onError: { error in
                // Surfacing-only for now; a future API revision should propagate this to callers.
                print("[VeloCore] inbox observation error: \(error)")
            },
            onChange: onChange
        )
    }
}
