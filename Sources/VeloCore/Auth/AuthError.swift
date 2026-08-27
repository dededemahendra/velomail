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

public extension AuthError {
    /// What to put in front of a person.
    ///
    /// `String(describing:)` put `server(code: "401", description:
    /// Optional("Invalid Credentials"))` in the status bar, which tells
    /// somebody nothing except that the app is not finished.
    var message: String {
        switch self {
        case let .network(underlying):
            return AuthError.networkMessage(underlying)
        case let .server(code, description):
            return AuthError.serverMessage(code: code, description: description)
        case .missingRefreshToken:
            return "Sign-in expired. Sign in again to keep syncing."
        case let .keychain(status):
            return "Could not reach the Keychain (\(status))."
        case .decoding:
            return "Gmail sent something this app could not read."
        case .invalidResponse:
            return "Gmail sent an unexpected reply."
        }
    }

    /// True when signing in again is the thing that fixes it.
    var needsSignIn: Bool {
        switch self {
        case .missingRefreshToken: return true
        case let .server(code, _): return code == "401" || code == "invalid_grant"
        default: return false
        }
    }

    /// True when nothing is wrong and nothing needs doing.
    ///
    /// A red light for a train tunnel teaches people to ignore the red light,
    /// which costs more than the tunnel did.
    var isTransient: Bool {
        switch self {
        case .network: return true
        case let .server(code, _): return ["429", "500", "502", "503", "504"].contains(code)
        default: return false
        }
    }

    /// Readable text for anything at all: not everything thrown is an
    /// `AuthError`, and the status bar takes whatever arrives.
    static func message(for error: Error) -> String {
        if let authError = error as? AuthError { return authError.message }
        if let urlError = error as? URLError { return networkMessage(urlError) }
        return "Something went wrong while syncing."
    }

    /// Being offline and Gmail being slow send someone to fix different
    /// things, so they are not told the same thing.
    private static func networkMessage(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return "Could not reach Gmail." }
        switch urlError.code {
        case .notConnectedToInternet: return "No internet connection"
        case .timedOut: return "Gmail took too long to answer"
        case .networkConnectionLost: return "The connection dropped"
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "Could not reach Gmail"
        default: return "Could not reach Gmail"
        }
    }

    private static func serverMessage(code: String, description: String?) -> String {
        switch code {
        case "401", "invalid_grant":
            return "Sign-in expired. Sign in again to keep syncing."
        case "403":
            return "Gmail refused the request. The account may not have access."
        case "429":
            return "Gmail is asking us to slow down. Syncing will resume shortly."
        case "500", "502", "503", "504":
            return "Gmail is having trouble. Syncing will resume shortly."
        default:
            // The code earns its place: it is the one thing worth quoting to
            // anybody trying to help.
            return "Gmail returned an error \(code)."
        }
    }
}
