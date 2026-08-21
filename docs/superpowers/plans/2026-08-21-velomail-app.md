# Velo Mail Build Plan — Increment H (The App)

Spec: `docs/superpowers/specs/2026-08-21-velomail-app-design.md`

View-model tasks are red→green. View tasks are not unit-tested (see spec §7);
their gate is that the app builds, launches, and looks right.

## Target layout

`VeloCore` (lib) → `VeloUI` (lib: view models + views) → `VeloMail` (executable).
Tests for `VeloUI` live in `VeloUITests`. The split exists because SwiftPM
cannot test an executable target.

---

## H1 — Targets, bundle script, a window that opens
Package.swift gains `VeloUI`, `VeloMail`, `VeloUITests`. `Scripts/make-app.sh`
assembles `VeloMail.app` (Info.plist + binary). **Gate:** app launches.

## H2 — `AppConfig` (credentials + demo seed)  *(TDD)*
- `readsClientIDFromTheEnvironment`
- `readsClientIDFromTheConfigFile`
- `environmentWinsOverTheConfigFile`
- `missingCredentialsIsAStateNotAnError`
- `demoFlagIsOffByDefault`

## H3 — `InboxViewModel`  *(TDD)*
- `loadsThreadsFromTheStore`
- `selectsTheFirstThreadOnLoad`
- `moveDownAndUpChangeTheSelectedThread`
- `archiveRemovesTheThreadAndAutoAdvances`
- `archiveOnTheLastThreadClampsSelection`
- `archivingTheOnlyThreadClearsSelection`
- `reloadKeepsSelectionInRangeWhenSyncShrinksTheList`
- `messagesForTheSelectedThreadAreExposed`

## H4 — `AppViewModel` (routing + key dispatch)  *(TDD)*
- `startsInSetupWhenUnconfigured`
- `startsInListWhenConfigured`
- `openSelectedRoutesToTheThreadView`
- `backFromThreadReturnsToTheList`
- `composeRoutesToCompose`
- `commandPaletteOpensAndClosesOnBack`
- `archiveIsDispatchedToTheInboxViewModel`
- `keystrokesAreIgnoredWhileComposing` (so typing "e" does not archive)

## H5 — `MessageListView` (AppKit `NSTableView`)
`NSViewRepresentable`, one row per thread, sender/subject/snippet/date, selection
bound to the view model. **Gate:** renders the demo inbox.

## H6 — `ThreadView` (`WKWebView`)
Blocks remote content by default. Renders the newest message's HTML, falling
back to plain text. **Gate:** renders a demo message.

## H7 — `ComposeViewModel` + `ComposeView`  *(VM is TDD)*
- `newComposeStartsEmpty`
- `replySeedsRecipientAndSubjectFromTheMessage`
- `cannotSendWithoutARecipient`
- `sendEnqueuesADraftAndClears`
- `sendTrimsWhitespaceFromRecipients`

## H8 — `CommandPaletteView`
Wraps `CommandRegistry` from G: query field, ranked results, Enter runs the
action. **Gate:** filters as typed.

## H9 — Sign-in (`ASWebAuthenticationSession`)
`AuthCoordinator` drives PKCE + the existing `TokenService`. Setup screen when
unconfigured. **Gate:** builds; the live round-trip needs the user's client id.

## H10 — Sync lifecycle + status indicator
App owns the `GmailSync.run(interval:)` task; `SyncStatus` drives the indicator.
**Gate:** demo mode runs without a network; status renders.

---

## Out of scope for H
Code signing/notarisation, distribution, multiple accounts, attachment UI,
threaded transcript with quote collapsing, reply body quoting, search UI.
