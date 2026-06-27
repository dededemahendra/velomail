import Foundation

public struct TokenSet: Codable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True if the token is at or past expiry, accounting for a safety `skew`.
    public func isExpired(now: Date = Date(), skew: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(skew) >= expiresAt
    }
}
