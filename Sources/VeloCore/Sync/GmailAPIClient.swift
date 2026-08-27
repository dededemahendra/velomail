import Foundation

/// The Gmail read operations `BackfillService` needs. Abstracted so backfill can
/// be driven by a scripted source in tests; `GmailAPIClient` is the live impl.
public protocol GmailReading: Sendable {
    func getProfile() async throws -> GmailProfile
    /// One page of message ids carrying `labelID`. Pass the returned
    /// `nextPageToken` back in to page; nil means no more pages.
    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?)
    func getMessage(id: String) async throws -> GmailMessageDTO
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse

    /// Base64url content of one attachment.
    func getAttachment(messageID: String, attachmentID: String) async throws -> String

    /// Every label on the account, so an id like `Label_7` can be shown as
    /// whatever its owner called it.
    func listLabels() async throws -> [GmailLabelDTO]
}

public extension GmailReading {
    /// The inbox page, for callers that only ever wanted that one label.
    func listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        try await listMessageIDs(labelID: "INBOX", pageToken: pageToken)
    }

    /// Default for sources with nothing to say about labels.
    func listLabels() async throws -> [GmailLabelDTO] { [] }

    /// Default for sources that do not serve attachments. It throws rather than
    /// returning empty, so a source that should have implemented this fails
    /// loudly instead of producing a zero-byte file.
    func getAttachment(messageID: String, attachmentID: String) async throws -> String {
        throw AttachmentError.unavailable
    }
}

/// The Gmail write operations `OutboundService` needs. Abstracted so the outbound
/// drain can be driven by a scripted writer in tests; `GmailAPIClient` is the live impl.
/// `Sendable` for the same reason `GmailReading` is: writers are held by
/// `Sendable` services and crossed between tasks.
public protocol GmailWriting: Sendable {
    /// Atomically adds/removes labels on many messages in one request, so a
    /// multi-message change can't be left half-applied.
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws

    /// Sends an already-serialized RFC 5322 message (base64url) and returns the
    /// created resource. `threadID` attaches the send to an existing thread.
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO
}

/// Thin read client over the Gmail REST API: lists INBOX message ids and hydrates
/// individual messages. Every request carries a bearer token obtained from
/// `AccessTokenProvider` (refreshed on demand).
public struct GmailAPIClient: GmailReading, GmailWriting, @unchecked Sendable {
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

    /// Lists the message ids carrying one label, a page at a time.
    public func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("users/me/messages"),
            resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "labelIds", value: labelID)]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = items

        let (data, response) = try await authorizedGET(components.url!)
        let decoded: ListResponse = try checkedDecode(data, response)
        return (decoded.messages?.map(\.id) ?? [], decoded.nextPageToken)
    }

    /// Every label on the account.
    public func listLabels() async throws -> [GmailLabelDTO] {
        let url = baseURL.appendingPathComponent("users/me/labels")
        let (data, response) = try await authorizedGET(url)
        let decoded: LabelListResponse = try checkedDecode(data, response)
        return decoded.labels ?? []
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
            URLQueryItem(name: "historyTypes", value: "labelAdded"),
            URLQueryItem(name: "historyTypes", value: "labelRemoved"),
        ]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = items

        let (data, response) = try await authorizedGET(components.url!)
        return try checkedDecode(data, response)
    }

    /// Fetches one attachment's content, base64url encoded.
    public func getAttachment(messageID: String, attachmentID: String) async throws -> String {
        let url = baseURL.appendingPathComponent(
            "users/me/messages/\(messageID)/attachments/\(attachmentID)")
        let (data, response) = try await authorizedGET(url)
        let decoded: AttachmentResponse = try checkedDecode(data, response)
        return decoded.data ?? ""
    }

    private struct AttachmentResponse: Decodable {
        let data: String?
        let size: Int?
    }

    /// Adds/removes labels on a message via `users.messages.modify`. Returns the
    /// updated message resource. Idempotent (removing a label twice is a no-op).
    public func modifyMessage(id: String, addLabelIDs: [String], removeLabelIDs: [String]) async throws -> GmailMessageDTO {
        let url = baseURL.appendingPathComponent("users/me/messages/\(id)/modify")
        let body = try JSONEncoder().encode(ModifyRequest(addLabelIds: addLabelIDs, removeLabelIds: removeLabelIDs))
        let (data, response) = try await authorizedPOST(url, body: body)
        return try checkedDecode(data, response)
    }

    /// Atomically adds/removes labels on many messages via
    /// `users.messages.batchModify` (returns 204 No Content on success).
    public func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        let url = baseURL.appendingPathComponent("users/me/messages/batchModify")
        let body = try JSONEncoder().encode(BatchModifyRequest(ids: ids, addLabelIds: addLabelIDs, removeLabelIds: removeLabelIDs))
        let (data, response) = try await authorizedPOST(url, body: body)
        try mapErrorIfNeeded(data, response)   // no body to decode on success
    }

    /// Sends a message via `users.messages.send`, returning the created resource
    /// (whose `id`/`threadId` are Gmail's, assigned only now).
    public func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        let url = baseURL.appendingPathComponent("users/me/messages/send")
        let body = try JSONEncoder().encode(SendRequest(raw: raw, threadId: threadID))
        let (data, response) = try await authorizedPOST(url, body: body)
        return try checkedDecode(data, response)
    }

    // MARK: - Internals

    /// `threadId` is omitted entirely when nil rather than encoded as null,
    /// which Gmail rejects. `JSONEncoder` skips nil optionals by default.
    private struct SendRequest: Encodable {
        let raw: String
        let threadId: String?
    }

    private struct ModifyRequest: Encodable {
        let addLabelIds: [String]
        let removeLabelIds: [String]
    }

    private struct BatchModifyRequest: Encodable {
        let ids: [String]
        let addLabelIds: [String]
        let removeLabelIds: [String]
    }

    private struct LabelListResponse: Decodable {
        let labels: [GmailLabelDTO]?
    }

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

    private func authorizedPOST(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
        let token = try await tokenProvider.validAccessToken()
        do {
            return try await httpClient.post(
                url: url,
                headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"],
                body: body)
        } catch {
            throw AuthError.network(error)
        }
    }

    /// Throws a typed error for a non-2xx response; returns normally on success.
    private func mapErrorIfNeeded(_ data: Data, _ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            if let err = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw AuthError.server(
                    code: err.error.status ?? String(err.error.code ?? 0),
                    description: err.error.message)
            }
            throw AuthError.invalidResponse
        }
    }

    private func checkedDecode<T: Decodable>(_ data: Data, _ response: HTTPURLResponse) throws -> T {
        try mapErrorIfNeeded(data, response)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AuthError.decoding(error)
        }
    }
}
