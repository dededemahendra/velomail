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

    public static func gmail(clientID: String, redirectURI: String) -> AuthConfig {
        AuthConfig(
            clientID: clientID,
            redirectURI: redirectURI,
            scopes: [
                "https://www.googleapis.com/auth/gmail.modify",
                "https://www.googleapis.com/auth/userinfo.email",
            ],
            authEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
    }
}
