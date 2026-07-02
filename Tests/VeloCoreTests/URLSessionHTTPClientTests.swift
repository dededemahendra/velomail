import Testing
import Foundation
@testable import VeloCore

// Intercepts requests so the real URLSessionHTTPClient can be tested offline.
final class StubURLProtocol: URLProtocol {
    // Shared mutable stub state — the test suite is @Suite(.serialized) so these are accessed by one test at a time. Keep that annotation if you add tests here.
    static var stubData = Data()
    static var stubStatus = 200
    static var lastBody: Data?
    static var lastMethod: String?
    static var lastHeaders: [String: String]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastMethod = request.httpMethod
        Self.lastHeaders = request.allHTTPHeaderFields
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

@Suite(.serialized) struct URLSessionHTTPClientTests {
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

    @Test func getReturnsBodyAndStatusAndAttachesHeaders() async throws {
        StubURLProtocol.stubData = Data("get-body".utf8)
        StubURLProtocol.stubStatus = 200
        let client = makeClient()
        let url = URL(string: "https://example.com/messages")!

        let (data, response) = try await client.get(
            url: url, headers: ["Authorization": "Bearer tok"])

        #expect(String(decoding: data, as: UTF8.self) == "get-body")
        #expect(response.statusCode == 200)
        #expect(StubURLProtocol.lastMethod == "GET")
        #expect(StubURLProtocol.lastHeaders?["Authorization"] == "Bearer tok")
    }
}
