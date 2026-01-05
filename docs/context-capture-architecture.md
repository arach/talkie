# Context Capture Flow in TalkieLive

## Overview

Context capture happens at **two points** in the dictation lifecycle to balance latency and richness.

---

## 1. WHAT TRIGGERS CONTEXT CAPTURE

### Point 1: Baseline Capture (Synchronous, ~1ms)
- **When**: Immediately when the user presses the hotkey to start recording
- **Where**: `LiveController.swift` line 385: `capturedContext = ContextCaptureService.shared.captureBaseline()`
- **Why**: Captures the "true" target app before focus might change
- **What it gets**: App name, bundle ID, window title, document URL (fast, no AX queries)

### Point 2: Enrichment (Asynchronous, ~250-400ms)
- **When**: After transcription completes and text is ready to be pasted
- **Where**: `ContextCaptureService.swift` line 240: `scheduleEnrichment()`
- **How**: Fire-and-forget background task that updates the database record after paste
- **What it gets**: Rich AX context (focused element details, selected text, browser URLs, terminal working directory)

This two-phase approach **keeps paste latency low** while still capturing rich context.

---

## 2. WHAT METADATA IS COLLECTED

### Basic App Context
```
activeAppBundleID       - e.g., "com.googlecode.iterm2"
activeAppName           - e.g., "iTerm2"
activeWindowTitle       - e.g., "claude ✳ talkie"
endAppBundleID          - (captured after paste, if user switched apps)
endAppName              - Where the user was when done
endWindowTitle          - The end window title
```

### Document/File Context
```
documentURL             - File path (Xcode, editors) or web URL (browsers)
browserURL              - Full URL extracted from browser AX
terminalWorkingDir      - Parsed from terminal window title (e.g., "~/dev/talkie")
```

### Focused Element Context (only in rich mode)
```
focusedElementRole      - AX role (AXTextArea, AXWebArea, AXTextField, etc.)
focusedElementValue     - Truncated content (code, terminal output, form text)
focusedDescription      - AX description attribute
```

### Performance Metrics
```
perfEngineMs            - Transcription time in TalkieEngine
perfEndToEndMs          - Total: stop-recording → delivery
perfInAppMs             - TalkieLive in-app processing time
```

---

## 3. CLAUDE CODE SESSION DETECTION

### Layer 1: BridgeContextMapper (Real-Time Detection)

`extractSessionId()` detects Claude sessions by:

1. **Window title analysis**:
   - Checks if title contains "claude" (case-insensitive)
   - Checks for "✳" prefix (Claude Code's task indicator)
   - Looks for " - " separator followed by a path

2. **Working directory extraction**:
   - If terminal title shows a path pattern like `user@host:~/dev/project`
   - Uses path to generate session ID: `/Users/arach/dev/talkie` → `-Users-arach-dev-talkie`

3. **Fallback detection via TerminalScanner**:
   - If window title has "✳" prefix but no working directory in metadata
   - Scans all terminals to find matching window

### Layer 2: TerminalScanner (Proactive Scanning)

`detectClaudeSession()` identifies Claude sessions by:

1. **Direct title keywords**: "claude", "claude code", "anthropic"
2. **Project folder verification**: Checks if `~/.claude/projects/{sessionId}/` exists
3. **Session ID conversion**: `/Users/arach/dev/talkie` → `-Users-arach-dev-talkie`

---

## 4. BridgeContextMapper's Role

Maintains a JSON file at `~/Library/Application Support/Talkie/.context/session-contexts.json`

### Data Structures

```swift
SessionContext {
    app: String                    // Most recent app (e.g., "iTerm2")
    bundleId: String               // Bundle ID
    windowTitle: String            // Window title
    pid: pid_t?                    // Process ID
    workingDirectory: String?      // e.g., "~/dev/talkie"
    timestamp: Date                // Last update time
    apps: [String]                 // History of apps used
    dictations: [DictationRecord]  // Last 50 dictations
}

DictationRecord {
    id: String                     // UUID
    text: String                   // Preview (first 200 chars)
    app: String                    // App when dictated
    bundleId: String
    windowTitle: String
    timestamp: Date
}
```

### When It Gets Updated

1. **After each dictation** (`updateAfterDictation()`):
   - Checks if the recording app is a terminal
   - Extracts session ID from window title or working directory
   - Records the dictation text snippet, app, and context
   - Keeps history of last 50 dictations per session

2. **From terminal scans** (`updateFromTerminalScan()`):
   - Updates all Claude session contexts with current PIDs
   - Preserves existing history

---

## 5. KEY FILES & FUNCTIONS

### ContextCaptureService.swift (~500 lines)
- `captureBaseline()` - Synchronous baseline capture
- `scheduleEnrichment()` - Async enrichment task
- `captureRichContext()` - Deep AX context capture
- `getFocusedWindowInfo()` - AX window extraction
- `getFocusedElementInfo()` - AX element details

### BridgeContextMapper.swift (~400 lines)
- `updateAfterDictation()` - Main update hook
- `extractSessionId()` - Core Claude detection logic
- `getContextByProjectPath()` - Reverse lookup

### TerminalScanner.swift (~260 lines)
- `scanAllTerminals()` - Full scan of open terminals
- `detectClaudeSession()` - Claude session heuristics
- `extractClaudeSessionId()` - Path-to-ID conversion

### LiveController.swift (~1200 lines)
- `start()` - Captures baseline on hotkey press
- `process()` - Triggers enrichment after transcription

---

## 6. DATA FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────┐
│                     User presses hotkey                      │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
        ┌─────────────────────────────────────────┐
        │  LiveController.start()                 │
        │  - Capture target app IMMEDIATELY       │
        │  - Start recording audio                │
        └────────────┬────────────────────────────┘
                     │
      ┌──────────────▼──────────────┐
      │  ContextCaptureService       │
      │  .captureBaseline()          │
      │  (~1ms - synchronous)        │
      └──────────────┬───────────────┘
                     │
      ┌──────────────┴─────────────────────┐
      │  User stops recording (hotkey up)  │
      └──────────────┬─────────────────────┘
                     │
         ┌───────────▼──────────────────────┐
         │  Transcription completes         │
         │  Text is ready to paste          │
         └───────────┬──────────────────────┘
                     │
    ┌────────────────▼─────────────────────┐
    │  Save to GRDB with baseline context  │
    │  (Do NOT wait for enrichment)        │
    └────────────────┬─────────────────────┘
                     │
    ┌────────────────▼────────────────────────────────┐
    │  Route transcript (paste/clipboard/queue)       │
    │  (Fast path - user sees immediate paste)        │
    └────────────────┬────────────────────────────────┘
                     │
  ┌──────────────────▼──────────────────────────────┐
  │  Background: scheduleEnrichment()               │
  │  (Fire-and-forget, doesn't block paste)         │
  │                                                  │
  │  1. captureRichContext() (async, 250-400ms)     │
  │  2. Merge baseline + rich context               │
  │  3. Update GRDB record with enriched metadata   │
  │  4. Call BridgeContextMapper.updateAfterDict()  │
  └────────────┬───────────────────────────────────┘
               │
    ┌──────────▼──────────────────────────────┐
    │  BridgeContextMapper.updateAfterDict()  │
    │                                          │
    │  1. Check if app is terminal            │
    │  2. Extract session ID                  │
    │  3. Record dictation history            │
    │  4. Save to session-contexts.json       │
    └─────────────────────────────────────────┘
```

---

## 7. SUMMARY

**Context capture in TalkieLive is a two-phase, non-blocking flow:**

1. **Baseline** (1ms, synchronous) - captures target app/window
2. **Enrichment** (250-400ms, background) - captures rich AX context without delaying paste
3. **Claude detection** uses three signals: "claude" keyword, "✳" prefix, project folder existence
4. **BridgeContextMapper** maintains persistent session history at `~/Library/Application Support/Talkie/.context/session-contexts.json`
5. **TerminalScanner** proactively scans terminals to detect Claude sessions

This prioritizes **low latency for the user** while **collecting rich context asynchronously**.
