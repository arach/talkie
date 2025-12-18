# Ambient Live Mode: Continuous Voice Buffer

**Status:** Parking Lot
**Created:** 2024-12-18
**Author:** Architecture discussion with Claude

## Overview

Transform Live Mode from an explicit "start/stop recording" model to an **ambient, always-on voice buffer** with selective export. The paradigm shift: instead of deciding when to record, you decide when to *use* what you've already recorded.

## The Core Idea

**Current model:** "I want to record" → Start Live → Dictate → Stop → Process
**New model:** Live Mode always on → Dictate naturally → "I want THIS" → Export segment

## Why This Works (Local-First Advantage)

This is only viable because Talkie runs locally:

- **Privacy**: All transcription stays on your machine. No cloud, no leaks.
- **Cost**: One-time Whisper model download, then infinite usage. No per-minute API costs.
- **Always-on**: No rate limits, no metering, no "should I record this?" decisions.
- **Zero friction**: No cognitive overhead. Just speak. Pull segments when needed.

**Counter-positioning:** This would be impossible/unusable/creepy as a cloud service:
- Cost would be prohibitive (continuous transcription 8+ hours/day)
- Privacy concerns would be massive
- Subscription pricing would be untenable

Local-first makes this a feature, not a liability.

## Visual UI Concept

### Timeline View (Command modifier reveal)

```
┌─ Screen (⌘ held) ────────────────────┐
│                                       │
│  [5m ago] "Refactor auth flow..."    │ ← Auto-summarized snapshots
│  [10m ago] "Bug in user validation"  │   Appear on left edge
│  [15m ago] "Update dependencies"     │   Click to copy/use
│  [20m ago] "Planning database..."    │
│                                       │
│         Your coding workspace         │
│                                       │
└───────────────────────────────────────┘
```

### Snapshot Cards

Each 5-minute segment is a hoverable card:
- **Title**: AI-generated summary (1 line)
- **Timestamp**: Relative ("5m ago") and absolute
- **Context**: Active file, git branch, project
- **Preview**: Hover to see full transcript
- **Actions**:
  - Click → Copy to clipboard
  - Shift+Click → Send to active agent as context
  - Cmd+Click → Open in scratchpad for editing
  - Drag → Combine multiple segments

## Technical Architecture

### Continuous Capture Flow

1. **Always listening** - TalkieLive runs in background, capturing audio
2. **Rolling transcription** - Whisper processes in 30-second chunks (local, fast)
3. **5-minute finalization** - Every 5 minutes:
   - Transcribe accumulated audio
   - Generate AI summary (1-2 sentences)
   - Tag with context (active app, file, git state)
   - Create snapshot card
   - Store in local database
4. **Retention policy** - Keep last 8 hours, configurable

### Storage Schema

```swift
struct VoiceSnapshot {
    let id: UUID
    let timestamp: Date
    let duration: TimeInterval
    let transcript: String
    let summary: String

    // Context
    let activeFile: String?
    let gitBranch: String?
    let activeProject: String?

    // Metadata
    let wordCount: Int
    let topics: [String]  // Extracted keywords
}
```

### Quick Actions

**Keyboard shortcuts:**
- `⌘ + Shift + V` → Show voice timeline
- `⌘ + Shift + L` → Copy last 10 minutes to clipboard
- `⌘ + Shift + P` → Promote current segment to memo

**Integration points:**
- **Cursor/IDE**: Paste voice segments as comments or context
- **Agent feedback**: Send voice context to active Claude session
- **Memo promotion**: Long-form ideas → permanent memos
- **Search**: "What was I saying about auth?"

## Target User

The **hardcore developer** who already thinks in:
- **Buffers** - Voice is just another buffer (like Vim registers)
- **Context management** - Already juggling terminal, editor, browser
- **Keyboard-driven workflows** - Minimal mouse, maximum efficiency
- **Local tools** - Prefers local-first, owns their data

Think: Vim/Emacs user, Linux enthusiast, terminal dweller.

## Use Cases

### 1. Coding Commentary
```
[Working on auth refactor]
You (speaking): "Need to check permissions before state updates..."
[5 minutes later, agent breaks something]
→ Shift+Click on that snapshot
→ Sends to agent: "Earlier context: [transcript]"
```

### 2. Design Discussion
```
[Whiteboarding session with team]
Live Mode captures entire discussion
→ End of meeting: "Copy last 30 minutes"
→ Paste into GitHub issue as context
```

### 3. Idea Parking
```
[Dictating a long idea while coding]
You: "Oh, I want to save this"
→ Cmd+Shift+P on current segment
→ Promotes to memo for later review
```

### 4. Ambient Agent Interaction
```
You: "Hey Claude, what was I saying about database migrations in the last hour?"
→ Searches voice buffer
→ Summarizes: "You mentioned 3 points..."
→ "Send point #2 to the agent working on schema.ts"
```

## Implementation Phases

### Phase 1: Core Buffer (MVP)
- Continuous audio capture in TalkieLive
- Local Whisper transcription (rolling 30s chunks)
- 5-minute snapshot creation with timestamps
- Simple timeline view (⌘ to reveal)
- Click to copy transcript

### Phase 2: Smart Features
- AI-generated summaries for each snapshot
- Context tagging (active file, git branch)
- Search/filter voice history
- Keyword extraction and topics

### Phase 3: Integration
- IDE plugins (Cursor, VS Code)
- Agent context injection
- Memo promotion workflow
- Configurable retention policies

### Phase 4: Polish
- Combine/edit segments before export
- Voice search ("play back when I said X")
- Snapshot annotations/labels
- Export to various formats (Markdown, JSON, plain text)

## Open Questions

1. **Privacy controls**: How to prevent accidental capture of sensitive info?
   - Pause zones (auto-pause when certain apps are active)?
   - Retroactive deletion ("delete last 5 minutes")?

2. **Performance**: Can local Whisper keep up with continuous transcription?
   - Benchmark: 8 hours of audio = how much CPU/battery?
   - Quality vs speed tradeoff?

3. **Storage**: 8 hours of transcripts per day = how much disk space?
   - Compression strategies?
   - Cloud backup (encrypted)?

4. **Accuracy**: How to handle transcription errors in buffer?
   - Manual correction before promotion?
   - Confidence scores?

## Success Metrics

- **Engagement**: % of Live Mode users who enable ambient mode
- **Usage**: Average snapshots exported per day
- **Retention**: Do users keep it on all day?
- **Promotion**: How often do voice segments → memos?
- **Agent integration**: How often sent to Claude as context?

## Competitive Advantage

**No other tool does this** because:
1. Most are cloud-based (cost prohibitive)
2. Privacy concerns for always-on recording
3. Require explicit start/stop (high friction)
4. Not local-first (can't run 8+ hours offline)

Talkie's local-first architecture makes this a **defensible moat**.

## Why Parking Lot?

Need to:
1. ✅ Finish status bar improvements
2. Land existing Live Mode features
3. Unify branches (feature/unify-live-ui)
4. Polish current UX

Once core is solid, ambient mode becomes a **killer differentiator** for power users.

---

## Appendix: Interaction Patterns

### Buffer as First-Class Concept

For Vim/Emacs users, this maps naturally:

**Vim analogy:**
- Voice buffer = unnamed register (`"`)
- Snapshots = numbered registers (`"0`, `"1`, etc.)
- `:reg` → Show voice timeline
- `"1p` → Paste snapshot #1

**Emacs analogy:**
- Voice buffer = kill ring
- Snapshots = kill ring entries
- `M-y` → Cycle through snapshots
- `C-y` → Yank (paste) selected snapshot

### Command Palette Integration

```
Cmd+K → "Voice: Show timeline"
Cmd+K → "Voice: Copy last 10 minutes"
Cmd+K → "Voice: Search for 'authentication'"
Cmd+K → "Voice: Promote to memo"
```

Natural extension of existing keyboard-driven workflows.
