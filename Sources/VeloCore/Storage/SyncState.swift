import Foundation
import GRDB

/// Per-account sync cursor. `historyId` is the Gmail history marker the next
/// incremental sync pages from; `backfilledLabels` records which labels have
/// actually been pulled down.
public struct SyncState: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var accountID: String
    public var historyId: String?
    /// Kept because it is what an older database recorded, and because "has
    /// this account ever synced" is still a question worth one boolean.
    public var backfillComplete: Bool
    /// The labels whose history has been fetched.
    ///
    /// A single `backfillComplete` flag was the bug: once set, adding a label
    /// to the app could never pull that label's history, so the Sent list
    /// shipped working and empty. Recording them one by one means a new label
    /// backfills itself without re-fetching the mailbox.
    public var backfilledLabels: [String]
    /// Where each label's listing stopped when it hit the cap, so older mail
    /// can be asked for from there rather than from the newest message again.
    /// A label with no entry has nothing older left.
    public var olderCursors: [String: String]
    /// The account's own address, learned from `users.getProfile` during
    /// backfill. It is what a send must use as its `From`.
    public var emailAddress: String?

    public var id: String { accountID }

    public static let databaseTableName = "syncState"

    public init(accountID: String, historyId: String?, backfillComplete: Bool,
                emailAddress: String? = nil, backfilledLabels: [String] = [],
                olderCursors: [String: String] = [:]) {
        self.accountID = accountID
        self.historyId = historyId
        self.backfillComplete = backfillComplete
        self.emailAddress = emailAddress
        self.backfilledLabels = backfilledLabels
        self.olderCursors = olderCursors
    }

    /// Where `label` stopped, if there is more behind it.
    public func olderCursor(for label: String) -> String? { olderCursors[label] }

    private enum CodingKeys: String, CodingKey {
        case accountID, historyId, backfillComplete, emailAddress, backfilledLabels, olderCursors
    }

    /// Reads a row written before labels were tracked.
    ///
    /// A NULL column on an account that had finished a backfill means it pulled
    /// INBOX and nothing else, because that is all there was to pull. Reading
    /// it as "everything is done" is what left the Sent list working and empty;
    /// reading it as "nothing is done" would re-fetch a mailbox already here.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try values.decode(String.self, forKey: .accountID)
        historyId = try values.decodeIfPresent(String.self, forKey: .historyId)
        backfillComplete = try values.decode(Bool.self, forKey: .backfillComplete)
        emailAddress = try values.decodeIfPresent(String.self, forKey: .emailAddress)
        if let labels = try values.decodeIfPresent([String].self, forKey: .backfilledLabels) {
            backfilledLabels = labels
        } else {
            backfilledLabels = backfillComplete ? ["INBOX"] : []
        }
        olderCursors = (try? values.decodeIfPresent([String: String].self,
                                                    forKey: .olderCursors)) as? [String: String] ?? [:]
    }

    /// Which of `wanted` still have to be fetched, in the order given: the
    /// inbox first, so the list the writer is looking at fills first.
    public func labelsNeedingBackfill(of wanted: [String]) -> [String] {
        let done = Set(backfilledLabels)
        return wanted.filter { !done.contains($0) }
    }
}
