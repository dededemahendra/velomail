# VeloCore Build Plan — Increment G (Keyboard & Selection)

Execute **top to bottom**, red→green, one commit per task.

Spec: `docs/superpowers/specs/2026-08-21-velocore-keyboard-design.md`

**No migration.** G adds no schema; it is pure logic in a new `Input/` folder.

## Shared-file edit ledger

None — every file in G is new. Nothing existing is touched.

---

## G1 — `MailAction` + `KeyInput`

**Tests** (`KeyInputTests`)
- `chordsAreEqualOnlyWhenKeyAndModifiersMatch`
- `charactersAreComparedCaseInsensitively`
- `modifierSetsCombine`

**Implementation** — `Input/MailAction.swift` (the v1 verb set),
`Input/KeyInput.swift`: `KeyInput.Key` (`.character(Character)`, `.enter`,
`.escape`), `KeyInput.Modifiers` (`OptionSet`: `.command`, `.shift`), `KeyInput`
value type. No AppKit.

## G2 — `KeyboardEngine`

**Tests** (`KeyboardEngineTests`)
- `mapsEveryV1BindingToItsAction` (j/k/Enter/o/e/r/c, Cmd+Enter, Cmd+K)
- `prefixKeyAloneProducesNoActionAndGoesPending`
- `goToInboxRequiresBothKeysOfTheChord`
- `unboundKeyAfterAPrefixIsSwallowedAndResets` (`g` then `j` must not scroll)
- `escapeAfterAPrefixCancelsTheChordWithoutGoingBack`
- `escapeWhenNothingIsPendingReportsBack`
- `unboundKeyIsUnhandled`
- `uppercaseAndLowercaseBindingsBothResolve`

**Implementation** — `Input/KeyboardEngine.swift`: `Outcome`
(`.action`/`.pending`/`.unhandled`), a keymap table of one- and two-key
sequences, two-state machine.

## G3 — `SelectionCursor`

**Tests** (`SelectionCursorTests`)
- `startsWithNoSelectionWhenEmpty`
- `firstItemIsSelectedWhenTheListBecomesNonEmpty`
- `moveDownAndUpWalkTheList`
- `moveDownStopsAtTheEnd` / `moveUpStopsAtTheStart`
- `removingTheCurrentItemKeepsTheIndexSoSelectionLandsOnTheNext`
- `removingTheLastItemClampsToTheNewLastIndex`
- `removingTheOnlyItemClearsSelection`

**Implementation** — `Input/SelectionCursor.swift`: `count`, `index`,
`moveDown()`, `moveUp()`, `removeCurrent()`.

## G4 — `CommandRegistry` (palette)

**Tests** (`CommandRegistryTests`)
- `emptyQueryReturnsEveryCommandInRegistrationOrder`
- `matchesASubsequenceNotJustAPrefix` (`gti` → Go to Inbox)
- `matchingIsCaseInsensitiveAndIgnoresSpaces`
- `prefixMatchesOutrankLaterMatches`
- `shorterTitleWinsATie`
- `noMatchReturnsEmpty`
- `everyV1ActionIsReachableFromThePalette`

**Implementation** — `Input/CommandRegistry.swift`: `Command` (title + action),
`v1` default registry, `matches(_:)` with the documented ranking.

---

## Out of scope for G (recorded)

- `NSEvent` → `KeyInput` translation (app layer, trivial adapter).
- Remappable bindings, prefix timeout, palette usage-learning.
- Executing actions — the view model owns that.
- Everything still blocked on an app target and real Google OAuth client
  credentials: interactive sign-in, the AppKit message list, ThreadView.
