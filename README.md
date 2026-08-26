# Velo Mail

A keyboard-first macOS Gmail client, in the spirit of Superhuman.

- **`VeloCore`** — the headless engine: OAuth, SQLite storage (GRDB), Gmail sync
  (backfill + incremental history), an outbound queue with optimistic apply and
  revert, RFC 5322 compose/send, a polling scheduler with backoff, and the
  keyboard/selection model. No UI, no network in tests.
- **`VeloUI`** — view models and views.
- **`VeloMail`** — the app.

821 tests, no XCTest, no `.xcodeproj`.

## Build and run

```bash
./Scripts/make-app.sh          # assembles VeloMail.app
open VeloMail.app
```

### Look around first, without an account

```bash
VELOMAIL_DEMO=1 VeloMail.app/Contents/MacOS/VeloMail
```

Demo mode seeds an in-memory mailbox. Nothing touches the network and nothing
is persisted.

### Connect a real account

You need a Google Cloud OAuth client id. In
[console.cloud.google.com](https://console.cloud.google.com) → APIs & Services:

1. Enable the **Gmail API**.
2. Credentials → Create credentials → **OAuth client ID** → type **iOS**, bundle ID
   `co.sistercreatives.velomail`.

   Not *Desktop app*: Velo Mail signs in through `ASWebAuthenticationSession`
   with a custom URI scheme, and Google only accepts that for an iOS client —
   where the scheme must be the reversed client id. A Desktop client accepts
   loopback only, and would need a local HTTP server to catch the redirect.
   The app derives the right redirect URI from your client id, so there is
   nothing to configure.
3. On the consent screen, add yourself as a test user (the `gmail.modify` scope
   needs Google's review before public distribution, but not for your own use).

Then give the app the id, either way:

If you created a **Desktop app** client, Google also issues a **client secret**,
and the token exchange fails with `client_secret is missing` without it. An
**iOS** client has no secret. Either works — supply what your client type has.

```bash
export VELOMAIL_CLIENT_ID="…apps.googleusercontent.com"
export VELOMAIL_CLIENT_SECRET="GOCSPX-…"   # Desktop clients only
# or
mkdir -p ~/.config/velomail
echo '{"clientID":"…apps.googleusercontent.com","clientSecret":"GOCSPX-…"}' \
  > ~/.config/velomail/config.json
```

Optionally set `VELOMAIL_IDENTITY` to your own address (it becomes the `From`
header on anything you send).

Launch, click **Sign in with Google**, and the inbox backfills.

## AI (optional)

Velo Mail can summarise threads, suggest replies, draft, rewrite, fix grammar,
translate and write subject lines. It runs against **either** a hosted API key
**or** a local model through Ollama — the same features, your choice of where
your mail goes.

With nothing configured, AI is simply off: the commands are not offered and the
app is exactly what it is without them.

### Local, via Ollama (nothing leaves your machine)

```bash
ollama serve
ollama pull llama3.2                      # or any chat model you prefer

export VELOMAIL_OLLAMA_MODEL="llama3.2"   # this alone turns AI on
export VELOMAIL_OLLAMA_URL="http://localhost:11434"   # optional
```

### Hosted, via an API key

```bash
export VELOMAIL_ANTHROPIC_API_KEY="sk-..."
export VELOMAIL_ANTHROPIC_MODEL="claude-sonnet-5"     # optional
```

Or put any of these in `~/.config/velomail/config.json`:

```json
{
  "clientID": "...apps.googleusercontent.com",
  "provider": "ollama",
  "ollamaModel": "llama3.2",
  "anthropicAPIKey": "sk-..."
}
```

With both configured the API key wins; set `VELOMAIL_LLM_PROVIDER` to `ollama`,
`anthropic` or `none` to choose explicitly.

**Note for reasoning models.** Velo Mail sends `think: false` to Ollama. Without
it a reasoning model spends the whole token budget on chain-of-thought and
returns empty content, which silently turns every AI feature into a no-op.

### AI keys

AI lives behind an `a` prefix, because it is optional and off by default: a
single key belongs to something that works on every launch.

| Key | Action |
|---|---|
| `a` `s` | summarise the open thread |
| `a` `r` | suggest replies (click one to open a pre-filled draft) |
| `a` `t` | triage the open thread |

Compose has a toolbar for tone, grammar, shortening, translation and subject
lines. Every one of those replaces the body, and a failure leaves what you wrote
untouched.

## Keys

| Key | Action |
|---|---|
| `j` / `k` | next / previous thread |
| `Enter` / `o` | open (also marks read) |
| `e` | archive and advance |
| `r` | reply |
| `c` | compose |
| `s` | star / unstar |
| `x` | mark the row for a bulk action |
| `Cmd+Enter` | send |
| `g` `i` | go to inbox |
| `Cmd+K` | command palette |
| `/` or `Cmd+F` | search |
| `h` | snooze for 4 hours |
| `u` | unsubscribe from the open thread |
| `Cmd+Z` | undo send (10s window) |
| `g` `f` | threads awaiting a reply |
| `g` `d` | focus mode (hides counts, silences banners) |
| `a` `s` / `a` `r` / `a` `t` | summarise / suggest replies / triage (AI) |
| `Esc` | back, or cancel a half-typed chord |

Every key is also in the command palette, so nothing is keyboard-only.

## Development

```bash
swift test          # 821 tests; offline and deterministic
swift build
```

If tests fail with `no such module 'Testing'`, `xcode-select` is pointing at the
Command Line Tools, which ship the swift-testing macro plugin but not the
module. Either prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or fix it once:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Design docs and per-increment build plans live in `docs/superpowers/`. Each plan
ends with a completion record listing what the post-implementation review found.

### Live model tests

The suite is offline by default. To exercise the real Ollama wire format:

```bash
VELOMAIL_LIVE_OLLAMA=1 VELOMAIL_OLLAMA_MODEL="your-model" swift test --filter OllamaLiveTests
```

## Drafts

A half-written message is saved as you type and comes back when you press `c`.
Quitting, or crashing, no longer loses it. An untouched composer is not saved —
opening the window and closing it does not leave a phantom draft to resume
forever — and sending clears it.

Drafts are **local**. Gmail's `users.drafts` would put the same message on your
phone, but that is a two-way sync with its own reconciliation, and a one-way
create would litter the account with a duplicate every time you typed another
sentence. Deferred deliberately.

## Notifications and focus

New mail raises a banner and updates the Dock badge. What gets announced is
deliberately conservative: nothing on the first run (a fresh account backfills
hundreds of messages), never your own sent mail, never the same message twice,
and a burst is capped at three banners plus a summary.

`g` `d` toggles focus, which silences banners and hides the unread count — not
knowing how much is waiting is the point of it.

If macOS refuses notification permission, or the build is unsigned and simply
not allowed to post, the app carries on without banners rather than complaining
every sync.

## Time

**Undo send.** Sending holds the message for 10 seconds; `Cmd+Z` takes it back.
It is a delay, not a recall — there is no unsending mail, and every client
offering "undo send" is doing exactly this.

**Snooze** (`h`) removes the thread from the inbox and puts it back later.
Removing the label syncs to every device; the wake time is local, because Gmail's
own snooze is not in the public API. A snoozed thread wakes on the machine that
snoozed it, while the app is running.

**Awaiting reply** (`g` `f`) lists threads where you spoke last and heard nothing
back for three days. It is derived rather than flagged, so a reply makes a thread
disappear from the list on its own.

## Triage

**Star** (`s`) is Gmail's own `STARRED` label, not a local flag, so a thread you
star here is starred everywhere. It rides the same outbound queue as archive:
applied locally at once, pushed in the background, rolled back if Gmail refuses
it. There is deliberately no separate "pin" — a pin that exists in Velo Mail and
nowhere else is a promise the app cannot keep on your phone.

**Marking** (`x`) widens what the next action applies to. It is not a separate
set of bulk commands: archive, star and snooze all run over the marked rows, or
over the row under the cursor when nothing is marked. Star on a mixed selection
stars rather than toggling each thread independently, because toggling would
leave the selection more mixed than it found it.

Marks are cleared whenever the list changes underneath them. A background sync
can drop a thread and slide another into its place, and silently archiving the
wrong mail is far worse than losing a selection.

**The split inbox** groups the same rows rather than running a second query:
starred or `IMPORTANT` first, then everything else. Importance is Gmail's own
server-side judgement, arriving with every message for free — when Gmail is
wrong about a thread, Velo Mail is wrong in the same way, and starring it is the
override. The grouping is taken when the list loads, so starring something does
not make it jump out from under the cursor mid-keystroke. With nothing
important, there are no headers and the inbox looks exactly like the flat list
it was. `j`/`k` walk straight across a section boundary without noticing one.

Empty it, and the list says so.

## Snippets, templates and signature

Drop a file at `~/.config/velomail/snippets.json`:

```json
{
  "signature": "Warren Roberts\nLiving Legacy Forest",
  "snippets": [
    { "name": "Thanks", "shortcut": "thx", "body": "Thanks so much — I'll come back to you today." },
    { "name": "Intro call", "shortcut": "intro", "subject": "Intro call?",
      "body": "Would twenty minutes this week suit?" }
  ]
}
```

In the composer, type `;` then a shortcut then a **space** (or tab, or newline)
and it expands. The space is eaten; a snippet ends with its own punctuation more
often than it wants a trailing one.

A **template is just a snippet with a subject**. Expanding one also fills the
subject — but only when the subject is empty, so expanding a template into a
reply cannot silently rewrite `Re: …`.

The **signature** goes into the draft when you start it, not onto the message
when you send it: two blank lines then your name on a new message, and above the
quote on a reply. What you see is what gets sent, and you can edit or delete it
like any other text. With no signature configured, drafts are exactly what they
were before.

The `;` must start a word, matching is case-insensitive and exact, and an
unknown shortcut is left alone rather than guessed at. A paste never triggers an
expansion — only a character you typed.

`VELOMAIL_SIGNATURE` overrides the file's signature. A missing or malformed
snippets file leaves you with no snippets rather than a failed launch. There is
no in-app editor yet.

## Unsubscribe

`u` acts on the sender's own `List-Unsubscribe` header, and does nothing at all
on mail that has none — which is nearly all of it. The thread view shows the
button only when there is something to press.

Given both a `mailto:` and an `https:` link, Velo Mail sends the **mailto**. It
is a channel the sender declared, it works without a browser, and it goes out
through the same outbound queue as everything else — so it survives a restart,
retries with backoff, and `Cmd+Z` takes it back for ten seconds. With only a web
link, that opens in your browser, because filling in someone's unsubscribe form
is not something a mail client should do on your behalf.

RFC 8058 one-click POST is deliberately not implemented: it is an
unauthenticated HTTP write to a URL taken out of untrusted mail.

**Unsubscribing does not archive.** They are different decisions — you often
want off a list and still want to read this issue — and coupling them would make
`Cmd+Z` ambiguous about which half it took back. `e` is the next key over.

## Attachments

Files on a message appear as chips under its header; clicking one saves it to
Downloads. Only metadata is synced — a 500-message backfill would otherwise drag
hundreds of megabytes for files that are mostly never opened — so content is
fetched when you ask for it.

Filenames arriving from strangers are never trusted as paths: a save is confined
to the directory you picked, and a collision is numbered rather than overwriting
what you already had.

Composing works the other way too: **Attach** on the composer adds files, chips
show what is attached, and the message goes out as `multipart/mixed` with the
body intact. Total size is capped at 22MB and enforced when you attach rather
than when the send fails — a server error ten seconds later, after the undo
window shut, is a much worse experience than being told up front.

## Search

`/` opens search. Plain keywords work with no setup — full-text over sender,
subject and body, with stemming, so "meeting" finds "meet".

With an AI provider configured you can also describe what you want:

```
unread emails from natalie last week about the open day
```

That gets translated into a structured query (terms, sender, unread, date range)
and run against the same index. **The model only ever sees your query string —
never your mail.** With no provider, or if translation fails, the text is used as
plain search terms.

## Not done yet

Draft sync to other devices (`users.drafts`), resumable upload for very large
attachments, multiple accounts, pinning a
thread to the top, collapsing the quoted part of a reply (parsing someone
else's quoting is its own problem), local filters and rules, calendar and contacts, anything needing a server (team features), and
code signing / notarisation.
