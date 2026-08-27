import Foundation
import SwiftUI
import VeloCore

/// The thread list and its cursor.
///
/// Reads only from `MailStore` and issues actions through `OutboundService`, so
/// the UI never waits on the network: an archive is visible immediately and the
/// sync actor pushes it later.
/// Which of the mailbox's lists is on screen.
public enum MailScope: Equatable, Sendable {
    case inbox
    case sent
    case snoozed
    case starred
    case archive
    /// A Gmail label, carrying the name to put on the header: the id is
    /// `Label_7` and nobody wants to read that.
    case label(String, String)

    /// What the list calls itself.
    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .snoozed: return "Snoozed"
        case .starred: return "Starred"
        case .archive: return "Archive"
        case let .label(_, name): return name
        }
    }
}

@MainActor
public final class InboxViewModel: ObservableObject {
    /// The list currently on screen. Changing it reloads from the top.
    @Published public private(set) var scope: MailScope = .inbox
    @Published public private(set) var threads: [MailThread] = []
    /// `threads`, grouped. A contiguous partition of the same array, so
    /// `sections.flatMap(\.threads) == threads` always holds and a flat row
    /// index means the same thread in both.
    @Published public private(set) var sections: [ThreadSection] = []
    @Published public private(set) var selectedMessages: [Message] = []
    /// Attachments for the open thread, by message id.
    @Published public private(set) var selectedAttachments: [String: [MailAttachment]] = [:]

    private let store: MailStore
    private let outbound: OutboundService
    private let preferences = AppPreferences()
    private var cursor = SelectionCursor(count: 0)
    /// The section each row was assigned, parallel to `threads`.
    ///
    /// Frozen at reload rather than recomputed: starring a thread must not make
    /// it jump out from under the cursor mid-keystroke, and a live re-group
    /// would break the invariant that a flat index means the same row on screen
    /// as in `threads`. The next reload lifts it into Important.
    private var sectionIDs: [String] = []
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
        regroup(try threadsInScope())
        cursor.reset(count: threads.count)
        try refreshSelectedMessages()
    }

    /// What the list calls itself, for the header.
    public var title: String { scope.title }

    /// Switches list. The cursor starts at the top rather than keeping its row:
    /// an index carried across two different lists lands on whatever happens to
    /// sit in that position.
    public func show(_ scope: MailScope) throws {
        guard scope != self.scope else { return }
        self.scope = scope
        try reload()
    }

    /// The person a row is about: who wrote it in the inbox, who it went to in
    /// Sent. "me" on every row of Sent tells the writer nothing.
    public func correspondent(of thread: MailThread) -> String {
        guard scope == .sent else { return MailFormatting.displayName(thread.sender) }
        let recipients = (try? store.messages(inThread: thread.id).last?.recipients) ?? []
        guard let first = recipients.first else { return MailFormatting.displayName(thread.sender) }
        let name = MailFormatting.displayName(first)
        guard recipients.count > 1 else { return name }
        return "\(name) and \(recipients.count - 1) other\(recipients.count == 2 ? "" : "s")"
    }

    /// The date a row should carry: when it comes back, in Snoozed, and when it
    /// arrived everywhere else. The received date is the one thing the writer
    /// already knows about a thread they chose to put away.
    public func rowDate(of thread: MailThread) -> String {
        guard scope == .snoozed, let wake = thread.snoozedUntil else {
            return MailFormatting.relativeDate(thread.lastMessageDate)
        }
        return MailFormatting.wakeTime(wake)
    }

    private func threadsInScope() throws -> [MailThread] {
        switch scope {
        case .inbox: return try store.inboxThreads()
        case .sent: return try store.sentThreads()
        case .snoozed: return try store.snoozedThreads()
        case .starred: return try store.starredThreads()
        case .archive: return try store.archivedThreads()
        case let .label(id, _): return try store.threads(withLabel: id)
        }
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

    /// The thread ids an action would act on, captured before it runs.
    public var targetThreadIDs: [String] {
        cursor.targets.compactMap { threads.indices.contains($0) ? threads[$0].id : nil }
    }

    /// Archives every target and advances onto the thread that takes the place
    /// of the first one. With nothing marked that is the selected thread, so
    /// this is also the single-row archive — there is no bulk variant.
    /// Brings every target back to the inbox now.
    public func unsnoozeSelected() throws {
        for id in targetThreadIDs { try outbound.unsnooze(threadID: id) }
        try reloadPreservingSelection()
    }

    public func archiveSelected() throws {
        try disposeTargets { try outbound.archive(threadID: $0) }
    }

    /// Moves the targets to the bin, advancing the same way archive does.
    public func trashSelected() throws {
        try disposeTargets { try outbound.trash(threadID: $0) }
    }

    /// Removes the targets from the list after applying `dispose` to each.
    ///
    /// Shared by archive and trash because the list bookkeeping is the fiddly
    /// part and duplicating it is how the two would drift.
    private func disposeTargets(_ dispose: (String) throws -> Void) throws {
        let indices = cursor.targets
        guard !indices.isEmpty else { return }
        for index in indices { try dispose(threads[index].id) }
        // Highest index first, so removing one does not shift the next.
        for index in indices.reversed() {
            threads.remove(at: index)
            if sectionIDs.indices.contains(index) { sectionIDs.remove(at: index) }
        }
        sections = InboxSections.group(threads, by: sectionIDs)
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

    /// Puts the unread flag back so the thread can be come back to.
    ///
    /// Unlike archive and trash it does *not* advance -- the thread stays where
    /// it is, because the point is that you are leaving it there.
    public func markSelectedUnread() throws {
        let targets = targetThreads
        guard !targets.isEmpty else { return }
        for thread in targets { try outbound.markUnread(threadID: thread.id) }
        try refreshTargetRows()
    }

    public func markSelectedRead() throws {
        guard let thread = selectedThread else { return }
        // Honours the reader's delay: someone triaging a busy inbox opens
        // things to look, not to clear them.
        let delay = preferences.marksReadAfter
        // Negative means never: the thread stays unread however long it is open.
        guard delay >= 0 else { return }

        guard delay > 0 else {
            try outbound.markRead(threadID: thread.id)
            try reloadPreservingSelection()
            return
        }

        // Waited out on the thread that is actually open. Moving on before the
        // delay is up leaves it unread, which is the point of asking for one.
        let id = thread.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.selectedThread?.id == id else { return }
            try? self.outbound.markRead(threadID: id)
            try? self.reloadPreservingSelection()
        }
    }

    // MARK: - Internals

    /// Re-reads just the rows an action touched. A star does not change the
    /// length of the list, so refreshing in place keeps both the cursor and the
    /// marks — a full reload would drop them (see `SelectionCursor.reset`).
    private func refreshTargetRows() throws {
        for index in cursor.targets where threads.indices.contains(index) {
            if let refreshed = try store.thread(id: threads[index].id) { threads[index] = refreshed }
        }
        // `sectionIDs` deliberately untouched: the row keeps its place.
        sections = InboxSections.group(threads, by: sectionIDs)
    }

    /// Takes a freshly fetched inbox, puts it in section order, and records
    /// which section each row landed in.
    private func regroup(_ fetched: [MailThread]) {
        threads = InboxSections.ordered(fetched)
        sectionIDs = threads.map(InboxSections.sectionID(for:))
        sections = InboxSections.group(threads, by: sectionIDs)
    }

    private func reloadPreservingSelection() throws {
        let previous = cursor.index
        regroup(try threadsInScope())
        cursor.reset(count: threads.count)
        if let previous { cursor.select(min(previous, max(threads.count - 1, 0))) }
        try refreshSelectedMessages()
    }

    private func refreshSelectedMessages() throws {
        guard let thread = selectedThread else {
            selectedMessages = []
            selectedAttachments = [:]
            return
        }
        let ordered = try store.messages(inThread: thread.id)
        // Newest first is a choice about reading, not about storage: the store
        // always answers in the order the conversation happened.
        selectedMessages = preferences.newestFirstInThread ? ordered.reversed() : ordered
        selectedAttachments = Dictionary(
            uniqueKeysWithValues: try selectedMessages.map {
                ($0.id, try store.attachments(forMessage: $0.id))
            })
        transcript.sync(threadID: thread.id, messages: selectedMessages)
    }

    // MARK: - Transcript

    public func isExpanded(_ messageID: String) -> Bool { transcript.isExpanded(messageID) }

    public func attachments(forMessage messageID: String) -> [MailAttachment] {
        selectedAttachments[messageID] ?? []
    }

    public func toggleExpansion(_ messageID: String) { transcript.toggle(messageID) }
}
