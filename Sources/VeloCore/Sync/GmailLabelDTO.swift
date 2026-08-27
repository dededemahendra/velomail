import Foundation

/// A label as Gmail returns it from `users.labels.list`.
public struct GmailLabelDTO: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// `system` for the ones Gmail made, `user` for the rest.
    public let type: String?

    public init(id: String, name: String, type: String?) {
        self.id = id
        self.name = name
        self.type = type
    }

    var label: MailLabel {
        MailLabel(id: id, name: name, kind: type == "user" ? .user : .system)
    }
}
