---
id: workflows
title: Workflows and triggers
summary: Multi-step pipelines that run after recordings, on context match, or on demand — each step pipes its output into the next.
category: workflows
tags: [workflow, automation, trigger, llm, shell, pipeline]
updated: 2026-05-22
surfaces:
  - { label: "Open Workflows",     url: "talkie://open/workflows" }
  - { label: "Automation settings",url: "talkie://settings/helpers" }
  - { label: "Models settings",    url: "talkie://settings/models" }
shortcuts:
  - { chord: "⌥⌘L", action: "Toggle Recording (often the trigger)", default: false }
related: [context-rules, console-agents, llm-providers]
agent_facts:
  - "A workflow is a JSON-defined chain of steps; each step's output is referenced by later steps via {{output_key}}."
  - "Workflows trigger three ways: recording finished, context rule matched, or manual run."
  - "Step types include llm, transform, conditional, shell, saveFile, clipboard, transcribe, speak, notification, iOSPush, trigger, intentExtract, executeWorkflows, appleReminders, webhook, email, and cloudUpload."
  - "User workflows live in 'Live Config/workflow-user/<slug>.json'; templates ship in Resources/WorkflowTemplates."
---

A workflow is an ordered chain of steps. Each step writes to an
`outputKey`; later steps reference earlier output with `{{key}}`. The
transcript of the current recording is always available as
`{{TRANSCRIPT}}`.

## Triggers

A workflow can fire from three places:

1. **Recording finished** — runs against the new transcript automatically.
2. **Context rule matched** — runs when a [context rule][cr] matches
   the foreground app at the moment a recording starts.
3. **Manual run** — open the workflow in the Workflows surface and
   press Run.

[cr]: talkie://open/context

## Step vocabulary

The capability map (see `AgentKit/docs/workflow-capabilities.md`) is the
authoritative list. Common steps:

- **`llm`** — generate or transform text with a prompt
- **`transform`** — reshape earlier output without another model call
- **`conditional`** — gate later steps on an expression
- **`shell`** — run a local executable (timeouts, env, stdin all supported)
- **`saveFile`** / **`clipboard`** — persist or expose the result
- **`speak`** / **`notification`** / **`iOSPush`** — surface output
- **`appleReminders`** / **`webhook`** / **`email`** / **`cloudUpload`** — outbound actions
- **`intentExtract`** + **`executeWorkflows`** — fan out into other workflows by intent

## Authoring

The simplest workflow has one `llm` step against `{{TRANSCRIPT}}`. See
`Resources/WorkflowTemplates/quick-summary.json` for the smallest
shipped example. Author user workflows into
`Live Config/workflow-user/<slug>.json`; the imported workflows
directory holds anything dragged in.
