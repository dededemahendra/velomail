import Foundation

/// `Sendable` because clients are held by `Sendable` types (the API client, the
/// LLM providers) and crossed between tasks; without it that is a warning today
/// and an error under Swift 6.
public protocol HTTPClient: Sendable {
    func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse)
    func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse)

    /// Replaces something that already exists. Gmail's `drafts.update` is the
    /// only caller today.
    func put(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse)
}

public extension HTTPClient {
    /// Default for clients that never replace anything. It throws rather than
    /// quietly posting instead: a client that should have implemented this
    /// should fail loudly, not create a second draft every time one is edited.
    func put(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        throw AuthError.invalidResponse
    }
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

    public func put(url: URL, headers: [String: String], body: Data) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
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

    public func get(url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
