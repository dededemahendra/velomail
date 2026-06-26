import Foundation
import CryptoKit
import Security

public struct PKCE: Equatable {
    public let codeVerifier: String
    public let codeChallenge: String
    public let state: String

    public init(codeVerifier: String, codeChallenge: String, state: String) {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.state = state
    }

    public static func generate() -> PKCE {
        let verifier = randomURLSafeString(byteCount: 32) // 32 bytes -> 43 base64url chars
        let challenge = codeChallenge(for: verifier)
        let state = randomURLSafeString(byteCount: 16)
        return PKCE(codeVerifier: verifier, codeChallenge: challenge, state: state)
    }

    public static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URLEncode(Data(bytes))
    }
}
