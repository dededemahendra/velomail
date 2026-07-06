import Testing
import Foundation
@testable import VeloCore

/// Compile-time guard: these sync collaborators must stay `Sendable` so the
/// `GmailSync` actor can hold them across isolation. Fails to build if any loses it.
private func requireSendable<T: Sendable>(_ value: T) {}

@Suite struct SendableConformanceTests {
    @Test func syncCollaboratorsAreSendable() throws {
        let db = try AppDatabase.makeInMemory()
        let mailStore = MailStore(db)
        let syncStore = SyncStateStore(db)

        requireSendable(db)
        requireSendable(mailStore)
        requireSendable(syncStore)
    }
}
