import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct AttachmentAllowanceTests {
    private func makeModel() throws -> ComposeViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        return ComposeViewModel(
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com")
    }

    /// Writes a file of `bytes` and attaches it.
    private func attach(_ bytes: Int, to model: ComposeViewModel, named name: String) throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(repeating: 0, count: bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try model.attach(url)
    }

    @Test func nothingAttachedSaysNothing() throws {
        #expect(try makeModel().attachmentAllowance == nil)
    }

    @Test func aSmallFileJustShowsItsSize() throws {
        // Crying "of 22 MB" over one photograph would be noise.
        let model = try makeModel()
        try attach(200_000, to: model, named: "photo.jpg")
        let allowance = try #require(model.attachmentAllowance)
        #expect(!allowance.contains("of"))
        #expect(!model.isNearAttachmentLimit)
    }

    @Test func gettingCloseSaysHowMuchRoomIsLeft() throws {
        // The first you knew of the limit was a file being refused.
        let model = try makeModel()
        try attach(17_000_000, to: model, named: "video.mov")
        #expect(model.isNearAttachmentLimit)
        #expect(try #require(model.attachmentAllowance).contains("of"))
    }

    @Test func theThresholdIsThreeQuarters() throws {
        let model = try makeModel()
        try attach(Draft.maximumAttachmentBytes * 3 / 4, to: model, named: "big.bin")
        #expect(model.isNearAttachmentLimit)
    }

    @Test func justUnderTheThresholdIsQuiet() throws {
        let model = try makeModel()
        try attach(Draft.maximumAttachmentBytes * 3 / 4 - 1_000, to: model, named: "big.bin")
        #expect(!model.isNearAttachmentLimit)
    }

    @Test func aFileThatWillNotFitIsStillRefused() throws {
        let model = try makeModel()
        #expect(throws: ComposeError.self) {
            try attach(Draft.maximumAttachmentBytes + 1, to: model, named: "huge.bin")
        }
    }
}
