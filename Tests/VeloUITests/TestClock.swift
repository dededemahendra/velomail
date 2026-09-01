import Foundation
@testable import VeloUI

/// A clock a test drives, in place of the one the app waits on.
///
/// The countdowns in `AppViewModel` -- a notice fading, an undo offer running
/// out -- were tested by setting a short window and sleeping past it. That is a
/// race between two real timers, and it was lost about one parallel run in
/// three: `aPassingMessagePasses` set a 50ms window, slept 200ms, and still
/// found the notice there because the continuation had not been scheduled yet.
///
/// Advancing this instead makes the same assertions exact and takes the wall
/// clock out of the suite.
@MainActor
final class TestClock {
    private struct Pending {
        let id: Int
        let at: TimeInterval
        let body: @MainActor () -> Void
    }

    private var now: TimeInterval = 0
    private var nextID = 0
    private var pending: [Pending] = []

    /// Hand this to `AppViewModel.afterDelay`.
    var delay: AppViewModel.DelayedWork {
        { [weak self] seconds, body in
            guard let self else { return }
            self.nextID += 1
            self.pending.append(Pending(id: self.nextID, at: self.now + seconds, body: body))
        }
    }

    /// Moves time forward, firing everything that comes due, in order.
    ///
    /// Re-checks after each one, so work scheduled by work that has just fired
    /// still runs at the right moment.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while true {
            var soonest: Pending?
            for item in pending where item.at <= target {
                if soonest == nil || item.at < soonest!.at { soonest = item }
            }
            guard let next = soonest else { break }
            pending.removeAll { $0.id == next.id }
            // Keep `now` honest while the work runs, so anything it schedules
            // is measured from the moment it actually fired.
            now = next.at
            next.body()
        }
        now = target
    }

    /// Nothing is waiting.
    var isIdle: Bool { pending.isEmpty }
}
