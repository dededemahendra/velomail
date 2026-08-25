# Velo Mail Build Plan — Increment O (Snippets, Signature, Unsubscribe)

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:executing-plans`
> or `superpowers:subagent-driven-development` to work this plan task by task.

**Goal:** reusable text in the composer (snippets, templates, signature) and a
one-key unsubscribe driven by the sender's own `List-Unsubscribe` header.

**Architecture:** snippets are a **file**, not a table — one `SnippetLibrary`
resolved like `LLMConfig`, with a template being a snippet that carries a
subject. Expansion is a pure function over `(text, cursor)` plus a thin adapter
that recovers the cursor from a single-character diff, because `TextEditor`
exposes no selection. Unsubscribe stores the raw header (migration v12), parses
it purely, and sends the `mailto` through the existing outbound queue so
`Cmd+Z` takes it back.

**Tech stack:** Swift 5.9, SwiftPM, GRDB, Swift Testing. macOS 14.

**Spec:** `docs/superpowers/specs/2026-08-25-velomail-snippets-design.md`

## Global Constraints

- No `.xcodeproj`. Build and test with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- Swift Testing (`@Test`/`@Suite`/`#expect`), never XCTest.
- Red→green, **one commit per task**, message prefixed `feat:`/`fix:`/`docs:`
  and suffixed with the task id, e.g. `(O3)`.
- Migration ledger: N claimed none, so v11 is the head. **O claims v12 only**,
  for `message.listUnsubscribe`. Snippets take no migration (spec §3).
- Baseline: 607 tests, all passing.
- New engine types go in `Sources/VeloCore/Models/`; they must not import
  AppKit, SwiftUI or GRDB.
- Do **not** push to origin. Leave the uncommitted `README.md` change alone
  until O7, which edits that same file.

---

## O1 — The snippet library is a file

**Files:**
- Create: `Sources/VeloCore/Models/Snippet.swift`
- Test: `Tests/VeloCoreTests/SnippetLibraryTests.swift`

**Produces:**

```swift
public struct Snippet: Codable, Equatable, Sendable {
    public var name: String
    public var shortcut: String
    /// Non-nil makes it a template: it fills an empty subject too.
    public var subject: String?
    public var body: String
    public init(name: String, shortcut: String, subject: String? = nil, body: String)
}

public struct SnippetLibrary: Equatable, Sendable {
    public let signature: String?
    public let snippets: [Snippet]
    public init(signature: String? = nil, snippets: [Snippet] = [])
    public static let empty: SnippetLibrary
    public func snippet(forShortcut shortcut: String) -> Snippet?
    public static var defaultFile: URL          // ~/.config/velomail/snippets.json
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               file: URL? = defaultFile) -> SnippetLibrary
}
```

`init` normalises, so every construction path — file, test, or caller — obeys
the same rules: shortcuts trimmed; blank shortcut or blank body dropped; first
of a duplicated shortcut wins; a blank signature becomes `nil`. Matching in
`snippet(forShortcut:)` is case-insensitive on a trimmed needle.

`resolve` reads `VELOMAIL_SIGNATURE` first, then the file, mirroring
`LLMConfig.resolve`. A missing or malformed file resolves to `.empty`, never
an error.

File shape (`snippets.json`):

```json
{
  "signature": "Warren Roberts\nLiving Legacy Forest",
  "snippets": [
    { "name": "Thanks", "shortcut": "thx", "body": "Thanks so much." },
    { "name": "Intro", "shortcut": "intro", "subject": "Intro call?", "body": "Does Thursday suit?" }
  ]
}
```

**Tests** (`SnippetLibraryTests`)
- `anEmptyLibraryHasNothingInIt`
- `aSnippetIsFoundByItsShortcut`
- `shortcutMatchingIsCaseInsensitive`
- `shortcutsAreTrimmedOnConstruction`
- `aSnippetWithABlankShortcutIsDropped`
- `aSnippetWithABlankBodyIsDropped`
- `theFirstOfTwoSnippetsSharingAShortcutWins`
- `aBlankSignatureIsNoSignature`
- `anUnknownShortcutFindsNothing`
- `aTemplateKeepsItsSubject`
- `aFileWithASignatureAndSnippetsLoadsBoth`
- `aMissingFileResolvesToAnEmptyLibrary`
- `aMalformedFileResolvesToAnEmptyLibraryRatherThanThrowing`
- `theEnvironmentSignatureOverridesTheFile`

Write the file-backed tests against a temp URL from
`FileManager.default.temporaryDirectory`, and delete it afterwards.

---

## O2 — Expansion is pure

**Files:**
- Create: `Sources/VeloCore/Models/SnippetExpansion.swift`
- Test: `Tests/VeloCoreTests/SnippetExpansionTests.swift`

**Consumes:** `SnippetLibrary`, `Snippet` (O1).

**Produces:**

```swift
public enum SnippetExpansion {
    public struct Expansion: Equatable, Sendable {
        public let text: String
        public let snippet: Snippet
    }

    /// Expands the `;shortcut` ending at `cursor` (a character offset).
    public static func expand(in text: String, at cursor: Int,
                              using library: SnippetLibrary) -> Expansion?

    /// The same for the single character just typed. Nil unless exactly one
    /// character was inserted and it is a space, tab or newline.
    public static func expandOnTyping(previous: String, current: String,
                                      using library: SnippetLibrary) -> Expansion?
}
```

`expand` scans backwards from `cursor` for a `;`, giving up at the first
whitespace. The `;` must start a word (index 0, or preceded by whitespace); the
token between it and the cursor must be non-empty; the match must be exact.
On a hit the token *including* the `;` is replaced by the snippet body.

`expandOnTyping` requires `current.count == previous.count + 1` and that the
insertion is a single character — take the common prefix length `p`, check that
`current` minus the character at `p` equals `previous`, check that character is
a boundary, then call `expand(in: current-without-that-character, at: p)`. The
boundary is consumed, which falls out of removing it before expanding.

**Tests** (`SnippetExpansionTests`)
- `aShortcutAtTheCursorExpands`
- `expansionKeepsTheTextAfterTheCursor`
- `matchingIsCaseInsensitive`
- `anUnknownShortcutDoesNotExpand`
- `aSemicolonAloneDoesNotExpand`
- `aSemicolonMidWordIsNotAToken`
- `aTokenPrecededByWhitespaceExpands`
- `expansionReportsTheSnippetItUsed`
- `anEmptyLibraryNeverExpands`
- `typingASpaceAfterAShortcutExpandsAndEatsTheSpace`
- `typingANewlineAfterAShortcutExpands`
- `typingATabAfterAShortcutExpands`
- `typingAnOrdinaryCharacterDoesNotExpand`
- `aPasteIsNotTyping`
- `aDeletionIsNotTyping`
- `typingABoundaryIntoTheMiddleExpandsTheTokenThere`

---

## O3 — The composer uses it

**Files:**
- Modify: `Sources/VeloUI/ComposeViewModel.swift`
- Test: `Tests/VeloUITests/ComposeViewModelTests.swift`

**Consumes:** `SnippetLibrary` (O1), `SnippetExpansion` (O2).

`ComposeViewModel.init` gains `library: SnippetLibrary = .empty` on both
initialisers, kept as `private let library`.

`body` becomes an observed property:

```swift
@Published public var body: String = "" {
    didSet { expandIfTyped(from: oldValue) }
}
private var isExpanding = false
```

`expandIfTyped` returns immediately when `isExpanding`, otherwise asks
`SnippetExpansion.expandOnTyping`; on a hit it sets `isExpanding = true`,
assigns `body = expansion.text`, clears the flag, and — only when
`expansion.snippet.subject` is non-nil and `subject` is empty — sets `subject`.

Signature placement, using
`private var signatureBlock: String { library.signature.map { "\n\n" + $0 } ?? "" }`:

- `startNew()` — `body = signatureBlock`
- `startReply(to:)` — `body = signatureBlock + "\n\n" + QuotedReply.text(quoting: message)`

With no signature `signatureBlock` is `""`, so both are byte-for-byte what they
are today. **The existing `ComposeViewModelTests` must pass unchanged** — that
is the regression gate.

**Tests** (`ComposeViewModelTests`, added to the existing suite; extend
`makeContext` with a `library: SnippetLibrary = .empty` parameter)
- `aNewMessageStartsWithTheSignature`
- `aReplyPutsTheSignatureAboveTheQuote`
- `typingABoundaryAfterAShortcutExpandsTheBody`
- `expandingATemplateFillsAnEmptySubject`
- `expandingATemplateLeavesANonEmptySubjectAlone`
- `expandingAPlainSnippetLeavesTheSubjectAlone`
- `anUnknownShortcutIsLeftAlone`
- `theSignatureGoesOutWithTheDraft`

---

## O4 — The header is stored (migration v12)

**Files:**
- Modify: `Sources/VeloCore/Models/Message.swift`
- Modify: `Sources/VeloCore/Storage/AppDatabase.swift`
- Modify: `Sources/VeloCore/Sync/GmailMessageMapper.swift`
- Test: `Tests/VeloCoreTests/AppDatabaseTests.swift`,
  `Tests/VeloCoreTests/ModelCodingTests.swift`,
  `Tests/VeloCoreTests/MailStoreTests.swift`,
  `Tests/VeloCoreTests/GmailMessageMapperTests.swift`

`Message` gains `public var listUnsubscribe: String?`, last in the member list
and last in `init` with a `= nil` default so no existing call site changes.

```swift
migrator.registerMigration("v12_add_message_listUnsubscribe") { db in
    try db.alter(table: "message") { t in
        t.add(column: "listUnsubscribe", .text)
    }
}
```

`GmailMessageMapper.message(from:)` maps it with the existing
`header("List-Unsubscribe")` helper. The **raw header string** is stored; parsing
belongs to O5.

**Tests**
- `AppDatabaseTests.messageTableHasAListUnsubscribeColumn`
- `ModelCodingTests.aMessageRoundTripsItsListUnsubscribeHeader`
- `MailStoreTests.theListUnsubscribeHeaderSurvivesAStoreRoundTrip`
- `GmailMessageMapperTests.theListUnsubscribeHeaderIsMapped`
- `GmailMessageMapperTests.aMessageWithoutTheHeaderHasNoListUnsubscribe`

---

## O5 — Parsing the header

**Files:**
- Create: `Sources/VeloCore/Models/Unsubscribe.swift`
- Test: `Tests/VeloCoreTests/UnsubscribeTests.swift`

**Consumes:** `Draft` (increment I).

**Produces:**

```swift
public enum UnsubscribeLink: Equatable, Sendable {
    case mailto(address: String, subject: String?, body: String?)
    case web(URL)
}

public enum Unsubscribe {
    public static func links(in header: String) -> [UnsubscribeLink]
    /// The first mailto, else the first web link.
    public static func preferred(in header: String) -> UnsubscribeLink?
    /// The mail that performs a mailto unsubscribe. Nil for a web link.
    public static func draft(for link: UnsubscribeLink) -> Draft?
}
```

Parsing, tolerant of real-world headers: take every `<…>` group; if there are
none, split the header on `,` and trim. For each candidate, match the scheme
case-insensitively — `mailto:` splits address from an optional `?k=v&k=v` query
whose `subject` and `body` values are percent-decoded (`+` is **not** treated as
a space; RFC 6068 says it is literal); `http:`/`https:` become `.web` via
`URL(string:)`; anything else is skipped rather than failing the header.

`draft(for:)` on a mailto returns
`Draft(to: [address], subject: subject ?? "Unsubscribe", bodyText: body ?? "Unsubscribe")`
and on a `.web` returns `nil`.

**Tests** (`UnsubscribeTests`)
- `aSingleWebLinkIsParsed`
- `aSingleMailtoIsParsed`
- `bothLinksAreParsedInHeaderOrder`
- `aMailtoSubjectIsPercentDecoded`
- `aMailtoBodyIsParsed`
- `angleBracketsAreOptional`
- `whitespaceAndNewlinesAreTolerated`
- `anUnknownSchemeIsSkippedRatherThanFailingTheHeader`
- `anEmptyHeaderHasNoLinks`
- `mailtoIsPreferredOverTheWebLink`
- `theWebLinkIsUsedWhenThereIsNoMailto`
- `aDraftIsBuiltFromAMailtoLink`
- `aDraftUsesTheHeadersSubjectWhenItHasOne`
- `aWebLinkHasNoDraft`

---

## O6 — `u` unsubscribes

**Files:**
- Modify: `Sources/VeloCore/Input/MailAction.swift`,
  `Sources/VeloCore/Input/KeyboardEngine.swift`,
  `Sources/VeloCore/Input/CommandRegistry.swift`
- Modify: `Sources/VeloUI/AppViewModel.swift`, `Sources/VeloUI/Composition.swift`
- Test: `Tests/VeloCoreTests/KeyboardEngineTests.swift`,
  `Tests/VeloCoreTests/CommandRegistryTests.swift`,
  `Tests/VeloUITests/AppViewModelTests.swift`

`MailAction.unsubscribe`; `KeyInput(.character("u")): .unsubscribe`;
`Command(title: "Unsubscribe", action: .unsubscribe)` in `CommandRegistry.v1`.
`everyV1ActionIsReachableFromThePalette` is the gate — this task cannot compile
green without the palette entry.

`AppViewModel`:

```swift
/// How a web unsubscribe link is opened. Injected so a test never launches a
/// browser.
public var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

public func unsubscribeSelected() {
    guard let header = inbox.selectedMessages.reversed().compactMap(\.listUnsubscribe).first,
          let link = Unsubscribe.preferred(in: header) else { return }
    switch link {
    case .mailto:
        guard let draft = Unsubscribe.draft(for: link),
              let queued = try? outbound.send(draft, after: Self.undoWindow) else { return }
        holdUndo(queued)
    case let .web(url):
        openURL(url)
    }
}
```

Extract the undo-window bookkeeping already inside `send()` into
`private func holdUndo(_ queued: Int64)` — it sets `undoableSend` and schedules
`expireUndo` — and call it from both, so the two paths cannot drift.
`perform` gains `case .unsubscribe: unsubscribeSelected()`. Requires
`import AppKit` in `AppViewModel.swift`.

`selectedMessages` is date-ascending, so `.reversed()` is newest-first: the
newest message that carries a header wins.

`AppViewModel.init` (both) gain `snippets: SnippetLibrary = .empty`, passed to
`ComposeViewModel`. `Composition.make` gains a `snippets: SnippetLibrary =
.resolve()` parameter and passes it to both `AppViewModel` constructions.

**Tests**
- `KeyboardEngineTests.uUnsubscribes`
- `CommandRegistryTests.unsubscribeIsInThePalette`
- `AppViewModelTests.unsubscribeQueuesTheMailto`
- `AppViewModelTests.unsubscribeOpensTheWebLinkWhenThereIsNoMailto`
- `AppViewModelTests.unsubscribeDoesNothingWithoutTheHeader`
- `AppViewModelTests.aQueuedUnsubscribeCanBeUndone`
- `AppViewModelTests.unsubscribeUsesTheNewestMessageCarryingAHeader`
- `AppViewModelTests.unsubscribeDoesNotArchiveTheThread`

---

## O7 — Views, demo data, README  *(view; gate is launch + offscreen render)*

**Files:**
- Modify: `Sources/VeloUI/ThreadView.swift`, `Sources/VeloUI/DemoData.swift`,
  `README.md`
- Test: `Tests/VeloUITests/AppViewModelTests.swift` (demo assertions only)

- `ThreadView` shows an **Unsubscribe** affordance in the thread header when any
  message in the open thread carries a `List-Unsubscribe` header, wired to
  `AppViewModel.unsubscribeSelected()`. Absent otherwise — an always-visible
  button that usually does nothing is worse than no button.
- `DemoData` seeds one newsletter thread carrying both a `mailto:` and an
  `https:` unsubscribe link, so `u` is exercisable on a demo launch.
- `README.md`: a **Snippets, templates and signature** section with the
  `snippets.json` example and the `;shortcut`+boundary gesture; an
  **Unsubscribe** note covering the mailto preference and the undo window; `u`
  added to the keymap table; the test count updated.

The gate is a launch plus an **offscreen** render (`cacheDisplay(in:to:)` from
inside the process — `screencapture` needs Screen Recording permission this
environment does not grant). Set `view.appearance = NSAppearance(named: .aqua)`
or every dynamic system colour resolves invisible.

Leave the pre-existing uncommitted `README.md` edit intact; add to it, do not
revert it.

---

## Self-review notes

- Spec §2 → O1 (`Snippet`, template = subject). §3 → O1 (file, normalisation).
  §4 → O2 (both functions, every rule is a named test). §5 → O3 (signature in
  the draft, both placements, regression gate). §6 → O5 + O6 (parse, prefer
  mailto, undo window, no archive — `unsubscribeDoesNotArchiveTheThread` pins
  it). §7 → O4 (v12, raw header). §8 → O6 (`u`, palette, no compose binding).
  §9 → the test lists. §10 → nothing built.
- Names used downstream are defined upstream: `SnippetLibrary.empty`,
  `snippet(forShortcut:)`, `SnippetExpansion.Expansion.text/.snippet`,
  `Unsubscribe.preferred(in:)`, `Unsubscribe.draft(for:)`,
  `Message.listUnsubscribe`, `AppViewModel.openURL`, `holdUndo(_:)`.
