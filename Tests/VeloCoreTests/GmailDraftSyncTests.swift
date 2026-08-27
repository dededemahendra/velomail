import Testing
import Foundation
@testable import VeloCore

@Suite struct GmailDraftSyncTests {
    private let account = "primary"

    private func makeContext(_ source: DraftSource) throws -> (GmailDraftService, DraftStore) {
        let db = try AppDatabase.makeInMemory()
        let drafts = DraftStore(db)
        return (GmailDraftService(source: source, drafts: drafts), drafts)
    }

    // MARK: - Pulling

    @Test func aDraftWrittenElsewhereTurnsUpHere() async throws {
        // The whole point: something started on a phone should be finishable
        // at a desk.
        let source = DraftSource(remote: [
            .init(id: "r1", to: "bob@x.com", subject: "From the train", body: "half a thought"),
        ])
        let (service, drafts) = try makeContext(source)

        try await service.pull()

        let stored = try #require(try drafts.all().first)
        #expect(stored.draft.subject == "From the train")
        #expect(stored.draft.to == ["bob@x.com"])
    }

    @Test func pullingTwiceDoesNotDuplicateIt() async throws {
        let source = DraftSource(remote: [.init(id: "r1", to: "b@x.com", subject: "One", body: "x")])
        let (service, drafts) = try makeContext(source)

        try await service.pull()
        try await service.pull()

        #expect(try drafts.all().count == 1)
    }

    @Test func aDraftDeletedInGmailGoesFromHereToo() async throws {
        let source = DraftSource(remote: [.init(id: "r1", to: "b@x.com", subject: "One", body: "x")])
        let (service, drafts) = try makeContext(source)
        try await service.pull()

        source.remote = []
        try await service.pull()

        #expect(try drafts.all().isEmpty)
    }

    @Test func aDraftWrittenHereIsNotDeletedByAPull() async throws {
        // Only the ones this service put there are its to remove. A local
        // draft that has never been pushed must survive.
        let source = DraftSource(remote: [])
        let (service, drafts) = try makeContext(source)
        try drafts.save(Draft(to: ["a@x.com"], subject: "Mine", bodyText: "local"), id: "local-1")

        try await service.pull()

        #expect(try drafts.all().map(\.draft.subject) == ["Mine"])
    }

    // MARK: - Pushing

    @Test func aLocalDraftIsCreatedInGmail() async throws {
        let source = DraftSource(remote: [])
        let (service, drafts) = try makeContext(source)
        try drafts.save(Draft(to: ["a@x.com"], subject: "Mine", bodyText: "local"), id: "local-1")

        try await service.push()

        #expect(source.created.count == 1)
        #expect(source.created.first?.contains("Subject: Mine") == true)
    }

    @Test func pushingTwiceUpdatesRatherThanPilesUp() async throws {
        // Otherwise every autosave would leave another copy in Gmail's drafts.
        let source = DraftSource(remote: [])
        let (service, drafts) = try makeContext(source)
        try drafts.save(Draft(to: ["a@x.com"], subject: "Mine", bodyText: "one"), id: "local-1")
        try await service.push()

        try drafts.save(Draft(to: ["a@x.com"], subject: "Mine", bodyText: "two"), id: "local-1")
        try await service.push()

        #expect(source.created.count == 1)
        #expect(source.updated.count == 1)
    }

    @Test func anEmptyDraftIsNotWorthSending() async throws {
        let source = DraftSource(remote: [])
        let (service, drafts) = try makeContext(source)
        try drafts.save(Draft(to: [], subject: "", bodyText: ""), id: "local-1")

        try await service.push()

        #expect(source.created.isEmpty)
    }
}

/// Records what was pushed and serves what is remote.
private final class DraftSource: GmailDrafting, @unchecked Sendable {
    struct Remote { let id: String; let to: String; let subject: String; let body: String }

    var remote: [Remote]
    private(set) var created: [String] = []
    private(set) var updated: [String] = []

    init(remote: [Remote]) { self.remote = remote }

    func listDrafts() async throws -> [GmailDraftDTO] {
        remote.map { entry in
            let raw = "To: \(entry.to)\r\nSubject: \(entry.subject)\r\n\r\n\(entry.body)"
            return GmailDraftDTO(id: entry.id, raw: Data(raw.utf8).base64EncodedString())
        }
    }

    func createDraft(raw: String) async throws -> String {
        created.append(decoded(raw))
        return "remote-\(created.count)"
    }

    func updateDraft(id: String, raw: String) async throws {
        updated.append(decoded(raw))
    }

    private func decoded(_ raw: String) -> String {
        var padded = raw.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded += "=" }
        return Data(base64Encoded: padded).flatMap { String(data: $0, encoding: .utf8) } ?? raw
    }
}
