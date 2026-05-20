---
id: 00000000-0000-0000-0000-000000000007
name: Capture Thought
description: library.note maps to `.saveFile` for Phase 1 — writes to `~/Library/Application Support/Talkie/Library/notes/` as markdown. Library indexing comes in a later phase.
icon: lightbulb.fill
color: yellow
isEnabled: true
---

WHEN voice "capture"

WITH dictation

DO   library.note
      ↳ title: derived
      ↳ tags: auto-classify

THEN voice ack
