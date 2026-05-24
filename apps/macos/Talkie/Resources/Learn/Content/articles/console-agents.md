---
id: console-agents
title: Console and agents
summary: A tabbed terminal-style inspector for the live state of Talkie's services, transcribers, and agent runs.
category: console
tags: [console, agent, debug, logs, tabs, pro-tools]
updated: 2026-05-22
surfaces:
  - { label: "Open Console",       url: "talkie://open/console" }
  - { label: "Helpers settings",   url: "talkie://settings/helpers" }
  - { label: "Mode settings",      url: "talkie://settings/surface" }
shortcuts: []
related: [workflows, llm-providers, privacy-local-sync]
agent_facts:
  - "The Console is only visible when Pro Tools is active in Mode settings — it isn't shown to simple-mode users."
  - "Each tab is registered by a TabDefinition; common tabs include Agent, Logs, Workflows, Sync, and Transcribers."
  - "Console tabs reflect live state — there's no separate refresh; XPC events stream in as services emit them."
  - "The Console is read-only by default. Mutating commands are gated behind explicit per-tab affordances."
---

The Console is a tabbed inspector for Talkie's internals. It sits behind
the **Console** entry in the sidebar and is only shown when **Pro Tools**
is enabled in Mode settings — simple-mode users never see it.

## What's in each tab

- **Agent** — live state of the agent daemon: queued runs, current
  step, last error, last successful run.
- **Workflows** — recently fired workflow runs with their step ladders
  and outputs. Click into a run to see the rendered prompt and the
  raw model response.
- **Transcribers** — engine status (Apple, Parakeet, cloud), warm-up
  cost, last failure.
- **Sync** — what the iCloud sync provider thinks it's doing, with
  per-record state (`syncing`, `synced`, …).
- **Logs** — recent entries by channel. Useful when something silently
  failed and you need to see why.

## Read vs write

The Console is read-mostly. Each tab can expose one or two mutating
controls (re-run, clear queue) but those are deliberate per-tab
affordances, not a free shell. If you want to mutate runtime state
broadly, that's still the job of Settings.
