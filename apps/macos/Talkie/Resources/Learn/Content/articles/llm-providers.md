---
id: llm-providers
title: LLM providers
summary: Apple Intelligence on-device, Anthropic and OpenAI by API key, Google Gemini, and local models via Ollama — chosen per feature in Settings.
category: providers
tags: [llm, provider, anthropic, openai, gemini, ollama, apple-intelligence, api-key]
updated: 2026-05-22
surfaces:
  - { label: "Provider keys",     url: "talkie://settings/providers" }
  - { label: "Models settings",   url: "talkie://settings/models" }
  - { label: "Helpers settings",  url: "talkie://settings/helpers" }
shortcuts: []
related: [compose-diffs, workflows, privacy-local-sync]
agent_facts:
  - "Configured providers ship today: Apple Intelligence (on-device, macOS 15.1+), Anthropic, OpenAI, Google Gemini, and local Ollama."
  - "Provider selection is per-feature: the LLM behind Compose, behind workflows, and behind quick actions can each be a different provider."
  - "API keys are stored in the macOS Keychain — never written to plain settings files."
  - "Hugging Face inference endpoints are listed as 'soon' on the Learn surface."
---

Talkie does not bundle a single LLM. It assembles one per feature from
the providers you've configured.

## Providers

| Provider             | Mode        | Notes                                    |
| -------------------- | ----------- | ---------------------------------------- |
| Apple Intelligence   | On-device   | Available on macOS 15.1+, no key needed  |
| Anthropic            | API key     | Defaults to `claude-opus-4-7`            |
| OpenAI               | API key     | Defaults to `gpt-4o`                     |
| Google Gemini        | API key     | Bring your own                           |
| Local (Ollama)       | Local HTTP  | e.g. `mistral 7b` against `localhost`    |
| Hugging Face         | API key     | Inference endpoints — listed as "soon"   |

## How selection works

Each feature has its own provider slot:

- **Compose** — the rewrite/diff engine
- **Workflows** — the default `llm` step model (a workflow step can
  override the provider in its JSON)
- **Quick actions** — context-rule-driven prompts
- **Memo polish** — light per-recording rewrites

Open **Models** settings to pick the provider per slot, and **Providers**
settings to manage API keys. Keys live in the macOS Keychain — they
aren't written into the plain settings JSON.

## Failover

If the selected provider is unreachable (no network, expired key,
rate-limited), Talkie surfaces the error in the Console's Agent tab and
won't silently fall back to a different provider. Pick fallbacks
explicitly in Models settings if you want them.
