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

    public func inboxThreads() throws -> [MailThread] {
        try database.dbQueue.read { db in
            try MailThread
                .filter(sql: "labelIDs LIKE ?", arguments: ["%\"INBOX\"%"])
                .order(sql: "lastMessageDate DESC")
                .fetchAll(db)
        }
    }

    public func messages(inThread threadID: String) throws -> [Message] {
        try database.dbQueue.read { db in
            try Message
                .filter(Column("threadID") == threadID)
                .order(Column("date").asc)
                .fetchAll(db)
        }
    }

    public func setLabels(_ labelIDs: [String], onThread threadID: String) throws {
        try database.dbQueue.write { db in
            guard var thread = try MailThread.fetchOne(db, key: threadID) else { return }
            thread.labelIDs = labelIDs
            try thread.update(db)
        }
    }

    public func observeInboxThreads(
        onChange: @escaping ([MailThread]) -> Void
    ) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try MailThread
                .filter(sql: "labelIDs LIKE ?", arguments: ["%\"INBOX\"%"])
                .order(sql: "lastMessageDate DESC")
                .fetchAll(db)
        }
        return observation.start(
            in: database.dbQueue,
            scheduling: .immediate,
            onError: { _ in },
            onChange: onChange
        )
    }
}
