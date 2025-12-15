# Talkie Feature Ideas

## In-Flight Refinement Interstitial

**Status:** Idea
**Date:** 2024-12-15

### Concept
An Alfred/Raycast-style floating window that appears when you hold a modifier (e.g., Shift) while ending a recording. Instead of text going directly to paste, you get a quick refinement step.

### Trigger
- Modifier + end-record hotkey (e.g., Shift + your normal hotkey)

### Experience
1. Centered floating window appears (like Alfred/Raycast)
2. Shows your transcription text
3. One pre-configured quick action button (runs through local LLM)
4. Can hit the action multiple times to iterate/refine
5. Copy or paste out when satisfied

### Why This Matters
- Don't want to open a full editing window
- Don't want to pollute ChatGPT/Claude history
- Don't want to burn cloud API quota
- Not everything needs autocorrect - just sometimes you want a quick polish
- Stay in flow - no context switching to another app

### Technical Notes
- Use local model (Ollama, mlx, etc.) - no cloud dependency
- Quick action could be configurable (grammar fix, restructure, summarize, etc.)
- Window should be dismissable with Escape
- Should feel instant - the "pit stop" between dictation and paste

---

## Background Task Completion Detection (ActionObserver)

**Status:** POC exists but disabled
**Date:** 2024-12-15

### Concept
Detect when background apps complete long-running tasks (e.g., ChatGPT finishes generating) using macOS Accessibility notifications.

### Current State
- ActionObserver.swift exists in TalkieLive
- Currently disabled (adds polling overhead without demonstrated value)
- Never actually tested the core premise: do AX notifications fire for background apps?

### Next Steps If Revisited
1. Grant proper Accessibility permissions
2. Test purely event-driven (no polling)
3. Verify notifications fire for background apps
4. Only then build detection logic

### Files
- `macOS/TalkieLive/TalkieLive/ActionObserver.swift`
