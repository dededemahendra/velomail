import Foundation

/// Decoded shape of a Gmail `users.history.list` response — the fields needed to
/// apply newly arrived messages, per-message label changes, and advance the cursor.
public struct GmailHistoryResponse: Decodable, Equatable {
    public struct Record: Decodable, Equatable {
        public struct Added: Decodable, Equatable {
            public struct Ref: Decodable, Equatable {
                public let id: String
            }
            public let message: Ref
        }
        public struct LabelChange: Decodable, Equatable {
            public let message: Added.Ref
            public let labelIds: [String]?
        }
        public let messagesAdded: [Added]?
        public let labelsAdded: [LabelChange]?
        public let labelsRemoved: [LabelChange]?
    }

    /// A per-message label change: labels added and/or removed on one message.
    public struct LabelDelta: Equatable {
        public let messageID: String
        public let added: [String]
        public let removed: [String]

        public init(messageID: String, added: [String], removed: [String]) {
            self.messageID = messageID
            self.added = added
            self.removed = removed
        }
    }

    public let history: [Record]?
    public let historyId: String?
    public let nextPageToken: String?

    /// Ids of messages added in this page, in record order.
    public var addedMessageIDs: [String] {
        (history ?? []).flatMap { $0.messagesAdded ?? [] }.map { $0.message.id }
    }

    /// Per-message label changes across all records, in record order (adds before
    /// removes within a record). Order matters: a remove then a re-add must apply
    /// in sequence.
    public var labelDeltas: [LabelDelta] {
        var deltas: [LabelDelta] = []
        for record in history ?? [] {
            for change in record.labelsAdded ?? [] {
                deltas.append(LabelDelta(messageID: change.message.id, added: change.labelIds ?? [], removed: []))
            }
            for change in record.labelsRemoved ?? [] {
                deltas.append(LabelDelta(messageID: change.message.id, added: [], removed: change.labelIds ?? []))
            }
        }
        return deltas
    }
}
