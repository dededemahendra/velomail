import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct NoopWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct ComposeAttachmentTests {
    private func makeContext() throws -> (ComposeViewModel, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        let outbound = OutboundService(writer: NoopWriter(), store: store,
                                       mutations: mutations, identity: "me@example.com")
        return (ComposeViewModel(outbound: outbound, identity: "me@example.com"), mutations)
    }

    private func file(named name: String, bytes: Int = 8) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo-compose-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    @Test func aNewComposeHasNoAttachments() throws {
        let (model, _) = try makeContext()
        model.startNew()
        #expect(model.attachments.isEmpty)
    }

    @Test func attachingReadsTheFileFromDisk() throws {
        let (model, _) = try makeContext()
        model.startNew()

        try model.attach(try file(named: "invoice.pdf", bytes: 12))

        #expect(model.attachments.count == 1)
        #expect(model.attachments.first?.filename == "invoice.pdf")
        #expect(model.attachments.first?.mimeType == "application/pdf")
        #expect(model.attachments.first?.data.count == 12)
    }

    @Test func removingAnAttachmentDropsIt() throws {
        let (model, _) = try makeContext()
        model.startNew()
        try model.attach(try file(named: "a.pdf"))
        try model.attach(try file(named: "b.pdf"))

        model.removeAttachment(at: 0)

        #expect(model.attachments.map(\.filename) == ["b.pdf"])
    }

    @Test func removingAnOutOfRangeIndexIsHarmless() throws {
        let (model, _) = try makeContext()
        model.startNew()
        model.removeAttachment(at: 3)
        #expect(model.attachments.isEmpty)
    }

    @Test func startingANewComposeClearsAttachments() throws {
        let (model, _) = try makeContext()
        try model.attach(try file(named: "a.pdf"))

        model.startNew()

        #expect(model.attachments.isEmpty)
    }

    @Test func aMissingFileReportsRatherThanCrashing() throws {
        let (model, _) = try makeContext()
        model.startNew()
        let gone = URL(fileURLWithPath: "/nope/does-not-exist.pdf")

        #expect(throws: (any Error).self) { try model.attach(gone) }
        #expect(model.attachments.isEmpty)
    }

    @Test func attachingBeyondTheLimitIsRefused() throws {
        let (model, _) = try makeContext()
        model.startNew()
        let huge = try file(named: "huge.bin", bytes: Draft.maximumAttachmentBytes + 1)

        #expect(throws: ComposeError.attachmentsTooLarge) { try model.attach(huge) }
        // Refused, so the composer is left exactly as it was.
        #expect(model.attachments.isEmpty)
    }

    @Test func theLimitCountsWhatIsAlreadyAttached() throws {
        let (model, _) = try makeContext()
        model.startNew()
        let half = Draft.maximumAttachmentBytes / 2 + 1
        try model.attach(try file(named: "one.bin", bytes: half))

        // Each is fine alone; together they are not.
        #expect(throws: ComposeError.attachmentsTooLarge) {
            try model.attach(try file(named: "two.bin", bytes: half))
        }
        #expect(model.attachments.count == 1)
    }

    @Test func sendingCarriesTheAttachmentsIntoTheQueue() throws {
        let (model, mutations) = try makeContext()
        model.startNew()
        model.to = "a@b.com"
        model.subject = "s"
        model.body = "b"
        try model.attach(try file(named: "invoice.pdf", bytes: 5))

        try model.send()

        let queued = try JSONDecoder().decode(
            QueuedDraft.self, from: try #require(try mutations.all().first).payload)
        #expect(queued.draft.attachments.count == 1)
        #expect(queued.draft.attachments.first?.filename == "invoice.pdf")
    }

    @Test func sendingClearsTheAttachmentsWithEverythingElse() throws {
        let (model, _) = try makeContext()
        model.startNew()
        model.to = "a@b.com"
        try model.attach(try file(named: "invoice.pdf"))

        try model.send()

        #expect(model.attachments.isEmpty)
    }
}

/// Mirrors the queue payload so OutboundSendPayload stays internal to VeloCore.
private struct QueuedDraft: Decodable {
    struct Inner: Decodable {
        struct File: Decodable { let filename: String }
        let attachments: [File]
    }
    let draft: Inner
}
