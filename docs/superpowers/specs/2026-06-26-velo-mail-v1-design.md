# Velo Mail — v1 Design

**Date:** 2026-06-26
**Status:** Approved (scope + stack)
**Platform:** macOS 14+ (developed on macOS 15.5, Intel)

## 1. Purpose

A fast, keyboard-first macOS mail client in the spirit of Superhuman. v1 delivers
the *core magic*: an inbox that feels instant and a triage flow driven entirely by
the keyboard. Everything else (snooze, send-later, snippets, AI, read tracking,
split inbox) is explicitly deferred to later phases.

The single success criterion for v1: **a single Gmail account where every common
interaction — open, navigate, read, archive, reply, send — feels instant
(<100ms perceived) and can be done without the mouse.**

## 2. Scope

### In scope (v1)
- Single Gmail account, OAuth sign-in.
- Local-first inbox: UI reads only from local storage; sync runs in background.
- Instant inbox load and scroll over large mailboxes.
- Full keyboard navigation:
  - `j` / `k` — move selection down / up
  - `Enter` / `o` — open selected thread
  - `e` — archive (mark done) + auto-advance to next thread
  - `r` — reply, `Cmd+Enter` — send
  - `c` — compose new
  - `g i` — go to inbox, `Esc` — back to list
  - `Cmd+K` — command palette (jump to any action)
- Read a thread (HTML rendering), reply, compose, send.
- Incremental background sync via Gmail API history.

### Explicitly out of scope (later phases)
Snooze, send later, follow-up reminders, snippets/templates, AI features,
read/open tracking, split inbox / auto-categorization, multiple accounts,
non-Gmail providers (IMAP/JMAP), calendar, contact enrichment, mobile/Windows.

## 3. Tech Stack

| Concern | Choice | Why |
|---|---|---|
| Language | Swift | Native, fast, first-class on macOS |
| UI (most) | SwiftUI | Fast to build, modern |
| UI (message list) | AppKit `NSTableView` via `NSViewRepresentable` | SwiftUI `List` degrades on huge mailboxes; need Superhuman-grade scroll |
| Local store | SQLite via GRDB.swift | Fast, reactive (UI auto-updates on DB change), FTS5 ready |
| Email backend | Gmail API (REST) | Simpler than IMAP; native threads/labels; history-based incremental sync |
| Auth | OAuth 2.0 via `ASWebAuthenticationSession`; tokens in Keychain | Apple-native, secure |
| Architecture | MVVM + background sync actor | Keeps UI thread free → instant feel |
| Deps | Swift Package Manager | GRDB; lightweight OAuth |
| Tests | XCTest | Engine (sync/storage) testable without UI |

**Key trade-off (accepted):** Gmail-only. Adding Outlook/iCloud later requires an
IMAP/JMAP layer. Accepted because it makes a dramatically better, faster v1 — the
same path Superhuman and Mimestream took.

## 4. Architecture

```
┌─────────────────────────────────────────────────────────┐
│                         UI (SwiftUI)                      │
│  InboxView   ThreadView   ComposeView   CommandPalette    │
│  MessageList (AppKit NSTableView)                          │
│        ▲ reads (reactive)         │ user actions          │
└────────┼───────────────────────────┼────────────────────┘
         │                            ▼
   ┌─────┴──────┐            ┌────────────────┐
   │  Storage   │◄───────────│  KeyboardEngine │ (maps keys→actions)
   │ (GRDB/SQL) │            └────────────────┘
   └─────▲──────┘                    │
         │ writes                     ▼ enqueues mutations
   ┌─────┴───────────────────────────────────┐
   │            GmailSync (background actor)   │
   │  - initial backfill (messages.list)      │
   │  - incremental (history.list)            │
   │  - outbound (send, modify labels)        │
   └─────▲────────────────────────────────────┘
         │ HTTPS
   ┌─────┴──────┐
   │  Auth      │  OAuth tokens (Keychain)
   └────────────┘
         │
    Gmail API
```

### Modules (clear boundaries, independently testable)

- **`Auth`** — OAuth flow, token refresh, Keychain storage.
  *Does:* gives a valid access token on demand. *Depends on:* Keychain, network.
- **`Storage`** — GRDB schema + typed read/write API for threads, messages, labels,
  and a sync-state table (history id, sync cursors). Exposes reactive queries.
  *Does:* persists and serves all mail data. *Depends on:* nothing (pure local).
- **`GmailSync`** — background actor. Backfill + incremental pull + outbound push.
  Reconciles API responses into `Storage`. *Depends on:* `Auth`, `Storage`, Gmail API.
- **`KeyboardEngine`** — maps key chords (incl. multi-key like `g i`) to actions;
  drives selection/auto-advance. *Depends on:* view-model action API.
- **`UI`** — SwiftUI views + view models reading `Storage`, issuing actions.

### Data flow (archive example)
1. User presses `e`. `KeyboardEngine` → `archive(currentThread)` action.
2. View model writes label change to `Storage` **immediately** (optimistic) and
   advances selection to next thread → UI updates instantly.
3. `GmailSync` picks up the queued mutation, calls Gmail `users.messages.modify`,
   reconciles result. On failure, it reverts the local change and surfaces an error.

## 5. Data Model (initial)

- **thread**: id, snippet, last_message_date, unread, has_attachments, label_ids
- **message**: id, thread_id, from, to, cc, subject, date, body_html, body_text,
  unread, label_ids
- **label**: id, name, type
- **sync_state**: account_id, history_id, last_full_sync_at, backfill_complete
- **pending_mutation**: id, kind (archive/read/send), payload, created_at, status

(FTS5 virtual table over message subject/body deferred until search phase, but
schema designed so it can be added without migration pain.)

## 6. Sync Strategy

- **Initial backfill:** page `messages.list` (INBOX) newest-first; hydrate via
  batched `messages.get` (format=full). Store as we go so the inbox populates
  progressively. Cap initial backfill (e.g. most recent N threads) for fast first
  paint; continue in background.
- **Incremental:** store latest `historyId`; poll `history.list` since last id on a
  short interval and on app focus. Apply added/removed labels and new messages.
- **Outbound:** `pending_mutation` queue drained by the sync actor; optimistic local
  apply with revert-on-failure.

## 7. Error Handling

- **Network down:** UI fully functional from local cache; sync retries with backoff;
  a subtle non-blocking status indicator shows "offline / syncing".
- **Auth expired:** silent token refresh; if refresh fails, prompt re-auth.
- **Mutation failure:** revert optimistic change, keep item, show inline error.
- **Partial backfill:** inbox usable immediately; remaining history fills in.
- **Malformed HTML email:** rendered in sandboxed `WKWebView` with remote content
  blocked by default.

## 8. Testing

- **Storage:** unit tests for schema, reads, reactive queries, mutation queue.
- **GmailSync:** tests against recorded/mocked Gmail API responses — reconciliation
  correctness (label add/remove, new message, dedupe), incremental history apply,
  outbound retry/revert. No live network in tests.
- **KeyboardEngine:** unit tests for chord parsing (`g i`), action mapping,
  auto-advance selection logic.
- **Auth:** token refresh logic tested with a mock token endpoint.
- UI is thin (reads Storage, issues actions), so most logic is covered without UI tests.

## 9. Milestones (build order)

1. **Skeleton:** Xcode project, SPM deps (GRDB), module folders, empty SwiftUI window.
2. **Storage:** schema + read/write API + tests.
3. **Auth:** OAuth sign-in, token in Keychain.
4. **GmailSync backfill:** pull recent inbox into Storage; show it in a basic list.
5. **MessageList (AppKit):** fast list, selection.
6. **KeyboardEngine + triage:** j/k/e/o/Enter, auto-advance, optimistic archive.
7. **ThreadView:** render messages (WKWebView), reply, compose, send (outbound queue).
8. **Incremental sync:** history.list polling + on-focus refresh.
9. **Command palette (`Cmd+K`).**
10. **Polish:** offline/sync indicator, error states, basic theme.

## 10. Open Questions (track, not blocking v1 start)

- Gmail API OAuth app verification: needs a Google Cloud project + consent screen;
  full mail scopes trigger Google's security review for public distribution. Fine for
  personal/dev use ("testing" mode) initially.
- Backfill cap (N threads) — tune for first-paint speed vs. completeness.
