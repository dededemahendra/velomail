# Velo Mail — Superhuman Feature Roadmap

**Date:** 2026-08-24, revised 2026-09-01
**Purpose:** map all 100 requested features to honest status, so scope is visible
rather than implied.

Status key: **DONE** shipped · **NOW** this increment · **NEXT** planned, no
blocker · **BIG** real but multi-increment · **EXT** needs a service or platform
we do not have · **FLAG** buildable but see the note.

## Already shipped

| # | Feature | Where |
|---|---|---|
| 1 | Unified Inbox | single account, so trivially unified |
| 4 | Gmail Integration | `GmailAPIClient`, backfill + history sync |
| 6 | Keyboard Shortcuts | `KeyboardEngine`, full v1 keymap |
| 7 | Command Bar | `CommandRegistry` + `CommandPaletteView` |
| 55/56 | Email Labels / Gmail Labels | per-message `labelIDs`, delta sync |
| 64 | Archive | `OutboundService.archive`, optimistic + revert |
| 67/68 | Conversation View / Thread Management | transcript view (increment I) |
| 69 | Mark Read/Unread | `markRead` / `markUnread` |
| 72 | Dark Mode | throughout |
| 74 | Desktop App | SwiftPM + `make-app.sh` |
| 78 | Offline Support | local-first; UI reads only SQLite |
| 79 | Cross-device Sync | via Gmail history |
| 100 | Keyboard-driven Workflow | the whole point |
| 10/97, 11/16, 12, 13, 14, 15/96, 91, 94, 95, 92/93, 98 | the AI features | increment J/K — `MailAssistant` over a pluggable `LLMProvider`, hosted key or local Ollama, entirely optional |
| 8, 9/99 | Instant Search / AI Search | increment L — FTS5 + `QueryTranslator` |
| 21/22/23, 24/25, 17/18/26 | Send Later / Scheduled Send / Undo Send, Snooze / Reminders, Auto Follow-up | increment M — `dueAt` on a queued mutation, plus derived follow-ups |
| 2, 51/52, 65/66, 70, 86 | Split Inbox, Custom Sections / Priority Inbox, Bulk Actions / Multi-select, Star, Inbox Zero | increment N — a wider cursor and a frozen grouping |
| 27/28/29 | Templates / Snippets / Signature | increment O — one `SnippetLibrary` from a file; a template is a snippet with a subject |
| 60/61 | Newsletter Management / Unsubscribe | increment O — `List-Unsubscribe`, mailto through the outbound queue |
| 30/31/32 | Attachments / search / inline | increments P/Q — parts, download, send; `has:attachment` and `filename:` (2026-09-01) |
| 57/58/59, 62/63 | Filters / Rules / Sorting, Blocking / Spam | increment U — one rule engine, `rules.json`, incremental arrivals only |
| 80/81, 83 | Notifications, Focus Mode | increment R — `MailAnnouncer` + `UNUserNotificationCenter` |
| 53 | VIP | the Senders screen (`g u`) plus always-archive rules |
| 3 | Multiple Accounts | `AccountList`, per-account database and sign-in — see the caveat below |

## NEXT — planned, nothing blocking

Rewritten 2026-09-01. Everything previously in this section had shipped and was
still listed here; planning off it would have meant planning work already done.
The check that produced this list is in the note at the bottom.

| # | Feature | Note |
|---|---|---|
| 37/38 | Contacts / Profiles | People API: real names and avatars. The list's letter disc (2026-09-01) is the placeholder it replaces |
| 33 | Link Previews | fetch + cache, respecting the remote-content block |
| 71 | Pin | deliberately not built — see the FLAG note |
| — | Snippet editor | increment O ships the file and the expansion, not an editor |
| — | Second-account sign-in | switching is tested; the OAuth path for account two has never been run end to end, and needs a real Google account to exercise |

## BIG — real, but each is its own project

| # | Feature | Why |
|---|---|---|
| 5 | Outlook Integration | needs a Graph/IMAP backend beside Gmail |
| 34/35/36 | Calendar / Meeting Scheduling / Availability | a second Google API surface |
| 37/38 | Contacts Integration / Profiles | People API |
| 75 | Web App | different runtime |
| 76/77 | iOS / Android | different platforms |
| 85/87/88 | Productivity / Velocity / Response-time Analytics | derived metrics + a UI |

## EXT — needs a server we do not have

| # | Feature |
|---|---|
| 43–50 | Team Collaboration, Shared Threads, Comments, Assignments, Team Analytics, Shared Drafts, Delegation |
| 82 | Mobile Notifications |
| 84 | Work Status |
| 89 | Team Productivity Analytics |
| 90 | Email CRM-like Contact Management |
| 39 | Social Insights (third-party enrichment) |

## FLAG — buildable, with a note

| # | Feature | Note |
|---|---|---|
| 19/20/40/41/42 | Read Receipts, Read Status, Email Tracking, Open Tracking, Link Tracking | These work by embedding a per-recipient remote image or rewritten link and logging the fetch — surveillance of the recipient, without their consent, and they need a server to log to. Velo Mail already **blocks remote content** in the thread view precisely because remote images are tracking pixels; shipping open-tracking means building the thing we defend our own users against. I will build it if you want it, but I would put it behind an explicit per-message opt-in and never on by default. Worth deciding deliberately rather than by default. |
| 73 | Custom Themes | fine; just deferred behind higher-value work |
| 71 | Pin Emails | local-only; will not survive to other clients |

## Ordering

1. **J** — LLM provider layer (API key + Ollama). Everything AI depends on it. *(done)*
2. **K** — the AI features above, as prompt templates over that layer. *(done)*
3. **L** — search (FTS5) + natural-language search, which needs both J and FTS. *(done)*
4. **M** — time-based actions: snooze, send later, undo send, follow-up. *(done)*
5. **N** — triage surface: star, multi-select, bulk actions, split inbox. *(done)*
6. **O** — templates, snippets, signatures, unsubscribe. *(done)*
7. **P** — attachments: MIME parts, download, and search over them. The last
   large gap between this and a mail client you could use exclusively.


## How this file goes stale

Every row above that turned out to be wrong on 2026-09-01 was wrong in the same
direction: shipped, still listed as planned. Reading it is not enough. Before
planning an increment, check the code:

- `public func` in `Sources/VeloCore` with no caller in `Sources/VeloUI` — an
  engine capability nothing can reach. Nine have turned up this way.
- `MailAction` cases against the keymap and `CommandRegistry` — an action bound
  to nothing is unreachable by definition.
- A value written for a consumer that does not exist, and a predicate nobody
  asks. Neither shows up in an API-level sweep.

Quote the glob: `grep -r --include='*.swift'` unquoted is eaten by zsh, searches
nothing, and reports everything as unreferenced.
