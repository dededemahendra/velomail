import SwiftUI
import AppKit
import VeloCore

/// The thread list, backed by `NSTableView`.
///
/// AppKit rather than SwiftUI `List` for the reason the v1 design gives: SwiftUI
/// `List` degrades on large mailboxes, and an inbox that stays instant while
/// scrolling is the whole point of v1.
struct MessageListView: NSViewRepresentable {
    /// The inbox, grouped. A contiguous partition of the flat list, so a row's
    /// running position *is* its cursor index.
    let sections: [ThreadSection]
    let selectedIndex: Int?
    let markedIndices: Set<Int>
    /// Which list this is. Needed because the viewport follows the selection
    /// only when it moves, and "moved" has to count arriving in a different
    /// list on the same thread.
    var scope: MailScope = .inbox
    /// The person a row is about. Supplied rather than read off the thread,
    /// because in Sent that is the recipient, not the sender.
    let name: (MailThread) -> String
    /// The date a row shows. In Snoozed that is when it comes back.
    let date: (MailThread) -> String
    /// How tall a row is and how much of the message it shows, both from the
    /// reader's own settings.
    var rowHeight: CGFloat = 64
    var previewLines: Int = 1
    /// A short name for each label a row carries, or nothing when it carries
    /// none worth showing.
    var labelNames: (MailThread) -> [String] = { _ in [] }
    let onSelect: (Int) -> Void
    let onOpen: () -> Void

    /// A table row: either a section header or a thread that knows its flat
    /// index. Headers are rows in AppKit but not in the cursor, so the index
    /// travels with the thread rather than being inferred from the row number.
    enum Row {
        case header(String)
        case thread(MailThread, index: Int)
    }

    /// One header per section, unless there is only one — a lone "Other" above
    /// an ordinary inbox is noise, and the split is meant to disappear when
    /// nothing is important.
    var rows: [Row] {
        var rows: [Row] = []
        var flat = 0
        let showHeaders = sections.count > 1
        for section in sections {
            if showHeaders { rows.append(.header(section.title)) }
            for thread in section.threads {
                rows.append(.thread(thread, index: flat))
                flat += 1
            }
        }
        return rows
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .inset
        // A full accent-filled row is loud in a list you stare at all day. The
        // source-list style keeps the sender legible and lets the unread dot and
        // star stay the things that draw the eye. Set via `style`, since the
        // matching selectionHighlightStyle has been deprecated since macOS 12.
        table.style = .sourceList
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
        context.coordinator.rows = rows
        table.reloadData()

        guard let index = selectedIndex, let row = context.coordinator.row(forThread: index) else {
            table.deselectAll(nil)
            // Coming back to the same thread after the selection was dropped is
            // a fresh request to go there, not a repeat of one already served.
            context.coordinator.forgetFollowedSelection()
            return
        }
        if table.selectedRow != row {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        // Keyboard navigation must drag the viewport with it, or j/k walks the
        // selection off-screen -- but only when the selection has actually
        // moved. This runs on every update, and an update is not the reader
        // asking to go anywhere.
        if context.coordinator.shouldFollowSelection(toRow: row, in: scope) {
            table.scrollRowToVisible(row)
        }
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: MessageListView
        /// Cached so the data source and the delegate see the same rows during
        /// one `reloadData`.
        var rows: [Row] = []
        /// Guards against the selection change we just applied bouncing back.
        private var isApplyingSelection = false
        /// The thread the viewport was last moved to follow, and the list it
        /// was in.
        ///
        /// Keyed on the thread rather than on its row: `updateNSView` runs on
        /// every published change anywhere in the app -- the sync status ticks
        /// once a second -- and scrolling to the selection on all of them
        /// dragged the list back under the reader's hands about a second after
        /// every manual scroll. Keying on the thread also means mail landing
        /// above the selection, which moves its row without the reader having
        /// asked for anything, leaves the viewport alone.
        ///
        /// The scope is half of the key because the cursor clamps rather than
        /// clearing when the list changes (`SelectionCursor.reset`), so Inbox
        /// -> Starred can land on the very thread that was already selected.
        /// On the thread alone that reads as "nobody moved", and the viewport
        /// would keep the offset it had in the list it just left.
        private var followedThreadID: String?
        private var followedScope: MailScope?

        /// Whether the viewport should be dragged to `row`, recording that it
        /// was. True when this is a different conversation from the one the
        /// viewport was last moved for, or a different list.
        func shouldFollowSelection(toRow row: Int, in scope: MailScope) -> Bool {
            guard rows.indices.contains(row),
                  case let .thread(thread, _) = rows[row] else { return false }
            guard scope != followedScope || thread.id != followedThreadID else { return false }
            followedScope = scope
            followedThreadID = thread.id
            return true
        }

        /// Drops the record, so the next selection scrolls even if it lands on
        /// the same thread.
        func forgetFollowedSelection() {
            followedThreadID = nil
            followedScope = nil
        }

        init(_ parent: MessageListView) {
            self.parent = parent
            self.rows = parent.rows
        }

        func row(forThread index: Int) -> Int? {
            rows.firstIndex { if case let .thread(_, i) = $0 { return i == index } else { return false } }
        }

        private func threadIndex(atRow row: Int) -> Int? {
            guard rows.indices.contains(row), case let .thread(_, index) = rows[row] else { return nil }
            return index
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            switch rows[row] {
            case let .header(title):
                let header = tableView.makeView(withIdentifier: SectionHeaderView.reuseIdentifier,
                                                owner: self) as? SectionHeaderView
                    ?? SectionHeaderView()
                header.configure(title: title)
                return header
            case let .thread(thread, index):
                // Recycled where the table has one to offer. Building a row is
                // five text fields, two stacks and a set of constraints;
                // pointing an existing one at another thread is ten
                // assignments.
                let view = tableView.makeView(withIdentifier: ThreadRowView.reuseIdentifier,
                                              owner: self) as? ThreadRowView
                    ?? ThreadRowView()
                view.configure(thread: thread,
                               isMarked: parent.markedIndices.contains(index),
                               name: parent.name(thread),
                               dateText: parent.date(thread),
                               previewLines: parent.previewLines,
                               labels: parent.labelNames(thread))
                return view
            }
        }

        // AppKit can ask about a row that a reload has already taken away, so
        // both of these tolerate an index that is no longer there.
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row), case .header = rows[row] else {
                return parent.rowHeight
            }
            return 24
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            guard rows.indices.contains(row), case .header = rows[row] else { return false }
            return true
        }

        /// A header is a label, not a destination: selecting it would give the
        /// cursor an index that means nothing.
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            threadIndex(atRow: row) != nil
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection,
                  let table = notification.object as? NSTableView,
                  let index = threadIndex(atRow: table.selectedRow),
                  // The selection we just applied in `updateNSView` comes back
                  // through here; reporting it would publish a change from
                  // inside a view update for no gain.
                  index != parent.selectedIndex else { return }
            isApplyingSelection = true
            parent.onSelect(index)
            isApplyingSelection = false
        }

        @objc func doubleClicked() { parent.onOpen() }
    }
}

/// A section header: quiet, because the mail is the content and this is a label.
private final class SectionHeaderView: NSView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("velo.sectionHeader")

    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseIdentifier

        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(title: String) {
        label.stringValue = title.uppercased()
    }

    required init?(coder: NSCoder) { nil }
}

final class ThreadRowView: NSView {
    /// What `NSTableView` recycles these under.
    ///
    /// Without it the table never offers a used row back and `viewFor` builds
    /// a fresh one every time -- five text fields, two stacks and a set of
    /// constraints, measured at 1.08ms. That is ~12ms to refill a screen and
    /// another 1.08ms for every row scrolled into view, against a 16.7ms frame.
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("velo.threadRow")
    static let snippetIdentifier = NSUserInterfaceItemIdentifier("velo.threadRow.snippet")

    // Fixed width whether or not it is showing, so marking a row does not
    // shuffle the text next to it.
    private let mark = NSTextField(labelWithString: "")
    private let dot = NSTextField(labelWithString: "")
    // Unread carries weight; read carries none. One signal, not two, so the
    // list reads as a single column of names rather than a checkerboard.
    // Beside the name rather than in the date column: it belongs to the
    // conversation, not to when it last moved.
    private let count = NSTextField(labelWithString: "")
    // A mark, not a word: it appears on a good fraction of rows and must not
    // compete with the sender. A middle dot was too quiet to read as anything
    // but a smudge; the guillemet is the convention other clients already use
    // for mail addressed to you and nobody else.
    private let direct = NSTextField(labelWithString: "")
    private let sender = NSTextField(labelWithString: "")
    // Stored on every thread since attachments were added and never once
    // shown. Knowing a message has a file is most of why you open it.
    private let clip = NSTextField(labelWithString: "")
    // One label, not all of them: a row is a glance, and three chips push the
    // sender out of the space it needs. The thread header lists the rest.
    private let labelChip = NSTextField(labelWithString: "")
    private let star = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private let snippet = NSTextField(labelWithString: "")

    /// Builds the hierarchy. Everything that depends on a particular thread is
    /// set in `configure`, so a recycled row costs an assignment rather than a
    /// construction.
    init() {
        super.init(frame: .zero)
        identifier = Self.reuseIdentifier

        mark.font = .systemFont(ofSize: 11, weight: .bold)
        mark.textColor = .controlAccentColor

        dot.font = .systemFont(ofSize: 7)
        dot.textColor = .controlAccentColor

        count.font = .systemFont(ofSize: 10, weight: .medium)
        count.textColor = .tertiaryLabelColor

        direct.font = .systemFont(ofSize: 11, weight: .medium)
        direct.textColor = .secondaryLabelColor

        sender.lineBreakMode = .byTruncatingTail
        sender.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        clip.font = .systemFont(ofSize: 10)

        labelChip.font = .systemFont(ofSize: 9, weight: .medium)
        labelChip.textColor = .tertiaryLabelColor
        labelChip.lineBreakMode = .byTruncatingTail
        // Below the sender's own low resistance, so a long label gives up its
        // space first. It used to win, and "Invoices to pay this quarter"
        // printed in full while the sender read "Peta Bil...".
        labelChip.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

        star.font = .systemFont(ofSize: 11)
        star.textColor = .systemYellow

        // Tabular figures so the dates form a straight right edge instead of
        // wobbling by a pixel per digit.
        date.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        date.textColor = .tertiaryLabelColor
        date.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Named so a test can find this one field among several that are
        // legitimately empty -- the tick and the unread dot are blank on most
        // rows and must stay visible.
        snippet.identifier = Self.snippetIdentifier
        snippet.font = .systemFont(ofSize: 12)
        // Secondary, not tertiary: the snippet is the thing you actually read
        // when deciding whether to open something.
        snippet.textColor = .secondaryLabelColor
        snippet.lineBreakMode = .byTruncatingTail

        let top = NSStackView(views: [mark, dot, sender, count, direct, NSView(), labelChip, clip, star, date])
        top.orientation = .horizontal
        top.spacing = 6
        top.alignment = .firstBaseline

        setAccessibilityElement(true)
        setAccessibilityRole(.row)

        let stack = NSStackView(views: [top, snippet])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Both fixed, so the sender sits at the same x whether or not the
            // row has a tick or a dot to show. The dot used to be an empty
            // field on a read row and collapsed, moving the whole line 7pt as
            // mail was read.
            mark.widthAnchor.constraint(equalToConstant: 10),
            dot.widthAnchor.constraint(equalToConstant: 8),
        ])
    }

    /// Points this row at a thread.
    ///
    /// Every field is assigned unconditionally, including the ones that are
    /// usually empty. A recycled row still carries the last thread's contents,
    /// so anything left unset shows a star, a tick or a paperclip belonging to
    /// a conversation three screens away.
    func configure(thread: MailThread, isMarked: Bool, name: String, dateText: String,
                   previewLines: Int, labels: [String] = []) {
        mark.stringValue = isMarked ? "\u{2713}" : ""
        dot.stringValue = thread.isUnread ? "\u{25CF}" : ""
        count.stringValue = MailFormatting.threadCount(thread.messageCount) ?? ""
        direct.stringValue =
            MailFormatting.isToYouAlone(recipientCount: thread.recipientCount) ? "\u{00BB}" : ""

        sender.stringValue = name
        sender.font = NSFont.systemFont(ofSize: 13, weight: thread.isUnread ? .semibold : .regular)
        sender.textColor = thread.isUnread ? .labelColor : .secondaryLabelColor

        clip.stringValue = thread.hasAttachments ? "\u{1F4CE}" : ""
        labelChip.stringValue = MailFormatting.shortLabel(labels.first ?? "")
        star.stringValue = thread.labelIDs.contains("STARRED") ? "\u{2605}" : ""
        date.stringValue = dateText

        // Gmail sends this escaped; without decoding the list reads
        // "It&#39;s Friday".
        snippet.stringValue = HTMLText.decoded(thread.snippet)
        snippet.maximumNumberOfLines = previewLines
        // Removed rather than left as an empty gap, in both the cases that
        // produce one: a reader who goes by subject alone and has set the
        // preview to zero lines, and a thread that simply has no snippet --
        // which is what a message carrying only an attachment, or an empty
        // body, arrives as. That drew a sender and then a void the height of a
        // line of text.
        snippet.isHidden = previewLines == 0 || snippet.stringValue.isEmpty

        setAccessibilityLabel(MailFormatting.rowDescription(thread, name: name, date: dateText,
                                                            labels: labels))
    }

    /// Build and configure in one step, for callers that are not recycling.
    convenience init(thread: MailThread, isMarked: Bool, name: String, dateText: String,
                     previewLines: Int, labels: [String] = []) {
        self.init()
        configure(thread: thread, isMarked: isMarked, name: name, dateText: dateText,
                  previewLines: previewLines, labels: labels)
    }

    required init?(coder: NSCoder) { nil }
}

/// Shared address and date formatting for anything that lists mail.
enum MailFormatting {
    /// "Alice <a@b.com>" reads as "Alice" wherever space is tight.
    ///
    /// Quotes are stripped because headers routinely arrive as
    /// `"Roberts, Natalie" <n@x.co>` -- the comma forces the quoting, and
    /// showing it would look like a bug.
    /// A row as one sentence, for anything that cannot see it.
    ///
    /// A row is four text views and two glyphs; without this VoiceOver reads
    /// six unlabelled fragments and the paperclip says nothing at all. Unread
    /// comes first because it is what decides whether to keep listening, and
    /// "read" is never said -- it would be noise on the great majority of rows.
    /// The date and time in full, for a tooltip.
    ///
    /// The transcript names days relatively -- "Today", "Yesterday", "Monday"
    /// -- which is what you want at a glance and useless when you need to
    /// quote the date. Nothing in the app would tell you.
    static func fullStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// The count that goes beside a sender, or nothing for a thread of one.
    ///
    /// A twelve-message thread and a one-message thread looked identical in the
    /// list, and how long a conversation has run is most of what tells you
    /// whether opening it is a minute or ten.
    static func threadCount(_ count: Int) -> String? {
        count > 1 ? "\(count)" : nil
    }

    /// True when the newest message went to one person, which in your own
    /// inbox is you. Mail written to you alone is not the same object as mail
    /// copied to forty, and the list gave no way to tell them apart.
    static func isToYouAlone(recipientCount: Int) -> Bool {
        recipientCount == 1
    }

    /// Cuts a label name down to something a row can carry beside a sender.
    ///
    /// At a word boundary where that leaves most of the allowance, and mid-word
    /// otherwise, so one long word does not collapse to a single letter.
    static func shortLabel(_ name: String, limit: Int = 16) -> String {
        guard name.count > limit else { return name }
        let cut = name.prefix(limit)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= limit / 2 {
            return cut[..<space] + "\u{2026}"
        }
        return cut.trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    static func rowDescription(_ thread: MailThread, name: String, date: String,
                               labels: [String] = []) -> String {
        var parts: [String] = []
        if thread.isUnread { parts.append("Unread") }
        if thread.labelIDs.contains("STARRED") { parts.append("starred") }
        parts.append("from \(name)")
        if thread.messageCount > 1 { parts.append("\(thread.messageCount) messages") }
        // Spelled out: a listener has no dot to see.
        if isToYouAlone(recipientCount: thread.recipientCount) { parts.append("to you only") }
        if !thread.snippet.isEmpty { parts.append(HTMLText.decoded(thread.snippet)) }
        if thread.hasAttachments { parts.append("has attachment") }
        // Every label, not just the one the row has room to draw: a listener
        // has no header beside them to read the rest from.
        parts.append(contentsOf: labels.map { "filed in \($0)" })
        parts.append(date)
        return parts.joined(separator: ", ")
    }

    /// One message in a thread, as one sentence.
    ///
    /// The transcript deliberately hides a repeated sender and a repeated
    /// preview, which is right on screen and wrong out loud: someone listening
    /// has no row above to have read it from.
    static func messageDescription(_ message: Message, time: String,
                                   isExpanded: Bool) -> String {
        var parts = ["From \(displayName(message.sender))"]
        let preview = (message.bodyText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(120)
        if !preview.isEmpty { parts.append(String(preview)) }
        parts.append(time)
        if !isExpanded { parts.append("collapsed") }
        return parts.joined(separator: ", ")
    }

    static func displayName(_ value: String) -> String {
        guard let open = value.firstIndex(of: "<") else { return value }
        let name = value[value.startIndex..<open]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            // " <bare@example.com>" -- no name at all, so show the address.
            let close = value.lastIndex(of: ">") ?? value.endIndex
            return String(value[value.index(after: open)..<close])
        }
        return name
    }

    /// A date the way someone thinks about it, rather than a calendar entry.
    ///
    /// A mail list is scanned, not read: "17:11" and "Monday" answer *when*
    /// instantly, where "25/08/26" makes you do arithmetic. The year only
    /// appears once it is actually ambiguous.
    /// When a snoozed thread comes back.
    ///
    /// Deliberately not `relativeDate`, which treats anything in the future as
    /// "today" and prints a bare clock time. On a list of future times that
    /// reads as today for every row, which is the one thing it must not say.
    static func wakeTime(_ date: Date, now: Date = Date(),
                         calendar: Calendar = .current) -> String {
        guard date > now else { return "Now" }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let time = formatted(date, calendar, timeStyle: .short, dateStyle: .none)

        switch days {
        case 0: return time
        case 1: return "Tomorrow \(time)"
        case 2..<7: return "\(formatted(date, calendar, template: "EEE")) \(time)"
        default:
            let sameYear = calendar.component(.year, from: date)
                == calendar.component(.year, from: now)
            return "\(formatted(date, calendar, template: sameYear ? "d MMM" : "d MMM yyyy")) \(time)"
        }
    }

    /// The same scale as `relativeDate`, except that today is named.
    ///
    /// A list row's date column can say "17.28" and mean today, because the
    /// column is understood to be a date. A heading above a day's messages
    /// cannot: it printed the clock, and the row beneath it printed the same
    /// clock again.
    static func dayHeading(_ date: Date, now: Date = Date(),
                           calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return days < 1 ? "Today" : relativeDate(date, now: now, calendar: calendar)
    }

    static func relativeDate(_ date: Date, now: Date = Date(),
                             calendar: Calendar = .current) -> String {
        // Day boundaries, not elapsed hours: 01:00 today and 23:00 yesterday
        // are two hours apart and belong on different sides of this.
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0

        switch days {
        case ..<1:
            return formatted(date, calendar, timeStyle: .short, dateStyle: .none)
        case 1:
            return "Yesterday"
        case 2..<7:
            return formatted(date, calendar, template: "EEEE")
        default:
            let sameYear = calendar.component(.year, from: date)
                == calendar.component(.year, from: now)
            return formatted(date, calendar, template: sameYear ? "d MMM" : "d MMM yyyy")
        }
    }

    private static func formatted(_ date: Date, _ calendar: Calendar,
                                  template: String? = nil,
                                  timeStyle: DateFormatter.Style = .none,
                                  dateStyle: DateFormatter.Style = .none) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        if let template {
            formatter.setLocalizedDateFormatFromTemplate(template)
        } else {
            formatter.timeStyle = timeStyle
            formatter.dateStyle = dateStyle
        }
        return formatter.string(from: date)
    }
}
