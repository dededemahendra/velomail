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

    public init(count: Int) {
        self.count = max(0, count)
        self.index = self.count > 0 ? 0 : nil
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

    /// Re-points the cursor at a list whose length changed underneath it —
    /// background sync adding or removing threads. An out-of-range selection
    /// clamps rather than disappearing.
    public mutating func reset(count newCount: Int) {
        count = max(0, newCount)
        guard count > 0 else {
            index = nil
            return
        }
        index = min(index ?? 0, count - 1)
    }
}
