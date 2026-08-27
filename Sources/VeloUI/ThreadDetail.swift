import Foundation
import VeloCore

/// What a thread's header has to say about itself beyond its subject.
///
/// Decided here rather than in the view so the rules are testable and so a
/// thread and the palette cannot disagree about the same set of labels.
enum ThreadDetail {
    /// The labels worth showing on a thread.
    ///
    /// Only ones whose name is known: names arrive on the next sync, and
    /// "Label_9" on screen is worse than nothing at all. The structural ones
    /// are left out for the same reason they are left out of the sidebar --
    /// "Inbox" on a thread in the inbox says nothing.
    static func labels(on ids: [String], known: [MailLabel]) -> [MailLabel] {
        let byID = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
        return MailLabel.browsableOrder(ids.compactMap { byID[$0] })
    }

    /// The labels a header has room to draw, and how many it had to leave out.
    ///
    /// Seven labels on a narrow pane squashed every chip until the words wrapped
    /// inside their own capsules -- "Somerville" came out as "Somerv ille" --
    /// and pushed the message count and the attachment mark off the row
    /// entirely. A few legible names and a count beats seven unreadable ones.
    static func chips(on ids: [String], known: [MailLabel],
                      limit: Int = 3) -> (shown: [MailLabel], extra: Int) {
        let all = labels(on: ids, known: known)
        guard all.count > limit else { return (all, 0) }
        return (Array(all.prefix(limit)), all.count - limit)
    }

    /// How long the thread is, when that is worth saying. "1 message" is a
    /// fact nobody needed.
    static func messageCount(_ count: Int) -> String? {
        count > 1 ? "\(count) messages" : nil
    }
}
