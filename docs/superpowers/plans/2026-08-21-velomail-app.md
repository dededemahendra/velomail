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

---

## Completion record

Suite went 252 → 300 tests, clean build with no warnings, and the app builds,
bundles, and launches (verified in demo mode).

**The premise was half wrong, which is the main finding.** Every prior session
recorded the app as blocked on "an Xcode app target and OAuth credentials". A
spike disproved the first half: SwiftUI, WebKit and AuthenticationServices all
build and link under SwiftPM, so an `executableTarget` plus a bundle script is
enough. Only the client id genuinely needs the user, and only for sign-in.

**Three defects found in review, each fixed with a reproducing test first:**

1. **Demo mode was unreachable.** It has no client id, so `start()` routed it to
   the setup screen — defeating the entire purpose of the flag. Only a genuinely
   unconfigured, non-demo launch shows setup now.
2. **The command palette ate its own keystrokes.** `handle` guarded Compose but
   not the palette, so typing "reply" in the search field fired `r`=reply and
   would have fired `e`=archive. Both text-field surfaces are guarded now.
3. **The inbox observation was cancelled immediately.** `observeInboxThreads`
   returns a cancellable that GRDB requires the caller to retain, and `AppHost`
   discarded it — so the list would never have repainted when sync landed rows.

**Also caught while building the list:** `MailThread` had no sender, so a row
had nothing to show. That is a genuine model gap rather than a UI detail, so it
became migration v7, derived from the newest message and refreshed by
`deriveThread`.

**Verification note:** views are not unit-tested (spec §7) and screen recording
is not permitted for this process, so no screenshot was taken. Their gate was
building, bundling, launching without error, plus end-to-end `CompositionTests`
that drive the real assembled app — triage and compose/send through the actual
composition root. A human visual pass is still worth doing.
