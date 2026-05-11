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

## Background Task Completion Detection

**Status:** Idea (code deleted)
**Date:** 2024-12-15

### Concept
Detect when background apps complete long-running tasks (e.g., ChatGPT finishes generating) using macOS Accessibility notifications.

### History
- ActionObserver.swift existed in TalkieAgent but was never integrated
- Deleted 2025-02 as dead code (added polling overhead, never called)
- Core premise was never validated: do AX notifications fire for background apps?

### If Revisited
1. Start fresh with event-driven approach (no polling)
2. Grant proper Accessibility permissions
3. Verify notifications fire for background apps
4. Only then build detection logic

---

## Unified Settings & Debug UI Across All Apps

**Status:** Idea
**Date:** 2025-01-22

### Problem
The three Talkie apps (Talkie, TalkieAgent, TalkieEngine) have inconsistent settings UIs:
- **Talkie** has well-structured settings with debug info sections
- **TalkieAgent** has settings but could benefit from similar debug info views
- **TalkieEngine** looks "foreign" compared to the other two - needs UI modernization

### Goal
Bring consistency across all three apps so they feel like a unified suite:
1. Shared design language (colors, spacing, typography)
2. Similar settings structure where applicable
3. Debug info sections in each app showing:
   - Version info
   - Current state/configuration
   - Diagnostic data relevant to that app's domain

### Per-App Debug Info

**TalkieAgent:**
- Audio capture strategy in use
- Current input device + format
- Buffer stats during recording
- XPC connection status

**TalkieEngine:**
- Loaded model info (Whisper/Parakeet)
- Transcription queue status
- Memory usage
- XPC service health

**Talkie (main app):**
- Already has debug settings
- Could add cross-app health dashboard

### Technical Notes
- Reuse design components from TalkieKit where possible
- Consider extracting shared settings components to a package
- TalkieEngine needs the most work - currently very utilitarian

---

## DEPRECATED: TWF (Talkie Workflow Format)
*Note: This format is inactive. Future workflow implementations will use a new schema.*