# Multi-Dictionary Architecture

## Overview

Talkie supports multiple dictionaries for different domains, each independently managed and applied to transcriptions. This enables users to organize vocabulary by context (technical, industry, codebase, personal) and control which dictionaries are active.

## Data Model

### Dictionary

```swift
struct Dictionary: Codable, Identifiable {
    let id: UUID
    var name: String
    var type: DictionaryType
    var isEnabled: Bool
    var priority: Int              // Lower = applied first
    var source: DictionarySource
    var createdAt: Date
    var updatedAt: Date

    // Metadata
    var description: String?
    var author: String?
    var version: String?
}

enum DictionaryType: String, Codable {
    case technical    // Programming, syntax, tech terms
    case domain       // Industry-specific (medical, legal, finance)
    case codebase     // Project-specific identifiers
    case personal     // Names, places, custom terms
    case shorthand    // Abbreviation expansions (AFK, BTW, LGTM)
    case imported     // External dictionary files
}

enum DictionarySource: Codable {
    case manual                    // User-created entries
    case imported(URL)             // Imported from file
    case generated(GeneratorType)  // Auto-generated
}

enum GeneratorType: String, Codable {
    case codebase      // Scanned from source files
    case contacts      // From system contacts
    case calendar      // From calendar events
}
```

### Entry (unchanged from current)

```swift
struct DictionaryEntry: Codable, Identifiable {
    let id: UUID
    var trigger: String
    var replacement: String
    var matchType: MatchType
    var isEnabled: Bool
    var category: String?
    var usageCount: Int
    var createdAt: Date
}

enum MatchType: String, Codable {
    case exact           // Word boundary, case-sensitive
    case caseInsensitive // Word boundary, any case
    case contains        // Substring match (future)
    case regex           // Full regex (future, power users)
}

enum EntryBehavior: String, Codable {
    case correction   // Fix transcription error: ios → iOS
    case expansion    // Expand shorthand: AFK → away from keyboard
}
```

## File Structure

```
~/Library/Application Support/Talkie/
└── Dictionaries/
    ├── manifest.json           # Index of all dictionaries
    ├── tech-general.dict.json  # Built-in tech terms
    ├── personal.dict.json      # User's personal dictionary
    ├── myapp-codebase.dict.json
    └── imported/
        └── medical-terms.dict.json
```

### manifest.json

```json
{
  "version": 1,
  "dictionaries": [
    {
      "id": "uuid-1",
      "name": "Tech & Programming",
      "type": "technical",
      "filename": "tech-general.dict.json",
      "isEnabled": true,
      "priority": 10,
      "source": { "type": "manual" },
      "entryCount": 45,
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-12-01T14:30:00Z"
    },
    {
      "id": "uuid-2",
      "name": "Talkie Codebase",
      "type": "codebase",
      "filename": "talkie-codebase.dict.json",
      "isEnabled": true,
      "priority": 20,
      "source": {
        "type": "generated",
        "generator": "codebase",
        "path": "/Users/arach/dev/talkie"
      },
      "entryCount": 128,
      "createdAt": "2024-12-01T09:00:00Z",
      "updatedAt": "2024-12-01T09:00:00Z"
    }
  ]
}
```

### Dictionary File (.dict.json)

```json
{
  "id": "uuid-1",
  "name": "Tech & Programming",
  "version": "1.0",
  "entries": [
    {
      "id": "entry-uuid-1",
      "trigger": "ios",
      "replacement": "iOS",
      "matchType": "caseInsensitive",
      "isEnabled": true,
      "category": "Apple",
      "usageCount": 42
    }
  ]
}
```

## Engine Architecture

### DictionaryEngine (replaces TextPostProcessor)

```swift
@MainActor
final class DictionaryEngine {
    static let shared = DictionaryEngine()

    // State
    private(set) var dictionaries: [Dictionary] = []
    private(set) var isGlobalEnabled: Bool = true
    private var matcher: OptimizedMatcher?

    // Paths
    private let dictionariesDir: URL
    private let manifestURL: URL

    // MARK: - Loading

    func loadAll() async {
        // Load manifest
        // Load each enabled dictionary's entries
        // Build optimized matcher
    }

    func reload(dictionaryId: UUID) async {
        // Reload single dictionary, rebuild matcher
    }

    // MARK: - Processing

    func process(_ text: String) -> ProcessingResult {
        guard isGlobalEnabled, let matcher else {
            return ProcessingResult(original: text, processed: text)
        }
        return matcher.process(text)
    }

    // MARK: - Matcher Rebuilding

    private func rebuildMatcher() {
        // Collect all enabled entries from enabled dictionaries
        // Sort by priority, then by trigger length
        // Build optimized data structure
        matcher = OptimizedMatcher(entries: allEnabledEntries)
    }
}
```

### OptimizedMatcher (future performance layer)

```swift
final class OptimizedMatcher {
    // Phase 1: Simple implementation (current approach)
    // - Sorted entries, sequential replacement

    // Phase 2: Compiled regex
    // - Single alternation pattern: (trigger1|trigger2|...)
    // - One pass through text

    // Phase 3: Aho-Corasick
    // - Trie-based multi-pattern matching
    // - O(text_length + matches)

    func process(_ text: String) -> ProcessingResult
}
```

## Sync Flow

```
Talkie                              TalkieEngine
───────                             ────────────

DictionaryService                   DictionaryEngine
    │                                    │
    ├── Manages Dictionaries/            ├── Receives via XPC
    │   folder in Talkie's               │
    │   App Support                      ├── Stores in TalkieEngine's
    │                                    │   App Support (own copy)
    ├── UI for managing                  │
    │   dictionaries                     ├── Builds OptimizedMatcher
    │                                    │
    └── Syncs enabled dictionaries ────► └── Processes transcriptions
        via XPC on changes
```

### XPC Protocol Extensions

```swift
protocol TalkieEngineXPCProtocol {
    // Existing
    func updateDictionary(_ entries: [DictionaryEntry]) async throws
    func setDictionaryEnabled(_ enabled: Bool) async

    // New
    func syncDictionaries(_ dictionaries: [DictionarySync]) async throws
    func getDictionaryStatus() async -> DictionaryEngineStatus
}

struct DictionarySync: Codable {
    let id: UUID
    let name: String
    let priority: Int
    let entries: [DictionaryEntry]
}

struct DictionaryEngineStatus: Codable {
    let isGlobalEnabled: Bool
    let loadedDictionaries: [LoadedDictionaryInfo]
    let totalEntries: Int
    let lastProcessedAt: Date?
    let matcherType: String  // "simple", "regex", "aho-corasick"
}

struct LoadedDictionaryInfo: Codable {
    let id: UUID
    let name: String
    let entryCount: Int
    let isEnabled: Bool
    let priority: Int
}
```

## UI Architecture

### Settings → Dictionaries

```
┌─────────────────────────────────────────────────────────────────┐
│ DICTIONARIES                                          [+ New ▼] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─ Master Toggle ────────────────────────────────────────────┐ │
│  │  ● Dictionary Processing                         [ON/OFF]  │ │
│  │    Apply word replacements to all transcriptions           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─ Engine Status ────────────────────────────────────────────┐ │
│  │  ✓ Connected  •  3 dictionaries  •  156 entries loaded     │ │
│  │  Last sync: 2 minutes ago                                  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ─── ACTIVE DICTIONARIES ───────────────────────────────────── │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ [≡] ☑ Tech & Programming                    45 entries  ▸ │ │
│  │     General programming and technology terms               │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │ [≡] ☑ Talkie Codebase                      128 entries  ▸ │ │
│  │     Auto-generated from /Users/arach/dev/talkie            │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │ [≡] ☐ Medical Terms                         89 entries  ▸ │ │
│  │     Imported • Disabled                                    │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ─── DROP ZONE ─────────────────────────────────────────────── │
│  ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐ │
│  ╎                                                            ╎ │
│  ╎         Drop .dict.json file to import                     ╎ │
│  ╎                                                            ╎ │
│  └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘ │
│                                                                 │
│  [Reveal in Finder]  [Refresh from Engine]                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Dictionary Detail (Side Panel)

```
┌─────────────────────────────────────────┐
│ Tech & Programming                   ✕  │
├─────────────────────────────────────────┤
│ Type: Technical                         │
│ Entries: 45  •  Used: 1,247 times       │
│ Priority: 10 (applied first)            │
│                                         │
│ [Edit JSON]  [Export]  [Delete]         │
├─────────────────────────────────────────┤
│ 🔍 Search entries...                    │
├─────────────────────────────────────────┤
│ ☑ ios → iOS                    (142)    │
│ ☑ api → API                     (89)    │
│ ☑ json → JSON                   (67)    │
│ ☑ macos → macOS                 (45)    │
│ ☐ graphql → GraphQL              (0)    │
│ ...                                     │
├─────────────────────────────────────────┤
│ [+ Add Entry]                           │
└─────────────────────────────────────────┘
```

## Codebase Scanner (Future)

```swift
struct CodebaseScanner {
    let rootPath: URL
    let languages: Set<Language>  // .swift, .typescript, .python

    func scan() async -> [DictionaryEntry] {
        // 1. Find source files
        // 2. Parse for identifiers:
        //    - Class/struct/enum names
        //    - Function names
        //    - Constants
        //    - Type aliases
        // 3. Generate entries:
        //    - "talkieengine" → "TalkieEngine"
        //    - "grdb" → "GRDB"
        // 4. Filter common words, stdlib types
    }
}
```

## JSON Schema

For external tools and validation:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Talkie Dictionary",
  "type": "object",
  "required": ["id", "name", "entries"],
  "properties": {
    "id": { "type": "string", "format": "uuid" },
    "name": { "type": "string", "minLength": 1 },
    "version": { "type": "string" },
    "description": { "type": "string" },
    "entries": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["trigger", "replacement"],
        "properties": {
          "id": { "type": "string", "format": "uuid" },
          "trigger": { "type": "string", "minLength": 1 },
          "replacement": { "type": "string" },
          "matchType": {
            "type": "string",
            "enum": ["exact", "caseInsensitive"],
            "default": "caseInsensitive"
          },
          "isEnabled": { "type": "boolean", "default": true },
          "category": { "type": "string" }
        }
      }
    }
  }
}
```

## Migration Path

### Phase 1: Current → Multi-Dictionary Files
1. Move existing `dictionary.json` to `Dictionaries/personal.dict.json`
2. Create `manifest.json` with single dictionary entry
3. Update DictionaryManager to use new paths
4. No Engine changes needed (still receives flat entry list)

### Phase 2: Engine Status & UI
1. Add XPC method for `getDictionaryStatus()`
2. Build new DictionarySettingsView with dictionary list
3. Add drop zone for imports
4. Add "Reveal in Finder" / "Edit JSON" buttons

### Phase 3: Per-Dictionary Sync
1. Update XPC to sync dictionary metadata + entries
2. Engine stores dictionaries separately
3. Engine reports per-dictionary stats

### Phase 4: Performance Optimization
1. Implement compiled regex matcher
2. Benchmark and profile
3. Consider Aho-Corasick if needed (1000+ entries)

### Phase 5: Codebase Generator
1. Build CodebaseScanner
2. UI for selecting project path
3. Auto-refresh option (watch for file changes)

## Shorthand Dictionaries

Shorthand is a special dictionary type for expanding abbreviations into full phrases. Unlike corrections (which fix transcription errors), expansions replace intentionally spoken abbreviations.

### Example Shorthand Dictionary

```json
{
  "id": "shorthand-general",
  "name": "Common Shorthand",
  "type": "shorthand",
  "entries": [
    { "trigger": "AFK", "replacement": "away from keyboard", "behavior": "expansion" },
    { "trigger": "BTW", "replacement": "by the way", "behavior": "expansion" },
    { "trigger": "LGTM", "replacement": "looks good to me", "behavior": "expansion" },
    { "trigger": "IIRC", "replacement": "if I recall correctly", "behavior": "expansion" },
    { "trigger": "TBD", "replacement": "to be determined", "behavior": "expansion" },
    { "trigger": "AFAIK", "replacement": "as far as I know", "behavior": "expansion" },
    { "trigger": "IMO", "replacement": "in my opinion", "behavior": "expansion" },
    { "trigger": "FWIW", "replacement": "for what it's worth", "behavior": "expansion" },
    { "trigger": "EOD", "replacement": "end of day", "behavior": "expansion" },
    { "trigger": "OOO", "replacement": "out of office", "behavior": "expansion" },
    { "trigger": "WFH", "replacement": "working from home", "behavior": "expansion" },
    { "trigger": "PR", "replacement": "pull request", "behavior": "expansion" },
    { "trigger": "PTAL", "replacement": "please take a look", "behavior": "expansion" }
  ]
}
```

### Corrections vs Expansions

| Type | Trigger | Result | Use Case |
|------|---------|--------|----------|
| Correction | "ios" | "iOS" | Fix capitalization/spelling |
| Correction | "aho corasick" | "Aho-Corasick" | Fix algorithm name |
| Expansion | "AFK" | "away from keyboard" | Expand abbreviation |
| Expansion | "LGTM" | "looks good to me" | Expand dev slang |

### Processing Order

1. Corrections applied first (fix transcription errors)
2. Expansions applied second (expand intentional shorthand)

This ensures "lgtm" → "LGTM" (correction) → "looks good to me" (expansion).

## Context-Aware Dictionaries

Dictionaries can be configured to activate based on the frontmost application. This enables domain-specific vocabulary without polluting other contexts.

### App-to-Dictionary Mapping

```swift
struct DictionaryContext: Codable {
    var enabledApps: [String]?      // Bundle IDs, nil = all apps
    var disabledApps: [String]?     // Bundle IDs to exclude
}

// Example configurations
let techDict = Dictionary(
    name: "Tech & Programming",
    context: DictionaryContext(
        enabledApps: [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode"
        ]
    )
)

let shorthandDict = Dictionary(
    name: "Shorthand",
    context: DictionaryContext(
        enabledApps: [
            "com.apple.mail",
            "com.google.Gmail",
            "com.tinyspeck.slackmacgap"
        ]
    )
)

let personalDict = Dictionary(
    name: "Personal",
    context: DictionaryContext(
        enabledApps: nil  // Always active
    )
)
```

### Example Configurations

| Dictionary | Active In |
|------------|-----------|
| Tech & Programming | iTerm, VS Code, Xcode, Terminal |
| Codebase (Talkie) | VS Code, Xcode (when in project) |
| Shorthand | Gmail, Mail, Slack, Messages |
| Medical Terms | Epic, medical apps |
| Personal | All apps (always on) |

### Implementation

```swift
// TalkieLive already knows the frontmost app
let frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

// Filter dictionaries by context
let activeDictionaries = dictionaries.filter { dict in
    guard let context = dict.context else { return true }  // No context = always active

    if let enabled = context.enabledApps {
        return enabled.contains(frontmostApp ?? "")
    }
    if let disabled = context.disabledApps {
        return !disabled.contains(frontmostApp ?? "")
    }
    return true
}

// Only sync active dictionaries to Engine
await engine.syncDictionaries(activeDictionaries)
```

### UI for Context Rules

```
┌─────────────────────────────────────────┐
│ Tech & Programming              [Edit]  │
├─────────────────────────────────────────┤
│ Active in:                              │
│ ┌─────────────────────────────────────┐ │
│ │ ☑ Terminal                          │ │
│ │ ☑ iTerm                             │ │
│ │ ☑ VS Code                           │ │
│ │ ☑ Xcode                             │ │
│ │ ☐ All other apps                    │ │
│ └─────────────────────────────────────┘ │
│ [+ Add App...]                          │
└─────────────────────────────────────────┘
```
