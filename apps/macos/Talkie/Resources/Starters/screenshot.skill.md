---
id: 00000000-0000-0000-0000-000000000033
name: Screenshot
description: Say "screenshot" to capture without lifting a finger — voice-first version of the Hyper+S chord. Phase 1 stops at the LLM placeholder; voice-triggered capture handoff to the Agent screenshot service lands next.
icon: camera.viewfinder
color: orange
isEnabled: true
---

WHEN voice "screenshot"

WITH context
      ↳ active window

DO screenshot.capture
      ↳ mode: window

THEN voice ack
