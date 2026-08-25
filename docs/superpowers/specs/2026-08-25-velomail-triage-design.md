# Velo Mail — Triage Surface (Increment N) Design

**Date:** 2026-08-25
**Depends on:** B (outbound queue), G (keyboard), M (time)

## 1. Why

Roadmap items 2, 51/52/53, 65/66, 70/71 and 86: Split Inbox, Custom Sections,
Priority Inbox, VIP, Multi-select, Bulk Actions, Star, Pin, Inbox Zero. Nine
items, and — as with increment M — they collapse into three mechanisms once you
stop reading them as nine features.

The theme is the one v1 was always about: triage. M made time an input to the
inbox. N makes *the selection* and *the ordering* inputs to it.

## 2. Star is a label, and the queue already pushes labels

`STARRED` is a real Gmail label. Adding and removing it needs no new machinery
whatsoever: `OutboundService.enqueueLabelChange` already applies a label change
to every message in a thread, captures the prior labels for revert, re-derives
the thread, and enqueues a durable mutation that `drain()` pushes and rolls back
on failure. Star is two new `MutationKind` cases and two one-line methods.

That is the whole argument for doing star before anything else in this
increment: it is the cheapest possible proof that the label path generalises,
and everything that follows leans on it.

**Pin is deliberately not built.** The roadmap already flags it as local-only.
Star is the durable version of the same gesture, and a pin that exists in Velo
Mail and nowhere else is a promise the app cannot keep on the user's phone. One
concept, honestly synced, beats two where the second quietly lies.

## 3. Multi-select is not a feature, it is a wider cursor

The instinct is to add bulk actions: bulk archive, bulk star, bulk snooze. That
is three new code paths that can each drift from their single-thread twin.

They are the same actions. What changes is how many rows they run over.

`SelectionCursor` gains a set of marked indices and one derived property:

```swift
/// The rows an action applies to: everything marked, or the cursor row when
/// nothing is.
public var targets: [Int]
```

Every triage action iterates `targets`. With nothing marked that is exactly one
row and today's behaviour is unchanged, which is the property that makes this
safe — the single-thread path is not a special case of the bulk path, it *is*
the bulk path with one element.

**Marks are indices, not thread ids.** That matches the cursor's existing
design, which is deliberately index-based so a held-down `e` sweeps the inbox.
The cost is that marks cannot survive the list changing underneath them, so
`reset(count:)` clears them. Background sync dropping a thread while three rows
are marked would otherwise leave marks pointing at whatever slid into their
place, and silently archiving the wrong mail is far worse than losing a
selection.

## 4. Split inbox is the same query, partitioned

`MailStore.inboxThreads()` is currently *the* inbox. A split inbox is not a
second query — it is the same rows, grouped.

```swift
public static func split(_ threads: [MailThread]) -> [ThreadSection]
```

Pure, synchronous, and given an already-fetched array: no database access, no
new observation, nothing to keep in sync. The sections concatenate back into a
flat display order, so `SelectionCursor` stays flat and `j`/`k` walk across a
section boundary without knowing one exists.

**Importance comes from Gmail, not from a heuristic we invent.** Gmail already
computes `IMPORTANT` server-side and it arrives in `labelIDs` for free with
every message. Priority Inbox is therefore `STARRED || IMPORTANT`, and the
alternative — writing our own importance scorer — would be a worse answer that
also costs more.

Empty sections are omitted rather than shown empty, so a mailbox with nothing
important looks like the flat list it did before.

VIP-by-sender (item 53) is the natural next rule and is **not** in this
increment: it needs a configured sender list, which is config plumbing rather
than triage, and the section layer is designed so adding a rule is adding a
predicate.

## 5. The keymap problem, and the decision

Star's conventional key is `s`, in Gmail and in Apple Mail's Flag. Velo Mail
gave `s` to *summarise* and `d` to *suggest replies* in increment K.

**Decision: the AI actions move behind an `a` chord prefix, and `s` becomes
star.**

- `a` `s` — summarise thread
- `a` `r` — suggest replies
- `a` `t` — triage thread
- `s` — star / unstar the selection
- `x` — mark the row (Gmail's own key for it)
- `d` — unbound

The reasoning, which is worth stating because it overturns a shipped binding:
AI is optional and off by default, so on most launches `s` and `d` are two of
the best keys on the keyboard doing *nothing at all*. Star works on every
launch, for every user, forever. A prime single key should go to the action
that is always there.

`KeyboardEngine` already models chord prefixes as a set, so `a` costs one entry
and no new state. This is exactly the "the moment a second chord is added, a
special case becomes a bug" note the engine was written with.

**This is the one reversible decision in the increment that a reader might
disagree with.** Vetoing it costs one line in `KeyboardEngine.bindings` (star
moves to `f`, for Flag, which is free) and nothing else in the design changes.

### Keymap constraint discovered while designing

`KeyMonitor.translate` filters key-downs to letters, numbers and `/`. Punctuation
does not reach the engine, so `*` — the obvious glyph for star — is not
bindable without widening that filter. That filter is deliberate and this
increment does not touch it.

## 6. Inbox Zero is an empty state

Item 86 is already the triage model; what is missing is what the app says when
you finish. An empty inbox currently renders an empty table, which reads as a
loading failure rather than as success.

A view change only, gated by launching and looking, exactly as increment I
gated `ThreadView`.

## 7. Scope

### In scope
- `MutationKind.star` / `.unstar`; `OutboundService.star`, `unstar`, `toggleStar`.
- Marked-set on `SelectionCursor`, and `targets` as the thing actions iterate.
- Archive, star and snooze applying to `targets`.
- `InboxSections.split` — Important (`STARRED` or `IMPORTANT`) then everything else.
- `a` chord prefix for AI; `s` = star; `x` = mark; palette entries for both.
- Inbox-zero empty state; star glyph and mark indicator in the list row.

### Explicitly out of scope
- **Pin** — see §2.
- **VIP / custom sections** — see §4.
- **User-configurable sections and section order.** The rule list is code in
  this increment.
- **Marks surviving a sync that changes the list.** See §3.
- **Select-all / range-select** (`Shift`-click, `x` then `j` extending). One
  mark at a time is the honest minimum; ranges are a cursor feature, not a
  triage one.

## 8. Migrations

**None.** N claims no schema version. Star is a label Gmail already has,
marks live in the cursor, and sections are derived from rows already fetched.
The ledger stays at v11.

That is a deliberate result rather than a happy accident: every mechanism here
was chosen partly because it did not need a column.

## 9. Testing

Star is tested through `OutboundService` the way archive is, including the
revert-on-failure path, because star is the first user-facing use of the label
queue that is *toggleable* — and a toggle that reverts to the wrong state is a
bug archive could never have exposed.

`SelectionCursor` and `InboxSections` are pure values, so both are tested
directly with no database and no clock.

The list row, section headers and the inbox-zero state are views: gated by
launching and looking, as in increments I and M, because synthetic input needs
Accessibility permission this environment does not have.

## 10. Known limitations (deliberate, recorded)

- Marks clear whenever the list changes underneath them.
- A thread starred here shows as starred everywhere, but the *order* of the
  split inbox is local: another client shows one flat list.
- `IMPORTANT` is Gmail's judgement, not ours. When Gmail is wrong about a
  thread, Velo Mail is wrong in the same way, and there is no local override
  short of starring it.
- No select-all, so "archive everything" is still a held-down `e`.
