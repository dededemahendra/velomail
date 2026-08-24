# Velo Mail — Mail Assistant (Increment K) Design

**Date:** 2026-08-24
**Depends on:** J (provider layer)

## 1. Why

With the pipe built, every AI feature on the list is the same three steps:
select the mail that matters, phrase the ask, use the answer. The value of doing
them together is that they share those three steps — so the interesting work is
*what goes in the prompt*, and that is testable without a model.

## 2. Operations

Each maps to roadmap items:

| Operation | Roadmap |
|---|---|
| `summarize(thread:)` | 10, 97 |
| `suggestReplies(to:)` | 94 |
| `draftReply(to:instruction:)` | 11, 16, 91 |
| `rewrite(_:tone:)` | 12, 13 |
| `fixGrammar(_:)` | 14 |
| `translate(_:to:)` | 15, 96 |
| `subjectLine(for:)` | 95 |
| `triage(thread:)` | 92, 93 |

## 3. What goes in the prompt

The part worth care, for two reasons: cost and privacy. Both argue the same way,
so there is no trade-off to make.

- **Bodies are truncated** to a character budget per message. A newsletter can
  be hundreds of kilobytes; the summary does not improve past the first few
  paragraphs, and the whole thing costs money or local latency.
- **Plain text is preferred over HTML.** Markup is most of the bytes and none of
  the meaning.
- **Only the thread being asked about is sent.** No inbox-wide context, no
  cross-thread retrieval.

Truncation is visible in the prompt (`…[truncated]`) so the model knows it is
seeing part of something, rather than silently reasoning about a cut-off
sentence.

## 4. Parsing

Models do not reliably return clean JSON, and asking for it makes short outputs
worse. So:

- Single-value operations (summary, rewrite, translation, subject) return text,
  trimmed, with surrounding quotes and any "Here is the..." preamble stripped.
- List operations (suggested replies) ask for one per line and parse lines,
  tolerating `-`, `*` and `1.` bullets.
- `triage` asks for one word from a fixed set and matches leniently, defaulting
  to `normal` on anything unexpected — a mis-parse must not invent urgency.

## 5. Testing

The prompt builders are pure and get most of the tests: that the subject and
sender are present, that bodies are truncated, that HTML is not sent when text
exists, that the instruction survives. The operations are driven by a scripted
provider asserting parsing and error propagation. No network, no model.

## 6. Known limitations (deliberate, recorded)

- No streaming, so long generations appear all at once.
- No conversation memory between operations.
- Truncation is by characters, not tokens.
- `triage` is a single-shot classification with no learning from user behaviour.
