import Foundation

public struct TokenService {
    private let config: AuthConfig
    private let httpClient: HTTPClient
    private let now: () -> Date

    public init(config: AuthConfig, httpClient: HTTPClient, now: @escaping () -> Date = { Date() }) {
        self.config = config
        self.httpClient = httpClient
        self.now = now
    }

    public func exchange(code: String, verifier: String) async throws -> TokenSet {
        let body = formBody(withSecret: [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
        ])
        return try await send(body: body, fallbackRefreshToken: nil)
    }

    public func refresh(refreshToken: String) async throws -> TokenSet {
        guard !refreshToken.isEmpty else { throw AuthError.missingRefreshToken }
        // The secret belongs here too: omitting it would work at sign-in and
        // fail an hour later when the first refresh comes due.
        let body = formBody(withSecret: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ])
        return try await send(body: body, fallbackRefreshToken: refreshToken)
    }

    // MARK: - Internals

    /// Adds `client_secret` when the client has one. A public (iOS) client has
    /// none, and sending an empty value would be rejected.
    private func formBody(withSecret fields: [String: String]) -> Data {
        var fields = fields
        if let secret = config.clientSecret { fields["client_secret"] = secret }
        return formBody(fields)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    private struct ErrorResponse: Decodable {
        let error: String
        let error_description: String?
    }

    private func send(body: Data, fallbackRefreshToken: String?) async throws -> TokenSet {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.post(
                url: config.tokenEndpoint,
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: body)
        } catch {
            throw AuthError.network(error)
        }

        guard (200..<300).contains(response.statusCode) else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AuthError.server(code: err.error, description: err.error_description)
            }
            throw AuthError.invalidResponse
        }

        let decoded: TokenResponse
        do {
            decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.decoding(error)
        }

        return TokenSet(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? fallbackRefreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(decoded.expires_in)))
    }

    private func formBody(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let pairs = params.sorted { $0.key < $1.key }.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
