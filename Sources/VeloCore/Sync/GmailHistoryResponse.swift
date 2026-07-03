import Foundation

/// Decoded shape of a Gmail `users.history.list` response — the fields needed to
/// apply newly arrived messages and advance the history cursor. Label deltas
/// (`labelsAdded`/`labelsRemoved`) are intentionally not decoded yet.
public struct GmailHistoryResponse: Decodable, Equatable {
    public struct Record: Decodable, Equatable {
        public struct Added: Decodable, Equatable {
            public struct Ref: Decodable, Equatable {
                public let id: String
            }
            public let message: Ref
        }
        public let messagesAdded: [Added]?
    }

    public let history: [Record]?
    public let historyId: String?
    public let nextPageToken: String?

    /// Ids of messages added in this page, in record order.
    public var addedMessageIDs: [String] {
        (history ?? []).flatMap { $0.messagesAdded ?? [] }.map { $0.message.id }
    }
}
