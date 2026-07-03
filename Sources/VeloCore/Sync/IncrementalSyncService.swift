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
        var labelDeltas: [GmailHistoryResponse.LabelDelta] = []
        var latestHistoryId = startHistoryId
        var pageToken: String?
        repeat {
            let page: GmailHistoryResponse
            do {
                page = try await source.fetchHistory(startHistoryId: startHistoryId, pageToken: pageToken)
            } catch let error as AuthError where Self.isHistoryExpired(error) {
                // Cursor is too old; throw before advancing/saving so the caller re-backfills.
                throw SyncError.historyExpired
            }
            addedIDs.append(contentsOf: page.addedMessageIDs)
            labelDeltas.append(contentsOf: page.labelDeltas)
            if let historyId = page.historyId { latestHistoryId = historyId }
            pageToken = page.nextPageToken
        } while pageToken != nil

        var seen = Set<String>()
        let uniqueIDs = addedIDs.filter { seen.insert($0).inserted }

        var dtos: [GmailMessageDTO] = []
        for id in uniqueIDs {
            dtos.append(try await source.getMessage(id: id))
        }
        // Reconcile newly-arrived messages first, so deltas targeting them find them present.
        try InboxReconciler.reconcile(dtos, into: store)
        try LabelDeltaApplier.apply(labelDeltas, into: store)

        state.historyId = latestHistoryId
        try syncState.save(state)
    }

    /// A too-old `startHistoryId` surfaces as a Gmail 404, which `checkedDecode`
    /// maps to `.server` with code `"404"` or (via Gmail's `status`) `"NOT_FOUND"`.
    private static func isHistoryExpired(_ error: AuthError) -> Bool {
        guard case let .server(code, _) = error else { return false }
        return code == "404" || code == "NOT_FOUND"
    }
}
