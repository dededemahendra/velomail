import Foundation

/// The passage of time, as the scheduler needs it. A seam purely so the polling
/// loop is testable: a fake clock makes every test instant and deterministic,
/// records the durations the loop asked for (which is how backoff is asserted),
/// and ends the loop on demand. No test ever sleeps for real.
public protocol SyncClock: Sendable {
    func now() -> Date
    /// Suspends for `duration` seconds. Must be a cancellation point, since it
    /// is where the polling loop spends nearly all of its time.
    func sleep(for duration: TimeInterval) async throws
}

public struct SystemSyncClock: SyncClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
    }
}
