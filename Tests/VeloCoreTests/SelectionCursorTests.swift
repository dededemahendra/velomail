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
}
