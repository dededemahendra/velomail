import Testing
import Foundation
import VeloCore
@testable import VeloUI

private final class FakeSource: GmailReading, @unchecked Sendable {
    var shouldFail = false
    func getProfile() async throws -> GmailProfile { fatalError() }
    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        fatalError()
    }
    func getMessage(id: String) async throws -> GmailMessageDTO { fatalError() }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse {
        fatalError()
    }
    func getAttachment(messageID: String, attachmentID: String) async throws -> String {
        if shouldFail { throw AuthError.invalidResponse }
        return "aGVsbG8"
    }
}

@MainActor
@Suite struct AttachmentViewModelTests {
    private func tempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func attachment() -> MailAttachment {
        MailAttachment(id: "a1", messageID: "m1", filename: "invoice.pdf",
                       mimeType: "application/pdf", size: 84_213,
                       attachmentID: "att-1", inlineData: nil)
    }

    @Test func startsIdle() throws {
        let model = AttachmentViewModel(service: AttachmentService(source: FakeSource()),
                                        downloads: try tempDirectory())
        #expect(model.state == .idle)
    }

    @Test func savingReportsWhereItLanded() async throws {
        let directory = try tempDirectory()
        let model = AttachmentViewModel(service: AttachmentService(source: FakeSource()),
                                        downloads: directory)

        await model.save(attachment())

        guard case let .saved(url) = model.state else {
            Issue.record("expected .saved, got \(model.state)")
            return
        }
        #expect(url.lastPathComponent == "invoice.pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aFailureBecomesAReadableMessage() async throws {
        let source = FakeSource()
        source.shouldFail = true
        let model = AttachmentViewModel(service: AttachmentService(source: source),
                                        downloads: try tempDirectory())

        await model.save(attachment())

        guard case let .failed(message) = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test func dismissReturnsToIdle() async throws {
        let model = AttachmentViewModel(service: AttachmentService(source: FakeSource()),
                                        downloads: try tempDirectory())
        await model.save(attachment())

        model.dismiss()

        #expect(model.state == .idle)
    }

    // MARK: - Display

    @Test func sizesAreHumanReadable() {
        #expect(AttachmentViewModel.formattedSize(0) == "")
        #expect(AttachmentViewModel.formattedSize(512).contains("512"))
        #expect(AttachmentViewModel.formattedSize(84_213).uppercased().contains("KB"))
        #expect(AttachmentViewModel.formattedSize(5_000_000).uppercased().contains("MB"))
    }

    @Test func anUnknownSizeShowsNothingRatherThanZeroBytes() {
        // "0 bytes" next to a real file reads as a bug.
        #expect(AttachmentViewModel.formattedSize(0).isEmpty)
    }

    @Test func iconsDistinguishCommonKinds() {
        #expect(AttachmentViewModel.symbol(for: "application/pdf") != AttachmentViewModel.symbol(for: "image/png"))
        #expect(!AttachmentViewModel.symbol(for: "application/octet-stream").isEmpty)
    }
}
