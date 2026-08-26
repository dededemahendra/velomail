import Testing
import Foundation
@testable import VeloCore

private struct Boom: Error {}

/// Serves attachment bytes and records what was asked for.
private final class FakeSource: GmailReading, @unchecked Sendable {
    var data: String?
    var shouldFail = false
    private(set) var requests: [(message: String, attachment: String)] = []

    init(data: String? = "aGVsbG8") { self.data = data }

    func getProfile() async throws -> GmailProfile { fatalError() }
    func listInboxMessageIDs(pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        fatalError()
    }
    func getMessage(id: String) async throws -> GmailMessageDTO { fatalError() }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        fatalError()
    }
    func getAttachment(messageID: String, attachmentID: String) async throws -> String {
        requests.append((messageID, attachmentID))
        if shouldFail { throw AuthError.invalidResponse }
        return data ?? ""
    }
}

@Suite struct AttachmentServiceTests {
    /// Compares directories by path, so a trailing slash does not read as a
    /// different location.
    private func isInside(_ url: URL, _ directory: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let expected = directory.standardizedFileURL.path
        return parent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == expected.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func tempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo-att-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func attachment(name: String = "invoice.pdf", inline: String? = nil,
                            attachmentID: String? = "att-1") -> MailAttachment {
        MailAttachment(id: "a1", messageID: "m1", filename: name,
                       mimeType: "application/pdf", size: 5,
                       attachmentID: inline == nil ? attachmentID : nil, inlineData: inline)
    }

    // MARK: - Resolving content

    @Test func inlineContentNeedsNoFetch() async throws {
        let source = FakeSource()
        let service = AttachmentService(source: source)

        let data = try await service.data(for: attachment(inline: "aGVsbG8"))

        #expect(String(decoding: data, as: UTF8.self) == "hello")
        #expect(source.requests.isEmpty)
    }

    @Test func referencedContentIsFetched() async throws {
        let source = FakeSource(data: "aGVsbG8")
        let service = AttachmentService(source: source)

        let data = try await service.data(for: attachment())

        #expect(String(decoding: data, as: UTF8.self) == "hello")
        #expect(source.requests.first?.attachment == "att-1")
    }

    @Test func anAttachmentWithNeitherIdNorDataFails() async throws {
        let service = AttachmentService(source: FakeSource())
        await #expect(throws: AttachmentError.unavailable) {
            _ = try await service.data(for: attachment(attachmentID: nil))
        }
    }

    @Test func aFetchFailurePropagates() async throws {
        let source = FakeSource()
        source.shouldFail = true
        let service = AttachmentService(source: source)

        await #expect(throws: AuthError.self) { _ = try await service.data(for: attachment()) }
    }

    @Test func undecodableContentIsReportedRatherThanWritingGarbage() async throws {
        let service = AttachmentService(source: FakeSource(data: "!!!not base64!!!"))
        await #expect(throws: AttachmentError.undecodable) {
            _ = try await service.data(for: attachment())
        }
    }

    // MARK: - Saving, treated as hostile input

    @Test func savesUnderTheGivenName() async throws {
        let directory = try tempDirectory()
        let service = AttachmentService(source: FakeSource())

        let url = try await service.save(attachment(inline: "aGVsbG8"), to: directory)

        #expect(url.lastPathComponent == "invoice.pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aTraversingFilenameCannotEscapeTheDirectory() async throws {
        let directory = try tempDirectory()
        let service = AttachmentService(source: FakeSource())

        // A filename arrives from a stranger. This is a real attack, not a
        // theoretical one.
        let url = try await service.save(
            attachment(name: "../../../../tmp/pwned.txt", inline: "aGVsbG8"), to: directory)

        #expect(isInside(url, directory))
        #expect(!url.path.contains(".."))
    }

    @Test func anAbsolutePathIsReducedToItsLastComponent() async throws {
        let directory = try tempDirectory()
        let service = AttachmentService(source: FakeSource())

        let url = try await service.save(
            attachment(name: "/etc/passwd", inline: "aGVsbG8"), to: directory)

        #expect(isInside(url, directory))
        #expect(url.lastPathComponent == "passwd")
    }

    @Test func aNameThatIsNothingButTraversalGetsASafeDefault() async throws {
        let directory = try tempDirectory()
        let service = AttachmentService(source: FakeSource())

        let url = try await service.save(attachment(name: "../..", inline: "aGVsbG8"), to: directory)

        #expect(isInside(url, directory))
        #expect(!url.lastPathComponent.isEmpty)
    }

    @Test func anEmptyNameGetsASafeDefault() async throws {
        let directory = try tempDirectory()
        let service = AttachmentService(source: FakeSource())

        let url = try await service.save(attachment(name: "", inline: "aGVsbG8"), to: directory)

        #expect(!url.lastPathComponent.isEmpty)
    }

    @Test func aCollisionIsNumberedRatherThanOverwritingTheUsersFile() async throws {
        let directory = try tempDirectory()
        let service = AttachmentService(source: FakeSource())

        let first = try await service.save(attachment(inline: "aGVsbG8"), to: directory)
        let second = try await service.save(attachment(inline: "aGVsbG8"), to: directory)

        #expect(first.lastPathComponent == "invoice.pdf")
        #expect(second.lastPathComponent == "invoice 2.pdf")
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    @Test func repeatedCollisionsKeepCounting() async throws {
        let directory = try tempDirectory()
        let service = AttachmentService(source: FakeSource())

        _ = try await service.save(attachment(inline: "aGVsbG8"), to: directory)
        _ = try await service.save(attachment(inline: "aGVsbG8"), to: directory)
        let third = try await service.save(attachment(inline: "aGVsbG8"), to: directory)

        #expect(third.lastPathComponent == "invoice 3.pdf")
    }

    @Test func theWrittenBytesAreTheAttachmentsBytes() async throws {
        let directory = try tempDirectory()
        let service = AttachmentService(source: FakeSource())

        let url = try await service.save(attachment(inline: "aGVsbG8"), to: directory)

        #expect(try Data(contentsOf: url) == Data("hello".utf8))
    }
}
