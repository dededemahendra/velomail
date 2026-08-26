# Velo Mail — Drafts (Increment S) Design

**Date:** 2026-08-26
**Depends on:** E (compose), Q (attachments)

## 1. Why

Right now a half-written message lives only in a view model. Quit the app, or
crash it, and the message is gone with no trace and no warning.

That is data loss, which is a different category from a missing feature. Every
other gap on the roadmap costs the user convenience; this one costs them work
they already did. It goes next for that reason alone.

## 2. Local, and honest about it

This increment persists drafts **locally**. Gmail's `users.drafts` — which would
put the same half-written message on your phone — is deliberately not here.

Server-side drafts are a two-way sync: a draft has its own id, editing it is an
update rather than a create, and a draft changed on another device has to
reconcile with the one being typed here. That is its own increment with its own
failure modes. Shipping a one-way create instead would quietly litter the
account with duplicate drafts every time someone typed another sentence — worse
than not doing it.

So: the message survives a quit. It does not yet appear on your phone, and the
README says so.

## 3. One draft, resumed by composing

There is a single draft slot, not a drafts folder.

A folder implies management — listing, choosing, deleting — and a keyboard-first
client with one compose window at a time does not have several drafts to manage.
Pressing `c` resumes what you were writing; that is the whole interaction, and
it is what someone expects when they reopen the app after being interrupted.

An explicit discard exists for when the answer is "no, throw it away".

## 4. Nothing is not a draft

An untouched composer — no recipient, no subject, no body beyond the signature
that was put there automatically — is not saved. Otherwise pressing `c`, seeing
the window, and pressing Escape would leave a phantom draft to resume forever.

## 5. Attachments come along

A draft's files are stored with it, bytes and all, the same trade the outbound
queue already makes: a path would break the moment the file moved, and the
promise here is precisely that nothing is lost.

## 6. Scope

### In scope
- `StoredDraft` + `draft` table (**migration v14**).
- Autosave from the composer; resume on `c`; discard.
- Clearing the draft when the message is actually sent.
- Attachments persisted with the draft.

### Explicitly out of scope
- `users.drafts` sync — see §2.
- Multiple simultaneous drafts, or a drafts folder.
- Per-thread drafts (a half-written reply to *each* of several threads).
- Undo of a discard.

## 7. Testing

Round-tripping every field including attachments; that an empty composer saves
nothing; that sending clears the draft; that discarding clears it; and that a
reply draft comes back still attached to its thread — losing that would turn a
resumed reply into a new message to the same person, which is worse than losing
the draft.

## 8. Known limitations (deliberate, recorded)

- Drafts do not reach other devices.
- One draft at a time; starting a new compose over an unsent one replaces it.
- A discard cannot be undone.

---

## Completion record

781 → 805 tests, clean build, no warnings. Migration v14.

The increment forced a refactor worth having: `send()` and `autosave()` both
need the composer as a `Draft`, so `currentDraft()` became the single builder.
Without it the two would drift, and a draft that restored differently from what
send would have sent is exactly the bug this feature exists to prevent.

**The subtle case, and the test that pins it:** a resumed reply has no parent
`Message` in memory — only what was stored. Threading therefore has to be
restored from the draft itself, or resuming a reply silently produces a brand
new message to the same person. That is worse than losing the draft, because it
looks like it worked.

**Also deliberate:** the signature is excluded from "has the user typed
anything". It was put there by the app, so counting it would make every opened
composer leave a phantom draft.

**Not verified:** the resume-on-`c` flow on screen, since opening the composer
needs key input. Every layer beneath it is covered, including through the
assembled `AppViewModel`.
