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

    /// How long the thread is, when that is worth saying. "1 message" is a
    /// fact nobody needed.
    static func messageCount(_ count: Int) -> String? {
        count > 1 ? "\(count) messages" : nil
    }
}
