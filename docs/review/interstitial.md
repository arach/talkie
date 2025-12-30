# Interstitial Module

`macOS/Talkie/Interstitial/` - Floating editor panel

Triggered via `talkie://interstitial/{id}` URL from TalkieLive (Shift-click to stop recording).

---

## Overview

The Interstitial module provides a floating editor panel for:
- Reviewing transcribed text before pasting
- Editing and polishing with LLM assistance
- Voice-guided editing ("make it more concise")
- Diff-based review of changes
- Smart actions (Fix Grammar, Concise, Professional, Bullet Points)

**Flow:** TalkieLive Shift-click → URL scheme → InterstitialManager.show() → Edit/Polish → Paste/Copy

---

## Files

### InterstitialManager.swift (~573 lines)
Panel lifecycle and orchestration. Singleton.

**Discussion:**
- **Singleton:** `InterstitialManager.shared`
- **Pattern:** @Observable for SwiftUI binding
- **Panel:** Creates floating NSPanel with `.nonactivatingPanel` style
- **State Machine:**
  - `.editing` - Normal text editing
  - `.reviewing` - Diff review after polish

**Key Properties:**
- `isVisible: Bool` - Panel visibility
- `currentDictationId: Int64?` - ID of loaded dictation
- `editedText: String` - Current text being edited
- `originalText: String` - Original transcription (for reset)
- `viewState: InterstitialViewState` - editing/reviewing
- `prePolishText: String` - Text before last polish (for diff)

**Voice Guidance:**
- `startVoiceInstruction()` - Start recording voice command
- `stopVoiceInstruction()` - Stop and transcribe via EphemeralTranscriber
- `cancelVoiceInstruction()` - Cancel without using
- Uses `EphemeralTranscriber.shared` for audio capture

**LLM Polish:**
- `polishText(instruction:)` - Apply LLM transformation
- Uses `LLMProviderRegistry` for provider resolution
- Configurable via `llmTemperature`, `llmMaxTokens`, `systemPrompt`
- Tracks `lastUsedProvider`, `lastUsedModel` for transparency

**Edit History:**
- In-memory micro-history of edits during session
- `EditSnapshot` - timestamp, instruction, before/after text
- `previewSnapshot(_:)` / `restoreFromSnapshot(_:)` - Preview and restore

**Actions:**
- `copyAndDismiss()` - Copy to clipboard and close
- `copyToClipboard()` - Copy without dismissing
- `pasteAndDismiss()` - Copy, close, simulate Cmd+V
- `openInDestination(_:)` - Open in target app via QuickOpenService
- `resetText()` - Revert to original
- `saveAsMemo()` - Promote to permanent memo
- `acceptChanges()` / `rejectChanges()` - Diff review actions

---

### InterstitialEditorView.swift
SwiftUI editor view with formatting toolbar.

**Discussion:**
- Theme-aware (light/dark mode)
- Split into `editingView` and `reviewingView`
- Smart actions bar with expandable prompts
- Custom instruction input field
- Voice recording button with audio level visualization
- Copy/Paste action buttons

**Layout:**
- Header bar with close button
- Main content area (text editor)
- Smart actions row
- Custom instruction input
- Footer bar with actions

---

### DiffReviewView.swift
Before/after diff display.

**Discussion:**
- Side-by-side or inline diff display
- Deletions in red with strikethrough
- Insertions in green with highlight
- Accept/Reject buttons
- Uses `TextDiff.attributedOriginal/Proposed` for styling

---

### TextDiff.swift (~348 lines)
Word-based diff using Longest Common Subsequence algorithm.

**Discussion:**
- **DiffOperation:** `.equal`, `.delete`, `.insert`
- **Algorithm:** LCS-based dynamic programming
- **Tokenization:** Word-level with newline preservation

**Key Types:**
- `TextDiff` - Container for operations
  - `changeCount` - Number of changes
  - `hasChanges` - Quick check
  - `attributedOriginal/Proposed` - Styled AttributedString

- `DiffEngine.diff(original:proposed:)` - Main entry point

**Performance:**
- O(m*n) time and space complexity
- Optimized for typical voice memo lengths (~10k words)
- Case-insensitive matching for stability

---

### SmartAction.swift (~101 lines)
Quick actions: Fix grammar, Make concise, Expand, Professional tone.

**Discussion:**
- Struct with `id`, `name`, `icon`, `defaultPrompt`
- Built-in actions:
  - **Fix Grammar** - Grammar, spelling, punctuation
  - **Concise** - 30-50% length reduction
  - **Professional** - Business communication tone
  - **Bullet Points** - Convert to organized list

**Prompt Templates:**
- Detailed guidelines for consistent results
- Explicit instruction to "return only the text"
- Preserve original meaning emphasis

---

### DictationPill.swift
Status indicator pill showing current state.

**Discussion:**
- States: idle, recording, transcribing, polishing
- Animated transitions
- Audio level visualization during recording

---

## Architecture Notes

**URL Scheme Flow:**
1. TalkieLive records with Shift held
2. Stores dictation with `mode: "interstitial"`
3. Opens `talkie://interstitial/{id}` URL
4. Talkie handles via Router → InterstitialManager.show()

**Panel Behavior:**
- Floating level (above normal windows)
- Non-activating (doesn't steal focus from target app)
- Escape key dismisses
- Resizable with min/max constraints

**Edit History:**
- Session-only (cleared on dismiss)
- Each polish creates a snapshot
- Non-destructive restoration (creates new history entry)

---

## TODO

- [ ] Consider persisting edit history across sessions
- [ ] Add undo/redo keyboard shortcuts
- [ ] Review paste simulation reliability

## Done

- [x] Complete documentation of InterstitialManager
- [x] Document diff algorithm
- [x] Document smart actions
- [x] Document voice guidance flow
