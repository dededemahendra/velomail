import Testing
import Foundation
@testable import VeloCore

@Suite struct PKCETests {
    // RFC 7636 Appendix B test vector.
    @Test func codeChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCE.codeChallenge(for: verifier)
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generateProducesUrlSafeVerifierOfValidLength() {
        let pkce = PKCE.generate()
        #expect(pkce.codeVerifier.count >= 43)
        #expect(pkce.codeVerifier.count <= 128)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let verifierChars = CharacterSet(charactersIn: pkce.codeVerifier)
        #expect(allowed.isSuperset(of: verifierChars))
    }

    @Test func generateProducesNonEmptyVaryingState() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        #expect(!a.state.isEmpty)
        #expect(a.state != b.state)
        #expect(a.codeVerifier != b.codeVerifier)
    }

    @Test func generatedChallengeMatchesItsVerifier() {
        let pkce = PKCE.generate()
        #expect(pkce.codeChallenge == PKCE.codeChallenge(for: pkce.codeVerifier))
    }
}
