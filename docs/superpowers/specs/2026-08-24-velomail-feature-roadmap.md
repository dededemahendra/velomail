# Velo Mail — Superhuman Feature Roadmap

**Date:** 2026-08-24
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

## NOW — increment J/K (this work)

The distinctive ask: **AI that runs against an API key *or* a local model via
Ollama.** Provider is pluggable and entirely optional — with none configured the
app is exactly what it is today.

| # | Feature |
|---|---|
| 10/97 | AI Email Summarization / Thread Summaries |
| 11/16 | AI Compose / Email Drafting |
| 12 | AI Rewrite |
| 13 | AI Tone Adjustment |
| 14 | AI Grammar Correction |
| 15/96 | AI Translation |
| 91 | AI Writing Assistant |
| 94 | AI Suggested Replies |
| 95 | AI-generated Subject Lines |
| 92/93 | AI Categorization / Prioritization |
| 98 | AI Context Awareness (thread is the context) |

## NEXT — planned, nothing blocking

| # | Feature | Note |
|---|---|---|
| 8 | Instant Search | FTS5; schema was designed for it |
| 9/99 | AI Search / Natural Language Search | NL query → structured filter, then FTS5 |
| 21/22/23 | Send Later / Scheduled Send / Undo Send | queue already durable; needs a due-time |
| 24/25 | Snooze / Reminders | label + due-time, same machinery |
| 17/18/26 | Auto Follow-up / Reminders / Tracking | derived from thread state |
| 27/28/29 | Templates / Snippets / Signature | local store + compose insertion |
| 30/31/32 | Attachments / search / inline | `hasAttachments` exists; parts do not |
| 33 | Link Previews | fetch + cache, respecting the remote-content block |
| 51/52/53 | Custom Sections / Priority Inbox / VIP | query layer over labels + sender |
| 2 | Split Inbox | the same query layer, presented as sections |
| 57/58/59 | Filters / Rules / Automatic Sorting | local rule engine over incoming messages |
| 60/61 | Newsletter Management / Unsubscribe | `List-Unsubscribe` header |
| 62/63 | Blocking / Spam | filter rules + Gmail labels |
| 65/66 | Bulk Actions / Multi-select | cursor already models a list |
| 70/71 | Star / Pin | STARRED label; pin is local |
| 80/81 | Notifications | `UNUserNotificationCenter` |
| 83 | Focus Mode | suppress notifications + hide counts |
| 86 | Inbox Zero Workflow | already the triage model; needs the celebration |

## BIG — real, but each is its own project

| # | Feature | Why |
|---|---|---|
| 3 | Multiple Accounts | account id is threaded through storage but singular everywhere |
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

1. **J** — LLM provider layer (API key + Ollama). Everything AI depends on it.
2. **K** — the AI features above, as prompt templates over that layer.
3. **L** — search (FTS5) + natural-language search, which needs both J and FTS.
4. **M** — time-based actions: snooze, send later, undo send, follow-up.
5. **N** — triage surface: star/pin, multi-select, bulk actions, split inbox.
6. **O** — templates, snippets, signatures, unsubscribe.
