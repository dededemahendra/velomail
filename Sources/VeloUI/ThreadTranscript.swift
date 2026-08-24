import Foundation
import VeloCore

/// Which messages in the open thread are expanded.
///
/// Newest expanded, older ones collapsed: the shape every threaded client
/// converges on, and the only one that keeps a long conversation navigable
/// without scrolling past history to reach the reply you came for.
struct ThreadTranscript: Equatable {
    private var threadID: String?
    private var expanded: Set<String> = []
    private var knownMessageIDs: Set<String> = []

    /// Points the transcript at a thread's current messages.
    ///
    /// Re-syncing the *same* thread preserves what the user opened -- background
    /// sync repaints constantly and must not keep snapping messages shut -- while
    /// a genuinely new message expands, because that is what you want to read.
    mutating func sync(threadID newThreadID: String, messages: [Message]) {
        let ids = Set(messages.map(\.id))

        if newThreadID != threadID {
            threadID = newThreadID
            expanded = []
            knownMessageIDs = []
        }

        let arrived = ids.subtracting(knownMessageIDs)
        knownMessageIDs = ids

        // Newest by date; ties broken by id so the choice is deterministic.
        let newest = messages.max { ($0.date, $0.id) < ($1.date, $1.id) }?.id

        if expanded.isEmpty, let newest {
            expanded = [newest]
        } else if let newest, arrived.contains(newest) {
            expanded.insert(newest)
        }
        expanded.formIntersection(ids)
    }

    func isExpanded(_ messageID: String) -> Bool { expanded.contains(messageID) }

    mutating func toggle(_ messageID: String) {
        if expanded.contains(messageID) {
            expanded.remove(messageID)
        } else {
            expanded.insert(messageID)
        }
    }
}
