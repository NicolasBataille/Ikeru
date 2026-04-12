# Ikeru — AI Provider Setup Guide

> Personal use only. Ikeru is not distributed on the App Store.

Ikeru routes AI requests across several free cloud providers + on-device Apple
FoundationModels. Each provider stores its API key in iOS Keychain and the
router falls back automatically when one is unavailable, rate-limited, or
returns an error.

This guide walks you through obtaining a free key for each provider.

---

## Quick reference — which key to start with?

If you only configure one, start with **Gemini**. The free tier is generous
enough for everyday use and the signup is the cleanest. Add **Groq** as your
second to get sub-second latency for Sakura conversation.

| Priority | Provider | What it gives you |
|---|---|---|
| 0 (already on) | **FoundationModels** | Apple on-device, zero setup, zero quota |
| 1 | **Gemini** | Gemini 2.0 Flash via Google AI Studio. Most generous free quota. |
| 2 | **Groq** | Llama 3.3 70B at sub-second latency. Best for live chat. |
| 3 | **OpenRouter** | Catalogue of free models (Llama, DeepSeek, Qwen, Mistral, Phi). |
| 4 | **Cerebras** | Llama 3.3 70B on wafer-scale silicon. Fastest tokens/sec on the planet. |
| 5 | **GitHub Models** | Llama / Phi / Mistral via your existing GitHub PAT. |
| 6 (paid, optional) | **Claude** | Anthropic API key. Pay-as-you-go. **Not** covered by your Pro/Max sub. |

The router uses different chains per request type:

- **`.simple`** (low latency wins): on-device → Cerebras → Groq
- **`.medium`** (balanced): Cerebras → Groq → OpenRouter → Gemini → GitHub Models → on-device
- **`.complex`** (quality wins): OpenRouter → Gemini → Cerebras → Groq → GitHub Models → Claude → on-device
- **`.batch`** (volume jobs): Gemini → OpenRouter → Cerebras → GitHub Models → on-device

You can leave any provider unconfigured — the router silently skips it.

---

## Gemini (recommended first)

1. Open <https://aistudio.google.com/apikey>
2. Sign in with your Google account
3. Click **Create API key**
4. Copy the key (starts with `AIza...`)
5. In Ikeru: Settings → AI Providers → Gemini → paste → Save

**Free quota at time of writing:** 15 RPM, 1M tokens/day on Gemini 2.0 Flash.
That's plenty for personal use.

## Groq

1. Open <https://console.groq.com/keys>
2. Sign up (Google or GitHub OAuth)
3. Click **Create API Key**, name it `ikeru`, copy the key (starts with `gsk_`)
4. In Ikeru: Settings → AI Providers → Groq → paste → Save

**Free quota:** 30 RPM, 14 400 req/day on Llama 3.3 70B Versatile.
**Why Groq:** sub-second response times — perfect for Sakura's chat.

## OpenRouter

1. Open <https://openrouter.ai/keys>
2. Sign up (GitHub / Google / email)
3. Click **Create Key**, copy (starts with `sk-or-v1-...`)
4. In Ikeru: Settings → AI Providers → OpenRouter → paste → Save

**Free quota:** 20 req/min, 50 req/day per `:free` model. Default model is
`meta-llama/llama-3.3-70b-instruct:free` which has excellent JP/EN abilities.

## Cerebras

1. Open <https://cloud.cerebras.ai>
2. Sign up
3. Dashboard → API Keys → Create
4. Copy the key (starts with `csk-...`)
5. In Ikeru: Settings → AI Providers → Cerebras → paste → Save

**Free quota:** 30 RPM, 1M tokens/day.
**Why Cerebras:** the fastest hosted inference available — 1000+ tokens/s on Llama 3.3 70B.

## GitHub Models

1. Open <https://github.com/settings/personal-access-tokens>
2. Click **Generate new token** → fine-grained
3. No special scopes are required for public Models inference
4. Set an expiration that makes sense for you (90 days is a good default)
5. Copy the token (starts with `github_pat_...`)
6. In Ikeru: Settings → AI Providers → GitHub Models → paste → Save

**Free quota:** approximately 50 req/day, 8K context per request.
**Why GitHub Models:** uses an account you already have, lets you tap into
Llama, Phi, Mistral Nemo, and DeepSeek through one auth.

## Claude (paid, optional)

⚠️ Anthropic announced on **2026-04-04** that third-party tools using Claude
subscription auth count as "third-party harness usage" and are billed
**pay-as-you-go**, separate from your Pro/Max subscription. There is no way
to make Claude API calls from Ikeru that consume your sub.

If you still want to use Claude (Opus 4.6 / Sonnet 4.6) and accept the cost:

1. Open <https://console.anthropic.com/settings/keys>
2. Create a key, copy (starts with `sk-ant-...`)
3. In Ikeru: Settings → AI Providers → Claude (Paid) → paste → Save
4. Set a billing limit on the Anthropic console to avoid surprises

---

## Where keys are stored

- iOS Keychain via `KeychainHelper` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Never on disk in plaintext, never in `UserDefaults`, never logged
- Cleared when you tap **Remove** on the matching provider section
- Survives app reinstall on the same device only if you have iCloud Keychain
  enabled (otherwise re-paste after a fresh install)

## Verifying it works

After saving a key, the green status dot appears next to the provider name
within a couple of seconds (the router calls `refreshTierStatuses()`). If it
stays gray:

- Check the device is online
- Re-paste the key (whitespace is trimmed automatically, but invisible
  characters from copy-paste can corrupt it)
- Check the console logs: `Logger.ai` entries are tagged with the provider
  name and HTTP status

---

## Roadmap

- **Story 7-3 / 7-4:** local rig server (Windows + Docker + RTX 5090) that
  exposes VOICEVOX and other heavy models for native Japanese TTS
- **Story 7-5:** SRS-aware pre-warming of audio assets in the background
- **Future:** OpenRouter PKCE OAuth flow to replace paste-key UX
