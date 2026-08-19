# VeloCore — Compose & Send (Increment E) Design

**Date:** 2026-08-19
**Status:** Approved (scope)
**Depends on:** B (outbound queue), C (per-message labels), D (GmailSync actor)

## 1. Why

VeloCore can currently *read* (backfill + incremental history) and *triage*
(archive / mark read / mark unread via the outbound queue). It cannot **send**.
The sync-completion plan deferred this explicitly:

> **Send path** (`MutationKind.send`, RFC 2822 raw, `messages/send`) — deferred to
> a later increment that depends on B.

B has shipped. This increment closes the last functional hole in the headless
engine, and it needs no GUI and no real OAuth credentials — the whole path is
testable against `MockHTTPClient` and an in-memory database, exactly like B.

Success criterion: **compose a new message or a reply, have it applied locally
the instant the user sends, pushed to Gmail on the next drain, threaded correctly
by Gmail, and reverted cleanly if the API rejects it.**

## 2. Scope

### In scope
- `Draft` value type (to/cc/bcc, subject, text + optional HTML body, threading context).
- Reply derivation: `Draft.reply(to:from:)` and `Draft.replyAll(to:from:)`.
- RFC 5322 message serialization (`MIMEBuilder`) incl. RFC 2047 encoded-words,
  `multipart/alternative` for HTML, base64 transfer encoding, CRLF, base64url `raw`.
- Schema **v5**: reply-threading headers on `message` (`cc`, `messageIDHeader`,
  `inReplyTo`, `references`), populated by `GmailMessageMapper`.
- `GmailWriting.sendMessage(raw:threadID:)` + `GmailAPIClient` implementation
  (`users.messages.send`).
- `MutationKind.send` + `OutboundSendPayload` in the existing durable queue.
- `OutboundService.send(_:)` — optimistic local apply behind a placeholder id.
- `drain()` send branch — placeholder→real swap on success, revert on failure.

### Explicitly out of scope
- Attachments (`multipart/mixed`, upload endpoints). Body only.
- Drafts API (`users.drafts.*`) — server-side draft autosave.
- Scheduled send / undo-send window.
- Rich-text composition UI, signatures, quoted-reply body construction.
- Address-book / contact completion.

## 3. Threading (the part that is easy to get wrong)

Gmail will only staple an outgoing message onto an existing thread when **all
three** of these agree:

1. the request body carries the target `threadId`;
2. `In-Reply-To` / `References` headers reference the parent's RFC 5322
   `Message-ID` (not the Gmail message id — they are different identifiers);
3. the `Subject` matches the thread's subject.

VeloCore never stored the RFC `Message-ID` header, so today it *cannot* build a
compliant reply. Hence migration **v5** adds `messageIDHeader`, `inReplyTo` and
`references` to `message`, and the mapper populates them from the payload
headers. `cc` is added in the same migration because reply-all needs it and it is
otherwise a second migration for one column.

`References` accumulates: a reply's `References` = parent's `References` +
parent's `Message-ID`. That is what keeps a long thread intact in other clients.

## 4. Optimistic send

Triage mutations mutate rows that already exist. A send has no row yet, so the
optimistic apply must *invent* one:

1. `send(_:)` writes a placeholder `Message` whose id is `local:<uuid>`, labelled
   `SENT`, into the draft's thread (creating a placeholder thread for a fresh
   compose), re-derives the thread, and enqueues a `.send` mutation carrying the
   full draft plus the placeholder id.
2. `drain()` builds the RFC 5322 bytes, POSTs `messages/send`, and on success
   **deletes the placeholder and inserts the real message** mapped from the
   returned resource (which carries Gmail's real id, threadId and labels).
3. On API failure it deletes the placeholder (and the placeholder thread, if the
   send created it and it is now empty) and marks the mutation `.failed`.

The draft survives failure because the payload persists it, so a later UI can
re-open a failed send. Nothing is lost.

**Why a placeholder id rather than reusing the real one:** the real Gmail id does
not exist until the API answers. Using a `local:` prefix keeps the local row
addressable, makes the swap unambiguous, and can never collide with a Gmail id.

## 5. Encoding decisions

| Decision | Choice | Why |
|---|---|---|
| Line endings | CRLF | RFC 5322 requires it; Gmail is lenient but other MTAs are not |
| Transfer encoding | base64 for all bodies | Sidesteps the 998-octet line limit and 8-bit UTF-8 entirely |
| Non-ASCII headers | RFC 2047 `=?UTF-8?B?…?=` | Subject/display-name are the realistic non-ASCII cases |
| HTML body | `multipart/alternative`, text part first | Least-capable client first, per RFC 2046 |
| `raw` field | base64url, padding stripped | What `users.messages.send` expects |
| `Message-ID`, `Date` | injected, not ambient | Deterministic tests; no clock or UUID in assertions |

## 6. Testing

Everything here is pure or mock-driven — no network, no secrets:
- `MIMEBuilder` — golden-string assertions on the serialized message.
- `Draft` reply derivation — pure value-in/value-out.
- `GmailAPIClient.sendMessage` — `MockHTTPClient` asserts URL, body and decode.
- `OutboundService.send` + `drain` — in-memory `AppDatabase`, scripted writer,
  asserting the placeholder swap, the revert, and the queue transitions.

## 7. Known limitations (deliberate, recorded)

- No attachment support; a draft with attachments cannot be represented.
- Quoted-reply body text is the caller's responsibility; `reply()` sets headers
  and recipients, not body quoting.
- `replyAll` de-duplicates against the sending identity by exact address match
  only (no alias/`+tag` awareness).
- A failed send is kept in the queue as `.failed` and never retried
  automatically — retry policy belongs with the future scheduler, same as B.
