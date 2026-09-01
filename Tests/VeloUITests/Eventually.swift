import Foundation
import Testing

/// Waits for a condition rather than for a duration.
///
/// The sleeps this replaces were all the same shape: start work that runs in a
/// detached `Task`, sleep long enough that it has "probably" finished, then
/// assert. The number is a guess about a machine's load, and it is wrong in
/// both directions -- too short and the test fails for no reason, too long and
/// every run pays for it. One of them lost that race about one parallel run in
/// three.
///
/// This returns the moment the condition holds, so the common case costs a
/// fraction of a millisecond, and it only spends the full budget when something
/// is actually broken -- at which point waiting was the right thing to do.
///
/// The budget is deliberately generous, for the reason `MailStoreObservationTests`
/// already records: two seconds passed in isolation and failed under the
/// contention of the full suite in parallel, which is the worst kind of test.
/// A long budget costs nothing except on a genuine failure.
@MainActor
func eventually(_ what: String,
                within budget: Duration = .seconds(10),
                sourceLocation: SourceLocation = #_sourceLocation,
                _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + budget
    while ContinuousClock.now < deadline {
        if condition() { return }
        // Yielding rather than sleeping: the work being waited on is a `Task`
        // on this same actor, and it needs a turn.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("\(what) did not happen within \(budget)", sourceLocation: sourceLocation)
}
