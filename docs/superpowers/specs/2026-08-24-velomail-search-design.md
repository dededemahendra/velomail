# Velo Mail — Search (Increment L) Design

**Date:** 2026-08-24
**Depends on:** storage; J/K for the natural-language half

## 1. Why

Roadmap items 8 (Instant Search), 9 (AI Search) and 99 (Natural Language
Search). The v1 design anticipated this and said so:

> FTS5 virtual table over message subject/body deferred until search phase, but
> schema designed so it can be added without migration pain.

Time to collect on that. Search is also the last thing that makes a large
mailbox usable — triage handles what arrives, search handles everything that
already did.

## 2. Two layers, and why both

**Structured search** is the foundation: terms plus filters (`from:`, `is:unread`,
date range). It is fast, exact, and works with no model configured.

**Natural-language search** sits on top and does one job: turn "emails from
natalie last week about the open day" into that same structured query. It is a
*translator*, not a search engine — the LLM never sees the mailbox, only the
query string. That matters for three reasons: it is fast (one small call), it is
private (no mail content in the prompt), and it degrades cleanly (no provider
means the raw text is used as search terms, which is still useful).

## 3. The index

FTS5 standalone table over sender, subject and body text, maintained by
**SQLite triggers** on `message`.

Triggers rather than application code on purpose: the index cannot drift,
because there is no code path that can forget to update it. Backfill, incremental
sync, optimistic send and revert all write through `MailStore.upsert`, and every
one of them fires the trigger without knowing search exists.

Porter stemming, so "meeting" finds "meet". Body is indexed from `bodyText`
only — HTML markup is noise that would produce hits on `<div>`.

Migration **v9** creates the table, the triggers, and backfills what is already
stored. That last part matters: without it, search would silently return nothing
for every message that arrived before the upgrade.

## 4. Query safety

User input goes through GRDB's `FTS5Pattern` rather than into SQL. FTS5 has its
own query syntax — a stray `"` or `*` in a search box is a syntax error at best,
and the pattern API is what makes arbitrary typing safe.

## 5. Results

Search returns **threads**, not messages, because that is the unit the UI shows
and the unit a person is looking for. A thread matches if any message does, and
results are newest-first, deduplicated.

## 6. Natural-language translation

The model is asked for JSON with a fixed shape. That is the opposite of the
choice made in increment K — short prose answers there, strict JSON here —
because this output is *consumed by code*, not read by a person.

Robustness matters more than elegance: models wrap JSON in code fences and add
prose around it, so parsing extracts the first balanced JSON object rather than
assuming the whole response is clean. Anything unparseable falls back to using
the raw text as search terms, which is exactly what a search box would have done
anyway.

Today's date is put in the prompt so relative ranges ("last week") can be
resolved; the model has no clock.

## 7. Testing

- Trigger behaviour: insert, update, delete, and the migration backfill.
- Query construction: filters, safety against FTS metacharacters.
- Results: thread dedup, ordering, empty query.
- NL: prompt shape, JSON extraction from fenced and prose-wrapped output,
  fallback on garbage, and that no mail body is ever sent.

## 8. Known limitations (deliberate, recorded)

- Body indexed from plain text only; a message with HTML and no text part is
  searchable by sender and subject only.
- No search-result highlighting or snippets.
- No `has:attachment` — attachment parts are not stored yet (roadmap item 30).
- Relative dates depend on the model resolving them correctly.
