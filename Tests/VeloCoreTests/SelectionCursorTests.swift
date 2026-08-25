import Testing
@testable import VeloCore

@Suite struct SelectionCursorTests {
    @Test func startsWithNoSelectionWhenEmpty() {
        #expect(SelectionCursor(count: 0).index == nil)
    }

    @Test func firstItemIsSelectedInANonEmptyList() {
        #expect(SelectionCursor(count: 3).index == 0)
    }

    @Test func moveDownAndUpWalkTheList() {
        var cursor = SelectionCursor(count: 3)
        cursor.moveDown()
        #expect(cursor.index == 1)
        cursor.moveDown()
        #expect(cursor.index == 2)
        cursor.moveUp()
        #expect(cursor.index == 1)
    }

    @Test func moveDownStopsAtTheEnd() {
        var cursor = SelectionCursor(count: 2)
        cursor.moveDown()
        cursor.moveDown()
        cursor.moveDown()
        #expect(cursor.index == 1)
    }

    @Test func moveUpStopsAtTheStart() {
        var cursor = SelectionCursor(count: 2)
        cursor.moveUp()
        #expect(cursor.index == 0)
    }

    @Test func movingAnEmptyListIsANoOp() {
        var cursor = SelectionCursor(count: 0)
        cursor.moveDown()
        cursor.moveUp()
        #expect(cursor.index == nil)
    }

    @Test func removingTheCurrentItemKeepsTheIndexSoSelectionLandsOnTheNext() {
        var cursor = SelectionCursor(count: 3)
        cursor.moveDown()                 // index 1 of [0,1,2]

        cursor.removeCurrent()

        // The item that moved up into the gap is now selected — that is what
        // makes a held-down "e" sweep the inbox.
        #expect(cursor.count == 2)
        #expect(cursor.index == 1)
    }

    @Test func removingTheLastItemClampsToTheNewLastIndex() {
        var cursor = SelectionCursor(count: 3)
        cursor.moveDown()
        cursor.moveDown()                 // index 2, the last

        cursor.removeCurrent()

        #expect(cursor.count == 2)
        #expect(cursor.index == 1)
    }

    @Test func removingTheOnlyItemClearsSelection() {
        var cursor = SelectionCursor(count: 1)

        cursor.removeCurrent()

        #expect(cursor.count == 0)
        #expect(cursor.index == nil)
    }

    @Test func removingFromAnEmptyListIsANoOp() {
        var cursor = SelectionCursor(count: 0)
        cursor.removeCurrent()
        #expect(cursor.count == 0)
        #expect(cursor.index == nil)
    }

    @Test func sweepingTheWholeListEndsWithNoSelection() {
        var cursor = SelectionCursor(count: 3)
        cursor.removeCurrent()
        cursor.removeCurrent()
        cursor.removeCurrent()
        #expect(cursor.index == nil)
    }

    @Test func resettingTheCountSelectsTheFirstItemAgain() {
        var cursor = SelectionCursor(count: 0)
        cursor.reset(count: 5)
        #expect(cursor.index == 0)
    }

    @Test func resettingClampsAnOutOfRangeSelection() {
        var cursor = SelectionCursor(count: 5)
        cursor.moveDown()
        cursor.moveDown()
        cursor.moveDown()                 // index 3

        cursor.reset(count: 2)            // sync dropped the list to 2

        #expect(cursor.index == 1)
    }

    @Test func selectMovesDirectlyToAnIndex() {
        var cursor = SelectionCursor(count: 5)
        cursor.select(3)
        #expect(cursor.index == 3)
    }

    @Test func selectIgnoresAnOutOfRangeIndex() {
        var cursor = SelectionCursor(count: 3)
        cursor.select(9)
        #expect(cursor.index == 0)
        cursor.select(-1)
        #expect(cursor.index == 0)
    }

    @Test func selectOnAnEmptyListIsANoOp() {
        var cursor = SelectionCursor(count: 0)
        cursor.select(0)
        #expect(cursor.index == nil)
    }

    // MARK: - Marks

    @Test func nothingIsMarkedInitially() {
        #expect(SelectionCursor(count: 3).marked.isEmpty)
    }

    @Test func targetsIsTheCursorRowWhenNothingIsMarked() {
        var cursor = SelectionCursor(count: 3)
        cursor.moveDown()
        // The single-thread path is not a special case of the bulk path; it is
        // the bulk path with one element.
        #expect(cursor.targets == [1])
    }

    @Test func targetsIsEmptyWhenTheListIsEmpty() {
        #expect(SelectionCursor(count: 0).targets.isEmpty)
    }

    @Test func toggleMarkMarksTheCurrentRow() {
        var cursor = SelectionCursor(count: 3)
        cursor.moveDown()
        cursor.toggleMark()
        #expect(cursor.marked == [1])
    }

    @Test func toggleMarkTwiceUnmarksIt() {
        var cursor = SelectionCursor(count: 3)
        cursor.toggleMark()
        cursor.toggleMark()
        #expect(cursor.marked.isEmpty)
        #expect(cursor.targets == [0])   // back to the cursor row
    }

    @Test func targetsAreTheMarkedRowsInAscendingOrder() {
        var cursor = SelectionCursor(count: 4)
        cursor.select(3)
        cursor.toggleMark()
        cursor.select(1)
        cursor.toggleMark()

        #expect(cursor.targets == [1, 3])
    }

    @Test func markingDoesNotMoveTheCursor() {
        var cursor = SelectionCursor(count: 3)
        cursor.moveDown()
        cursor.toggleMark()
        #expect(cursor.index == 1)
    }

    @Test func removeTargetsRemovesEveryMarkedRow() {
        var cursor = SelectionCursor(count: 5)
        cursor.toggleMark()              // 0
        cursor.select(2)
        cursor.toggleMark()              // 2

        cursor.removeTargets()

        #expect(cursor.count == 3)
    }

    @Test func removeTargetsLandsSelectionOnTheLowestRemovedIndex() {
        var cursor = SelectionCursor(count: 5)
        cursor.select(1)
        cursor.toggleMark()
        cursor.select(3)
        cursor.toggleMark()

        cursor.removeTargets()

        // Index 1 is where the first gap was, so whatever slid up into it is
        // now selected — the same rule a single archive follows.
        #expect(cursor.index == 1)
    }

    @Test func removeTargetsClampsWhenTheTailWasRemoved() {
        var cursor = SelectionCursor(count: 3)
        cursor.select(1)
        cursor.toggleMark()
        cursor.select(2)
        cursor.toggleMark()

        cursor.removeTargets()

        #expect(cursor.count == 1)
        #expect(cursor.index == 0)
    }

    @Test func removeTargetsClearsTheSelectionWhenTheListEmpties() {
        var cursor = SelectionCursor(count: 2)
        cursor.toggleMark()
        cursor.select(1)
        cursor.toggleMark()

        cursor.removeTargets()

        #expect(cursor.count == 0)
        #expect(cursor.index == nil)
    }

    @Test func removeTargetsClearsTheMarks() {
        var cursor = SelectionCursor(count: 3)
        cursor.toggleMark()

        cursor.removeTargets()

        #expect(cursor.marked.isEmpty)
    }

    @Test func removeTargetsWithNothingMarkedBehavesLikeRemoveCurrent() {
        var marked = SelectionCursor(count: 3)
        var single = SelectionCursor(count: 3)
        marked.moveDown()
        single.moveDown()

        marked.removeTargets()
        single.removeCurrent()

        #expect(marked == single)
    }

    @Test func resetClearsMarksBecauseIndicesNoLongerMeanAnything() {
        var cursor = SelectionCursor(count: 5)
        cursor.toggleMark()

        cursor.reset(count: 5)

        // Sync can move a row out from under a mark, and silently archiving the
        // wrong mail is far worse than losing a selection.
        #expect(cursor.marked.isEmpty)
    }

    @Test func clearMarksLeavesTheCursorWhereItIs() {
        var cursor = SelectionCursor(count: 3)
        cursor.moveDown()
        cursor.toggleMark()

        cursor.clearMarks()

        #expect(cursor.marked.isEmpty)
        #expect(cursor.index == 1)
        #expect(cursor.count == 3)
    }
}
