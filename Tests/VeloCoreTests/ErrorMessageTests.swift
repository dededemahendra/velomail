import Testing
import Foundation
@testable import VeloCore

@Suite struct ErrorMessageTests {
    // MARK: - What a person is told

    @Test func aDroppedConnectionSaysSo() {
        let offline = URLError(.notConnectedToInternet)
        #expect(AuthError.network(offline).message == "No internet connection")
    }

    @Test func aTimeoutIsNotTheSameAsBeingOffline() {
        // One is your wifi, the other is Gmail being slow. Telling someone
        // their connection is down when it is not sends them to fix the wrong
        // thing.
        #expect(AuthError.network(URLError(.timedOut)).message == "Gmail took too long to answer")
    }

    @Test func anExpiredSignInSaysWhatToDo() {
        let error = AuthError.server(code: "401", description: "Invalid Credentials")
        #expect(error.message == "Sign-in expired. Sign in again to keep syncing.")
    }

    @Test func aMissingRefreshTokenIsTheSameProblemInPractice() {
        #expect(AuthError.missingRefreshToken.message.contains("Sign in again"))
    }

    @Test func rateLimitingIsNotPresentedAsBreakage() {
        // Nothing is wrong and nothing needs doing; it resumes on its own.
        let error = AuthError.server(code: "429", description: "Rate Limit Exceeded")
        #expect(error.message == "Gmail is asking us to slow down. Syncing will resume shortly.")
    }

    @Test func anUnrecognisedServerErrorQuotesItsCode() {
        // The raw description leaked into the status bar as
        // server(code: "400", description: Optional("boom")). The code earns
        // its place -- it is the one thing worth quoting to anybody helping --
        // but the Swift syntax around it does not.
        let message = AuthError.server(code: "400", description: "boom").message
        #expect(!message.contains("Optional"))
        #expect(!message.contains("code:"))
        #expect(message.contains("400"))
    }

    @Test func aRecognisedServerErrorSaysWhatItMeansInstead() {
        // Nobody needs to be told "503"; they need to be told to wait.
        let message = AuthError.server(code: "503", description: "boom").message
        #expect(message.contains("resume"))
        #expect(!message.contains("503"))
    }

    @Test func aKeychainFailureNamesTheKeychain() {
        #expect(AuthError.keychain(status: -25300).message.contains("Keychain"))
    }

    @Test func anythingElseIsStillPlainEnglish() {
        #expect(!AuthError.invalidResponse.message.isEmpty)
        #expect(!AuthError.invalidResponse.message.contains("("))
    }

    // MARK: - What the app should do about it

    @Test func onlyAnExpiredSignInAsksForSigningIn() {
        #expect(AuthError.server(code: "401", description: nil).needsSignIn)
        #expect(AuthError.missingRefreshToken.needsSignIn)
        #expect(!AuthError.network(URLError(.timedOut)).needsSignIn)
        #expect(!AuthError.server(code: "500", description: nil).needsSignIn)
    }

    @Test func aConnectionProblemIsNotAFailure() {
        // It resolves itself when the laptop comes off the train, and a red
        // light for it teaches people to ignore the red light.
        #expect(AuthError.network(URLError(.notConnectedToInternet)).isTransient)
        #expect(AuthError.server(code: "429", description: nil).isTransient)
        #expect(AuthError.server(code: "503", description: nil).isTransient)
        #expect(!AuthError.server(code: "400", description: nil).isTransient)
    }

    // MARK: - Anything at all

    @Test func anErrorFromSomewhereElseIsStillReadable() {
        // Not everything thrown is an AuthError; the status bar takes whatever
        // arrives.
        struct Odd: Error {}
        #expect(!AuthError.message(for: Odd()).isEmpty)
        #expect(!AuthError.message(for: Odd()).contains("Odd()"))
    }

    @Test func aURLErrorFromAnywhereReadsTheSameWay() {
        #expect(AuthError.message(for: URLError(.notConnectedToInternet))
                == "No internet connection")
    }
}
