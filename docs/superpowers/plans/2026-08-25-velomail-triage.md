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

*(to be filled in after implementation)*
