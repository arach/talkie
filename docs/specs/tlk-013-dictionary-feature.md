# TLK-013 — Dictionary & Vocabulary

**Status**: Draft
**Owner**: TBD

## Summary

Two related post-processing features for improving transcription quality:

1. **Personal Dictionary** — user-defined word replacements and technical terms (e.g. `react → React`, `hippa → HIPAA`, `gonna → going to`).
2. **Filler Word Removal** — automatic detection and removal of personal speech patterns (`um`, `uh`, `like`, `you know`).

Both run as passes between raw transcription and the final text that lands in the paste target, memo, or scratchpad.

Inspiration: [VoiceInk](https://github.com/Beingpax/VoiceInk) ("Train the AI to understand your unique terminology with custom words, industry terms, and smart text replacements") and [Wispr Flow](https://wisprflow.ai/) (custom dictionary up to 800 words/phrases).

## User stories

Dictionary:

- As a developer, I want "react" to always be capitalized as "React"
- As a medical professional, I want "HIPAA" spelled correctly, not "hippa"
- As a user, I want "gonna" replaced with "going to" automatically
- As a user, I want shorthand like "btw" expanded to "by the way"

Filler removal:

- As a user, I want to identify my personal filler words from my history
- As a user, I want automatic removal of "um", "uh", "like" from dictations
- As a power user, I want to analyze my speech patterns over time

## Feature 1 — Personal Dictionary

### Data model

```swift
struct DictionaryEntry: Codable, Identifiable {
    let id: UUID
    var trigger: String           // What to look for (case-insensitive match)
    var replacement: String       // What to replace with
    var matchType: MatchType      // How to match
    var isEnabled: Bool           // Quick toggle without deleting
    var category: String?         // Optional grouping (e.g., "Technical", "Names")
    var createdAt: Date
    var usageCount: Int           // Track how often this fires

    enum MatchType: String, Codable {
        case exact          // "react" → "React" (whole word only)
        case caseInsensitive // "React", "REACT", "react" all match
        case prefix         // "dev" matches "developer", "development"
        case contains       // Match anywhere in text
    }
}
```

### Storage

- UserDefaults or dedicated JSON file: `~/Library/Application Support/Talkie/dictionary.json`
- CloudKit sync (optional)
- Import/Export as JSON for sharing

### Processing pipeline

```
[Raw Transcription]
    → [Dictionary Replacement Pass]
    → [Final Text]
```

**Performance target**: < 5 ms for 1000-word transcription with 500 dictionary entries.

### Algorithm

```swift
func applyDictionary(to text: String, entries: [DictionaryEntry]) -> String {
    var result = text

    // Sort by trigger length (longest first) to avoid partial replacements
    let sorted = entries
        .filter { $0.isEnabled }
        .sorted { $0.trigger.count > $1.trigger.count }

    for entry in sorted {
        switch entry.matchType {
        case .exact:
            // Word boundary regex: \b{trigger}\b
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: entry.trigger))\\b",
                with: entry.replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        case .caseInsensitive:
            result = result.replacingOccurrences(
                of: entry.trigger,
                with: entry.replacement,
                options: .caseInsensitive
            )
        // ... other match types
        }
    }

    return result
}
```

### UI sketch — Settings → Dictionary

```
┌─────────────────────────────────────────────────────────┐
│ PERSONAL DICTIONARY                          [+ Add]    │
├─────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────┐ │
│ │ 🔤 react → React                    [✓] 23 uses    │ │
│ │ 🔤 gonna → going to                 [✓] 156 uses   │ │
│ │ 🔤 talkie → Talkie                  [✓] 89 uses    │ │
│ │ 🔤 ios → iOS                        [✓] 12 uses    │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ [Import JSON]  [Export]  [Clear All]                    │
│                                                         │
│ ☑️ Apply dictionary to Live dictations                  │
│ ☑️ Apply dictionary to Memo transcriptions              │
│ ☐ Show replacement indicator in UI                      │
└─────────────────────────────────────────────────────────┘
```

### Add/Edit entry modal

```
┌────────────────────────────────────────┐
│ Add Dictionary Entry                   │
├────────────────────────────────────────┤
│ Trigger:     [react____________]       │
│ Replace with: [React____________]      │
│                                        │
│ Match type:  (•) Exact word match      │
│              ( ) Case insensitive      │
│              ( ) Prefix                │
│                                        │
│ Category:    [Technical________] ▼     │
│                                        │
│         [Cancel]        [Save]         │
└────────────────────────────────────────┘
```

### Integration points

1. **TalkieAgent** — apply after transcription, before paste
2. **Talkie Memos** — apply when transcription completes
3. **ScratchPad** — apply on dictation insert (optional)

## Feature 2 — Filler word detection & removal

### Phase 1: Static filler list (ship first)

```swift
struct FillerWordConfig {
    static let defaultFillers = [
        "um", "uh", "uhh", "umm",
        "like",           // When used as filler, not comparison
        "you know",
        "I mean",
        "basically",
        "actually",       // Often unnecessary
        "literally",      // Often misused
        "so",             // At sentence start
        "right",          // Tag questions
        "okay so",
    ]
}
```

### Phase 2: Personalized filler detection (LLM-powered)

**Input**: last 1000+ dictations from user history.

**Process**:
1. Batch dictations into chunks (100 at a time)
2. Use local MLX model to analyze patterns
3. Identify candidate filler phrases
4. Present to user for confirmation

**Prompt for local LLM**:

```
Analyze these transcriptions from the same speaker. Identify repeated
filler words and phrases that don't add meaning. Return a JSON list of:
- phrase: the filler word/phrase
- count: approximate occurrences
- confidence: how likely this is a filler (0-1)
- suggestion: recommended action (remove, replace, keep)

Transcriptions:
{batch}
```

**Output**:
```json
[
  {"phrase": "you know what I mean", "count": 47, "confidence": 0.95, "suggestion": "remove"},
  {"phrase": "sort of", "count": 23, "confidence": 0.7, "suggestion": "keep"},
  {"phrase": "right right", "count": 31, "confidence": 0.9, "suggestion": "remove"}
]
```

### UI sketch — Filler Word Settings

```
┌─────────────────────────────────────────────────────────┐
│ FILLER WORD REMOVAL                                     │
├─────────────────────────────────────────────────────────┤
│ ☑️ Remove common fillers (um, uh, like)                 │
│                                                         │
│ ┌─ DETECTED FROM YOUR HISTORY ─────────────────────────┐│
│ │ ☑️ "you know" - found 156 times                      ││
│ │ ☑️ "I mean" - found 89 times                         ││
│ │ ☐ "basically" - found 34 times                       ││
│ │ ☐ "right right" - found 23 times                     ││
│ └──────────────────────────────────────────────────────┘│
│                                                         │
│ [Analyze My History]  (Last run: 2 days ago)            │
│                                                         │
│ Processing: ○ Ultra-fast (regex only)                   │
│             ● Smart (context-aware, slightly slower)    │
└─────────────────────────────────────────────────────────┘
```

### Algorithm — smart filler removal

```swift
func removeFillers(from text: String, fillers: [String], mode: ProcessingMode) -> String {
    switch mode {
    case .ultraFast:
        // Simple regex replacement - might over-match
        return regexReplace(text, fillers: fillers)

    case .smart:
        // Context-aware: "like" in "I like pizza" stays, "like" in "it was like amazing" goes
        return contextAwareRemoval(text, fillers: fillers)
    }
}

func contextAwareRemoval(_ text: String, fillers: [String]) -> String {
    // Use simple heuristics, not LLM:
    // 1. "like" followed by adjective/adverb → filler
    // 2. "you know" at sentence boundaries → filler
    // 3. Repeated words → filler ("right right", "yeah yeah")
    // ...
}
```

## Implementation priority

### MVP (week 1)
- [ ] `DictionaryEntry` model and storage
- [ ] Basic dictionary UI in Settings
- [ ] Apply dictionary to TalkieAgent transcriptions
- [ ] Static filler word removal (regex)

### V1.1 (week 2)
- [ ] Dictionary import/export
- [ ] Usage statistics
- [ ] Context-aware filler removal

### V1.2 (future)
- [ ] LLM-powered filler detection from history
- [ ] CloudKit sync for dictionary
- [ ] Suggested entries based on common corrections

## Files to create/modify

### New files
- `apps/macos/Talkie/Models/DictionaryEntry.swift` — data model
- `apps/macos/Talkie/Services/DictionaryManager.swift` — storage & processing
- `apps/macos/Talkie/Views/Settings/DictionarySettings.swift` — settings UI
- `apps/macos/TalkieAgent/Services/TextPostProcessor.swift` — apply to live dictation

### Modify
- `apps/macos/TalkieAgent/Services/TranscriptionPipeline.swift` — hook in post-processing
- `apps/macos/Talkie/Views/Settings/SettingsView.swift` — add dictionary section

## Open questions

1. Should dictionary sync across devices via CloudKit?
2. Max number of dictionary entries before performance degrades?
3. Should we show a "X replacements made" indicator after dictation?
4. For filler removal: remove silently or show struck-through in UI?
