# Velo Mail

A keyboard-first macOS Gmail client, in the spirit of Superhuman.

- **`VeloCore`** — the headless engine: OAuth, SQLite storage (GRDB), Gmail sync
  (backfill + incremental history), an outbound queue with optimistic apply and
  revert, RFC 5322 compose/send, a polling scheduler with backoff, and the
  keyboard/selection model. No UI, no network in tests.
- **`VeloUI`** — view models and views.
- **`VeloMail`** — the app.

499 tests, no XCTest, no `.xcodeproj`.

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

| Key | Action |
|---|---|
| `s` | summarise the open thread |
| `d` | suggest replies (click one to open a pre-filled draft) |

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
| `s` | summarise thread (AI) |
| `d` | suggest replies (AI) |
| `Cmd+Enter` | send |
| `g` `i` | go to inbox |
| `Cmd+K` | command palette |
| `/` or `Cmd+F` | search |
| `Esc` | back, or cancel a half-typed chord |

## Development

```bash
swift test          # 499 tests; offline and deterministic
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

Attachments, server-side drafts, scheduled/undo send, multiple accounts,
threaded transcripts with quote collapsing, reply-body quoting, code signing and
notarisation.
