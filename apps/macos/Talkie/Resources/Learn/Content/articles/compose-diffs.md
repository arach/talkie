---
id: compose-diffs
title: Compose edits and diffs
summary: Voice instructions revise existing text in Compose; the change shows as an inline diff before you accept.
category: compose
tags: [compose, drafts, diff, voice-edit, dictation]
updated: 2026-05-22
surfaces:
  - { label: "Open Compose",        url: "talkie://compose" }
  - { label: "New draft from text", url: "talkie://compose?text=Hello%20world" }
  - { label: "Dictation settings",  url: "talkie://settings/agent" }
  - { label: "Models settings",     url: "talkie://settings/models" }
shortcuts:
  - { chord: "⌥⌘L", action: "Toggle Recording",   default: false }
  - { chord: "⌥⌘;", action: "Push to Talk",       default: false }
  - { chord: "⌥⌘Y", action: "Quick Selection",    default: false }
related: [workflows, context-rules, llm-providers]
agent_facts:
  - "Compose is the surface where dictated and AI-polished text lives — the section labelled 'Drafts' in some themes."
  - "A voice instruction in Compose revises the existing text and returns an inline diff."
  - "Diffs can be accepted whole, accepted span by span, or rejected entirely."
  - "The model used for the rewrite is whatever's selected in Models settings — Apple Intelligence, Anthropic, OpenAI, Gemini, or local Ollama."
---

Compose is where dictated text and AI-polished drafts live. The
**Drafts** label in the sidebar opens the same surface — same data,
same diff model.

## Editing by voice

Start a recording inside an existing draft and Talkie treats your speech
as **instructions about the text**, not new dictation. "Make the second
paragraph more direct" or "drop the third bullet" both work; so does
"replace 'soon' with a specific date".

When the rewrite returns, Compose enters a **reviewing** state and
shows:

- the original text and the revision side by side
- inline span markers for each change (insertions, deletions, replacements)

You can:

- **Accept all** — apply the entire diff
- **Accept span** — keep some edits, drop others
- **Reject** — discard the rewrite, keep the original

## What handles the rewrite

The LLM behind the rewrite is whichever is selected for **Compose** in
**Models** settings. The default uses your highest-trust configured
provider; on macOS 15.1+ with no API key set, Apple Intelligence runs
the rewrite on-device.
