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
