# Velo Mail — First Real Use (Increment I) Design

**Date:** 2026-08-24
**Status:** Approved (scope)
**Depends on:** VeloCore, increment H (the app)

## 1. Why

Running the app for the first time exposed things that only matter once a real
account is attached. One is a genuine bug, two are gaps that make the promised
v1 experience incomplete.

### The bug: the app does not know its own address

`users.getProfile` returns `emailAddress` alongside `historyId`.
`BackfillService` reads the history id and **discards the address**. Meanwhile
the app's identity comes from `VELOMAIL_IDENTITY`, defaulting to
`me@example.com` — a value no user will set and every user will inherit.

That one string is used for four things:

| Used as | Consequence of it being wrong |
|---|---|
| the `From` header | Gmail rejects or rewrites the send |
| the `Message-ID` domain | replies thread badly in other clients |
| reply-all self-exclusion | you CC yourself on every reply-all |
| the sync `accountID` | state is keyed to a fictional account |

The correct value is already being fetched and thrown away. That is the fix.

### The gaps

- **A thread shows one message.** `ThreadView` renders `messages.last`. v1 scope
  says "read a thread"; showing the newest message of a five-message
  conversation is not reading a thread.
- **A reply has no quoted context.** `Draft.reply` sets headers only — a
  deliberate deferral in E, and the right one then, but it means the recipient
  gets a bare sentence with no indication of what it answers.

## 2. Scope

### In scope
- Discover the account address during backfill; persist it (migration **v8** on
  `syncState`) and use it everywhere identity is needed.
- Resolve identity *late*, so a send picks up the discovered address without the
  app being reconstructed.
- Reply quoting: an attribution line plus the parent body, quoted.
- Thread transcript: every message in the thread, newest expanded, older ones
  collapsed to a one-line summary that expands on click.

### Explicitly out of scope
- Multiple accounts (identity stays singular).
- Quote *collapsing* inside a single message body (the "show trimmed content"
  chevron). Different problem: that is parsing someone else's quoting.
- Attachments, search, drafts API — unchanged deferrals.

## 3. Late-bound identity

The address is not known at launch: it arrives with the first backfill. But
`OutboundService` is constructed at launch. Rather than rebuild the object graph
when sync completes, `identity` becomes a closure resolved at send time.

A `String` convenience initializer stays for tests and for the demo path, so the
change costs nothing at the call sites that genuinely know their identity up
front.

Fallback order at send time: the persisted profile address, then the configured
`VELOMAIL_IDENTITY`, then a placeholder. A placeholder `From` is still wrong,
but it only survives until the first successful backfill, which is seconds.

## 4. Quoting

The convention every mail client follows, and worth matching exactly because
recipients read it in *their* client, not ours:

```
On 24 Aug 2026 at 10:14, Natalie Roberts <natalie@…> wrote:
> the parent body, one "> " per line
```

Plain text gets `> ` prefixes; HTML gets `<blockquote>`. The attribution date is
formatted from the parent message, and the quoted body is the parent's — so a
reply to a reply nests naturally, because the parent body already contains its
own quote.

Quoting is opt-in at the call site (`Draft.reply(to:from:quoting:)`), because the
engine should not decide composition policy for every caller.

## 5. Transcript

Newest message expanded; older ones collapse to sender + date + snippet. That is
the shape every threaded client converges on, and it is the only one that keeps
a long conversation navigable without scrolling past history to reach the reply
you came for.

Expansion is view-model state, so it is testable: which ids are expanded, what
toggling does, and that a thread change resets it rather than leaking expansion
from the previous conversation.

## 6. Testing

- Identity: backfill persists the address; the resolver's fallback order; a send
  uses the discovered address rather than the configured one.
- Quoting: attribution format, `> ` prefixing, blockquote wrapping, nesting.
- Transcript: default expansion, toggling, reset on thread change.
- Views: unchanged policy — build, launch, look.

## 7. Known limitations (deliberate, recorded)

- Identity is discovered only by backfill; an account that never backfills keeps
  the configured fallback.
- Quoting emits the parent body verbatim; it does not trim signatures.
- Collapsed messages show the message's own snippet, which for a quoted reply
  may include quoted text.
