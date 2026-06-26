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
    }
}
