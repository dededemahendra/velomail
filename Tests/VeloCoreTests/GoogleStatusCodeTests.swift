import Testing
import Foundation
@testable import VeloCore

/// Seen live: "Sync problem: Gmail returned an error RESOURCE_EXHAUSTED."
///
/// That banner is wrong twice over. Gmail asking a client to slow down is the
/// most ordinary thing that can happen to a sync loop -- it is not a problem,
/// it resolves itself, and the app already backs off. And the app already had
/// a good sentence for it, under "429".
///
/// It never reached it. A Google API error carries both a numeric `code` and a
/// canonical `status`, and the client prefers the status: every rule written
/// against "429" or "500" only fired when Gmail omitted the string, which it
/// does not. The rules now know both spellings of the same thing.
@Suite struct GoogleStatusCodeTests {
    private func server(_ code: String) -> AuthError {
        .server(code: code, description: nil)
    }

    // MARK: - Slow down

    @Test func aRateLimitIsTransientUnderEitherSpelling() {
        #expect(server("429").isTransient)
        #expect(server("RESOURCE_EXHAUSTED").isTransient)
    }

    @Test func aRateLimitSaysItWillResumeRatherThanQuotingTheCode() {
        #expect(server("RESOURCE_EXHAUSTED").message
                    == "Gmail is asking us to slow down. Syncing will resume shortly.")
    }

    // MARK: - Gmail having a bad day

    @Test func serverTroubleIsTransientUnderEitherSpelling() {
        for code in ["500", "502", "503", "504", "INTERNAL", "UNAVAILABLE", "DEADLINE_EXCEEDED"] {
            #expect(server(code).isTransient, "\(code) should be transient")
        }
        #expect(server("UNAVAILABLE").message
                    == "Gmail is having trouble. Syncing will resume shortly.")
    }

    // MARK: - Things signing in again fixes

    /// The one that was quietly missing. An expired token caught at the token
    /// endpoint arrives as `invalid_grant` and was recognised; the same expiry
    /// caught on an API call arrives as `UNAUTHENTICATED` and was not, so the
    /// app would have gone on retrying instead of asking for a sign-in.
    @Test func anUnauthenticatedCallAsksForASignIn() {
        #expect(server("401").needsSignIn)
        #expect(server("UNAUTHENTICATED").needsSignIn)
        #expect(server("invalid_grant").needsSignIn)
    }

    @Test func aSignInProblemIsNotTreatedAsTransient() {
        // Retrying cannot fix it, and backing off only delays the moment the
        // reader finds out.
        #expect(!server("UNAUTHENTICATED").isTransient)
        #expect(!server("401").isTransient)
    }

    // MARK: - Refusals

    @Test func aRefusalSaysTheAccountMayNotHaveAccess() {
        for code in ["403", "PERMISSION_DENIED"] {
            #expect(server(code).message
                        == "Gmail refused the request. The account may not have access.")
            #expect(!server(code).isTransient)
        }
    }

    // MARK: - Everything else

    /// An unrecognised code is still quoted. It is the one thing worth showing
    /// to anybody trying to help.
    @Test func somethingUnrecognisedIsStillQuoted() {
        #expect(server("TEAPOT").message == "Gmail returned an error TEAPOT.")
        #expect(!server("TEAPOT").isTransient)
        #expect(!server("TEAPOT").needsSignIn)
    }
}
