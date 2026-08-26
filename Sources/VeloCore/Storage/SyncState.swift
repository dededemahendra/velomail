import Foundation
import GRDB

/// Per-account sync cursor. `historyId` is the Gmail history marker the next
/// incremental sync pages from; `backfillComplete` records whether the initial
/// backfill has finished.
public struct SyncState: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var accountID: String
    public var historyId: String?
    public var backfillComplete: Bool
    /// The account's own address, learned from `users.getProfile` during
    /// backfill. It is what a send must use as its `From`.
    public var emailAddress: String?

    public var id: String { accountID }

    public static let databaseTableName = "syncState"

    public init(accountID: String, historyId: String?, backfillComplete: Bool,
                emailAddress: String? = nil) {
        self.accountID = accountID
        self.historyId = historyId
        self.backfillComplete = backfillComplete
        self.emailAddress = emailAddress
    }
}
