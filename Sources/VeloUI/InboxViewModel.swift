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

    public init(store: MailStore, outbound: OutboundService) {
        self.store = store
        self.outbound = outbound
    }

    public var selectedIndex: Int? { cursor.index }

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

    /// Archives the selection and advances onto the thread that takes its place.
    public func archiveSelected() throws {
        guard let thread = selectedThread, let index = cursor.index else { return }
        try outbound.archive(threadID: thread.id)
        threads.remove(at: index)
        cursor.removeCurrent()
        try refreshSelectedMessages()
    }

    public func markSelectedRead() throws {
        guard let thread = selectedThread else { return }
        try outbound.markRead(threadID: thread.id)
        try reloadPreservingSelection()
    }

    // MARK: - Internals

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
    }
}
