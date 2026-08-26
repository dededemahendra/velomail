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

    /// Waits for `condition`, failing the test if it never becomes true.
    ///
    /// The budget is deliberately generous. GRDB delivers these emissions on the
    /// main queue, and the full suite runs hundreds of tests in parallel -- a
    /// two-second budget passed in isolation and failed under that contention,
    /// which is the worst kind of test. Waiting longer costs nothing except on a
    /// genuine failure.
    private func pollUntil(_ what: String, _ condition: () -> Bool,
                           sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<500 {                      // ~10s
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("timed out waiting for \(what)", sourceLocation: sourceLocation)
    }

    @Test @MainActor func observationEmitsInitialThenUpdatesOnInsert() async throws {
        let store = MailStore(try AppDatabase.makeInMemory())
        let collector = Collector()

        let cancellable = store.observeInboxThreads { collector.append($0.map(\.id)) }
        defer { cancellable.cancel() }

        // `.immediate` scheduling delivers the initial value synchronously.
        await pollUntil("the initial emission") { !collector.values.isEmpty }
        #expect(collector.values.first == [])

        try store.upsert(MailThread(id: "t", snippet: "",
                                    lastMessageDate: Date(timeIntervalSince1970: 1),
                                    isUnread: false, hasAttachments: false, labelIDs: ["INBOX"]))

        // The post-write emission is delivered asynchronously on the main queue.
        await pollUntil("the post-write emission") { collector.values.count >= 2 }
        #expect(collector.values.last == ["t"])
    }
}
