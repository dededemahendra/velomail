import Testing
@testable import VeloCore

/// Moving a highlight through a list that has an end.
///
/// Written down once because two lists want it -- the command palette and the
/// recipient suggestions in the composer -- and they should not disagree about
/// what pressing Down on the last row does.
@Suite struct WrappingIndexTests {
    @Test func itMovesTheObviousWay() {
        #expect(WrappingIndex.moved(from: 0, by: 1, count: 5) == 1)
        #expect(WrappingIndex.moved(from: 3, by: -1, count: 5) == 2)
    }

    /// Down from the bottom comes back to the top, which is what the composer
    /// already did and what a palette of eight things should do.
    @Test func itWrapsAtBothEnds() {
        #expect(WrappingIndex.moved(from: 4, by: 1, count: 5) == 0)
        #expect(WrappingIndex.moved(from: 0, by: -1, count: 5) == 4)
    }

    @Test func anEmptyListHasNowhereToGo() {
        #expect(WrappingIndex.moved(from: 0, by: 1, count: 0) == 0)
        #expect(WrappingIndex.moved(from: 3, by: -1, count: 0) == 0)
    }

    /// A filter can shrink the list under a highlight that was further down.
    @Test func anIndexPastTheEndComesBackInsideIt() {
        #expect(WrappingIndex.moved(from: 9, by: 1, count: 3) < 3)
        #expect(WrappingIndex.moved(from: 9, by: 0, count: 3) < 3)
    }

    @Test func aListOfOneStaysWhereItIs() {
        #expect(WrappingIndex.moved(from: 0, by: 1, count: 1) == 0)
        #expect(WrappingIndex.moved(from: 0, by: -1, count: 1) == 0)
    }
}
