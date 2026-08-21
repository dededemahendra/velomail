import Foundation

/// Exponential backoff for repeated sync failures: `base * multiplier^(n-1)`,
/// clamped to `cap`.
///
/// Pure and deterministic — no clock, no jitter. Jitter is deliberately absent:
/// one account polling one mailbox is not a thundering herd, and being able to
/// assert exact delays is worth more here than herd avoidance.
public struct BackoffPolicy: Equatable, Sendable {
    public let base: TimeInterval
    public let multiplier: Double
    public let cap: TimeInterval

    public init(base: TimeInterval, multiplier: Double, cap: TimeInterval) {
        self.base = base
        self.multiplier = multiplier
        self.cap = cap
    }

    /// 2s doubling to a 5-minute ceiling. Five minutes is about the longest a
    /// user should wait for a client to notice the network came back.
    public static let standard = BackoffPolicy(base: 2, multiplier: 2, cap: 300)

    /// The delay to wait after `failures` consecutive failures. Zero failures
    /// means success, so there is nothing to wait for.
    public func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let raw = base * pow(multiplier, Double(failures - 1))
        return min(raw, cap)
    }
}
