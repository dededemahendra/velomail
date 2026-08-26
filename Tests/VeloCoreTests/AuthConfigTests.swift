import Testing
import Foundation
@testable import VeloCore

@Suite struct AuthConfigTests {
    @Test func gmailFactorySetsGoogleEndpointsAndScopes() {
        let config = AuthConfig.gmail(clientID: "abc", redirectURI: "com.velomail:/oauth")
        #expect(config.clientID == "abc")
        #expect(config.redirectURI == "com.velomail:/oauth")
        #expect(config.authEndpoint == URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!)
        #expect(config.tokenEndpoint == URL(string: "https://oauth2.googleapis.com/token")!)
        #expect(config.scopes.contains("https://www.googleapis.com/auth/gmail.modify"))
        #expect(config.scopes.contains("https://www.googleapis.com/auth/userinfo.email"))
    }

    @Test func authErrorEqualityIgnoresUnderlyingErrorForNetworkAndDecoding() {
        struct E: Error {}
        #expect(AuthError.network(E()) == AuthError.network(E()))
        #expect(AuthError.server(code: "x", description: nil) == AuthError.server(code: "x", description: nil))
        #expect(AuthError.server(code: "x", description: nil) != AuthError.server(code: "y", description: nil))
        #expect(AuthError.missingRefreshToken != AuthError.invalidResponse)
        #expect(AuthError.decoding(E()) == AuthError.decoding(E()))
        #expect(AuthError.network(E()) != AuthError.decoding(E()))
        #expect(AuthError.keychain(status: 1) != AuthError.keychain(status: 2))
    }

    // MARK: - Redirect URI

    @Test func theRedirectSchemeIsDerivedFromTheClientID() {
        let uri = AuthConfig.nativeRedirectURI(
            clientID: "947847957818-kc3abf3msjdta5nmgvqlab55lv31gtrh.apps.googleusercontent.com")

        // Google only accepts the reversed client id as a custom scheme; an
        // arbitrary one is rejected with redirect_uri_mismatch.
        #expect(uri == "com.googleusercontent.apps.947847957818-kc3abf3msjdta5nmgvqlab55lv31gtrh:/oauth2redirect")
    }

    @Test func aClientIDWithoutTheGoogleSuffixIsUsedAsIs() {
        let uri = AuthConfig.nativeRedirectURI(clientID: "123-abc")
        #expect(uri == "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    @Test func surroundingWhitespaceIsIgnored() {
        // Pasted from a browser, this routinely arrives with a newline.
        let uri = AuthConfig.nativeRedirectURI(clientID: "  123-abc.apps.googleusercontent.com\n")
        #expect(uri == "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    @Test func theSchemeIsWhatASWebAuthenticationSessionWillWatchFor() {
        let uri = AuthConfig.nativeRedirectURI(clientID: "123-abc.apps.googleusercontent.com")
        #expect(URL(string: uri)?.scheme == "com.googleusercontent.apps.123-abc")
    }

    @Test func gmailConfigDerivesItsOwnRedirectWhenNotGivenOne() {
        let config = AuthConfig.gmail(clientID: "123-abc.apps.googleusercontent.com")
        #expect(config.redirectURI == "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    @Test func anExplicitRedirectStillWins() {
        let config = AuthConfig.gmail(clientID: "123-abc.apps.googleusercontent.com",
                                      redirectURI: "http://127.0.0.1:7890")
        // Loopback is the other shape Google accepts, for a Desktop client.
        #expect(config.redirectURI == "http://127.0.0.1:7890")
    }
}
