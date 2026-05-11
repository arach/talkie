# RFC: File-Based Context System

**Status:** Draft
**Date:** 2026-03-21
**Audience:** Product, platform, workflow, dictation, and developer-experience work

## Summary

This RFC proposes a file-first extensibility model for Talkie.

Instead of forcing all customization through Talkie's UI, users and developers can register one or more filesystem roots. Talkie then discovers capabilities by folder convention.

Each root exposes a small set of first-class concepts:

- `rules/` for matching and transforming input
- `tools/` for executable custom logic
- `workflows/` for Talkie-native execution graphs
- `automations/` for scheduled or event-bound workflow runs

The goal is to make Talkie programmable without turning the product into a generic plugin host.

## Motivation

Talkie already has multiple adjacent systems:

- dictionaries / corrections
- snippets / shorthand expansions
- context rules
- workflows
- automations

These are all related, but they do different jobs at different phases of the pipeline.

The current risk is that every new power-user need pushes us toward more UI, more settings panels, and more special-case feature surfaces. That creates two problems:

1. advanced users cannot move quickly without waiting on UI support
2. the product model becomes muddy because every concept is defined by where it lives in settings rather than what it does

We need a model that:

- keeps the conceptual boundaries sharp
- allows deep customization without UI work
- remains inspectable, debuggable, and git-friendly

## Goals

- Make Talkie programmable from disk with minimal UI dependency
- Preserve clear demarcation between normalization, expansion, routing, execution, and scheduling
- Let users keep custom behavior in source control
- Support per-project or per-workspace Talkie behavior
- Allow arbitrary custom logic without embedding every language runtime into Talkie
- Keep Talkie as the runtime and policy engine, not just a shell launcher

## Non-Goals

- Replace Talkie's UI for mainstream users
- Turn Talkie into a general-purpose plugin marketplace in v1
- Let arbitrary scripts mutate Talkie internals in-process
- Collapse rules, workflows, and automations into one indistinguishable object
- Design the final settings UI in this RFC

## Context

This RFC is adjacent to, but distinct from:

- `specs/multi-dictionary-architecture.md`
- `docs/CONTEXT_SETTINGS_PLAN.md`

Those documents focus on user-facing organization and dictionary evolution. This RFC focuses on file-based definition, discovery, and execution.

## Terminology

### Context System

The umbrella term for all programmable behavior that shapes how Talkie interprets and acts on captured input.

### Rule

A lightweight declarative object that matches some input and produces a structured outcome.

Rules belong to one of three phases:

- `normalize`: fix or standardize text
- `expand`: turn shorthand into richer text, prompts, or templates
- `route`: decide what workflow or tool should run

Rules do not directly perform arbitrary side effects.

### Tool

A custom executable unit owned by the user. Tools receive structured input and return structured effects over a stable stdin/stdout contract.

Tools are how developers extend Talkie with custom logic without waiting for native UI or product support.

### Workflow

A Talkie-native execution graph. Workflows remain the preferred way to express multi-step operations and side effects inside Talkie.

### Automation

A schedule or event binding that runs a workflow or tool later, periodically, or in the background.

## Design Principle

The system should be organized by pipeline phase, not by settings page.

The phases are:

1. Normalize
2. Expand
3. Route
4. Execute
5. Schedule

This yields a stable litmus test:

- if it only fixes text, it is a `normalize` rule
- if it expands shorthand into text or a prompt scaffold, it is an `expand` rule
- if it chooses what should happen next, it is a `route` rule
- if it performs work or side effects, it is a workflow or tool
- if it decides when work runs, it is an automation

## Proposal

Talkie will support one or more configured context roots.

Examples:

```text
~/Documents/Talkie
~/code/my-project/.talkie
~/code/client-workspace/.talkie
```

Each root uses a conventional layout:

```text
.talkie/
  rules/
    normalize-company-names/
      rule.yaml
    standup-template/
      rule.yaml
    summarize-for-slack/
      rule.yaml

  tools/
    jira-ticket/
      tool.yaml
      run.ts
      README.md

    post-to-slack/
      tool.yaml
      run.py

  workflows/
    meeting-follow-up/
      workflow.json

  automations/
    morning-inbox/
      automation.yaml
```

Talkie discovers behavior by walking these folders and validating known entry files.

## Why Folder-Based Definitions

Each capability is a directory instead of a single flat file because a directory gives us room for:

- metadata
- source files
- fixtures
- docs
- tests
- assets

That makes each item self-contained, movable, and easy to share.

## Root Discovery

Talkie should support three root classes:

### Global Roots

User-configured paths such as:

```text
~/Documents/Talkie
~/Library/Application Support/Talkie/Context
```

### Workspace Roots

Project-local directories such as:

```text
/Users/example/dev/talkie/.talkie
```

These are ideal for team-shared rules and tools.

### Built-In Roots

Talkie-shipped presets and examples bundled with the app.

Discovery precedence:

1. workspace roots
2. user-configured global roots
3. built-in roots

Later roots are lower priority by default unless a manifest or rule priority overrides them.

## Directory Conventions

### Rules

Path:

```text
rules/<rule-id>/rule.yaml
```

Each rule folder defines one declarative rule.

Suggested schema:

```yaml
id: standup-template
kind: expand
name: Standup Template
enabled: true
priority: 100

when:
  event: dictation.finalized
  apps: [Slack, Notes]
  sources: [dictation, memo]

match:
  type: exact
  text: "standup"

produce:
  insertTemplate: |
    Yesterday:
    Today:
    Blockers:
```

Supported `kind` values in v1:

- `normalize`
- `expand`
- `route`

Supported `match.type` values in v1:

- `exact`
- `contains`
- `regex`
- `prefix`

### Tools

Path:

```text
tools/<tool-id>/tool.yaml
```

Each tool folder contains metadata plus one or more source files.

Example:

```yaml
id: jira-ticket
name: Jira Ticket
enabled: true
runtime: node
entry: run.ts
input: talkie/v1
timeoutMs: 10000
```

Example folder:

```text
tools/jira-ticket/
  tool.yaml
  run.ts
  README.md
  fixture.json
```

### Workflows

Path:

```text
workflows/<workflow-id>/workflow.json
```

These remain Talkie-native workflow definitions.

This RFC does not replace TWF. It adds a discoverable filesystem location that can coexist with current workflow storage.

### Automations

Path:

```text
automations/<automation-id>/automation.yaml
```

Automations bind a schedule or event to a workflow or tool.

Example:

```yaml
id: morning-inbox
name: Morning Inbox
enabled: true

trigger:
  type: schedule
  at: "08:00"
  weekdays: [mon, tue, wed, thu, fri]

run:
  workflow: inbox-review
```

## Rule Semantics

Rules are intentionally declarative.

They should answer four questions:

1. when does this apply?
2. what does it match?
3. what does it produce?
4. where is it allowed to run?

### Normalize Rule

Example:

```yaml
id: normalize-company-names
kind: normalize

when:
  event: text.transcribed

match:
  type: regex
  pattern: "\\bjetty eye\\b"

produce:
  replaceText: "JDI"
```

### Expand Rule

Example:

```yaml
id: commit-template
kind: expand

when:
  event: dictation.finalized
  apps: [Xcode, Terminal]

match:
  type: exact
  text: "commit message"

produce:
  insertTemplate: |
    type(scope): summary

    Why:
    - 

    What changed:
    - 
```

### Route Rule

Example:

```yaml
id: summarize-for-slack
kind: route

when:
  event: dictation.finalized

match:
  type: regex
  pattern: "^summarize (.+) for slack$"

produce:
  runWorkflow: slack-summary
  vars:
    topic: "$1"
```

## Execution Model

Talkie remains the runtime.

Rules and tools do not directly mutate Talkie state. They return structured outcomes that Talkie validates and executes.

This keeps the system:

- observable
- debuggable
- policy-controlled
- safer than arbitrary in-process plugins

## Tool Runtime Contract

Tools are invoked by Talkie as subprocesses.

Talkie provides input over stdin as JSON.
The tool returns a JSON document over stdout.

### Tool Input

Example:

```json
{
  "version": "talkie/v1",
  "event": "dictation.finalized",
  "text": "file jira fix login timeout",
  "vars": {
    "title": "fix login timeout"
  },
  "context": {
    "appName": "Linear",
    "bundleID": "com.linear",
    "source": "dictation",
    "workspacePath": "/Users/example/dev/talkie",
    "timestamp": "2026-03-21T15:05:00Z"
  }
}
```

### Tool Output

Example:

```json
{
  "effects": [
    {
      "type": "runWorkflow",
      "workflow": "create-jira-ticket",
      "vars": {
        "title": "fix login timeout"
      }
    }
  ]
}
```

### Supported Returned Effect Types in v1

- `replaceText`
- `insertText`
- `runWorkflow`
- `showSuggestion`
- `notify`
- `skip`

This should stay intentionally small at first.

## Runtime Invocation

The `runtime` field defines how Talkie launches the tool entrypoint.

Proposed v1 supported runtimes:

- `node`
- `python`
- `shell`
- `binary`

Rust does not need a dedicated runtime. A Rust program can compile to a binary and use `runtime: binary`.

TypeScript does not need a separate runtime if we define a documented Node-based invocation path. If we later support Bun or Deno, that should be explicit.

This avoids exploding product scope into "Talkie supports every language" while still making the system language-agnostic in practice.

## Event Model

The event model is the seam that keeps the system coherent.

Proposed starter events:

- `audio.captured`
- `text.transcribed`
- `text.normalized`
- `dictation.finalized`
- `dictation.beforeInsert`
- `memo.saved`
- `workflow.completed`

We should start with a small number of stable events and expand later.

## Matching Model

Rules should support a constrained but useful matcher set in v1:

- exact string match
- contains
- prefix
- regex

Future possibilities:

- alias groups
- fuzzy matching
- semantic similarity
- structured slot extraction

Those should not be required for the first version.

## Context Selectors

All rule kinds should support the same contextual selectors so the system feels unified.

Suggested selectors:

- `apps`
- `bundleIDs`
- `sources`
- `workspacePaths`
- `projects`
- `modes`
- `minConfidence`

These selectors should be additive and optional.

## Validation and Diagnostics

Talkie should validate every discovered item before enabling it.

Each item can be in one of three states:

- valid
- invalid
- disabled

Validation failures should surface:

- in logs
- in a diagnostics view
- in CLI output

Examples:

- missing `entry` in `tool.yaml`
- duplicate `id`
- invalid regex
- workflow reference not found
- unsupported runtime

## Security and Safety

The system must assume that user-provided roots are trusted by the user but still not fully safe.

Guardrails for v1:

- tools run out-of-process
- tools are time-limited
- Talkie captures stdout and stderr
- returned effect types are validated before execution
- Talkie never loads arbitrary user code in-process

Future enhancements:

- trust prompts for new roots
- per-root allowlists
- "dry run" mode
- tool capability permissions

## UI Implications

The UI should not be the source of truth for this system.

Instead, the UI should act as:

- a browser for discovered items
- a validator and diagnostics surface
- a launcher for opening folders or files
- a helper for adding roots

This keeps the file-first model intact while still supporting discoverability.

## Example Root

```text
.talkie/
  rules/
    normalize-company-names/
      rule.yaml
    standup-template/
      rule.yaml
    summarize-for-slack/
      rule.yaml

  tools/
    jira-ticket/
      tool.yaml
      run.ts

  workflows/
    slack-summary/
      workflow.json

  automations/
    morning-inbox/
      automation.yaml
```

`rules/summarize-for-slack/rule.yaml`

```yaml
id: summarize-for-slack
kind: route
name: Summarize For Slack
enabled: true

when:
  event: dictation.finalized

match:
  type: regex
  pattern: "^summarize (.+) for slack$"

produce:
  runWorkflow: slack-summary
  vars:
    topic: "$1"
```

`tools/jira-ticket/tool.yaml`

```yaml
id: jira-ticket
name: Jira Ticket
enabled: true
runtime: node
entry: run.ts
input: talkie/v1
timeoutMs: 10000
```

## Proposed Rollout

### Phase 1

- add root path registration
- discover `rules/`, `tools/`, `workflows/`, and `automations/`
- validate and log discovered items
- support declarative rules
- support tools via stdin/stdout JSON
- support rules that reference workflows and tools

### Phase 2

- diagnostics UI for discovered items
- open-in-editor actions
- per-root enable/disable
- test fixtures and preview tooling
- CLI for validation and dry-run simulation

### Phase 3

- richer event model
- slot extraction helpers
- higher-level authoring templates
- shared examples and starter packs

## Open Questions

1. Should built-in workflows continue to live in their current location and be mirrored into discovered roots, or should roots become the only source of truth over time?
2. Should `rule.yaml` allow an inline shell or script block, or should all executable logic be forced into `tools/`?
3. Do we want one unified `rules/` directory with `kind:` inside each rule, or separate top-level directories such as `normalize/`, `expand/`, and `route/`?
4. Should workspace roots be auto-discovered by walking up from the current app context, or only through explicit user configuration?
5. How much of the tool runtime matrix do we want to support in v1 versus document as external wrappers?

## Recommendation

Adopt the file-based model with this principle:

**Rules decide. Workflows do work. Automations decide when work runs. Tools provide code-backed capabilities.**

That gives Talkie a coherent mental model and a powerful extensibility surface without collapsing the product into a generic scripting shell.
