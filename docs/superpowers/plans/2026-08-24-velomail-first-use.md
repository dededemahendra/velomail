# Velo Mail Build Plan — Increment I (First Real Use)

Spec: `docs/superpowers/specs/2026-08-24-velomail-first-use-design.md`
Red→green, one commit per task. Migration ledger: F took v6, H took v7.
I claims **`v8_add_syncstate_email`**.

## I1 — Backfill discovers and persists the account address
**Tests** (`AppDatabaseTests`, `SyncStateStoreTests`, `BackfillServiceTests`)
- `syncStateTableHasAnEmailAddressColumn`
- `syncStateRoundTripsEmailAddress`
- `backfillPersistsTheProfileEmailAddress`
- `backfillKeepsTheEmailAddressOnASecondRun`

## I2 — Late-bound identity on `OutboundService`
**Tests** (`OutboundServiceTests`)
- `identityIsResolvedAtSendTimeNotConstructionTime`
- `stringInitializerStillWorks`

## I3 — Identity resolver in the app
**Tests** (`IdentityResolverTests`)
- `prefersThePersistedProfileAddress`
- `fallsBackToTheConfiguredIdentity`
- `fallsBackToAPlaceholderWhenNothingIsKnown`

## I4 — Reply quoting
**Tests** (`QuotedReplyTests`, `DraftTests`)
- `attributionNamesTheSenderAndDate`
- `plainTextIsPrefixedWithAngleBrackets`
- `htmlIsWrappedInABlockquote`
- `quotingIsOptIn`
- `nestedRepliesKeepTheOuterQuote`

## I5 — Thread transcript state
**Tests** (`ThreadTranscriptTests`)
- `theNewestMessageStartsExpanded`
- `olderMessagesStartCollapsed`
- `togglingExpandsAndCollapses`
- `changingThreadResetsExpansion`
- `aSingleMessageThreadIsExpanded`

## I6 — `ThreadView` renders the transcript  *(view; gate is launch + look)*

---

## Completion record

304 → 343 tests, clean build, verified by launching and looking.

**The headline fix was a bug the tests could never have caught**, because it was
about a value nobody had told the tests was wrong: the app did not know its own
address. `users.getProfile` returns `emailAddress` and backfill discarded it, so
identity fell back to a hardcoded `me@example.com` — the `From` on every send,
the `Message-ID` domain, the reply-all self-exclusion and the sync account id.
Now discovered from Gmail (migration v8) and resolved *late*, since the answer
arrives with the first backfill, after the object graph is built.

**Found while looking at the running app:**

- Rewriting `ThreadView` as a transcript silently dropped the **subject** from
  the thread pane. Restored as a thread-level header, above the messages rather
  than repeated in each one.
- Long senders (`Name <addr>`) wrapped to two lines in every collapsed row.
  Display name only when collapsed; the full address earns its space once
  opened. The list's `displayName`/`shortDate` helpers moved to a shared
  `MailFormatting` rather than being duplicated.

Demo data gained a three-message conversation, ordered newest so the transcript
is what you land on — otherwise the multi-message path was never visible when
reviewing the app.

**Still not verified:** synthetic input (Accessibility permission), so
click-to-expand is covered by `ThreadTranscriptTests` rather than by driving it.

**Deferred, unchanged:** attachments, drafts API, scheduled/undo send, search,
multiple accounts, quote *collapsing* inside a body (parsing someone else's
quoting is a different problem), signature trimming.
