# Velo Mail — Snippets, Signature and Unsubscribe (Increment O) Design

**Date:** 2026-08-25
**Depends on:** B (outbound queue), G (keyboard), I (compose), N (triage)

## 1. Why

Roadmap items 27/28/29 (Templates, Snippets, Signature) and 60/61 (Newsletter
Management, Unsubscribe). Five items, two mechanisms.

The first four are all "reusable text that goes into a draft". The fifth is the
one gesture a keyboard-first client owes a mailbox full of newsletters: get me
off this list without leaving the keyboard.

## 2. A template is a snippet with a subject

The roadmap lists Templates, Snippets and Signature as three features. Built as
three, they are three stores, three editors and three insertion paths that drift.

They are one piece of data — a named piece of text — differing only in *when* it
goes in:

| | carries a subject | inserted |
|---|---|---|
| Snippet | no | where you type its shortcut |
| Template | yes | where you type its shortcut; fills an empty subject too |
| Signature | no | automatically, on every draft you start |

So there is one record:

```swift
public struct Snippet: Codable, Equatable, Sendable {
    public var name: String
    public var shortcut: String
    public var subject: String?
    public var body: String
}
```

and a template is a `Snippet` whose `subject` is non-nil. That is the whole
distinction, and it deletes a picker UI, a route and a view: you reach a template
the same way you reach a snippet, by typing its shortcut. Nothing new to learn.

The signature is *not* in that list. It is a single value, not a library entry,
so it sits beside the list rather than in it as a flagged member — an
`isSignature` boolean would admit a "two signatures" state the schema then has to
forbid, and forbidding states you can simply not represent is wasted work.

## 3. Snippets are a file, not a table

Every other thing the user provides this app — the OAuth client id, the LLM
provider, the identity — arrives through the environment and then
`~/.config/velomail/`. Snippets follow the same grain:

```json
{
  "signature": "Warren Roberts\nLiving Legacy Forest",
  "snippets": [
    { "name": "Thanks",     "shortcut": "thx",   "body": "Thanks so much — I'll come back to you today." },
    { "name": "Intro call", "shortcut": "intro", "subject": "Intro call?",
      "body": "Would a 20 minute call this week suit?" }
  ]
}
```

`SnippetLibrary.resolve(environment:file:)` reads `VELOMAIL_SIGNATURE` then the
file, exactly as `LLMConfig.resolve` does. A missing or malformed file resolves
to an **empty library**, never an error: a typo in a snippets file must not stop
a mail client launching.

This costs no migration, no store, no editor UI, and no schema version. The
ledger stays at v11 for snippets — see §7 for the one migration this increment
does take, which is for unsubscribe.

**An in-app snippet editor is deliberately not built.** It is a real feature and
a real amount of view code, and it can be added later over exactly this model
without changing how expansion works. Shipping the *expansion* — the part that
saves keystrokes every day — before the *editor* is the right order; an editor
with nothing to expand into would have been the wrong one.

The library normalises on load, because a hand-edited file is a hostile input:

- shortcuts are trimmed and compared case-insensitively;
- a snippet with a blank shortcut or a blank body is dropped;
- on duplicate shortcuts the first wins, so the file reads top-down;
- a blank signature is `nil`, not `""`.

## 4. Expansion happens on a boundary, not on a key

The compose body is a SwiftUI `TextEditor` bound to `ComposeViewModel.body`.
It offers no selection or cursor API, so "expand at the cursor when I press Tab"
cannot be built without replacing the editor with an `NSTextView` — a change far
larger than the feature.

There is a better trigger anyway, and it is what every text expander uses: expand
when the user types a **word boundary** after a complete shortcut.

The cursor is then recoverable without the editor's help. `body` is `@Published`;
its `didSet` sees both the old and the new string, and a single inserted
character identifies its own position:

```
previous:  "Hi — ;thx"
current:   "Hi — ;thx "        one character inserted at offset 9
                     ^ the insertion point is the cursor
```

So the pure core takes a cursor, and a thin adapter recovers one from a diff:

```swift
public enum SnippetExpansion {
    /// Expands the `;shortcut` ending at `cursor`, if there is one.
    public static func expand(in text: String, at cursor: Int,
                              using library: SnippetLibrary) -> Expansion?

    /// The same, for the single character just typed. Nil unless exactly one
    /// character was inserted and it is a word boundary.
    public static func expandOnTyping(previous: String, current: String,
                                      using library: SnippetLibrary) -> Expansion?
}
```

`Expansion` carries the new text and the snippet that produced it, so the caller
can also fill the subject.

Rules, all of which are tests:

- The token is `;` plus the characters up to the cursor, and the `;` must start a
  word — preceded by whitespace or by nothing at all. `foo;thx` is not a token,
  because a semicolon mid-word is punctuation.
- A token containing whitespace is not a token. `;` alone is not a token.
- Matching is case-insensitive and must be **exact**. A prefix match would expand
  `;th` into whatever `;thx` holds, which is guessing.
- No match returns nil and the typed character stands. Expansion never eats input
  it did not recognise.
- A boundary is a space, a tab or a newline, and it is **consumed**. A snippet
  ends with its own punctuation far more often than it wants a trailing space,
  and "the trigger disappears" is a rule you learn once.
- Only `subject == nil` snippets leave the subject alone; a template fills it
  **only when it is empty**, so expanding a template into a reply cannot silently
  rewrite `Re: …`.

Restricting the adapter to a single inserted character is what keeps it honest.
A paste, a deletion, or a programmatic assignment (`startReply` writing the quote
block) is not typing, so it cannot trigger an expansion.

## 5. The signature goes in the draft, not on the wire

Two places could append a signature: `ComposeViewModel` when a draft starts, or
`OutboundService` at send time.

It goes in the draft. What the user sees is what gets sent — the same argument
increment I already settled for reply quoting, which put the quote in the editor
rather than adding it during `send()`. A signature the user cannot see, edit or
delete before sending is a surprise, and surprises in outgoing mail are expensive.

Placement:

- **New message** — two blank lines, then the signature. The cursor starts at the
  top, so the signature is below what you are about to write.
- **Reply** — two blank lines, the signature, then the quoted parent. Signature
  above the quote is where every client puts it and where every reader looks.

With no signature configured, both are byte-for-byte what they are today. That is
the regression gate: the existing compose tests must pass unchanged.

## 6. Unsubscribe is the sender's own instruction

`List-Unsubscribe` (RFC 2369) is a header the sender writes, declaring how to
leave the list:

```
List-Unsubscribe: <https://example.com/u/abc123>, <mailto:leave@example.com?subject=unsubscribe>
```

Velo Mail prefers the **mailto** when there is one:

- it is a channel the sender declared, and it works without a browser;
- it goes out through the existing outbound queue, so it is durable across a
  restart, retried with backoff, and **cancellable for ten seconds with `Cmd+Z`**
  exactly like any other send;
- it keeps the gesture entirely inside the app, which is the point of the app.

Falling back to the `https` link opens the browser, because completing a web
unsubscribe form is not something a mail client can or should do on the user's
behalf. RFC 8058 one-click POST is **not** implemented: it is an unauthenticated
HTTP write to an arbitrary URL taken from untrusted mail, and the mailto path
already gets the same result through machinery that can be undone.

### Unsubscribe does not archive

The tempting version of the gesture is "unsubscribe and archive, one key". It is
rejected: they are different decisions — you often want off the list *and* still
want to read this issue — and coupling them makes `Cmd+Z` ambiguous about which
half it takes back. `u` unsubscribes. `e` archives, and it is the next key over.

### Parsing

```swift
public enum UnsubscribeLink: Equatable, Sendable {
    case mailto(address: String, subject: String?, body: String?)
    case web(URL)
}

public enum Unsubscribe {
    public static func links(in header: String) -> [UnsubscribeLink]
    public static func preferred(in header: String) -> UnsubscribeLink?
    public static func draft(for link: UnsubscribeLink) -> Draft?
}
```

Tolerant, because real headers are not: angle brackets optional, whitespace and
newlines anywhere, unknown schemes skipped rather than failing the whole header,
`?subject=` and `?body=` percent-decoded. `preferred` is the first mailto, else
the first web link.

## 7. The one migration: v12

The thread view reads stored `Message` rows, so the header has to be stored.
Migration **v12** adds `message.listUnsubscribe TEXT` and `GmailMessageMapper`
maps it. The **raw header string** is stored, not the parsed link: the database
stays dumb, and parsing can improve without a migration.

Storing it also gives newsletter detection for free — a message with the header
*is* a bulk mailing, by the sender's own admission — which is roadmap item 60
without a classifier.

## 8. The keymap

`u` → `.unsubscribe`. Single key, and safe to make one because:

- it is a no-op on any thread whose messages carry no `List-Unsubscribe`, which
  is nearly all of them;
- the mailto goes through the ten-second undo window.

Palette gains "Unsubscribe". `CommandRegistryTests.everyV1ActionIsReachableFrom
ThePalette` asserts the registry covers `MailAction.allCases`, so that entry is
not optional — the test is the gate.

Snippet expansion gets **no keybinding at all**. Compose owns the keyboard while
it is open (`AppViewModel.handle` lets only Escape through), and expansion is a
text-editing gesture, not a mail action. It belongs to the editor.

## 9. Testing

Pure and file-backed throughout, so nearly all of it is unit-testable with no
database and no network:

- `SnippetLibraryTests` — parsing, normalisation, precedence, malformed input.
- `SnippetExpansionTests` — token scanning, boundaries, case, misses, templates.
- `UnsubscribeTests` — header parsing, preference, draft construction.
- `ComposeViewModelTests` — signature placement, expansion through `body`,
  subject filling, and the unchanged no-signature behaviour.
- `GmailMessageMapperTests` / `MailStoreTests` / `ModelCodingTests` — the header
  survives the wire, the schema and the codable round trip.
- `AppViewModelTests` — `u` picks the right link, queues a cancellable send for
  a mailto, opens the URL for a web link, and does nothing when there is no
  header. The URL opener is injected, so no browser launches in a test.

## 10. Out of scope, deliberately

- **In-app snippet editor** (§3) — later, over this model.
- **RFC 8058 one-click POST** (§6) — a write to an untrusted URL.
- **Bulk unsubscribe across a sender's mail** — needs a sender-grouped view that
  does not exist; the marks from increment N would make it cheap later.
- **Attachments in snippets** — the MIME layer has no attachment support yet.
- **Sender-specific signatures** — one account, so one signature.
