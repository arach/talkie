---
id: 00000000-0000-0000-0000-000000000031
name: Research
description: Speak a topic; the agent digs through your memos and the web, then files the brief as a note. Phase 1 ships a single-LLM placeholder — web search + memo-retrieval wiring lands later.
icon: magnifyingglass.circle.fill
color: blue
isEnabled: true
---

WHEN voice "research"

WITH dictation
      ↳ topic

DO llm.research
      ↳ depth: deep
      ↳ sources: memos + web

THEN library.note
