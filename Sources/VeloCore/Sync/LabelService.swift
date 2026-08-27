import Foundation

/// Keeps the local label list in step with Gmail's.
///
/// Separate from backfill because it is one cheap call that answers a different
/// question: backfill asks what mail exists, this asks what the mail's labels
/// are called.
public struct LabelService: Sendable {
    private let source: GmailReading
    private let store: MailStore

    public init(source: GmailReading, store: MailStore) {
        self.source = source
        self.store = store
    }

    /// Refetches the list. A failure leaves the last good one in place: a
    /// sidebar that empties itself on a dropped connection is worse than one
    /// showing a label that has since been renamed.
    public func refresh() async throws {
        let fetched = try await source.listLabels()
        guard !fetched.isEmpty else { return }
        try store.replaceLabels(fetched.map(\.label))
    }
}
