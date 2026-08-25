import Foundation

/// One group of the split inbox: a title and the rows under it.
public struct ThreadSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let threads: [MailThread]

    public init(id: String, title: String, threads: [MailThread]) {
        self.id = id
        self.title = title
        self.threads = threads
    }
}

/// Groups the inbox without re-querying it.
///
/// A split inbox is not a second query — it is the same rows, grouped. So this
/// is pure and synchronous over an array already fetched: no database access,
/// no new observation, nothing to keep in sync.
public enum InboxSections {
    /// The labels that make a thread important.
    ///
    /// `IMPORTANT` is Gmail's own server-side judgement and arrives in
    /// `labelIDs` for free; writing our own importance scorer would be a worse
    /// answer that also costs more.
    static let importantLabels: Set<String> = ["STARRED", "IMPORTANT"]

    /// Splits the inbox into Important then everything else, preserving the
    /// order within each group and omitting a group that would be empty — so a
    /// mailbox with nothing important looks like the flat list it did before.
    public static func split(_ threads: [MailThread]) -> [ThreadSection] {
        var important: [MailThread] = []
        var other: [MailThread] = []
        for thread in threads {
            // A thread that is both starred and important appears once: this is
            // a partition, not two filters.
            if thread.labelIDs.contains(where: importantLabels.contains) {
                important.append(thread)
            } else {
                other.append(thread)
            }
        }
        return [ThreadSection(id: "important", title: "Important", threads: important),
                ThreadSection(id: "other", title: "Other", threads: other)]
            .filter { !$0.threads.isEmpty }
    }

    /// The flat display order the sections concatenate into — what the cursor
    /// walks, so `j`/`k` cross a section boundary without knowing one exists.
    ///
    /// Idempotent: ordering an already-ordered list moves nothing, which is what
    /// lets the view model store this order and still derive the same sections
    /// from it.
    public static func ordered(_ threads: [MailThread]) -> [MailThread] {
        split(threads).flatMap(\.threads)
    }
}
