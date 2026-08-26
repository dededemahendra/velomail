import Foundation

/// Decoded shape of a Gmail `users.messages.get` (format=full) response — only
/// the fields VeloCore maps. `Part` is recursive (a MIME tree); Swift allows the
/// self-reference because `[Part]?` stores its elements out-of-line.
public struct GmailMessageDTO: Decodable, Equatable {
    public struct Header: Decodable, Equatable {
        public let name: String
        public let value: String
    }

    public struct Body: Decodable, Equatable {
        public let data: String?
        /// Gmail's handle for a part whose content is not inlined.
        public let attachmentId: String?
        public let size: Int?
    }

    public struct Part: Decodable, Equatable {
        public let mimeType: String?
        public let filename: String?
        public let headers: [Header]?
        public let body: Body?
        public let parts: [Part]?
    }

    public let id: String
    public let threadId: String
    public let labelIds: [String]?
    public let snippet: String?
    public let internalDate: String?
    public let payload: Part?
}
