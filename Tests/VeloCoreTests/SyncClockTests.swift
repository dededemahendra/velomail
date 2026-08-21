import Testing
import Foundation
@testable import VeloCore

@Suite struct SyncClockTests {
    @Test func systemClockSleepsForTheRequestedDuration() async throws {
        let clock = SystemSyncClock()
        let before = clock.now()
        try await clock.sleep(for: 0.05)
        #expect(clock.now().timeIntervalSince(before) >= 0.04)
    }

    @Test func systemClockSleepIsCancellable() async throws {
        let task = Task {
            try await SystemSyncClock().sleep(for: 60)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
