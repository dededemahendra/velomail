# Velo Mail — Fast Backfill (Increment T) Design

**Date:** 2026-08-26
**Depends on:** backfill, auth

## 1. Why

The first sign-in against a real Gmail account showed "Inbox zero" and
"Syncing…" for minutes, with zero rows in SQLite. Sampling the process rather
than guessing put the stack squarely in the `messages.get` loop — working, not
hung, just doing 500 round trips end to end.

No test could have found this. Against a scripted source, 500 fetches are
instant; only a real mailbox has latency.

## 2. Three causes, all in the same path

**Nothing was stored until everything arrived.** `backfillInbox` hydrated the
whole list, then reconciled once. The v1 design said the opposite in as many
words — *"store as we go so the inbox populates progressively"* — so this was a
straight deviation from the design, not an unconsidered case. It also meant one
failed fetch at message 499 discarded the 498 before it.

**Fetches were strictly sequential.** The design said *"hydrate via batched
`messages.get`"*. They were not batched.

**The Keychain was read once per request.** `AccessTokenProvider.validAccessToken()`
called `store.load()` on every call — 500 crossings into `securityd` for a token
valid for an hour. Nine of ten stack samples sat there.

## 3. What changes

- Hydrate in chunks of 20 and reconcile each chunk, so rows land within seconds
  and partial progress survives a failure.
- Fetch with a bounded task group, 8 in flight, refilled as each completes.
  Unbounded would be rate-limited and would exhaust the connection pool.
- Cache the token in the provider until it actually expires.

The cursor is still recorded only after the whole backfill succeeds, so an
interrupted run resumes rather than believing it finished. Chunks already
written stay written; upserts make the re-run idempotent.

**`AccessTokenProvider` becomes an actor.** It is now called from concurrent
tasks, and a cache on a plain class would be a data race.

## 4. Measured

Against a real mailbox, cold store, 500 messages:

| | Before | After |
|---|---|---|
| First mail on screen | still zero rows when sampled at 4 min | 30s |
| Backfill complete | several minutes | 63s |

## 5. Known limitations (deliberate, recorded)

- The id listing is still sequential — five round trips for 500 ids. It is a
  small share of the total and paging is inherently serial.
- The first 30 seconds are launch, profile and listing before any hydration.
- Concurrency is a fixed 8, not adaptive to the connection.
