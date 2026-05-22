---
id: 00000000-0000-0000-0000-000000000034
name: Monitor
description: A passive watcher that pings you when a topic moves — new memo, new mention, new context. Phase 1 ships a single-LLM placeholder — Automation scheduling + change-detection wiring lands later.
icon: antenna.radiowaves.left.and.right
color: purple
isEnabled: true
---

WHEN schedule
      ↳ every 30m

WITH context
      ↳ inbox + recent memos

DO llm.watch
      ↳ condition: meaningful change

THEN notification
