import Foundation
import GRDB

/// Per-account sync cursor. `historyId` is the Gmail history marker the next
/// incremental sync pages from; `backfillComplete` records whether the initial
/// backfill has finished.
public struct SyncState: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    public var accountID: String
    public var historyId: String?
    public var backfillComplete: Bool

    public var id: String { accountID }

    public static let databaseTableName = "syncState"

    public init(accountID: String, historyId: String?, backfillComplete: Bool) {
        self.accountID = accountID
        self.historyId = historyId
        self.backfillComplete = backfillComplete
    }
}
