# Velo Mail

A keyboard-first macOS Gmail client, in the spirit of Superhuman.

- **`VeloCore`** — the headless engine: OAuth, SQLite storage (GRDB), Gmail sync
  (backfill + incremental history), an outbound queue with optimistic apply and
  revert, RFC 5322 compose/send, a polling scheduler with backoff, and the
  keyboard/selection model. No UI, no network in tests.
- **`VeloUI`** — view models and views.
- **`VeloMail`** — the app.

607 tests, no XCTest, no `.xcodeproj`.

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
2. Credentials → Create credentials → **OAuth client ID** → type **Desktop app**.
3. On the consent screen, add yourself as a test user (the `gmail.modify` scope
   needs Google's review before public distribution, but not for your own use).

Then give the app the id, either way:

```bash
export VELOMAIL_CLIENT_ID="…apps.googleusercontent.com"
# or
mkdir -p ~/.config/velomail
echo '{"clientID":"…apps.googleusercontent.com"}' > ~/.config/velomail/config.json
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
| `Cmd+Z` | undo send (10s window) |
| `g` `f` | threads awaiting a reply |
| `a` `s` / `a` `r` / `a` `t` | summarise / suggest replies / triage (AI) |
| `Esc` | back, or cancel a half-typed chord |

Every key is also in the command palette, so nothing is keyboard-only.

## Development

```bash
swift test          # 607 tests; offline and deterministic
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

Attachments, server-side drafts, multiple accounts,
threaded transcripts with quote collapsing, reply-body quoting, code signing and
notarisation.
