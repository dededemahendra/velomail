# Velo Mail

A keyboard-first macOS Gmail client, in the spirit of Superhuman.

- **`VeloCore`** — the headless engine: OAuth, SQLite storage (GRDB), Gmail sync
  (backfill + incremental history), an outbound queue with optimistic apply and
  revert, RFC 5322 compose/send, a polling scheduler with backoff, and the
  keyboard/selection model. No UI, no network in tests.
- **`VeloUI`** — view models and views.
- **`VeloMail`** — the app.

300 tests, no XCTest, no `.xcodeproj`.

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

## Keys

| Key | Action |
|---|---|
| `j` / `k` | next / previous thread |
| `Enter` / `o` | open (also marks read) |
| `e` | archive and advance |
| `r` | reply |
| `c` | compose |
| `Cmd+Enter` | send |
| `g` `i` | go to inbox |
| `Cmd+K` | command palette |
| `Esc` | back, or cancel a half-typed chord |

## Development

```bash
swift test          # 300 tests
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

## Not done yet

Attachments, server-side drafts, scheduled/undo send, search, multiple accounts,
threaded transcripts with quote collapsing, reply-body quoting, code signing and
notarisation.
