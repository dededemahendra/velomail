# Velo Mail — LLM Provider Layer (Increment J) Design

**Date:** 2026-08-24
**Status:** Approved (scope)

## 1. Why

Every AI feature on the roadmap is the same shape: build a prompt from mail the
app already has, send it somewhere, use the answer. The only real decisions are
*where it goes* and *what happens when it is not configured*. Getting those two
right once means the fifteen AI features after it are prompt templates.

Two destinations, both first-class:

- **A hosted API, via an API key.** Better quality, costs money, and your mail
  leaves the machine.
- **A local model, via Ollama.** Free, private, and as good as whatever you have
  pulled locally.

That second one is not a nice-to-have. A mail client sending your inbox to a
third party is a real privacy decision, and the user should be able to say no
without losing the features. Ollama is how they say no.

Success criterion: **the same AI feature works against either provider, and with
neither configured the app behaves exactly as it does today.**

## 2. Scope

### In scope
- `LLMProvider` protocol; `LLMRequest`/`LLMError`.
- `AnthropicProvider` — hosted, API key.
- `OllamaProvider` — local, no key.
- `LLMConfig` resolution (environment → config file) and a factory.
- Everything driven through the existing `HTTPClient` seam, so tests are
  offline and keyless.

### Explicitly out of scope
- Streaming. Mail assistance is short-form; a spinner and a result is fine, and
  streaming doubles the parsing surface for no user-visible gain here.
- Tool use / function calling. No AI feature on the roadmap needs it.
- Token accounting and cost display.
- Embeddings and vector search — natural-language search (increment L) is
  planned as NL → structured filter, which needs no embedding store.
- Prompt templates themselves. Those are increment K; J is only the pipe.

## 3. Nothing is hardcoded that could change

Model ids, base URLs and the API version header are **configuration with
defaults**, never constants in the call site. Providers rev their models faster
than a mail client ships, and a user pointing at a different model or a proxy
should not need a code change. It also means the code makes no claim about
provider specifics that could quietly rot.

| Setting | Default | Why a default at all |
|---|---|---|
| Anthropic base URL | `https://api.anthropic.com` | a proxy is the exception |
| Anthropic version header | `2023-06-01` | override if it moves |
| Anthropic model | `claude-sonnet-5` | good balance for short mail tasks |
| Ollama base URL | `http://localhost:11434` | where Ollama listens |
| Ollama model | `llama3.2` | commonly pulled; override freely |

## 4. Resolution and precedence

`VELOMAIL_LLM_PROVIDER` = `anthropic` | `ollama` | `none`. Unset means **infer**:
an Anthropic key present picks Anthropic, otherwise an explicitly configured
Ollama picks Ollama, otherwise none.

Inference deliberately does *not* probe the network to see whether Ollama is
running. Launch must not block on a socket that may not answer, and a mail
client that pauses at startup because a local model is not up would be a worse
bug than the missing feature.

Config file is the same one the app already uses,
`~/.config/velomail/config.json`, so there is one place to look.

## 5. Absence is a supported state

`LLMConfig.provider == nil` is normal, not degraded. The AI commands are absent
from the palette rather than present-and-failing, because an action that is
visible and always errors is worse than one that is not offered.

## 6. Errors

One typed error, because callers can only do three things about it:

| Case | Caller's move |
|---|---|
| `notConfigured` | do not offer the feature |
| `unauthorized` | tell the user the key is wrong |
| `unavailable` | tell the user the model or daemon is not reachable — the common Ollama case |
| `server(status:message:)` | show it |
| `malformedResponse` | show a generic failure |

`unavailable` exists separately from `server` specifically for Ollama: "you have
not started Ollama" and "the model returned an error" need different words.

## 7. Testing

`MockHTTPClient` and scripted responses. Assertions cover the request each
provider builds (URL, headers, JSON body), the response each parses, the mapping
of every error case, and each precedence rule in resolution. No network, no
keys, no local model required to run the suite.

## 8. Known limitations (deliberate, recorded)

- No streaming, so a long generation shows nothing until it finishes.
- No retry or backoff on the LLM call; a failure surfaces to the user.
- Ollama's `/api/chat` is assumed; other local runtimes would need their own
  provider (which is exactly what the protocol is for).
- No redaction: whatever the prompt builder puts in the prompt is what gets
  sent. Increment K owns deciding how much of a message to include.
