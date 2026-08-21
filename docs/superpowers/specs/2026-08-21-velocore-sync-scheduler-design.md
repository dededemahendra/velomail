# VeloCore — Sync Scheduler & Resilience (Increment F) Design

**Date:** 2026-08-21
**Status:** Approved (scope)
**Depends on:** D (GmailSync actor), E (send path in the drain)

## 1. Why

`GmailSync.start()` is still a single `syncNow()`. The D plan deferred the whole
runtime story in one line:

> **Timers, polling, on-focus refresh, offline backoff, and history-expired
> auto-re-backfill wiring** — out of D; `start()` is a single `syncNow()`.
> Re-backfill policy on `SyncError.historyExpired` belongs to a future scheduler.

This is that scheduler. Four things are broken or missing without it:

1. **`SyncError.historyExpired` is fatal.** Gmail drops history older than about
   a week. Leave the app closed over a holiday and the next sync throws with no
   recovery, even though the fix (re-backfill to re-establish a cursor) is known
   and already implemented.
2. **Nothing polls.** The v1 design promises an inbox that stays fresh.
3. **A network blip is indistinguishable from a permanent failure.** The design's
   error-handling section asks for retry with backoff and a subtle
   "offline / syncing" indicator; neither exists.
4. **A `.failed` mutation is stranded forever.** `pending()` excludes it and
   nothing ever moves it back.

Success criterion: **start the engine once and the mailbox stays current —
through expired cursors, dropped connections, and failed writes — without the
caller orchestrating anything.**

## 2. Scope

### In scope
- `SyncStatus` published from the actor, so a UI can render the indicator.
- Automatic re-backfill on `SyncError.historyExpired` (bounded to one attempt
  per pass, so a persistently bad cursor cannot spin).
- `BackoffPolicy` — pure, deterministic exponential backoff with a cap.
- `SyncClock` seam + `run(interval:)` polling loop with cancellation.
- Bounded retry of `.failed` mutations (migration **v6**: `attempts`).

### Explicitly out of scope
- On-focus refresh: that is an app-lifecycle signal. The engine exposes
  `syncNow()`; wiring `NSApplication` notifications to it belongs to the app.
- Push (Gmail `watch` + Pub/Sub) — polling is the v1 promise.
- Jitter on the backoff. One account polling one mailbox is not a thundering
  herd, and determinism is worth more here than herd avoidance.
- Surfacing per-mutation errors to the user; `.failed` is still terminal once
  the attempt cap is reached.

## 3. Failure taxonomy (what retries and what does not)

The scheduler has to tell three cases apart, because they need opposite
responses:

| Case | Example | Response |
|---|---|---|
| **Recoverable state** | `historyExpired` | Reset the cursor and re-backfill *in the same pass*. Not a failure; the pass still succeeds. |
| **Transient** | network drop, 5xx, 429 | Keep the cursor, back off, retry. Status goes `offline`. |
| **Programmer error** | decode failure, DB fault | Propagate. A bug must not be retried into silence. |

`notInitialized` is deliberately treated as recoverable too: it means the
baseline is missing, and backfill is exactly what establishes it.

## 4. Backoff

`delay(afterFailures:) = min(base * multiplier^(n-1), cap)`, evaluated as a pure
function so it is testable without a clock. Defaults: base 2s, multiplier 2,
cap 300s — five minutes is the longest a user should wait for a client to
notice the network came back, and it reaches that in seven failures.

A successful pass resets the failure count to zero, so recovery is immediate
rather than serving out a long backoff that was already scheduled.

## 5. The polling loop

`run(interval:)` alternates `syncNow()` and a sleep, forever, until cancelled.
Cancellation is cooperative: the loop checks `Task.isCancelled` and the injected
clock's `sleep` is the cancellation point.

`SyncClock` exists purely so tests are deterministic and instant. The fake
records every requested duration (which is how the backoff assertions are made)
and ends the loop by throwing `CancellationError` after a scripted number of
sleeps. No test sleeps for real.

## 6. Mutation retry

Migration **v6** adds `attempts` to `pendingMutation`. `markFailed` increments
it; `retryFailed(maxAttempts:)` flips rows back to `.pending` only while they
are under the cap. The scheduler calls it at the top of each pass, so a write
that failed on a dropped connection goes out on the next tick, while one that
fails deterministically stops after `maxAttempts` (default 3) instead of
retrying forever.

**Why a column and not an in-memory counter:** the queue is durable precisely so
a restart does not lose writes; an in-memory count would reset on every launch
and turn a permanently-failing mutation into an infinite loop across sessions.

## 7. Testing

All deterministic, no real time, no network:
- `BackoffPolicy` — pure value assertions incl. the cap.
- Re-backfill — a scripted source that throws `historyExpired` once, asserting
  the cursor is re-established and the pass still completes.
- Loop — fake clock asserting tick count, recorded intervals, and that a failing
  pass produces backoff intervals rather than the poll interval.
- Retry — queue transitions across the attempt cap.

## 8. Known limitations (deliberate, recorded)

- One account per `GmailSync`; multi-account scheduling is not modelled.
- `attempts` counts *drain* attempts, not per-message API attempts.
- A mutation that exhausts `maxAttempts` stays `.failed` with no user-facing
  surface yet; the UI increment owns that.
- The loop polls at a fixed interval; it does not adapt to mailbox activity.
