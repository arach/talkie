---
id: context-rules
title: Context rules
summary: App-aware rules that change what Talkie does based on the foreground app at trigger time.
category: context
tags: [context, app-profile, rules, matcher, dictionary, post-transcription]
updated: 2026-05-22
surfaces:
  - { label: "Open Context",          url: "talkie://open/context" }
  - { label: "Context settings",      url: "talkie://settings/context" }
  - { label: "Dictation settings",    url: "talkie://settings/agent" }
shortcuts: []
related: [workflows, compose-diffs, hyper-keys]
agent_facts:
  - "A context rule is bound to one app, a list of apps, or 'everywhere except' a set."
  - "The matcher reads the foreground app at trigger time — typically the moment a recording starts."
  - "A rule can carry a custom dictionary, processing transforms, a prompt template, and a workflow to run after transcription."
  - "Rules are evaluated in priority order; the first match wins."
---

Context rules — also called **app profiles** in some surfaces — bind
behaviour to the foreground app. When Talkie starts a recording, the
rules engine looks at which app is in front and applies the first rule
that matches.

## Scope

A rule can scope to:

- **One app** — e.g. only iTerm
- **A list** — e.g. iTerm, Ghostty, Terminal
- **Everywhere except** — e.g. anywhere but Slack and Messages

## What a rule carries

A single rule can ship any subset of:

- a **dictionary** — words and phrases Talkie should prefer when
  transcribing in this context (proper nouns, internal jargon)
- **processing rules** — symbolic substitutions, regex transforms,
  formatters that run on the transcript before it's surfaced
- a **prompt template** — appended to LLM steps that fire inside the
  rule's scope (e.g. "format as a git commit message")
- a **workflow** — fires when the rule matches a finished recording

## Disabling

Each rule has its own enable toggle. The whole rules engine can be
turned off in Context settings; when off, Talkie falls back to global
dictation behaviour.
