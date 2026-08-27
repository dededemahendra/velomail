import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@MainActor
@Suite struct DropAttachTests {
    private func makeModel() throws -> ComposeViewModel {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        return ComposeViewModel(
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(db), identity: "me@x.com"),
            identity: "me@x.com")
    }

    /// The unique part goes in the directory, so the file keeps the name a
    /// person would recognise in an error.
    private func file(_ name: String, bytes: Int = 8) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("velo-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    @Test func droppingFilesAttachesThemAll() throws {
        let model = try makeModel()
        model.startNew()

        let failed = model.attach([try file("plan.pdf"), try file("map.png")])

        #expect(model.attachments.map(\.filename).sorted().count == 2)
        #expect(failed.isEmpty)
    }

    @Test func oneBadFileDoesNotLoseTheGoodOnes() throws {
        // Dropping five files and getting none because one was unreadable is
        // worse than getting four and being told which failed.
        let model = try makeModel()
        model.startNew()
        let missing = URL(fileURLWithPath: "/nowhere/at/all.pdf")

        let failed = model.attach([try file("good.pdf"), missing])

        #expect(model.attachments.count == 1)
        #expect(failed == ["all.pdf"])
    }

    @Test func aFileOverTheLimitIsReportedNotSilentlyDropped() throws {
        let model = try makeModel()
        model.startNew()

        let failed = model.attach([try file("huge.bin", bytes: Draft.maximumAttachmentBytes + 1)])

        #expect(model.attachments.isEmpty)
        #expect(failed == ["huge.bin"])
    }

    @Test func droppingNothingChangesNothing() throws {
        let model = try makeModel()
        model.startNew()
        #expect(model.attach([]).isEmpty)
        #expect(model.attachments.isEmpty)
    }

    @Test func aDroppedFileJoinsTheOnesAlreadyThere() throws {
        let model = try makeModel()
        model.startNew()
        _ = model.attach([try file("first.pdf")])

        _ = model.attach([try file("second.pdf")])

        #expect(model.attachments.count == 2)
    }
}
