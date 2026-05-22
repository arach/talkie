---
id: 00000000-0000-0000-0000-000000000032
name: Prepare
description: Pull every memo, note, and capture about a topic; synthesize a brief — for a meeting, a doc, anything. Phase 1 ships a single-LLM placeholder — local-context search lands later.
icon: doc.text.magnifyingglass
color: green
isEnabled: true
---

WHEN voice "prepare"

WITH dictation
      ↳ for what

DO search.local
      ↳ scope: memos, notes, captures
      ↳ window: 14d

DO llm.synthesize

THEN library.note
