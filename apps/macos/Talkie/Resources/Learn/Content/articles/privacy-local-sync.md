---
id: privacy-local-sync
title: Privacy, local, and sync
summary: Recordings live on your Mac first; iCloud is the optional, private sync layer; cloud LLMs only see what you send them.
category: privacy
tags: [privacy, local, sync, icloud, bridge, on-device, keychain]
updated: 2026-05-22
surfaces:
  - { label: "Sync settings",       url: "talkie://settings/sync" }
  - { label: "Storage settings",    url: "talkie://settings/helpers" }
  - { label: "Provider keys",       url: "talkie://settings/providers" }
  - { label: "About / permissions", url: "talkie://settings" }
shortcuts: []
related: [llm-providers, console-agents, workflows]
agent_facts:
  - "Recordings, transcripts, and notes are stored locally first; the canonical store is on disk on your Mac."
  - "iCloud sync is opt-in and end-to-end private — sync is per-device, not via a Talkie server."
  - "On-device transcription uses Apple Speech or the bundled Parakeet model; cloud transcription only runs when you select it."
  - "The Bridge API runs as a local HTTP server on port 7745 — it never opens a remote port."
  - "All third-party API keys are stored in the macOS Keychain, never in plain settings."
---

Talkie is local-first. The canonical store for every recording,
transcript, and note is the database on your Mac. iCloud is the only
sync layer Talkie ships, and it's optional.

## What stays local by default

- The audio file and the transcript on disk
- Compose drafts and their diff history
- Workflow run history (`workflow_runs` in the local SQLite DB)
- API keys (stored in the macOS Keychain)

## What can leave the device

Only when you explicitly route it there:

- **Cloud transcription** — fires when you pick a cloud STT engine for
  a recording. The default is on-device (Apple Speech / Parakeet).
- **Cloud LLM calls** — Anthropic, OpenAI, Gemini, Hugging Face. The
  payload is the prompt + the transcript or selection you sent.
- **Webhook / email / cloudUpload workflow steps** — only the data
  passed into them, only when the step runs.
- **iOS push** — short payloads to your own iPhone via your Apple ID.

## iCloud sync

iCloud sync is opt-in and per-device. There is no Talkie server in the
loop — sync is direct device-to-iCloud-to-device. You can see what the
sync provider thinks it's doing in the Console's Sync tab.

## The Bridge API

The Bridge API runs as a local HTTP server bound to **localhost:7745**.
It never opens a port on a remote interface. It exists so on-device
helpers (the agent daemon, the iOS keyboard's app-to-app handoff) can
talk to Talkie without going through XPC.
