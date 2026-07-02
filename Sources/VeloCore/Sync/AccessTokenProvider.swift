import Foundation

/// Supplies a valid Gmail access token on demand, refreshing and persisting a
/// new one when the stored token has expired.
///
/// This is the "Using / refreshing" flow from the Auth design (§5), deferred to
/// GmailSync: `GmailAPIClient` calls `validAccessToken()` before each request.
public final class AccessTokenProvider {
    private let store: TokenStore
    private let service: TokenService
    private let now: () -> Date

    public init(store: TokenStore, service: TokenService, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.service = service
        self.now = now
    }

    /// Returns a currently-valid access token. Refreshes and persists a new
    /// token set when the stored one is expired.
    ///
    /// - Throws: `AuthError.missingRefreshToken` when there is no stored token,
    ///   or the stored token is expired but carries no usable refresh token —
    ///   signalling the caller to force re-sign-in rather than retry.
    public func validAccessToken() async throws -> String {
        guard let token = try store.load() else {
            throw AuthError.missingRefreshToken
        }

        if !token.isExpired(now: now()) {
            return token.accessToken
        }

        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            throw AuthError.missingRefreshToken
        }

        let refreshed = try await service.refresh(refreshToken: refreshToken)
        try store.save(refreshed)
        return refreshed.accessToken
    }
}
