import Foundation

/// The Gmail read operations `BackfillService` needs. Abstracted so backfill can
/// be driven by a scripted source in tests; `GmailAPIClient` is the live impl.
public protocol GmailReading {
    func getProfile() async throws -> GmailProfile
    func listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?)
    func getMessage(id: String) async throws -> GmailMessageDTO
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse
}

/// Thin read client over the Gmail REST API: lists INBOX message ids and hydrates
/// individual messages. Every request carries a bearer token obtained from
/// `AccessTokenProvider` (refreshed on demand).
public struct GmailAPIClient: GmailReading {
    private let httpClient: HTTPClient
    private let tokenProvider: AccessTokenProvider
    private let baseURL: URL

    public init(httpClient: HTTPClient,
                tokenProvider: AccessTokenProvider,
                baseURL: URL = URL(string: "https://gmail.googleapis.com/gmail/v1/")!) {
        self.httpClient = httpClient
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
    }

    /// Fetches the mailbox profile, whose `historyId` is the canonical baseline
    /// for incremental sync.
    public func getProfile() async throws -> GmailProfile {
        let url = baseURL.appendingPathComponent("users/me/profile")
        let (data, response) = try await authorizedGET(url)
        return try checkedDecode(data, response)
    }

    /// Lists INBOX message ids for one page. Pass the returned `nextPageToken`
    /// back in to page; `nil` means no more pages.
    public func listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("users/me/messages"),
            resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "labelIds", value: "INBOX")]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = items

        let (data, response) = try await authorizedGET(components.url!)
        let decoded: ListResponse = try checkedDecode(data, response)
        return (decoded.messages?.map(\.id) ?? [], decoded.nextPageToken)
    }

    /// Fetches a single message in `format=full`.
    public func getMessage(id: String) async throws -> GmailMessageDTO {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("users/me/messages/\(id)"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]

        let (data, response) = try await authorizedGET(components.url!)
        return try checkedDecode(data, response)
    }

    /// Fetches one page of history since `startHistoryId`, restricted to added
    /// messages. Pass the response `nextPageToken` back in to page.
    public func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("users/me/history"),
            resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "startHistoryId", value: startHistoryId),
            URLQueryItem(name: "historyTypes", value: "messageAdded"),
        ]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = items

        let (data, response) = try await authorizedGET(components.url!)
        return try checkedDecode(data, response)
    }

    // MARK: - Internals

    private struct ListResponse: Decodable {
        struct Ref: Decodable { let id: String }
        let messages: [Ref]?
        let nextPageToken: String?
    }

    private struct APIErrorResponse: Decodable {
        struct Inner: Decodable {
            let code: Int?
            let message: String?
            let status: String?
        }
        let error: Inner
    }

    private func authorizedGET(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let token = try await tokenProvider.validAccessToken()
        do {
            return try await httpClient.get(url: url, headers: ["Authorization": "Bearer \(token)"])
        } catch {
            throw AuthError.network(error)
        }
    }

    private func checkedDecode<T: Decodable>(_ data: Data, _ response: HTTPURLResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            if let err = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw AuthError.server(
                    code: err.error.status ?? String(err.error.code ?? 0),
                    description: err.error.message)
            }
            throw AuthError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AuthError.decoding(error)
        }
    }
}
