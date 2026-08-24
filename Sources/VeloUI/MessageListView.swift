import SwiftUI
import AppKit
import VeloCore

/// The thread list, backed by `NSTableView`.
///
/// AppKit rather than SwiftUI `List` for the reason the v1 design gives: SwiftUI
/// `List` degrades on large mailboxes, and an inbox that stays instant while
/// scrolling is the whole point of v1.
struct MessageListView: NSViewRepresentable {
    let threads: [MailThread]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void
    let onOpen: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 64
        table.style = .inset
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        table.addTableColumn(NSTableColumn(identifier: .init("thread")))
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        table.reloadData()

        guard let index = selectedIndex, threads.indices.contains(index) else {
            table.deselectAll(nil)
            return
        }
        if table.selectedRow != index {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        // Keyboard navigation must drag the viewport with it, or j/k walks the
        // selection off-screen.
        table.scrollRowToVisible(index)
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: MessageListView
        /// Guards against the selection change we just applied bouncing back.
        private var isApplyingSelection = false

        init(_ parent: MessageListView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.threads.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.threads.indices.contains(row) else { return nil }
            return ThreadRowView(thread: parent.threads[row])
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let table = notification.object as? NSTableView,
                  table.selectedRow >= 0 else { return }
            isApplyingSelection = true
            parent.onSelect(table.selectedRow)
            isApplyingSelection = false
        }

        @objc func doubleClicked() { parent.onOpen() }
    }
}

/// One row: sender, subject, snippet, date, and an unread dot.
private final class ThreadRowView: NSView {
    init(thread: MailThread) {
        super.init(frame: .zero)

        let dot = NSTextField(labelWithString: thread.isUnread ? "●" : "")
        dot.font = .systemFont(ofSize: 9)
        dot.textColor = .controlAccentColor

        let sender = NSTextField(labelWithString: MailFormatting.displayName(thread.sender))
        sender.font = NSFont.systemFont(ofSize: 13, weight: thread.isUnread ? .semibold : .regular)
        sender.lineBreakMode = .byTruncatingTail

        let date = NSTextField(labelWithString: MailFormatting.shortDate(thread.lastMessageDate))
        date.font = .systemFont(ofSize: 11)
        date.textColor = .secondaryLabelColor

        let snippet = NSTextField(labelWithString: thread.snippet)
        snippet.font = .systemFont(ofSize: 12)
        snippet.textColor = .secondaryLabelColor
        snippet.lineBreakMode = .byTruncatingTail

        let top = NSStackView(views: [dot, sender, NSView(), date])
        top.orientation = .horizontal
        top.spacing = 6

        let stack = NSStackView(views: [top, snippet])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

/// Shared address and date formatting for anything that lists mail.
enum MailFormatting {
    /// "Alice <a@b.com>" reads better as "Alice" wherever space is tight.
    static func displayName(_ value: String) -> String {
        guard let open = value.firstIndex(of: "<") else { return value }
        let name = value[value.startIndex..<open].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? value : name
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        formatter.timeStyle = Calendar.current.isDateInToday(date) ? .short : .none
        return formatter.string(from: date)
    }
}
