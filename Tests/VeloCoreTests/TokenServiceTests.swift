import Testing
import Foundation
@testable import VeloCore

private final class MockHTTPClient: HTTPClient {
    var result: Result<(Data, HTTPURLResponse), Error>
    private(set) var lastURL: URL?
    private(set) var lastBody: Data?

    init(_ result: Result<(Data, HTTPURLResponse), Error>) { self.result = result }

    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        lastURL = url
        lastBody = body
        return try result.get()
    }

    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        fatalError("get not used by TokenService")
    }
}

private func http(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://oauth2.googleapis.com/token")!,
                    statusCode: status, httpVersion: nil, headerFields: nil)!
}

private let fixedNow = Date(timeIntervalSince1970: 10_000)

private func makeService(_ result: Result<(Data, HTTPURLResponse), Error>) -> (TokenService, MockHTTPClient) {
    let client = MockHTTPClient(result)
    let service = TokenService(
        config: .gmail(clientID: "cid", redirectURI: "com.velomail:/oauth"),
        httpClient: client,
        now: { fixedNow })
    return (service, client)
}

@Suite struct TokenServiceTests {
    @Test func exchangeParsesTokensAndComputesExpiry() async throws {
        let json = Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8)
        let (service, client) = makeService(.success((json, http(200))))

        let token = try await service.exchange(code: "auth-code", verifier: "ver")

        #expect(token.accessToken == "at")
        #expect(token.refreshToken == "rt")
        #expect(token.expiresAt == fixedNow.addingTimeInterval(3600))
        let sentBody = client.lastBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        #expect(sentBody.contains("grant_type=authorization_code"))
        #expect(sentBody.contains("code=auth-code"))
        #expect(sentBody.contains("code_verifier=ver"))
        #expect(sentBody.contains("client_id=cid"))
        #expect(sentBody.contains("redirect_uri="))
    }

    @Test func refreshReusesSuppliedRefreshTokenWhenResponseOmitsIt() async throws {
        let json = Data(#"{"access_token":"at2","expires_in":1800}"#.utf8)
        let (service, _) = makeService(.success((json, http(200))))

        let token = try await service.refresh(refreshToken: "old-rt")

        #expect(token.accessToken == "at2")
        #expect(token.refreshToken == "old-rt")
        #expect(token.expiresAt == fixedNow.addingTimeInterval(1800))
    }

    @Test func serverErrorBodyMapsToServerError() async throws {
        let json = Data(#"{"error":"invalid_grant","error_description":"bad"}"#.utf8)
        let (service, _) = makeService(.success((json, http(400))))

        await #expect(throws: AuthError.server(code: "invalid_grant", description: "bad")) {
            _ = try await service.exchange(code: "c", verifier: "v")
        }
    }

    @Test func malformedSuccessBodyMapsToDecodingError() async throws {
        let json = Data(#"{"not_a_token":true}"#.utf8)
        let (service, _) = makeService(.success((json, http(200))))

        await #expect(throws: AuthError.decoding(NSError(domain: "", code: 0))) {
            _ = try await service.exchange(code: "c", verifier: "v")
        }
    }

    @Test func networkFailureMapsToNetworkError() async throws {
        struct Boom: Error {}
        let (service, _) = makeService(.failure(Boom()))

        await #expect(throws: AuthError.network(NSError(domain: "", code: 0))) {
            _ = try await service.refresh(refreshToken: "rt")
        }
    }

    @Test func nonJSONErrorBodyMapsToInvalidResponse() async throws {
        let (service, _) = makeService(.success((Data("not json".utf8), http(500))))
        await #expect(throws: AuthError.invalidResponse) {
            _ = try await service.exchange(code: "c", verifier: "v")
        }
    }

    @Test func emptyRefreshTokenThrowsMissingRefreshToken() async throws {
        let (service, _) = makeService(.success((Data(), http(200))))

        await #expect(throws: AuthError.missingRefreshToken) {
            _ = try await service.refresh(refreshToken: "")
        }
    }
}
