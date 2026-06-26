# VeloCore Auth (Headless Token Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless OAuth 2.0 token core for Velo Mail's Gmail auth — PKCE, authorization-URL building, token exchange/refresh, and token storage — all unit-tested without network, GUI, or real Google credentials.

**Architecture:** New code lives in the existing `VeloCore` SPM target under `Sources/VeloCore/Auth/`. Each component is a small, single-purpose unit. All network access goes through an injectable `HTTPClient` protocol so the deterministic test suite never touches the network. The interactive browser sign-in is intentionally NOT built here (it needs the future GUI app).

**Tech Stack:** Swift 6.1 (Swift 5.9 tools / Swift 5 language mode), SPM, Swift Testing, Foundation + CryptoKit + Security (all system frameworks — no new SPM dependencies). Command Line Tools only.

## Global Constraints

- All new source files go under `Sources/VeloCore/Auth/`; tests under `Tests/VeloCoreTests/`.
- Tests use **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — NOT XCTest (unavailable under Command Line Tools).
- Do NOT write `#expect(try someThrowingCall())`. Extract the throwing call to a local `let` first, then `#expect` on the result (Swift 6.1.2 macro/`try` limitation observed in this repo).
- No new third-party dependencies. Only Foundation, CryptoKit, Security.
- Deterministic default suite: no real network, no real Keychain, no real Google credentials. The Keychain test is opt-in via an environment variable.
- Builds/tests run via `swift test` (Command Line Tools, no Xcode.app).
- Commit after every task with the trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Work on branch `feat/velocore-auth` (created off `master`).

---

### Task 1: AuthConfig + AuthError

**Files:**
- Create: `Sources/VeloCore/Auth/AuthConfig.swift`
- Create: `Sources/VeloCore/Auth/AuthError.swift`
- Test: `Tests/VeloCoreTests/AuthConfigTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct AuthConfig: Equatable` with `clientID: String`, `redirectURI: String`, `scopes: [String]`, `authEndpoint: URL`, `tokenEndpoint: URL`, a public memberwise `init`, and `static func gmail(clientID: String, redirectURI: String) -> AuthConfig`.
  - `enum AuthError: Error, Equatable` with cases `.invalidResponse`, `.server(code: String, description: String?)`, `.network(Error)`, `.decoding(Error)`, `.missingRefreshToken`, `.keychain(status: OSStatus)`. (`.keychain` is added here for Task 8; `.network`/`.decoding` compare by case only in `Equatable`.)

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/AuthConfigTests.swift`:
```swift
import Testing
import Foundation
@testable import VeloCore

@Suite struct AuthConfigTests {
    @Test func gmailFactorySetsGoogleEndpointsAndScopes() {
        let config = AuthConfig.gmail(clientID: "abc", redirectURI: "com.velomail:/oauth")
        #expect(config.clientID == "abc")
        #expect(config.redirectURI == "com.velomail:/oauth")
        #expect(config.authEndpoint == URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!)
        #expect(config.tokenEndpoint == URL(string: "https://oauth2.googleapis.com/token")!)
        #expect(config.scopes.contains("https://www.googleapis.com/auth/gmail.modify"))
        #expect(config.scopes.contains("https://www.googleapis.com/auth/userinfo.email"))
    }

    @Test func authErrorEqualityIgnoresUnderlyingErrorForNetworkAndDecoding() {
        struct E: Error {}
        #expect(AuthError.network(E()) == AuthError.network(E()))
        #expect(AuthError.server(code: "x", description: nil) == AuthError.server(code: "x", description: nil))
        #expect(AuthError.server(code: "x", description: nil) != AuthError.server(code: "y", description: nil))
        #expect(AuthError.missingRefreshToken != AuthError.invalidResponse)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AuthConfigTests`
Expected: FAIL — `AuthConfig` / `AuthError` not found.

- [ ] **Step 3: Implement `AuthError`**

`Sources/VeloCore/Auth/AuthError.swift`:
```swift
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
```

- [ ] **Step 4: Implement `AuthConfig`**

`Sources/VeloCore/Auth/AuthConfig.swift`:
```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AuthConfigTests`
Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/VeloCore/Auth/AuthConfig.swift Sources/VeloCore/Auth/AuthError.swift Tests/VeloCoreTests/AuthConfigTests.swift
git commit -m "feat: add AuthConfig and AuthError"
```

---

### Task 2: PKCE

**Files:**
- Create: `Sources/VeloCore/Auth/PKCE.swift`
- Test: `Tests/VeloCoreTests/PKCETests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct PKCE: Equatable` with `codeVerifier: String`, `codeChallenge: String`, `state: String`, a public memberwise `init`.
  - `static func generate() -> PKCE`.
  - `static func codeChallenge(for verifier: String) -> String` (base64url of SHA-256).
  - `static func base64URLEncode(_ data: Data) -> String`.

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/PKCETests.swift`:
```swift
import Testing
import Foundation
@testable import VeloCore

@Suite struct PKCETests {
    // RFC 7636 Appendix B test vector.
    @Test func codeChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCE.codeChallenge(for: verifier)
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generateProducesUrlSafeVerifierOfValidLength() {
        let pkce = PKCE.generate()
        #expect(pkce.codeVerifier.count >= 43)
        #expect(pkce.codeVerifier.count <= 128)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let verifierChars = CharacterSet(charactersIn: pkce.codeVerifier)
        #expect(allowed.isSuperset(of: verifierChars))
    }

    @Test func generateProducesNonEmptyVaryingState() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        #expect(!a.state.isEmpty)
        #expect(a.state != b.state)
        #expect(a.codeVerifier != b.codeVerifier)
    }

    @Test func generatedChallengeMatchesItsVerifier() {
        let pkce = PKCE.generate()
        #expect(pkce.codeChallenge == PKCE.codeChallenge(for: pkce.codeVerifier))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PKCETests`
Expected: FAIL — `PKCE` not found.

- [ ] **Step 3: Implement `PKCE`**

`Sources/VeloCore/Auth/PKCE.swift`:
```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PKCETests`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add Sources/VeloCore/Auth/PKCE.swift Tests/VeloCoreTests/PKCETests.swift
git commit -m "feat: add PKCE generation"
```

---

### Task 3: AuthURLBuilder

**Files:**
- Create: `Sources/VeloCore/Auth/AuthURLBuilder.swift`
- Test: `Tests/VeloCoreTests/AuthURLBuilderTests.swift`

**Interfaces:**
- Consumes: `AuthConfig` (Task 1), `PKCE` (Task 2).
- Produces: `enum AuthURLBuilder` with `static func url(config: AuthConfig, pkce: PKCE) -> URL`.

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/AuthURLBuilderTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AuthURLBuilderTests`
Expected: FAIL — `AuthURLBuilder` not found.

- [ ] **Step 3: Implement `AuthURLBuilder`**

`Sources/VeloCore/Auth/AuthURLBuilder.swift`:
```swift
import Foundation

public enum AuthURLBuilder {
    public static func url(config: AuthConfig, pkce: PKCE) -> URL {
        var comps = URLComponents(url: config.authEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return comps.url!
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AuthURLBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VeloCore/Auth/AuthURLBuilder.swift Tests/VeloCoreTests/AuthURLBuilderTests.swift
git commit -m "feat: add AuthURLBuilder"
```

---

### Task 4: TokenSet

**Files:**
- Create: `Sources/VeloCore/Auth/TokenSet.swift`
- Test: `Tests/VeloCoreTests/TokenSetTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct TokenSet: Codable, Equatable` with `accessToken: String`, `refreshToken: String?`, `expiresAt: Date`, a public memberwise `init`, and `func isExpired(now: Date = Date(), skew: TimeInterval = 60) -> Bool`.

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/TokenSetTests.swift`:
```swift
import Testing
import Foundation
@testable import VeloCore

@Suite struct TokenSetTests {
    @Test func isExpiredFalseWellBeforeExpiry() {
        let now = Date(timeIntervalSince1970: 1000)
        let token = TokenSet(accessToken: "a", refreshToken: nil,
                             expiresAt: Date(timeIntervalSince1970: 5000))
        #expect(token.isExpired(now: now) == false)
    }

    @Test func isExpiredTrueAfterExpiry() {
        let now = Date(timeIntervalSince1970: 6000)
        let token = TokenSet(accessToken: "a", refreshToken: nil,
                             expiresAt: Date(timeIntervalSince1970: 5000))
        #expect(token.isExpired(now: now) == true)
    }

    @Test func isExpiredTrueWithinSkewWindow() {
        let now = Date(timeIntervalSince1970: 4970) // 30s before expiry, skew 60s
        let token = TokenSet(accessToken: "a", refreshToken: nil,
                             expiresAt: Date(timeIntervalSince1970: 5000))
        #expect(token.isExpired(now: now, skew: 60) == true)
    }

    @Test func codableRoundTrips() throws {
        let token = TokenSet(accessToken: "a", refreshToken: "r",
                             expiresAt: Date(timeIntervalSince1970: 5000))
        let data = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(TokenSet.self, from: data)
        #expect(decoded == token)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TokenSetTests`
Expected: FAIL — `TokenSet` not found.

- [ ] **Step 3: Implement `TokenSet`**

`Sources/VeloCore/Auth/TokenSet.swift`:
```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TokenSetTests`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add Sources/VeloCore/Auth/TokenSet.swift Tests/VeloCoreTests/TokenSetTests.swift
git commit -m "feat: add TokenSet model"
```

---

### Task 5: HTTPClient protocol + URLSessionHTTPClient

**Files:**
- Create: `Sources/VeloCore/Auth/HTTPClient.swift`
- Test: `Tests/VeloCoreTests/URLSessionHTTPClientTests.swift`

**Interfaces:**
- Consumes: `AuthError` (Task 1).
- Produces:
  - `protocol HTTPClient { func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) }`
  - `struct URLSessionHTTPClient: HTTPClient` with `init(session: URLSession = .shared)`.

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/URLSessionHTTPClientTests.swift`:
```swift
import Testing
import Foundation
@testable import VeloCore

// Intercepts requests so the real URLSessionHTTPClient can be tested offline.
final class StubURLProtocol: URLProtocol {
    static var stubData = Data()
    static var stubStatus = 200
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.readStream)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.stubStatus,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.stubData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func readStream(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite struct URLSessionHTTPClientTests {
    private func makeClient() -> URLSessionHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(session: URLSession(configuration: config))
    }

    @Test func postReturnsBodyAndStatusAndSendsBody() async throws {
        StubURLProtocol.stubData = Data("response-body".utf8)
        StubURLProtocol.stubStatus = 201
        let client = makeClient()
        let url = URL(string: "https://example.com/token")!

        let (data, response) = try await client.post(
            url: url, headers: ["Content-Type": "text/plain"], body: Data("sent-body".utf8))

        #expect(String(decoding: data, as: UTF8.self) == "response-body")
        #expect(response.statusCode == 201)
        let sent = StubURLProtocol.lastBody.map { String(decoding: $0, as: UTF8.self) }
        #expect(sent == "sent-body")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter URLSessionHTTPClientTests`
Expected: FAIL — `HTTPClient` / `URLSessionHTTPClient` not found.

- [ ] **Step 3: Implement `HTTPClient`**

`Sources/VeloCore/Auth/HTTPClient.swift`:
```swift
import Foundation

public protocol HTTPClient {
    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        return (data, http)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter URLSessionHTTPClientTests`
Expected: PASS. (If the body assertion fails because URLSession moved the body to a stream, the `readStream` fallback handles it — both paths are covered.)

- [ ] **Step 5: Commit**

```bash
git add Sources/VeloCore/Auth/HTTPClient.swift Tests/VeloCoreTests/URLSessionHTTPClientTests.swift
git commit -m "feat: add HTTPClient protocol and URLSession implementation"
```

---

### Task 6: TokenService (exchange + refresh)

**Files:**
- Create: `Sources/VeloCore/Auth/TokenService.swift`
- Test: `Tests/VeloCoreTests/TokenServiceTests.swift`

**Interfaces:**
- Consumes: `AuthConfig`, `AuthError` (Task 1), `TokenSet` (Task 4), `HTTPClient` (Task 5).
- Produces:
  - `struct TokenService` with `init(config: AuthConfig, httpClient: HTTPClient, now: @escaping () -> Date = { Date() })`.
  - `func exchange(code: String, verifier: String) async throws -> TokenSet`.
  - `func refresh(refreshToken: String) async throws -> TokenSet`.
  - Behavior: form-encodes the request body; on 2xx decodes `access_token`/`expires_in`/optional `refresh_token`, computing `expiresAt = now() + expires_in`; on non-2xx decodes `{error, error_description}` into `.server`, else `.invalidResponse`; network failure → `.network`; JSON decode failure on success body → `.decoding`. `refresh` with an empty token throws `.missingRefreshToken`. A refresh response that omits `refresh_token` reuses the supplied token.

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/TokenServiceTests.swift`:
```swift
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

    @Test func emptyRefreshTokenThrowsMissingRefreshToken() async throws {
        let (service, _) = makeService(.success((Data(), http(200))))

        await #expect(throws: AuthError.missingRefreshToken) {
            _ = try await service.refresh(refreshToken: "")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TokenServiceTests`
Expected: FAIL — `TokenService` not found.

- [ ] **Step 3: Implement `TokenService`**

`Sources/VeloCore/Auth/TokenService.swift`:
```swift
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
        let body = formBody([
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
        let body = formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ])
        return try await send(body: body, fallbackRefreshToken: refreshToken)
    }

    // MARK: - Internals

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
        let pairs = params.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TokenServiceTests`
Expected: PASS (all six). Note: `#expect(throws:)` here matches on `AuthError`'s `Equatable` conformance, so `.network`/`.decoding` match any underlying error per Task 1's equality rules.

- [ ] **Step 5: Commit**

```bash
git add Sources/VeloCore/Auth/TokenService.swift Tests/VeloCoreTests/TokenServiceTests.swift
git commit -m "feat: add TokenService for code exchange and refresh"
```

---

### Task 7: TokenStore protocol + InMemoryTokenStore

**Files:**
- Create: `Sources/VeloCore/Auth/TokenStore.swift`
- Test: `Tests/VeloCoreTests/InMemoryTokenStoreTests.swift`

**Interfaces:**
- Consumes: `TokenSet` (Task 4).
- Produces:
  - `protocol TokenStore { func load() throws -> TokenSet?; func save(_ tokenSet: TokenSet) throws; func clear() throws }`
  - `final class InMemoryTokenStore: TokenStore` with public `init()`.

- [ ] **Step 1: Write the failing test**

`Tests/VeloCoreTests/InMemoryTokenStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import VeloCore

@Suite struct InMemoryTokenStoreTests {
    private func sampleToken() -> TokenSet {
        TokenSet(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 5000))
    }

    @Test func loadReturnsNilWhenEmpty() throws {
        let store = InMemoryTokenStore()
        let loaded = try store.load()
        #expect(loaded == nil)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = InMemoryTokenStore()
        let token = sampleToken()
        try store.save(token)
        let loaded = try store.load()
        #expect(loaded == token)
    }

    @Test func clearRemovesStoredToken() throws {
        let store = InMemoryTokenStore()
        try store.save(sampleToken())
        try store.clear()
        let loaded = try store.load()
        #expect(loaded == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InMemoryTokenStoreTests`
Expected: FAIL — `TokenStore` / `InMemoryTokenStore` not found.

- [ ] **Step 3: Implement `TokenStore` + `InMemoryTokenStore`**

`Sources/VeloCore/Auth/TokenStore.swift`:
```swift
import Foundation

public protocol TokenStore {
    func load() throws -> TokenSet?
    func save(_ tokenSet: TokenSet) throws
    func clear() throws
}

public final class InMemoryTokenStore: TokenStore {
    private var stored: TokenSet?

    public init() {}

    public func load() throws -> TokenSet? { stored }
    public func save(_ tokenSet: TokenSet) throws { stored = tokenSet }
    public func clear() throws { stored = nil }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter InMemoryTokenStoreTests`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
git add Sources/VeloCore/Auth/TokenStore.swift Tests/VeloCoreTests/InMemoryTokenStoreTests.swift
git commit -m "feat: add TokenStore protocol and in-memory store"
```

---

### Task 8: KeychainTokenStore (opt-in integration test)

**Files:**
- Create: `Sources/VeloCore/Auth/KeychainTokenStore.swift`
- Test: `Tests/VeloCoreTests/KeychainTokenStoreTests.swift`

**Interfaces:**
- Consumes: `TokenStore` (Task 7), `TokenSet` (Task 4), `AuthError` (Task 1).
- Produces: `final class KeychainTokenStore: TokenStore` with `init(service: String = "com.velomail.tokens", account: String = "default")`. Stores the JSON-encoded `TokenSet` as a generic-password Keychain item; `load` returns nil when absent; keychain failures throw `AuthError.keychain(status:)`.

- [ ] **Step 1: Write the opt-in integration test**

`Tests/VeloCoreTests/KeychainTokenStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import VeloCore

// Opt-in: real Keychain access can prompt or flake under Command Line Tools, so
// this suite is excluded from the default `swift test` run. Enable with:
//   VELO_KEYCHAIN_TESTS=1 swift test --filter KeychainTokenStoreTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VELO_KEYCHAIN_TESTS"] == "1"))
struct KeychainTokenStoreTests {
    private func makeStore() -> KeychainTokenStore {
        // Unique service per run avoids collisions with any real stored item.
        KeychainTokenStore(service: "com.velomail.tokens.test", account: "unit-test")
    }

    @Test func saveLoadClearRoundTrips() throws {
        let store = makeStore()
        try? store.clear()

        let initial = try store.load()
        #expect(initial == nil)

        let token = TokenSet(accessToken: "a", refreshToken: "r",
                             expiresAt: Date(timeIntervalSince1970: 5000))
        try store.save(token)
        let loaded = try store.load()
        #expect(loaded == token)

        // Overwrite path (SecItemUpdate).
        let token2 = TokenSet(accessToken: "a2", refreshToken: "r2",
                              expiresAt: Date(timeIntervalSince1970: 6000))
        try store.save(token2)
        let loaded2 = try store.load()
        #expect(loaded2 == token2)

        try store.clear()
        let afterClear = try store.load()
        #expect(afterClear == nil)
    }
}
```

- [ ] **Step 2: Run the default suite to verify the test is SKIPPED**

Run: `swift test --filter KeychainTokenStoreTests`
Expected: The suite is skipped/known-disabled (0 tests run) because `VELO_KEYCHAIN_TESTS` is unset — confirms it does not gate the default suite.

- [ ] **Step 3: Implement `KeychainTokenStore`**

`Sources/VeloCore/Auth/KeychainTokenStore.swift`:
```swift
import Foundation
import Security

public final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.velomail.tokens", account: String = "default") {
        self.service = service
        self.account = account
    }

    public func load() throws -> TokenSet? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AuthError.keychain(status: status)
        }
        return try JSONDecoder().decode(TokenSet.self, from: data)
    }

    public func save(_ tokenSet: TokenSet) throws {
        let data = try JSONEncoder().encode(tokenSet)
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AuthError.keychain(status: addStatus) }
        } else {
            guard updateStatus == errSecSuccess else { throw AuthError.keychain(status: updateStatus) }
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychain(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
```

- [ ] **Step 4: Verify the package builds and the default suite stays green**

Run: `swift build`
Expected: builds with no errors.

Run: `swift test`
Expected: the full default suite PASSES (all prior tests plus the new Auth tests; the Keychain suite is skipped).

- [ ] **Step 5: (Optional) Run the opt-in Keychain test manually**

Run: `VELO_KEYCHAIN_TESTS=1 swift test --filter KeychainTokenStoreTests`
Expected: `saveLoadClearRoundTrips` PASSES. (May prompt for keychain access on first run; this is expected and is why the test is opt-in.)

- [ ] **Step 6: Commit**

```bash
git add Sources/VeloCore/Auth/KeychainTokenStore.swift Tests/VeloCoreTests/KeychainTokenStoreTests.swift
git commit -m "feat: add KeychainTokenStore with opt-in integration test"
```

---

## What this plan delivers

A complete headless OAuth token core in `VeloCore`: PKCE, authorization-URL building, token exchange/refresh (success + all error paths, tested with a mock HTTP client), an in-memory token store, and a real Keychain-backed store. The default `swift test` run is fully deterministic and offline; the Keychain store is verifiable on demand.

## Next plans (not in this one)

- **Interactive sign-in** (`ASWebAuthenticationSession`) — built with the GUI app; consumes `AuthURLBuilder` + `TokenService`. Requires real Google Cloud OAuth credentials.
- **GmailSync** — uses `TokenStore` + `TokenService.refresh` to authorize API calls.

## Self-Review

- **Spec coverage:** Every spec §4 component maps to a task — AuthConfig+AuthError (T1), PKCE (T2), AuthURLBuilder (T3), TokenSet (T4), HTTPClient+URLSessionHTTPClient (T5), TokenService (T6), TokenStore+InMemoryTokenStore (T7), KeychainTokenStore (T8). Spec §6 error handling is covered by T6 (server/network/decoding/missingRefreshToken) and T8 (keychain). Spec §7 testing strategy — deterministic suite (T1–T7) + opt-in Keychain (T8) — is implemented. The `.keychain(status:)` case is an addition beyond the spec's enumerated AuthError list, required by the KeychainTokenStore component the spec defines.
- **Placeholder scan:** No TBD/TODO; every code step shows complete code; no `#expect(try ...)` patterns (throwing calls extracted to locals, or use `#expect(throws:)`/async).
- **Type consistency:** `AuthConfig`, `PKCE`, `TokenSet`, `HTTPClient`, `AuthError` signatures are defined once (T1–T5) and consumed with matching names/types in `AuthURLBuilder` (T3), `TokenService` (T6), and the stores (T7–T8). `now: () -> Date` injection in `TokenService` matches the fixed-date test. `TokenStore`'s three methods are identical across protocol, in-memory, and Keychain implementations.
