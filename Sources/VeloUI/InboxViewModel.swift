import Foundation
import SwiftUI
import VeloCore

/// The thread list and its cursor.
///
/// Reads only from `MailStore` and issues actions through `OutboundService`, so
/// the UI never waits on the network: an archive is visible immediately and the
/// sync actor pushes it later.
@MainActor
public final class InboxViewModel: ObservableObject {
    @Published public private(set) var threads: [MailThread] = []
    @Published public private(set) var selectedMessages: [Message] = []

    private let store: MailStore
    private let outbound: OutboundService
    private var cursor = SelectionCursor(count: 0)
    @Published private var transcript = ThreadTranscript()

    public init(store: MailStore, outbound: OutboundService) {
        self.store = store
        self.outbound = outbound
    }

    public var selectedIndex: Int? { cursor.index }

    /// The rows explicitly marked for a bulk action, for the list to indicate.
    public var markedIndices: Set<Int> { cursor.marked }

    public func isMarked(index: Int) -> Bool { cursor.marked.contains(index) }

    public var markedThreadIDs: [String] {
        cursor.marked.sorted().compactMap { threads.indices.contains($0) ? threads[$0].id : nil }
    }

    /// The threads an action applies to: everything marked, or the selected
    /// thread when nothing is.
    public var targetThreads: [MailThread] {
        cursor.targets.compactMap { threads.indices.contains($0) ? threads[$0] : nil }
    }

    /// Marks or unmarks the row under the cursor.
    ///
    /// Nothing `@Published` changes, so the notification is sent by hand —
    /// otherwise the indicator would not appear until the next reload.
    public func toggleMark() {
        objectWillChange.send()
        cursor.toggleMark()
    }

    public var selectedThread: MailThread? {
        guard let index = cursor.index, threads.indices.contains(index) else { return nil }
        return threads[index]
    }

    /// Re-reads the inbox. Selection clamps rather than dangling, because
    /// background sync can shrink the list under the cursor at any moment.
    public func reload() throws {
        threads = try store.inboxThreads()
        cursor.reset(count: threads.count)
        try refreshSelectedMessages()
    }

    public func moveDown() {
        cursor.moveDown()
        try? refreshSelectedMessages()
    }

    public func moveUp() {
        cursor.moveUp()
        try? refreshSelectedMessages()
    }

    public func select(index: Int) {
        cursor.select(index)
        try? refreshSelectedMessages()
    }

    /// Archives every target and advances onto the thread that takes the place
    /// of the first one. With nothing marked that is the selected thread, so
    /// this is also the single-row archive — there is no bulk variant.
    public func archiveSelected() throws {
        let indices = cursor.targets
        guard !indices.isEmpty else { return }
        for index in indices { try outbound.archive(threadID: threads[index].id) }
        // Highest index first, so removing one does not shift the next.
        for index in indices.reversed() { threads.remove(at: index) }
        cursor.removeTargets()
        try refreshSelectedMessages()
    }

    /// Stars the targets, or unstars them when every one is already starred.
    ///
    /// Toggling each thread independently would leave a mixed selection *more*
    /// mixed, which is never what the gesture meant; Gmail resolves it the same
    /// way.
    public func toggleStarSelected() throws {
        let targets = targetThreads
        guard !targets.isEmpty else { return }
        let allStarred = targets.allSatisfy { $0.labelIDs.contains("STARRED") }
        for thread in targets {
            if allStarred {
                try outbound.unstar(threadID: thread.id)
            } else if !thread.labelIDs.contains("STARRED") {
                try outbound.star(threadID: thread.id)
            }
        }
        try refreshTargetRows()
    }

    public func markSelectedRead() throws {
        guard let thread = selectedThread else { return }
        try outbound.markRead(threadID: thread.id)
        try reloadPreservingSelection()
    }

    // MARK: - Internals

    /// Re-reads just the rows an action touched. A star does not change the
    /// length of the list, so refreshing in place keeps both the cursor and the
    /// marks — a full reload would drop them (see `SelectionCursor.reset`).
    private func refreshTargetRows() throws {
        for index in cursor.targets where threads.indices.contains(index) {
            if let refreshed = try store.thread(id: threads[index].id) { threads[index] = refreshed }
        }
    }

    private func reloadPreservingSelection() throws {
        let previous = cursor.index
        threads = try store.inboxThreads()
        cursor.reset(count: threads.count)
        if let previous { cursor.select(min(previous, max(threads.count - 1, 0))) }
        try refreshSelectedMessages()
    }

    private func refreshSelectedMessages() throws {
        guard let thread = selectedThread else {
            selectedMessages = []
            return
        }
        selectedMessages = try store.messages(inThread: thread.id)
        transcript.sync(threadID: thread.id, messages: selectedMessages)
    }

    // MARK: - Transcript

    public func isExpanded(_ messageID: String) -> Bool { transcript.isExpanded(messageID) }

    public func toggleExpansion(_ messageID: String) { transcript.toggle(messageID) }
}
