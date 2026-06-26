import Testing
import Foundation
import GRDB
@testable import VeloCore

@Suite struct MailStoreObservationTests {
    /// Thread-safe collector for emissions delivered from GRDB's scheduler.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [[String]] = []
        func append(_ value: [String]) { lock.lock(); stored.append(value); lock.unlock() }
        var values: [[String]] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// Polls `condition` up to ~2s (100 × 20ms), failing the test if never true.
    private func pollUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("condition not met within timeout")
    }

    @Test @MainActor func observationEmitsInitialThenUpdatesOnInsert() async throws {
        let store = MailStore(try AppDatabase.makeInMemory())
        let collector = Collector()

        let cancellable = store.observeInboxThreads { collector.append($0.map(\.id)) }
        defer { cancellable.cancel() }

        // `.immediate` scheduling delivers the initial value synchronously.
        await pollUntil { !collector.values.isEmpty }
        #expect(collector.values.first == [])

        try store.upsert(MailThread(id: "t", snippet: "",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))

        // The post-write emission is delivered asynchronously on the main queue.
        await pollUntil { collector.values.count >= 2 }
        #expect(collector.values.last == ["t"])
    }
}
