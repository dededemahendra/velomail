import Testing
import Foundation
@testable import VeloCore

@Suite struct BackoffPolicyTests {
    private let policy = BackoffPolicy(base: 2, multiplier: 2, cap: 300)

    @Test func zeroFailuresHasNoDelay() {
        #expect(policy.delay(afterFailures: 0) == 0)
    }

    @Test func firstFailureWaitsTheBaseDelay() {
        #expect(policy.delay(afterFailures: 1) == 2)
    }

    @Test func delayDoublesWithEachConsecutiveFailure() {
        #expect(policy.delay(afterFailures: 2) == 4)
        #expect(policy.delay(afterFailures: 3) == 8)
        #expect(policy.delay(afterFailures: 4) == 16)
    }

    @Test func delayIsClampedToTheCap() {
        // 2 * 2^7 = 256, still under; the next step would be 512.
        #expect(policy.delay(afterFailures: 8) == 256)
        #expect(policy.delay(afterFailures: 9) == 300)
        #expect(policy.delay(afterFailures: 50) == 300)
    }

    @Test func negativeFailureCountIsTreatedAsZero() {
        #expect(policy.delay(afterFailures: -1) == 0)
    }

    @Test func defaultPolicyReachesTheCapWithinSevenFailures() {
        let standard = BackoffPolicy.standard
        #expect(standard.delay(afterFailures: 1) == 2)
        #expect(standard.delay(afterFailures: 9) == standard.cap)
    }
}
