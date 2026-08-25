# Velo Mail Build Plan — Increment N (Triage Surface)

Spec: `docs/superpowers/specs/2026-08-25-velomail-triage-design.md`
Red→green, one commit per task. Migration ledger: M took v10 and v11.
**N claims no migration** — see spec §8.

Baseline: 538 tests.

## N1 — Star is a label

`MutationKind.star` / `.unstar`. `OutboundService.star(threadID:)`,
`unstar(threadID:)`, `toggleStar(threadID:)` — all three through the existing
`enqueueLabelChange`, so revert-on-failure comes for free.

`toggleStar` reads the thread's current labels to decide direction, and must
read them *before* enqueueing, or a double-tap enqueues two adds.

**Tests** (`OutboundServiceTests`, `PendingMutationTests`)
- `starAddsTheStarredLabelOptimistically`
- `unstarRemovesTheStarredLabel`
- `toggleStarStarsAnUnstarredThread`
- `toggleStarUnstarsAStarredThread`
- `starringAnUnknownThreadIsANoOp`
- `drainPushesAStarToGmail`
- `aFailedStarRevertsToUnstarred`
- `aFailedUnstarRevertsToStarred`
- `starAndUnstarRoundTripThroughTheMutationKindCoding`

## N2 — The cursor holds a set

`SelectionCursor` gains `marked: Set<Int>`, `toggleMark()`, `clearMarks()`,
`targets: [Int]`, and `removeTargets()`.

`targets` is `marked` sorted ascending when non-empty, else `[index]` — the
property that keeps the single-thread path and the bulk path the same code.
`removeTargets()` removes from the highest index down so earlier removals do not
shift later ones, then lands the selection on the lowest removed index, clamped.
`reset(count:)` clears marks (spec §3).

**Tests** (`SelectionCursorTests`)
- `nothingIsMarkedInitially`
- `targetsIsTheCursorRowWhenNothingIsMarked`
- `targetsIsEmptyWhenTheListIsEmpty`
- `toggleMarkMarksTheCurrentRow`
- `toggleMarkTwiceUnmarksIt`
- `targetsAreTheMarkedRowsInAscendingOrder`
- `markingDoesNotMoveTheCursor`
- `removeTargetsRemovesEveryMarkedRow`
- `removeTargetsLandsSelectionOnTheLowestRemovedIndex`
- `removeTargetsClampsWhenTheTailWasRemoved`
- `removeTargetsClearsTheSelectionWhenTheListEmpties`
- `removeTargetsClearsTheMarks`
- `removeTargetsWithNothingMarkedBehavesLikeRemoveCurrent`
- `resetClearsMarksBecauseIndicesNoLongerMeanAnything`
- `clearMarksLeavesTheCursorWhereItIs`

## N3 — Triage applies to the target set

`InboxViewModel`: `toggleMark()`, `isMarked(index:)`, `markedThreadIDs`,
`targetThreads: [MailThread]`, `toggleStarSelected()`, and `archiveSelected()`
rewritten over `targets`.

The existing single-row tests must pass **unchanged** — that is the regression
gate for §3's claim that nothing special-cases one row.

**Tests** (`InboxViewModelTests`)
- `archiveWithNothingMarkedArchivesTheCursorRow`
- `archiveArchivesEveryMarkedThread`
- `bulkArchiveClearsTheMarks`
- `bulkArchiveLeavesSelectionOnTheFirstGap`
- `toggleStarStarsTheCursorRowWhenNothingIsMarked`
- `toggleStarAppliesToEveryMarkedThread`
- `toggleStarOnAMixedSelectionStarsRatherThanTogglingEachIndependently`
- `markedThreadIDsReportsWhatIsMarked`
- `reloadClearsTheMarks`

`toggleStarOnAMixedSelection…` is the one genuinely ambiguous case: two threads
marked, one starred. Per-thread toggling would leave the set *more* mixed, which
is never what the gesture meant. Star-unless-all-are-starred, as Gmail does.

## N4 — Sections over the same rows

New `Sources/VeloCore/Storage/InboxSections.swift`: `ThreadSection`
(`id`, `title`, `threads`) and `InboxSections.split(_:)`. Pure, no database.

**Tests** (`InboxSectionsTests`)
- `starredThreadsGoToImportant`
- `gmailsImportantLabelAlsoCounts`
- `aThreadThatIsBothAppearsOnlyOnce`
- `everythingElseGoesToOther`
- `orderWithinASectionIsPreserved`
- `flattenedSectionsAreTheCursorOrder`
- `anEmptySectionIsOmitted`
- `noThreadsGivesNoSections`
- `aFlatInboxWithNothingImportantIsOneSection`

## N5 — The keymap decision

`MailAction.toggleStar` and `.toggleMark`. `KeyboardEngine`: `a` joins `g` as a
chord prefix; `a s` / `a r` / `a t` take the AI actions; `s` becomes star; `x`
becomes mark; `d` is unbound.

`CommandRegistryTests.everyV1ActionIsReachableFromThePalette` already asserts
the registry covers `MailAction.allCases`, so this task **cannot** be finished
without adding "Star" and "Select" to the palette. That test is the gate; no new
one is needed for coverage.

**Tests** (`KeyboardEngineTests`, `CommandRegistryTests`)
- `sStarsTheSelection`
- `xTogglesTheMark`
- `aThenSSummarisesTheThread`
- `aThenRSuggestsReplies`
- `aThenTTriagesTheThread`
- `aAloneIsPending`
- `escapeCancelsAHalfTypedAChord`
- `aThenAnUnboundKeyIsSwallowed`
- `dIsNoLongerBound`
- `commandAIsNotAChordPrefix`
- `starIsInThePalette`
- `selectIsInThePalette`

`commandAIsNotAChordPrefix` mirrors the existing `g` guard: `Cmd+A` is
select-all in a text field and must not open a chord.

## N6 — Wiring

`AppViewModel.perform` gains `.toggleStar` and `.toggleMark`; `snoozeSelected`
iterates `inbox.targetThreads`; the AI actions still route through
`runAssistant`, which already no-ops without a provider — so `a s` on an
unconfigured app does nothing, exactly as `s` did before.

`AppViewModel` exposes `sections: [ThreadSection]` derived from `inbox.threads`.

**Tests** (`AppViewModelTests`)
- `starActionStarsTheSelection`
- `markActionMarksTheRow`
- `snoozeAppliesToEveryMarkedThread`
- `snoozeWithNothingMarkedSnoozesTheCursorRow`
- `sectionsFollowTheInbox`
- `aiChordStillDoesNothingWithoutAProvider`

## N7 — Views  *(view; gate is launch + look)*

- Star glyph and mark indicator in `ThreadRowView`.
- Section headers in `MessageListView` — the flat index must survive, so headers
  are rendered as non-selectable rows or as a grouped `NSTableView`, whichever
  keeps `selectedIndex` meaning what it means today. **Take the simpler one; if
  headers cost the flat cursor, ship the flat list and record why.**
- Inbox-zero empty state.
- README: keymap table, and a Triage section.

---

## Completion record

**Done.** 538 → 607 tests, all passing. No migration; the ledger stays at v11,
as §8 said it would.

One commit per task, in order: N1 `e90610a`, N2 `2698881`, N3 `2c95729`,
N4 `48c98c1`, N5 `fccff2f`, N6 `ac88e92`, N7 `0d787b4` + `90b6353`.

### What the plan did not anticipate

**Sections and the flat cursor collide, and the fix is to freeze the grouping.**
The plan has `AppViewModel.sections` "derived from `inbox.threads`". Derived
*live*, that is a bug: the list maps a flat row index straight into
`inbox.threads`, so the moment you star a row in the middle, a live `split`
hoists it into Important on screen while the array still holds it in place, and
the next click selects the wrong thread.

Resolved by ordering the inbox by section at reload and recording which section
each row landed in, parallel to `threads`. Sections are then a contiguous
partition of the flat list by construction —
`sections.flatMap(\.threads) == threads` always, and a test asserts it. The
consequence, which is also the better behaviour: starring does not make a row
jump out from under the cursor. The next reload lifts it into Important.
`InboxSections.ordered` is idempotent so that ordering is stable.

**Nothing was propagating the inbox's changes to the views.** `RootView`
observes `AppViewModel`; `InboxViewModel` is a separate `ObservableObject` that
nothing forwarded. The list happened to refresh because *something else* — a
sync tick, a route change — redrew the surface. A mark is a pure `InboxViewModel`
change with no such coat-tails, so `x` would have appeared to do nothing until
the next poll. `AppViewModel` now forwards `inbox.objectWillChange`, and the
table coordinator drops the selection notification that its own `updateNSView`
provoked, so the forwarding cannot loop.

**Star deliberately does not clear the marks.** §3 clears marks whenever the
list changes underneath them, and every other path obeys that. A star changes no
row's position (see above), so `toggleStarSelected` refreshes only the rows it
touched instead of reloading — otherwise starring a marked set would throw the
set away mid-gesture.

### The N7 gate, honestly

Section headers did **not** cost the flat cursor, so the fallback the plan
allowed was not needed: headers are AppKit group rows that are non-selectable,
and each thread row carries its own flat index rather than inferring one from
the row number. Headers are omitted entirely when there is one section.

The gate was "launch + look". The app builds, launches and runs clean in demo
mode, but **`screencapture` cannot run in this environment** — Screen Recording
permission is not granted, and even a full-display capture fails. So the window
image the plan intended was not available.

Two things were done instead, and both found something:

1. The row/index mapping — the part of the view the eye could not have checked,
   and the part that silently selects the wrong thread when it is wrong — is
   covered by `MessageListViewTests`.
2. The views were rendered **offscreen** into a PNG from inside the process
   (`cacheDisplay(in:to:)`), which needs no Screen Recording permission, and
   looked at. That confirmed the section headers, the star glyph, the mark
   indicator not shifting the text beside it, and the inbox-zero state. It also
   caught two rendering traps worth recording: an offscreen view has no
   appearance, so every dynamic system colour resolves invisible until
   `appearance` is set explicitly; and an `NSTableColumn` defaults to 100pt wide
   when there is no scroll view to autosize it, which looks exactly like a
   broken layout.

### Deviations from the plan, in full

- `InboxSections` gained `ordered`, `sectionID(for:)`, `title(forSection:)` and
  `group(_:by:)` beyond the plan's `split`, for the frozen grouping above.
- `AppViewModelTests` gained `sectionsAreAContiguousPartitionOfTheFlatList` and
  `starringDoesNotMakeTheRowJumpUnderTheCursor` as regression gates for it.
- `MessageListViewTests` is new (7 tests), standing in for the visual gate.
- `SelectionCursorTests` gained `orderingIsIdempotentSoTheFlatListIsStable`;
  `InboxSectionsTests` likewise.
- N5 dispatches `.toggleStar` / `.toggleMark` in `AppViewModel` because the
  switch is exhaustive and would not compile otherwise. N6 wired the rest.
- The two existing AI tests moved from `s` to the `a s` chord, as §5 requires.
- `DemoData` starts one thread starred and one `IMPORTANT`, so the split inbox
  is visible on a demo launch.

### Not done, deliberately

Pin, VIP, custom sections, select-all and range-select — all out of scope per
§7, and none of them started.
