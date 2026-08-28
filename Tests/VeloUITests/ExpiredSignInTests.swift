import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct ExpiredSignInTests {
    // MARK: - The engine recognises it

    @Test func aRefusedTokenIsNotJustAnotherFailure() {
        // needsSignIn existed in the engine and nothing in the UI ever read it.
        #expect(AuthError.server(code: "401", description: nil).needsSignIn)
        #expect(AuthError.server(code: "invalid_grant", description: nil).needsSignIn)
        #expect(AuthError.missingRefreshToken.needsSignIn)
    }

    @Test func thingsThatFixThemselvesAreNotThis() {
        // A red light for a train tunnel teaches people to ignore red lights.
        #expect(!AuthError.server(code: "503", description: nil).needsSignIn)
        #expect(!AuthError.server(code: "429", description: nil).needsSignIn)
        #expect(!AuthError.invalidResponse.needsSignIn)
    }

    // MARK: - What the reader is told

    @Test func theEmptyStateOffersTheThingThatWorks() {
        // "Try again" on an expired sign-in is a button that can never
        // succeed, however many times it is pressed.
        let state = EmptyState.of(scope: .inbox, status: .expired, hasSeenMail: false)
        #expect(state.headline == "Sign-in expired")
        #expect(state.retry == "Sign in")
        #expect(!state.isWaiting)
    }

    @Test func aFullInboxStillSaysSoSomewhere() {
        // Once mail has arrived the empty state never appears at all -- and an
        // inbox with four hundred threads in it is never empty. That is why
        // there is a banner.
        let settled = EmptyState.of(scope: .inbox, status: .expired, hasSeenMail: true)
        #expect(settled.headline == "Inbox zero")
    }

    @Test func theStatusBarNamesIt() {
        #expect(StatusBar(status: .expired, count: 0, unread: 0, isFocused: false)
            .label == "Sign-in expired")
    }

    @Test func itLooksAsSeriousAsItIs() {
        #expect(StatusBar(status: .expired, count: 0, unread: 0, isFocused: false)
            .colour == .red)
    }
}
