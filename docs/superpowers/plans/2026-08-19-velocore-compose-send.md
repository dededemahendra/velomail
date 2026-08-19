# VeloCore Build Plan — Increment E (Compose & Send)

Execute **top to bottom**. Every task is red→green: write the listed test cases
first, watch them fail, then implement, then run `swift test` (the whole target
must compile and be green after each task). One commit per task.

Spec: `docs/superpowers/specs/2026-08-19-velocore-compose-send-design.md`

## Migration ledger

B took `v3_create_pending_mutation`, C took `v4_add_message_labelIDs`.
E claims **`v5_add_message_reply_headers`** and registers after v4.
Never renumber a shipped identifier. **Schema tests assert by column existence,
never by migration count**, so they survive a future rebase.

## Shared-file edit ledger

| File | Tasks that touch it | Order |
|---|---|---|
| `Models/Message.swift` | E1 | once |
| `Storage/AppDatabase.swift` | E1 | once |
| `Sync/GmailMessageMapper.swift` | E1 | once |
| `Sync/GmailAPIClient.swift` (`GmailWriting`) | E4 | once |
| `Models/PendingMutation.swift` (`MutationKind`) | E5 | once |
| `Storage/MailStore.swift` | E5 | once |
| `Sync/OutboundService.swift` | E6, E7 | E6 then E7 |

---

## E1 — Reply-threading headers on `message` (migration v5)

**Tests** (`AppDatabaseTests`, `ModelCodingTests`, `GmailMessageMapperTests`)
- `messageTableHasReplyThreadingColumns` — `cc`, `messageIDHeader`, `inReplyTo`,
  `references` exist on `message`.
- `messageRoundTripsReplyHeaders` — insert/fetch preserves all four.
- `mapperPopulatesMessageIDAndInReplyToAndReferencesFromHeaders`
- `mapperParsesMultipleReferencesSeparatedByWhitespace`
- `mapperLeavesReplyHeadersEmptyWhenAbsent`

**Implementation**
- `Message`: `cc: [String]`, `messageIDHeader: String?`, `inReplyTo: String?`,
  `references: [String]`. Defaulted in `init` so existing call sites compile.
- Migration `v5_add_message_reply_headers` (4 `alter`-added columns, NOT NULL
  defaults `"[]"` for the array columns, nullable for the two scalars).
- Mapper reads `Cc`, `Message-ID`, `In-Reply-To`, `References`; `References`
  splits on whitespace.

## E2 — `Draft` + reply derivation

**Tests** (`DraftTests`)
- `replyAddressesTheSenderAndKeepsTheThread`
- `replyPrefixesSubjectWithReOnlyOnce`
- `replyChainsReferencesFromParent` — parent refs + parent Message-ID.
- `replyAllCarriesOtherRecipientsToCcExcludingSelf`
- `replyToMessageWithoutMessageIDLeavesInReplyToNil`

**Implementation** — `Models/Draft.swift`: value type + two static factories.
Pure; no storage, no network.

## E3 — `MIMEBuilder` (RFC 5322 serialization)

**Tests** (`MIMEBuilderTests`)
- `buildsPlainTextMessageWithRequiredHeaders` — From/To/Subject/Date/Message-ID/MIME-Version.
- `usesCRLFLineEndings`
- `encodesNonASCIISubjectAsRFC2047EncodedWord`
- `omitsEmptyCcAndBccHeaders`
- `emitsMultipartAlternativeWithTextPartFirstWhenHTMLPresent`
- `emitsInReplyToAndReferencesWhenReplying`
- `rawIsBase64URLWithoutPadding`

**Implementation** — `Sync/MIMEBuilder.swift`. `Date` and `Message-ID` are
injected (no ambient clock/UUID) so assertions are deterministic.

## E4 — `sendMessage` API seam

**Tests** (`GmailAPIClientWriteTests`)
- `sendMessagePOSTsRawAndThreadIDToSendEndpoint`
- `sendMessageOmitsThreadIDForNewCompose`
- `sendMessageDecodesReturnedMessageResource`
- `sendMessageMapsServerErrorToAuthError`

**Implementation** — add `sendMessage(raw:threadID:) async throws -> GmailMessageDTO`
to `GmailWriting`; implement on `GmailAPIClient` (POST `users/me/messages/send`).
Update the test doubles that conform to `GmailWriting`.

## E5 — Queue + store support for send

**Tests** (`MutationStoreTests`, `MailStoreTests`, `PendingMutationTests`)
- `sendMutationRoundTripsThroughTheQueue` — `MutationKind.send` persists.
- `deleteMessageRemovesOnlyThatMessage`
- `deleteThreadRemovesThreadAndCascadesMessages`

**Implementation** — `MutationKind.send`; `OutboundSendPayload` (draft +
placeholder message id + placeholder thread id + `createdThread` flag);
`MailStore.deleteMessage(id:)` and `MailStore.deleteThread(id:)`.

## E6 — `OutboundService.send(_:)` optimistic apply

**Tests** (`OutboundServiceTests`)
- `sendInsertsPlaceholderMessageLabelledSENTIntoExistingThread`
- `sendCreatesAPlaceholderThreadForANewCompose`
- `sendEnqueuesASendMutationCarryingTheDraft`
- `sendPlaceholderIsNotMarkedUnread`

**Implementation** — placeholder id `local:<uuid>` (uuid injected for tests),
upsert message (+ thread when new), re-derive thread, enqueue.

## E7 — `drain()` send branch

**Tests** (`OutboundServiceTests`)
- `drainSendsRawBuiltFromTheQueuedDraft`
- `drainReplacesPlaceholderWithTheRealMessageOnSuccess`
- `drainRemovesTheQueueRowOnSuccessfulSend`
- `drainRevertsPlaceholderAndMarksFailedWhenSendFails`
- `drainDropsThePlaceholderThreadWhenAFailedSendCreatedIt`
- `drainStillDrainsLabelMutationsAfterASendFailure`

**Implementation** — switch on `mutation.kind`; `.send` decodes
`OutboundSendPayload`, builds raw via `MIMEBuilder`, calls `sendMessage`,
swaps placeholder→real (mapper) or reverts. Label kinds keep their existing path.

---

## Out of scope for E (recorded, not forgotten)

- Attachments, `users.drafts.*`, scheduled send, undo-send.
- Automatic retry of `.failed` sends — belongs with the future scheduler,
  same deferral B made.
- Quoted-reply body construction (headers only; body text is the caller's).
- `KeyboardEngine` and any SwiftUI/AppKit surface — still blocked on an app
  target and real OAuth client credentials.

---

## Completion record

All seven tasks landed red→green, one commit each. Suite went 129 → 181 tests,
clean build, no warnings.

**Two defects found in the post-implementation review, each fixed with a
reproducing test first:**

1. **Thread date never moved on send.** `deriveThread` restored
   `thread.labelIDs == union(message.labelIDs)` but not
   `thread.lastMessageDate == max(message.date)`, so a thread you had just
   replied to did not sort to the top of a date-ordered inbox. `deriveThread`
   now derives both. The date got its own `MailStore` method rather than being
   folded into `updateThreadDerivedLabels`, because `LabelDeltaApplier` shares
   that call and a label delta must not move a thread's date.

2. **Stale optimistic label when Gmail rethreads.** If the server declined the
   requested `threadId` and filed the message in a new thread, the origin thread
   kept the optimistic `SENT` label after the message had left it. `applySent`
   now re-derives the origin thread whenever the server's thread differs.

**Still deferred after E** (unchanged from the plan above): attachments,
`users.drafts.*`, scheduled/undo send, automatic retry of `.failed` sends,
quoted-reply body construction, and the whole UI layer (`KeyboardEngine`,
SwiftUI/AppKit), which remains blocked on an app target and real Google OAuth
client credentials.
