# VeloCore — Keyboard & Selection (Increment G) Design

**Date:** 2026-08-21
**Status:** Approved (scope)
**Depends on:** nothing at runtime — pure logic over the existing action surface

## 1. Why

The v1 design names `KeyboardEngine` as a first-class module and milestone 6,
and its testing section is explicit that this is engine work, not UI work:

> **`KeyboardEngine`** — maps key chords (incl. multi-key like `g i`) to actions;
> drives selection/auto-advance.
> **Testing:** unit tests for chord parsing (`g i`), action mapping, and
> auto-advance selection logic.

It is also the single success criterion of v1 — *"every common interaction can be
done without the mouse"* — reduced to code. None of it needs a window, a
credential, or a network: it is a keystroke going in and an action coming out.
Building it now means that when the app target and OAuth credentials arrive, the
interaction model is already specified and tested, and the SwiftUI layer is a
thin adapter rather than the place where the behaviour gets invented.

Success criterion: **every binding in the v1 design resolves to an action, `g i`
works as a two-key chord, and archiving auto-advances the selection correctly at
both ends of the list.**

## 2. Scope

### In scope
- `MailAction` — the full v1 verb set, as a value type.
- `KeyChord` / `KeyInput` — a keystroke, independent of AppKit.
- `KeyboardEngine` — chord → action, including the `g` prefix state machine.
- `SelectionCursor` — move, clamp, and the auto-advance rule after a removal.
- `CommandRegistry` — the `Cmd+K` palette's command list and subsequence
  matching with ranking.

### Explicitly out of scope
- Any AppKit/SwiftUI type. The engine speaks `KeyInput`; translating
  `NSEvent` into one is the app layer's job and is trivial.
- User-remappable bindings. v1 ships one keymap.
- Prefix timeout. Superhuman clears a half-typed chord after a beat; that needs
  a clock in the engine and buys little, so a pending prefix is cleared by the
  next key or `Esc` instead.
- Executing the actions. The engine decides *what* was asked for; the view model
  performs it against `OutboundService`/`MailStore`.

## 3. The `g` prefix

`g i` is the only multi-key chord in v1, but modelling it as a special case
would be a trap the moment `g s` or `g t` arrives. So the engine is a small
state machine with exactly two states — `ready` and `awaitingChord(prefix:)` —
and the keymap is a table of one- and two-key sequences.

Three rules, each of which is a test:

1. A prefix key alone produces **no action** and leaves the engine pending.
2. A pending prefix plus an unbound key produces **no action** and returns to
   ready. It must not fall through and fire the second key's own binding —
   typing `g` then `j` should not scroll the list.
3. `Esc` always returns to ready, and reports `.back` **only** when nothing was
   pending. Escaping a half-typed chord cancels the chord, not the view.

## 4. Auto-advance

The rule that makes triage feel right, and the one that is easy to get subtly
wrong at the ends of the list. After archiving the item at index `i` of `n`:

- the list is now `n-1` long;
- selection **stays at index `i`**, which is the item that moved up into the gap
  — the next thread, which is what the user expects to be looking at;
- if `i` was the last index, selection clamps to the new last index;
- if the list is now empty, selection becomes `nil`.

Keeping the *index* rather than tracking the next item's identity is deliberate:
it is what makes a held-down `e` sweep the inbox without the cursor jumping.

## 5. Palette matching

`Cmd+K` wants "type a few letters, get the command". Subsequence matching
(letters in order, gaps allowed) is what every palette does, so `arc` matches
"Archive" and `gti` matches "Go to Inbox".

Ranking, in order: exact prefix of the title first, then earliest match position,
then shortest title. That makes the obvious command the first hit rather than
whichever happened to be registered first, and it is deterministic, so it can be
asserted.

Matching is case-insensitive and ignores spaces in the query.

## 6. Testing

Everything is a pure function or a value-type state machine; no clock, no
storage, no network. Tests assert the whole v1 keymap, each prefix rule, the
auto-advance rule at both ends and on the empty list, and the palette's ranking.

## 7. Known limitations (deliberate, recorded)

- One fixed keymap; no remapping, no per-view keymaps beyond the `g` prefix.
- No prefix timeout (see scope).
- The palette ranks by title only; it does not learn from usage.
- `SelectionCursor` models a flat list. Threaded/grouped selection is not v1.
