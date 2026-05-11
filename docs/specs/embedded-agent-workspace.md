# Embedded Agent Workspace

## Purpose

Talkie's embedded console should feel like a real operating surface, not just a prompt wrapper. The generated workspace is intentionally small, but it now needs to teach the agent three things clearly:

1. where the declarative config lives
2. where memo and workflow data lives
3. which surfaces are safe to edit directly

The code remains canonical. This document is a compact map for humans and agents.

## Current Workspace Shape

Each managed agent session currently generates:

- `AGENTS.md`
- `SYSTEM_PROMPT.md`
- `PROMPT.md`
- `CONTEXT.md`
- `EXAMPLES.md`
- `CONFIGURATION_GUIDE.md`
- `MEMO_GUIDE.md`
- `WORKFLOW_GUIDE.md`
- `Rule Packs/`
- `Live Config/`
- `Tools/`

The console harness can run with OpenCode, Claude, or a local shell. The PTY-backed console already supports optional tmux-backed persistent sessions for the richer console flow.

## Live Config Strategy

The generated workspace should mount the file-backed canonical surfaces when they exist locally:

- macOS settings config
- macOS workflow preference/runtime config
- macOS context rules
- workflow definition directories

This lets the agent edit durable product state without driving settings UI and without bouncing through compatibility mirrors.

## Memo Strategy

Memos are not declarative config. They are operational app data backed by SQLite/GRDB.

Because of that, the current embedded-agent strategy is:

- document the live memo database path
- point at the owning repository/schema files
- provide small read-only helper tools for inspection
- avoid direct raw database edits unless the task is explicitly repair or migration work

The current helper surface should cover:

- listing recent memos
- searching memos by text
- showing one memo with transcript/workflow context
- listing workflow runs globally or for a memo

## Workflow Strategy

Workflow behavior is split across:

- workflow definition files on disk
- workflow preference/runtime config in `workflows/config.json`
- workflow run history in `workflow_runs`

The agent should prefer editing:

- workflow JSON definition files
- file-backed workflow config

And it should treat workflow run history as read-mostly operational data.

## What The Agent Should Read First

If the task is about:

- command interpretation or context refinement:
  - read `Rule Packs/*.trf.toml`
- settings, quick actions, SSH, bridge, or iPhone preferences:
  - read `CONFIGURATION_GUIDE.md`
- memos, transcripts, recordings, pinned actions, or workflow output:
  - read `MEMO_GUIDE.md` and `WORKFLOW_GUIDE.md`

## Near-Term Evolution

The next meaningful step is not more prompt-writing. It is giving Talkie Agent a first-class memo/query API.

The current repo already has a placeholder route surface at:

- `apps/macos/TalkieAgent/TalkieAgent/Services/TalkieRoutes.swift`

That is the obvious evolution path:

1. keep the file-backed config editing approach
2. keep the read-only SQLite tools as a fallback
3. add real memo/query routes through TalkieAgent so agents can inspect and act through Talkie's own bridge

## Editing Rules

- Edit mounted file-backed config and workflow files directly when that is the canonical source.
- Do not edit transport mirrors directly.
- Do not edit `talkie.sqlite` directly unless the task is explicitly a repair, migration, or forensic recovery.
- When adding or moving a durable config surface, update:
  - `docs/specs/file-based-settings-inventory.md`
  - `docs/specs/agent-manageable-configuration.md`
  - this document if the embedded workspace contract changed
