# Velo Mail — Notifications & Focus (Increment R) Design

**Date:** 2026-08-26
**Depends on:** sync, storage

## 1. Why

Roadmap items 80, 81, 83. The app now syncs, triages, searches, snoozes and
sends — and still cannot tell you mail arrived. You have to go and look, which
is the one thing a mail client exists to save you from.

## 2. The hard part is deciding what deserves one

Showing a banner is four lines of AppKit. Choosing *what* to show is where this
goes wrong, and every failure mode is the same shape: telling the user something
they did not need to hear.

Four rules, each of which is a test:

1. **Never announce on the first run.** A fresh account backfills five hundred
   messages. Announcing them would fire five hundred banners, and the user's
   very first experience of the app would be one they never forgive. With no
   baseline, announce nothing and record the mark.
2. **Never announce your own mail.** Sending puts a message in the thread; it
   must not come back as "you have new mail from you".
3. **Never announce twice.** A high-water mark by date, so a restart does not
   re-announce every unread message in the inbox.
4. **Cap the banners.** Twelve messages arriving at once is one summary, not
   twelve interruptions.

## 3. A high-water mark, not a set of seen ids

Tracking which ids have been announced is exact and grows forever. A single
"newest thing I have announced" timestamp is one value, cannot grow, and is
wrong only in a case that does not matter: a message that arrives *dated* older
than one already announced stays silent.

That trade is deliberate. Silence on an out-of-order message is a smaller
failure than an unbounded set, or than re-announcing the inbox on every launch.

## 4. It is app state, not mailbox data

The mark lives in `UserDefaults`, not SQLite — no migration. "Which banners have
I already shown on this Mac" is a property of this installation, not of the
mailbox, and it should not sync or survive a database rebuild.

## 5. Focus

Focus mode suppresses banners and hides unread counts, including the Dock badge.
It is a switch, not a schedule; a schedule needs a whole settings surface and
this earns its keep without one.

## 6. Degrading when notifications are refused

An unsigned development build may simply not be allowed to post notifications,
and the user may say no. Neither is an error: the announcer still computes what
it *would* have shown, the Dock badge still works, and nothing logs an
apology every sync tick.

## 7. Scope

### In scope
- `MailAnnouncer` — the decision, pure and headless.
- Unread count and Dock badge.
- Focus mode suppressing both.
- A thin `UNUserNotificationCenter` adapter that degrades quietly.

### Explicitly out of scope
- Per-sender or per-label notification rules (roadmap 53 territory).
- Notification actions (archive from the banner).
- Scheduled focus, or following the system Focus state.
- Sounds.

## 8. Testing

The announcer gets all of it: the first-run silence, self-authored mail, the
high-water mark across a simulated restart, the cap and summary, and that a
read message never announces. The AppKit adapter is not unit-tested — it has no
logic beyond forwarding, and it cannot run in a test process anyway.

## 9. Known limitations (deliberate, recorded)

- A message arriving dated older than the last announced one stays silent.
- The mark is per-installation; two Macs each announce once.
- No notification actions, no sounds, no per-sender rules.

---

## Completion record

753 → 781 tests, clean build, no warnings. No migration, as §4 said: the mark is
`UserDefaults`.

The announcer carries the increment's weight — 18 tests for a type with one
method — because every way this feature goes wrong is a decision, not a
mechanism. First-run silence, self-authored mail through a display name, the
mark surviving a simulated restart, the mark refusing to go backwards, the burst
cap, and showing the *newest* few rather than the first few.

**One trap worth recording:** `UNUserNotificationCenter.current()` traps outright
when the process has no bundle identifier, which is exactly the case in a test
runner. The presenter guards on `Bundle.main.bundleIdentifier` before touching
it — without that, importing the type into a test target is enough to crash the
suite.

**Verified by launching:** the status bar shows "2 unread" against the demo
mailbox and the app logs nothing on start.

**Not verified:** an actual banner. Demo mode announces nothing by design (first
run, no mark), and an unsigned build may not be permitted to post at all — which
is exactly the case §6 says must degrade quietly, and it does.
