import Foundation

/// An outbound change the queue has given up on.
///
/// The local side of a failed push is already undone by the time one of these
/// exists -- `drain()` reverts before it marks a mutation failed -- so this is
/// not a repair job. It is the app telling the truth about something it
/// previously implied had worked.
public struct MailFailure: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let kind: MutationKind
    /// What the writer will recognise: the subject of the message or thread.
    public let subject: String
    public let attempts: Int
    /// The message that never went, for a send. Carrying it is the whole reason
    /// a failed send is worth keeping: the words can go back in the composer.
    public let draft: Draft?

    public init(id: Int64, kind: MutationKind, subject: String, attempts: Int, draft: Draft?) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.attempts = attempts
        self.draft = draft
    }

    /// One line, in the writer's terms rather than the queue's.
    public var summary: String {
        let named = subject.isEmpty ? "(no subject)" : subject
        guard kind != .send else { return "Not sent: \(named)" }
        return "Could not \(MailFailure.verb(for: kind)): \(named)"
    }

    private static func verb(for kind: MutationKind) -> String {
        switch kind {
        case .archive: return "archive"
        case .markRead: return "mark as read"
        case .markUnread: return "mark as unread"
        case .snooze: return "snooze"
        case .unsnooze: return "wake"
        case .trash: return "delete"
        case .unarchive: return "put back"
        case .star: return "star"
        case .unstar: return "unstar"
        case .send: return "send"
        }
    }
}
