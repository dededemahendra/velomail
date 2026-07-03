import Foundation

/// Applies Gmail `history.list` deltas since the stored `historyId`: hydrates
/// newly arrived messages, reconciles them into `MailStore`, and advances the
/// stored cursor. Per-message label deltas are not yet applied (deferred).
public struct IncrementalSyncService {
    private let source: GmailReading
    private let store: MailStore
    private let syncState: SyncStateStore

    public init(source: GmailReading, store: MailStore, syncState: SyncStateStore) {
        self.source = source
        self.store = store
        self.syncState = syncState
    }

    /// Syncs the account forward from its stored `historyId`.
    ///
    /// - Throws: `SyncError.notInitialized` when no `historyId` baseline exists.
    public func sync(accountID: String) async throws {
        guard var state = try syncState.load(accountID: accountID),
              let startHistoryId = state.historyId else {
            throw SyncError.notInitialized
        }

        var addedIDs: [String] = []
        var latestHistoryId = startHistoryId
        var pageToken: String?
        repeat {
            let page = try await source.fetchHistory(startHistoryId: startHistoryId, pageToken: pageToken)
            addedIDs.append(contentsOf: page.addedMessageIDs)
            if let historyId = page.historyId { latestHistoryId = historyId }
            pageToken = page.nextPageToken
        } while pageToken != nil

        var seen = Set<String>()
        let uniqueIDs = addedIDs.filter { seen.insert($0).inserted }

        var dtos: [GmailMessageDTO] = []
        for id in uniqueIDs {
            dtos.append(try await source.getMessage(id: id))
        }
        try InboxReconciler.reconcile(dtos, into: store)

        state.historyId = latestHistoryId
        try syncState.save(state)
    }
}
