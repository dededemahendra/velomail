import Foundation

/// The list cursor behind `j`/`k` and the auto-advance that follows an archive.
///
/// Models a flat list by index rather than by item identity, which is exactly
/// what makes a held-down `e` sweep the inbox: after a removal the selection
/// stays on the same index, so the thread that moved up into the gap is the one
/// now selected.
public struct SelectionCursor: Equatable, Sendable {
    public private(set) var count: Int
    public private(set) var index: Int?
    /// The rows explicitly marked for a bulk action.
    ///
    /// Indices rather than thread ids, matching the cursor's own design. The
    /// cost is that marks cannot survive the list changing underneath them, so
    /// `reset(count:)` clears them.
    public private(set) var marked: Set<Int> = []

    public init(count: Int) {
        self.count = max(0, count)
        self.index = self.count > 0 ? 0 : nil
    }

    /// The rows an action applies to: everything marked, or the cursor row when
    /// nothing is.
    ///
    /// This is the property that keeps the single-thread path and the bulk path
    /// the same code — with nothing marked it is exactly one row, so today's
    /// behaviour is unchanged.
    public var targets: [Int] {
        guard marked.isEmpty else { return marked.sorted() }
        return index.map { [$0] } ?? []
    }

    /// Marks or unmarks the cursor row, leaving the cursor where it is: marking
    /// is not navigation.
    public mutating func toggleMark() {
        guard let current = index else { return }
        if marked.contains(current) {
            marked.remove(current)
        } else {
            marked.insert(current)
        }
    }

    public mutating func clearMarks() {
        marked.removeAll()
    }

    public mutating func moveDown() {
        guard let current = index, count > 0 else { return }
        index = min(current + 1, count - 1)
    }

    public mutating func moveUp() {
        guard let current = index, count > 0 else { return }
        index = max(current - 1, 0)
    }

    /// Removes the selected item and advances. Selection stays at the same
    /// index (now the next item), clamping at the end of the list and clearing
    /// when the list empties.
    public mutating func removeCurrent() {
        guard let current = index, count > 0 else { return }
        count -= 1
        index = count > 0 ? min(current, count - 1) : nil
    }

    /// Removes every target and lands the selection on the lowest gap.
    ///
    /// With nothing marked this is `removeCurrent()`; with rows marked it is
    /// the same rule applied to all of them at once, which is why archive needs
    /// no bulk variant.
    public mutating func removeTargets() {
        let removed = targets
        guard !removed.isEmpty else { return }
        count = max(0, count - removed.count)
        marked.removeAll()          // the surviving indices have all shifted
        index = count > 0 ? min(removed[0], count - 1) : nil
    }

    /// Jumps straight to an index — a mouse click, rather than j/k walking.
    /// An out-of-range index is ignored rather than clamped, because a click
    /// outside the list is a miss, not a request to move to the end.
    public mutating func select(_ newIndex: Int) {
        guard count > 0, (0..<count).contains(newIndex) else { return }
        index = newIndex
    }

    /// Re-points the cursor at a list whose length changed underneath it —
    /// background sync adding or removing threads. An out-of-range selection
    /// clamps rather than disappearing.
    public mutating func reset(count newCount: Int) {
        count = max(0, newCount)
        // A row can move out from under a mark, and silently acting on the
        // wrong mail is far worse than losing a selection.
        marked.removeAll()
        guard count > 0 else {
            index = nil
            return
        }
        index = min(index ?? 0, count - 1)
    }
}
