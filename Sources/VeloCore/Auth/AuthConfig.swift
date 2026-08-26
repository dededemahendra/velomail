import Foundation

public struct AuthConfig: Equatable {
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]
    public let authEndpoint: URL
    public let tokenEndpoint: URL

    public init(clientID: String, redirectURI: String, scopes: [String],
                authEndpoint: URL, tokenEndpoint: URL) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.authEndpoint = authEndpoint
        self.tokenEndpoint = tokenEndpoint
    }

    /// The redirect URI Google accepts for a native (iOS/macOS) client.
    ///
    /// It is a *function of the client id*, not a free choice: Google rejects an
    /// arbitrary custom scheme with `redirect_uri_mismatch`, and only accepts
    /// the reversed client id — `123-abc.apps.googleusercontent.com` becomes
    /// `com.googleusercontent.apps.123-abc`. Hardcoding a scheme of our own,
    /// which is what this replaced, could never have worked.
    ///
    /// (The other shape Google accepts is a loopback URI, which belongs to the
    /// Desktop client type and needs a local HTTP server to catch the redirect.
    /// Pass one explicitly if you want that instead.)
    public static func nativeRedirectURI(clientID: String) -> String {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = trimmed.hasSuffix(googleClientSuffix)
            ? String(trimmed.dropLast(googleClientSuffix.count))
            : trimmed
        return "com.googleusercontent.apps.\(identifier):/oauth2redirect"
    }

    private static let googleClientSuffix = ".apps.googleusercontent.com"

    /// - Parameter redirectURI: defaults to the one derived from `clientID`,
    ///   which is what a native client needs.
    public static func gmail(clientID: String, redirectURI: String? = nil) -> AuthConfig {
        AuthConfig(
            clientID: clientID,
            redirectURI: redirectURI ?? nativeRedirectURI(clientID: clientID),
            scopes: [
                "https://www.googleapis.com/auth/gmail.modify",
                "https://www.googleapis.com/auth/userinfo.email",
            ],
            authEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
    }
}
