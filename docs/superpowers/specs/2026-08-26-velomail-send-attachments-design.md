# Velo Mail — Sending Attachments (Increment Q) Design

**Date:** 2026-08-26
**Depends on:** E (compose/send), P (reading attachments)

## 1. Why

Increment P made files arrive. This makes them leave. The asymmetry is the whole
motivation: a mail client that can save your colleague's PDF but cannot send one
back is obviously half-finished.

No migration — an outgoing attachment lives in the draft, and the draft already
has a home.

## 2. The MIME shape is the substance

A body-only message is `text/plain`, or `multipart/alternative` when it has
HTML. Adding files does **not** mean appending parts to that: it means wrapping
it.

```
multipart/mixed
├── multipart/alternative      ← the message, unchanged
│   ├── text/plain
│   └── text/html
├── application/pdf            ← a file
└── image/png                  ← another
```

Getting this wrong is the classic failure — appending file parts *inside*
`multipart/alternative` tells the recipient's client they are alternative
renderings of the same content, so it picks one and shows the PDF *instead of*
the message. The nesting is the feature.

A plain-text message with files is the same shape with `text/plain` in the first
slot instead of the nested alternative.

## 3. Bytes go in the queue, not a file path

A queued send stores the attachment content, base64, inside the payload.

The alternative is storing file paths and reading at drain time, which is
smaller and wrong: the queue's existing promise is that a send survives a
restart and a failure without losing anything. A path breaks that the moment the
user moves, renames or deletes the file between hitting send and the drain
completing — and with a ten-second undo window, that gap is real.

Cost, recorded honestly: a 20MB attachment is ~27MB of base64 in a SQLite row
until the send completes.

## 4. Refuse early rather than fail late

Gmail rejects a `messages.send` request over roughly 35MB, and base64 inflates
content by a third. So the composer enforces a limit **when the file is
attached**, not when the send fails.

Telling someone their 40MB video cannot be attached is a fine experience.
Accepting it, appearing to send, and surfacing a server error ten seconds later
after the undo window closed is not.

## 5. Filenames, again

The same discipline as P but pointed the other way: a filename going *out* is
encoded, not sanitised. Non-ASCII names get RFC 2047 encoded-words in
`Content-Disposition`, because that header is ASCII-only and a raw "résumé.pdf"
is malformed.

## 6. Scope

### In scope
- `DraftAttachment` (filename, MIME type, bytes) on `Draft`.
- `MIMEBuilder` emitting `multipart/mixed` with correct nesting.
- A total-size limit with a typed error.
- Compose: attach via the open panel, chips, remove, and the limit surfaced.

### Explicitly out of scope
- Resumable upload for large files. That is a different endpoint and a
  different failure model; the limit stands instead.
- Inline images referenced by `cid:` from the HTML body.
- Drag-and-drop onto the composer.
- Re-attaching a file from a received message without saving it first.

## 7. Testing

The MIME structure gets the most attention, because it is what other clients
parse and what is easiest to get subtly wrong: nesting with and without HTML,
boundary uniqueness between the outer and inner multiparts, encoded filenames,
and that the body survives unchanged when files are added.

## 8. Known limitations (deliberate, recorded)

- Total size is capped; no resumable upload.
- Attachment bytes sit in the mutation row until the send completes.
- No progress indication while a large message uploads.
