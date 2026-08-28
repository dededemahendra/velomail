import Testing
import Foundation
@testable import VeloCore

/// A Gmail that refuses everything with the error the reader will actually
/// hit: a Desktop client in testing mode expires its refresh token after a
/// week, so this is a state the app reaches in ordinary use.
private final class RefusingGmail: GmailReading, GmailWriting, @unchecked Sendable {
    let error: AuthError
    init(_ error: AuthError) { self.error = error }

    func getProfile() async throws -> GmailProfile { throw error }
    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { throw error }
    func getMessage(id: String) async throws -> GmailMessageDTO { throw error }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse { throw error }
    func getAttachment(messageID: String, attachmentID: String) async throws -> String { throw error }
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws { throw error }
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { throw error }
}

@Suite struct ExpiredSyncStatusTests {
    private func sync(refusing error: AuthError) throws -> GmailSync {
        let db = try AppDatabase.makeInMemory()
        let store = MailStore(db)
        let syncState = SyncStateStore(db)
        let mutations = MutationStore(db)
        let source = RefusingGmail(error)
        return GmailSync(
            accountID: "acct",
            backfill: BackfillService(source: source, store: store, syncState: syncState),
            incremental: IncrementalSyncService(source: source, store: store, syncState: syncState),
            outbound: OutboundService(writer: source, store: store, mutations: mutations,
                                      identity: "me@x.com"),
            syncState: syncState)
    }

    @Test func arefusedSignInStopsBeingCalledAFailure() async throws {
        // It became .failed, which the UI answers with "Try again" -- a button
        // that can never succeed however many times it is pressed.
        let engine = try sync(refusing: .server(code: "401", description: nil))
        try? await engine.syncNow()
        #expect(await engine.status == .expired)
    }

    @Test func anInvalidGrantIsTheSameThing() async throws {
        let engine = try sync(refusing: .server(code: "invalid_grant", description: nil))
        try? await engine.syncNow()
        #expect(await engine.status == .expired)
    }

    @Test func aMissingRefreshTokenIsTheSameThing() async throws {
        let engine = try sync(refusing: .missingRefreshToken)
        try? await engine.syncNow()
        #expect(await engine.status == .expired)
    }

    @Test func adroppedConnectionIsStillJustOffline() async throws {
        // The distinction is the whole point: one of these resolves itself.
        let engine = try sync(refusing: .server(code: "503", description: nil))
        try? await engine.syncNow()
        if case .offline = await engine.status {} else {
            Issue.record("503 should be offline, got \(await engine.status)")
        }
    }

    @Test func somethingElseBrokenIsStillAFailure() async throws {
        let engine = try sync(refusing: .invalidResponse)
        try? await engine.syncNow()
        if case .failed = await engine.status {} else {
            Issue.record("expected .failed, got \(await engine.status)")
        }
    }
}
