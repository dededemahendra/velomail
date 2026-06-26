import Testing
import Foundation
@testable import VeloCore

@Suite struct AuthURLBuilderTests {
    private func queryDict(_ url: URL) -> [String: String] {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var dict: [String: String] = [:]
        for item in comps?.queryItems ?? [] { dict[item.name] = item.value }
        return dict
    }

    @Test func buildsAuthorizationURLWithAllRequiredQueryItems() {
        let config = AuthConfig.gmail(clientID: "client-123", redirectURI: "com.velomail:/oauth")
        let pkce = PKCE(codeVerifier: "v", codeChallenge: "chal", state: "st8")
        let url = AuthURLBuilder.url(config: config, pkce: pkce)

        #expect(url.absoluteString.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth?"))
        let q = queryDict(url)
        #expect(q["response_type"] == "code")
        #expect(q["client_id"] == "client-123")
        #expect(q["redirect_uri"] == "com.velomail:/oauth")
        #expect(q["code_challenge"] == "chal")
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["state"] == "st8")
        #expect(q["access_type"] == "offline")
        #expect(q["prompt"] == "consent")
        #expect(q["scope"] == "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/userinfo.email")
    }
}
