import Foundation

public enum AuthError: Error {
    case invalidResponse
    case server(code: String, description: String?)
    case network(Error)
    case decoding(Error)
    case missingRefreshToken
    case keychain(status: OSStatus)
}

extension AuthError: Equatable {
    public static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse): return true
        case let (.server(c1, d1), .server(c2, d2)): return c1 == c2 && d1 == d2
        case (.network, .network): return true
        case (.decoding, .decoding): return true
        case (.missingRefreshToken, .missingRefreshToken): return true
        case let (.keychain(s1), .keychain(s2)): return s1 == s2
        default: return false
        }
    }
}
