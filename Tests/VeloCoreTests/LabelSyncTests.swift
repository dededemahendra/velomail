import Testing
import Foundation
@testable import VeloCore

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

@Suite struct LabelSyncTests {
    private func makeContext() throws -> (OutboundService, MailStore, MutationStore) {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let mutations = MutationStore(db)
        return (OutboundService(writer: Quiet(), store: store, mutations: mutations,
                                identity: "me@x.com", now: { Date(timeIntervalSince1970: 1) }),
                store, mutations)
    }

    private func seed(_ store: MailStore, labels: [String]) throws {
        try store.upsert(MailThread(id: "t", sender: "a@b.com", snippet: "s",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: labels))
        try store.upsert(Message(id: "m", threadID: "t", sender: "a@b.com", recipients: [],
                                 subject: "s", date: Date(timeIntervalSince1970: 1),
                                 bodyHTML: nil, bodyText: "b", isUnread: false, labelIDs: labels))
    }

    // MARK: - Applying one

    @Test func labellingAThreadShowsImmediately() throws {
        let (service, store, _) = try makeContext()
        try seed(store, labels: ["INBOX"])

        try service.addLabel("Label_7", toThread: "t")

        #expect(try store.threads(withLabel: "Label_7").map(\.id) == ["t"])
    }

    @Test func labellingIsPushedLikeEveryOtherChange() throws {
        let (service, store, mutations) = try makeContext()
        try seed(store, labels: ["INBOX"])

        try service.addLabel("Label_7", toThread: "t")

        #expect(try mutations.all().map(\.kind) == [.label])
    }

    @Test func removingALabelTakesItOff() throws {
        let (service, store, _) = try makeContext()
        try seed(store, labels: ["INBOX", "Label_7"])

        try service.removeLabel("Label_7", fromThread: "t")

        #expect(try store.threads(withLabel: "Label_7").isEmpty)
        #expect(try store.inboxThreads().map(\.id) == ["t"])   // still in the inbox
    }

    @Test func labellingSomethingUnknownIsHarmless() throws {
        let (service, _, mutations) = try makeContext()
        try service.addLabel("Label_7", toThread: "nope")
        #expect(try mutations.all().isEmpty)
    }

    @Test func aLabelAlreadyThereIsNotAddedTwice() throws {
        let (service, store, _) = try makeContext()
        try seed(store, labels: ["INBOX", "Label_7"])

        try service.addLabel("Label_7", toThread: "t")

        let thread = try #require(try store.thread(id: "t"))
        #expect(thread.labelIDs.filter { $0 == "Label_7" }.count == 1)
    }

    // MARK: - Learning their names

    @Test func namesComeFromGmailAndAreStored() async throws {
        let source = LabelSource(labels: [
            ("Label_7", "Clients/Mornington", "user"),
            ("CATEGORY_UPDATES", "CATEGORY_UPDATES", "system"),
        ])
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let service = LabelService(source: source, store: store)

        try await service.refresh()

        #expect(try store.labels().count == 2)
        #expect(try store.browsableLabels().map(\.displayName) == ["Updates", "Clients/Mornington"])
    }

    @Test func aFailureLeavesTheLastGoodListAlone() async throws {
        // A label list that empties itself on a dropped connection would make
        // every label vanish from the sidebar mid-session.
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        try store.replaceLabels([MailLabel(id: "Label_7", name: "Work", kind: .user)])
        let service = LabelService(source: FailingLabelSource(), store: store)

        try? await service.refresh()

        #expect(try store.labels().map(\.name) == ["Work"])
    }
}

private struct LabelSource: GmailReading {
    let labels: [(String, String, String)]
    func getProfile() async throws -> GmailProfile { GmailProfile(emailAddress: "m@x.com", historyId: "1") }
    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func getMessage(id: String) async throws -> GmailMessageDTO { fatalError() }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse { fatalError() }
    func listLabels() async throws -> [GmailLabelDTO] {
        labels.map { GmailLabelDTO(id: $0.0, name: $0.1, type: $0.2) }
    }
}

private struct FailingLabelSource: GmailReading {
    func getProfile() async throws -> GmailProfile { fatalError() }
    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func getMessage(id: String) async throws -> GmailMessageDTO { fatalError() }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse { fatalError() }
    func listLabels() async throws -> [GmailLabelDTO] { throw AuthError.invalidResponse }
}
