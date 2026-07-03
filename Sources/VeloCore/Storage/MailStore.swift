import Foundation
import GRDB

public final class MailStore {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func upsert(_ thread: MailThread) throws {
        try database.dbQueue.write { try thread.save($0) }
    }

    public func upsert(_ message: Message) throws {
        try database.dbQueue.write { try message.save($0) }
    }

    /// The canonical inbox query: threads labeled INBOX, newest first.
    private static func inboxRequest() -> QueryInterfaceRequest<MailThread> {
        MailThread
            .filter(sql: "labelIDs LIKE ?", arguments: ["%\"INBOX\"%"])
            .order(sql: "lastMessageDate DESC")
    }

    public func inboxThreads() throws -> [MailThread] {
        try database.dbQueue.read { try Self.inboxRequest().fetchAll($0) }
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
