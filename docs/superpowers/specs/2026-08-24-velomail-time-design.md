# Velo Mail — Time-based Actions (Increment M) Design

**Date:** 2026-08-24
**Depends on:** B (outbound queue), F (scheduler)

## 1. Why

Roadmap items 21–26: Send Later, Scheduled Send, Undo Send, Snooze, Reminders,
Follow-up Tracking. They look like six features and are really three mechanisms,
which is the argument for building them together rather than one at a time.

## 2. Undo Send and Send Later are the same feature

Both are "do not actually send this yet". The outbound queue is already durable
and already drained by a scheduler, so the entire mechanism is one column:
**`dueAt` on a pending mutation**, and a drain that ignores anything not yet due.

- **Undo Send** = enqueue with `dueAt = now + 10s`. Undo deletes the row and the
  optimistic placeholder before it ever leaves.
- **Send Later** = the same, with a date the user picked.

Existing mutations get `dueAt = nil`, meaning "due now", so archive and
mark-read are unaffected.

**Why a delay rather than a real recall:** there is no such thing as unsending
mail. Every client that offers "undo send" is holding the message back for a few
seconds. Being honest about that in the design keeps the UI honest too — the
window is finite and visible.

## 3. Snooze is a label plus a date

Snoozing removes `INBOX` — pushed to Gmail through the same queue, so it is
visible on every device — and records `snoozedUntil` locally. The inbox query
excludes threads whose time has not come. A wake pass in the sync loop re-adds
`INBOX` when it has.

`snoozedUntil` is local rather than a Gmail label because the *label* change is
what syncs; the wake time is this client's business. The cost is honest and
recorded below: snooze wakes on the machine that set it.

## 4. Follow-up is a query, not a state

A thread needs following up when **you sent the last message** and nothing came
back within a window. That is derivable from what is already stored — no column,
no background job, no risk of the flag going stale.

Deriving it also means it self-corrects: the moment a reply arrives the thread
stops needing follow-up, without anything having to notice and clear a flag.

## 5. Scope

### In scope
- `dueAt` on `pendingMutation` (**migration v10**); drain respects it.
- `OutboundService.send(_:after:)` returning the mutation id, and `cancelSend`.
- `snoozedUntil` on `thread` (**migration v11**); snooze, wake, and an inbox
  query that hides sleeping threads.
- `FollowUpService` — threads awaiting a reply.
- Wake wired into the sync pass; UI for undo, snooze and follow-up.

### Explicitly out of scope
- Gmail's own snooze. It is not in the public API, so a thread snoozed here
  looks archived in Gmail's own client until it wakes.
- Recurring reminders and per-thread custom reminder times.
- Waking while the app is closed — the wake pass runs when the app runs.

## 6. Testing

All time is injected. No test sleeps: due-ness, wake and follow-up windows are
all functions of a `now` that the test supplies, which is the only way these are
testable at all.

## 7. Known limitations (deliberate, recorded)

- Undo is a delay, not a recall. Once the window passes the mail is gone.
- A queued send that is due while the app is closed goes out at next launch,
  not at the scheduled minute.
- Snooze wakes only on the machine that set it, and only while the app runs.
- Follow-up windows are global, not per-thread or per-recipient.

---

## Completion record

499 → 538 tests, clean build, no warnings.

Three mechanisms covering six roadmap items, as designed: `dueAt` gave Undo Send
and Send Later together, snooze is a label plus a local date, and follow-up is a
query rather than a state.

**Found while building:**

- `FollowUpService` originally looked up each thread's newest sender through
  `MailStore`, from inside a `dbQueue.read` — which re-enters the connection and
  makes GRDB trap. The sender is fetched in the same query now.
- Adding a default argument to `MutationStore.pending()` changed its mangled
  symbol, so incremental builds failed to link against stale test objects. A
  clean build fixes it; worth knowing, because the error names a missing symbol
  rather than the real cause.
- Making the send window non-zero broke three compose tests that asserted on
  `pending()`. They were right to fail — a queued send is deliberately *not due*
  for ten seconds — so they now assert on `all()`, which is what they meant.
- `HTTPClient` was not `Sendable`, which the AI providers surfaced as a warning
  that is an error under Swift 6. Fixed at the protocol rather than silenced.

**Verified by launching:** the app runs and renders correctly on a fresh launch.
One capture showed the list selection and the thread pane disagreeing; a clean
relaunch was correct both before and after window activation, so that frame was
a stale instance from repeated launches rather than a defect.

**Not verified:** the undo banner and follow-up bar appearing, since triggering
them needs key input that macOS will not synthesise without Accessibility
permission.
