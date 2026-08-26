# Velo Mail — Rules (Increment U) Design

**Date:** 2026-08-26
**Depends on:** sync, outbound queue

## 1. Why

Six roadmap items are one feature wearing different hats: Filters (57), Rules
(58), Automatic Sorting (59), VIP Contacts (53), Email Blocking (62) and Spam
Management (63). Each is "when a message looks like *this*, do *that*". Building
six mechanisms would be six sets of bugs.

- **VIP** is a rule: sender is X → mark important.
- **Blocking** is a rule: sender is X → archive, never notify.
- **Spam** is blocking with a coarser condition.

## 2. Rules never run on backfill

The single most important decision here, and the one that would be a disaster to
get wrong.

A first sync pulls 500 existing messages. If rules ran over those, a
newly-written "archive anything from noreply@" rule would archive hundreds of
messages the user had already dealt with — and every one of those archives is a
real change pushed to Gmail, on every device.

So rules apply **only to messages that arrive through incremental sync**, never
to backfill. Same principle as notifications not announcing on first run: the
first sync is history, not events.

## 3. A file, not a table

Rules live in `~/.config/velomail/rules.json`, like snippets.

No migration, and more importantly the user can read and edit them in a text
editor. A rule engine whose rules are invisible inside a database is one nobody
trusts — and trust matters more here than anywhere else in the app, because
these actions happen without asking.

## 4. Shape

A rule is conditions plus actions, with `matchAll` choosing AND or OR:

| Condition | |
|---|---|
| `senderContains` | the VIP and blocking primitive |
| `subjectContains` | |
| `bodyContains` | |
| `isUnread` | |
| `hasAttachment` | |

| Action | |
|---|---|
| `archive` | |
| `star` | |
| `markRead` | |
| `markImportant` | VIP |
| `applyLabel` | |
| `block` | archive, mark read, and suppress the notification |

Rules are ordered and all matching rules apply, rather than stopping at the
first. Ordering matters only for reporting; the actions are a set.

## 5. Actions go through the outbound queue

A rule does not write labels directly. It calls the same `OutboundService` the
keyboard does, so a rule-driven archive is optimistic locally, pushed to Gmail,
and reverted on failure exactly like a manual one. One path, one set of
failure modes.

## 6. Blocked mail is not announced

`block` suppresses the notification as well as archiving. Announcing something
the user asked never to see would make the feature actively worse than nothing.

## 7. Scope

### In scope
- `MailRule` + conditions/actions; `RuleLibrary` reading the file.
- `RuleEngine` — pure matching, producing actions for a message.
- Applied on incremental arrival only; wired through `OutboundService`.
- Blocked senders excluded from notifications.

### Explicitly out of scope
- An in-app rule editor. The file is the interface for now.
- Regular expressions in conditions. Substring matching is what people
  actually write, and a bad regex is a support problem.
- Rules that move between arbitrary Gmail labels beyond `applyLabel`.
- Server-side Gmail filters. These are local, and deliberately so — they run
  where the user can see them.

## 8. Testing

Matching for every condition and both combinators; that rules never touch
backfilled mail; that actions route through the queue; that a blocked sender is
not announced; and that a malformed rules file disables rules rather than
crashing the app.
