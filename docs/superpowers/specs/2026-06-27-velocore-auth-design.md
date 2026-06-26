# VeloCore: Auth (headless token core) — Design

**Date:** 2026-06-27
**Status:** Approved (scope + design)
**Depends on:** VeloCore storage foundation (already on `master`)

## 1. Purpose

Provide the OAuth 2.0 token machinery Velo Mail needs to authenticate against
Gmail — built and tested **headlessly**, without the interactive browser flow
(which requires the GUI app that does not exist yet). This delivers everything
around the interactive sign-in: building the authorization request, exchanging
an authorization code for tokens, refreshing access tokens, and persisting them.

Success criterion: a `swift test` suite (no network, no GUI, no real Google
credentials) fully covers PKCE generation, auth-URL construction, token
exchange/refresh (success + error paths), and the in-memory token store; plus a
real `KeychainTokenStore` implementation that exists and is manually verifiable.

## 2. Scope

### In scope
- PKCE generation (code verifier, S256 challenge, random `state`).
- Authorization-URL construction (Google OAuth endpoint) from config + PKCE.
- `TokenSet` model (access token, refresh token, expiry; `isExpired`).
- `TokenService`: `exchange(code:)` and `refresh(refreshToken:)` network calls
  via an injectable `HTTPClient` protocol.
- `TokenStore` protocol; `InMemoryTokenStore` (tested); `KeychainTokenStore`
  (real Security-framework implementation).
- Typed `AuthError`.

### Out of scope (deferred to the GUI / integration phase)
- Interactive sign-in via `ASWebAuthenticationSession` (needs a GUI app host).
- Real Google Cloud OAuth client credentials + consent screen.
- End-to-end live sign-in against Google.
- Wiring tokens into `GmailSync` (separate milestone).

## 3. Tech Stack

Same as VeloCore foundation: Swift 6.1 (5.9 tools), SPM, Swift Testing,
Command Line Tools only. New auth code lives in the existing `VeloCore` target
under `Sources/VeloCore/Auth/`. No new third-party dependencies (Foundation +
Security framework only). `Security` is a system framework, no SPM dependency
needed.

## 4. Components

All under `Sources/VeloCore/Auth/`. Each is small and independently testable.

| Unit | Responsibility | Depends on |
|---|---|---|
| `AuthConfig` | Value type: `clientID`, `redirectURI`, `scopes`, `authEndpoint`, `tokenEndpoint`. A static `gmail(clientID:redirectURI:)` factory fills Google endpoints + Gmail scopes. | — |
| `PKCE` | Generates `codeVerifier` (43–128 char URL-safe), `codeChallenge` (base64url SHA-256 of verifier), and a random `state`. | Foundation, CryptoKit |
| `AuthURLBuilder` | Pure function: `url(config:pkce:) -> URL` building the authorization URL with `response_type=code`, `code_challenge`, `code_challenge_method=S256`, `state`, `scope`, `access_type=offline`, `prompt=consent`. | `AuthConfig`, `PKCE` |
| `TokenSet` | `accessToken: String`, `refreshToken: String?`, `expiresAt: Date`. `isExpired(now:)` with a small skew margin. Codable. | Foundation |
| `HTTPClient` | Protocol: `func post(url:headers:body:) async throws -> (Data, HTTPURLResponse)`. `URLSessionHTTPClient` real impl. | Foundation |
| `TokenService` | `exchange(code:verifier:) async throws -> TokenSet` and `refresh(refreshToken:) async throws -> TokenSet`. Builds form-encoded bodies, parses Google's JSON token response, maps errors. | `HTTPClient`, `AuthConfig` |
| `TokenStore` | Protocol: `load() throws -> TokenSet?`, `save(_:) throws`, `clear() throws`. | — |
| `InMemoryTokenStore` | Dictionary-backed `TokenStore` for tests. | `TokenStore` |
| `KeychainTokenStore` | `TokenStore` backed by the Security framework (generic password item, one account key). JSON-encodes `TokenSet`. | Security |
| `AuthError` | Typed errors: `.invalidResponse`, `.server(code:description:)`, `.network(Error)`, `.decoding(Error)`, `.missingRefreshToken`. | — |

## 5. Data Flow

**Sign-in (future GUI wires the middle step):**
1. `PKCE.generate()` → verifier/challenge/state.
2. `AuthURLBuilder.url(config:pkce:)` → authorization URL.
3. *(GUI, deferred)* present URL via `ASWebAuthenticationSession`; receive
   redirect with `code` + `state`; verify `state` matches.
4. `TokenService.exchange(code:verifier:)` → `TokenSet`.
5. `TokenStore.save(tokenSet)`.

**Using / refreshing (future GmailSync):**
1. `TokenStore.load()` → `TokenSet`.
2. If `isExpired`, `TokenService.refresh(refreshToken:)` → new `TokenSet`;
   `save`. (Google may omit `refresh_token` on refresh — reuse the prior one.)
3. Use `accessToken` for API calls.

## 6. Error Handling

- Non-2xx token responses: parse Google's `{ "error", "error_description" }`
  into `.server(code:description:)`.
- Network failures wrapped as `.network`. JSON decode failures as `.decoding`.
- `refresh` with no usable refresh token → `.missingRefreshToken` (distinct so
  the future UI knows to force re-sign-in rather than retry).
- On a refresh response that omits `refresh_token`, retain the existing one
  rather than nil-ing it.

## 7. Testing

Deterministic `swift test` suite (no network, no GUI, no real credentials):
- `PKCE`: verifier length/charset; challenge is valid base64url SHA-256 of
  verifier; `state` is non-empty and varies between calls.
- `AuthURLBuilder`: URL has correct host/path and all required query items with
  expected values (challenge method S256, offline access, scopes joined).
- `TokenSet.isExpired`: true past expiry, false before, honors skew.
- `TokenService.exchange`/`refresh` via a **mock `HTTPClient`**: success parses
  tokens + computes `expiresAt` from `expires_in`; server-error JSON → `.server`;
  malformed JSON → `.decoding`; refresh response missing `refresh_token` reuses
  the input refresh token.
- `InMemoryTokenStore`: save/load/clear round-trip.

**`KeychainTokenStore`**: real implementation, but its test is an **opt-in
integration test** excluded from the default suite (real Keychain access can
prompt or flake under Command Line Tools). It is verified manually / on demand,
not gated in CI. The default `swift test` run stays deterministic.

## 8. Milestones (build order)

1. `AuthConfig` + `AuthError`.
2. `PKCE`.
3. `AuthURLBuilder`.
4. `TokenSet` (+ `isExpired`).
5. `HTTPClient` protocol + `URLSessionHTTPClient`.
6. `TokenService` (exchange + refresh) against mock `HTTPClient`.
7. `TokenStore` protocol + `InMemoryTokenStore`.
8. `KeychainTokenStore` (+ opt-in integration test).

## 9. Open Questions (non-blocking)

- Exact Google scopes for v1 (likely `gmail.modify` + `userinfo.email`) — final
  value chosen when the real OAuth client is created in the GUI phase. The
  headless core treats scopes as config, so this does not block the build.
- Keychain access group / app identifier — finalized when the app target exists.
