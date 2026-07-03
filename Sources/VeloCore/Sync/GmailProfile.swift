import Foundation

/// Decoded `users.getProfile` response. `historyId` is the mailbox's current
/// history marker — the canonical baseline for incremental sync. Gmail sends it
/// as a JSON string; keep it a `String` (never parse to Int).
public struct GmailProfile: Decodable, Equatable {
    public let emailAddress: String
    public let historyId: String

    public init(emailAddress: String, historyId: String) {
        self.emailAddress = emailAddress
        self.historyId = historyId
    }
}
