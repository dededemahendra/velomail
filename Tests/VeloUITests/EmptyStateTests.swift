import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct EmptyStateTests {
    private func state(_ status: SyncStatus, seen: Bool,
                       scope: MailScope = .inbox) -> EmptyState {
        EmptyState.of(scope: scope, status: status, hasSeenMail: seen)
    }

    @Test func mailThatHasNotArrivedIsNotInboxZero() {
        // The app said "Inbox zero" under a green tick while it was still
        // downloading the mailbox.
        #expect(state(.syncing, seen: false).headline == "Fetching your mail")
        #expect(state(.idle, seen: false).headline == "Fetching your mail")
    }

    @Test func aWaitingStateShowsMotionNotAVerdict() {
        #expect(state(.syncing, seen: false).isWaiting)
        #expect(state(.upToDate(lastSyncedAt: Date()), seen: true).isWaiting == false)
    }

    @Test func anUnreachableGmailSaysSoRatherThanClaimingSuccess() {
        let off = state(.offline(consecutiveFailures: 3), seen: false)
        #expect(off.headline == "Cannot reach Gmail")
        // The symbol carries it; the status bar below counts the retries. A
        // spinner over a struck-through aerial contradicts itself.
        #expect(off.isWaiting == false)
        #expect(off.symbol == "wifi.slash")
    }

    @Test func aFailureQuotesTheReasonSoItCanBeActedOn() {
        let failed = state(.failed(reason: "The sync cursor is no longer valid"), seen: false)
        #expect(failed.detail == "The sync cursor is no longer valid")
        // Not "waiting": nothing is coming without a hand on it.
        #expect(failed.isWaiting == false)
    }

    @Test func onceMailHasArrivedAnEmptyListIsAFactAboutTheList() {
        // A sync failing right now does not change what is already in the
        // inbox, so a triaged inbox still reads as finished.
        #expect(state(.offline(consecutiveFailures: 2), seen: true).headline == "Inbox zero")
        #expect(state(.syncing, seen: true).headline == "Inbox zero")
    }

    @Test func onlyAStuckStateOffersAButton() {
        // "Try again" over a sync that is already running invites the reader
        // to press it and watch nothing change.
        #expect(state(.syncing, seen: false).retry == nil)
        #expect(state(.upToDate(lastSyncedAt: Date()), seen: true).retry == nil)
        #expect(state(.offline(consecutiveFailures: 1), seen: false).retry == "Try again")
        #expect(state(.failed(reason: "x"), seen: false).retry == "Try again")
    }

    @Test func aSyncedAccountWithNoMailIsGenuinelyEmpty() {
        #expect(state(.upToDate(lastSyncedAt: Date()), seen: false).headline == "Inbox zero")
    }

    @Test func eachScopeKeepsItsOwnWords() {
        let done = SyncStatus.upToDate(lastSyncedAt: Date())
        #expect(state(done, seen: true, scope: .sent).headline == "Nothing sent yet")
        #expect(state(done, seen: true, scope: .starred).detail.contains("Press s"))
        #expect(state(done, seen: true, scope: .label("L", "Clients")).headline
                    == "Nothing in Clients")
    }
}
