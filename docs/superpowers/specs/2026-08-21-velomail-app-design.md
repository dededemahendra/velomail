# Velo Mail — The App (Increment H) Design

**Date:** 2026-08-21
**Status:** Approved (scope)
**Depends on:** VeloCore (engine), increments E/F/G

## 1. Why, and why it is no longer blocked

Every prior session recorded the app as blocked on "an Xcode app target and real
Google OAuth credentials". Half of that was wrong. A spike confirms **SwiftUI,
WebKit and AuthenticationServices all build and link under SwiftPM** on this
machine, so no `.xcodeproj` is needed: an `executableTarget` plus a small script
that assembles a `.app` bundle is enough to produce a launchable, sandboxed-
enough macOS app.

What genuinely requires the user is **one value** — a Google Cloud OAuth client
id — and only for the sign-in step. Everything else can be built, run and
verified now.

So this increment builds the whole app, and treats the missing credential as a
first-class state rather than a reason to stop.

Success criterion: **`./Scripts/make-app.sh && open VeloMail.app` launches a
keyboard-driven mail client that reads the local store, and the only thing
standing between it and live mail is pasting a client id.**

## 2. Module layout

Splitting the app in two is what keeps it testable:

| Target | Kind | Contains |
|---|---|---|
| `VeloCore` | library | the engine (unchanged) |
| `VeloUI` | library | view models **and** views |
| `VeloMail` | executable | `@main`, ~10 lines |
| `VeloUITests` | test | view-model tests |

View models live in a library, not the executable, because SwiftPM cannot test
an executable target. That is the whole reason for the split: the logic that
decides *what the UI does* stays under test, and the SwiftUI/AppKit files stay
thin enough that not testing them is honest rather than convenient.

## 3. The credential state

`AppConfig` resolves the client id from, in order:

1. `VELOMAIL_CLIENT_ID` in the environment;
2. `~/.config/velomail/config.json`.

Missing is **not** an error and must not crash or show an empty window. The app
routes to a setup screen that says exactly what to create in Google Cloud and
where to put it. A mail client that dies because it has no credentials is worse
than one that explains itself.

`VELOMAIL_DEMO=1` seeds the local store with sample threads. This exists so the
app is runnable and reviewable *today*, without credentials and without touching
the network — and so this increment can actually be verified rather than merely
compiled.

## 4. Views

Per the v1 design, and each for a stated reason:

- **Message list — AppKit `NSTableView`** via `NSViewRepresentable`. SwiftUI
  `List` degrades on large mailboxes; the whole point of v1 is a list that stays
  instant.
- **Thread — `WKWebView`** with a configuration that blocks remote content by
  default. Mail HTML is hostile; remote images are tracking pixels.
- **Compose, palette, setup, status — SwiftUI.** Small, static, no reason to
  reach for AppKit.

## 5. Keyboard

One `NSEvent` local monitor translates to `KeyInput` and feeds the
`KeyboardEngine` built in G. The engine returns a `MailAction`; `AppViewModel`
performs it. The monitor swallows the event only when the engine handled it, so
unbound keys still reach text fields — otherwise typing in Compose would trigger
archive on every `e`.

Routing is a small explicit state machine (`list`/`thread`/`compose`/`palette`/
`setup`), because "which view is focused" decides what a keystroke means.

## 6. Sync lifecycle

The app owns a `Task` running `GmailSync.run(interval:)` from F, started once
signed in and cancelled on quit. `SyncStatus` drives a small indicator. The UI
never waits on the network: it reads `MailStore` through the existing
`observeInboxThreads` reactive query, so sync landing rows repaints the list.

## 7. Testing

- **View models** — real tests against an in-memory `AppDatabase`, exactly like
  the engine: selection, routing, action dispatch, compose validation, palette
  filtering, the unconfigured state.
- **Views** — not unit-tested. There is no UI test harness in a SwiftPM package,
  and the views hold no logic worth testing: they render a view model and send
  actions back. Verification for them is launching the app and looking at it,
  which this increment does.

## 8. Known limitations (deliberate, recorded)

- Not code-signed or notarised; `make-app.sh` produces a local development
  bundle. Distribution is out of scope.
- Single account, matching the engine.
- The thread view renders the newest message's HTML; a full threaded transcript
  with quote-collapsing is post-v1.
- No attachment UI (the engine has no attachment support either).
- Reply body quoting is not implemented; `Draft.reply` sets headers only, as
  designed in E.
