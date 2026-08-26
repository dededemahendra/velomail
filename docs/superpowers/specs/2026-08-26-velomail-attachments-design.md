# Velo Mail — Attachments (Increment P) Design

**Date:** 2026-08-26
**Depends on:** storage, sync

## 1. Why

Roadmap items 30, 31, 32. Today `MailThread.hasAttachments` is a boolean derived
from the MIME tree and thrown away — the app knows a message *has* a file and
can do nothing whatsoever with it. That is the largest remaining hole in
everyday use: you cannot get a file out of your mail.

## 2. Metadata is stored; bytes are not

An attachment row records filename, MIME type, size and Gmail's `attachmentId`.
The content is fetched when the user asks for it.

The alternative — downloading during sync — is wrong on every axis that matters
here. Most attachments are never opened, a backfill of 500 messages would pull
hundreds of megabytes before the inbox is usable, and SQLite would carry it
forever. Metadata is small, searchable, and enough to render the UI.

## 3. Two kinds of part, one table

Gmail returns file parts two ways:

- **Referenced** — `body.attachmentId` set, no data. Everything of any size.
- **Inline** — `body.data` present, no `attachmentId`. Small parts, often the
  logo in a signature.

Both become rows. An inline part keeps its data, so it needs no fetch; a
referenced one records the id. `AttachmentService` handles the difference so no
caller has to know which kind it got.

## 4. Saving a file is where the danger is

A filename arrives from a stranger. `../../.ssh/authorized_keys` is a valid
string in a MIME header, and writing it where the user asked to save "invoice.pdf"
would be a real vulnerability, not a theoretical one.

So the saved name is **derived, never trusted**: path separators and traversal
segments are stripped, the result is confined to the chosen directory, and an
empty or wholly-suspicious name becomes a safe default. A collision gets a
numbered suffix rather than overwriting a file the user already had.

This is the one part of the increment with tests written primarily as attacks.

## 5. Scope

### In scope
- `Attachment` model + `attachment` table (**migration v13**).
- Mapper extracts parts; `MailStore` stores and reads them.
- `GmailReading.getAttachment(messageID:attachmentID:)`.
- `AttachmentService` — resolve data (inline or fetched), save safely.
- Thread-view chips showing name, type and size, with a save action.

### Explicitly out of scope
- **Sending** attachments. Composing one means `multipart/mixed` and an upload
  endpoint; it is its own increment and the engine's send path is body-only by
  design (increment E).
- Rendering inline images inside the message body. The thread view blocks
  remote content and inline images would need a `cid:` scheme handler.
- Attachment search by content (roadmap 31 is filename search, which FTS gives
  us; content extraction is not in scope).
- Quick Look preview.

## 6. Testing

Mapper extraction from real Gmail payload shapes (nested multiparts, inline vs
referenced, parts with no filename). Storage round-trip and cascade. Fetch
against a mock HTTP client. And the filename-safety cases as attacks:
traversal, absolute paths, empty names, collisions.

## 7. Known limitations (deliberate, recorded)

- Cannot attach files to outgoing mail.
- Fetched bytes are not cached; saving the same file twice fetches twice.
- No progress reporting on a large download.
- Inline images are listed as attachments rather than rendered in place.
