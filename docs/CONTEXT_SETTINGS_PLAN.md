# Context Settings Redesign

## Goal

Replace the scattered Context Rules / Dictionary / Rules / Actions settings with a single unified **Context** panel. One place to answer: "what happens to my text, and where?"

## Current State

| Sidebar Item | Section | What It Does |
|---|---|---|
| DICTATION > Dictionary | `DictionarySettingsView` | Word replacements, multi-dictionary, import, playground |
| DICTATION > Rules | `RulesSettingsView` (`TransformsSettings.swift`) | Engine picker + symbolic mapping |
| WORKFLOWS > Actions | `ActionsSettingsView` | Assistant personality, workflow-as-button, context toggles |
| WORKFLOWS > Context Rules | `ContextRulesSettingsView` | App-specific LLM prompts (refine/edit behavior) |
| WORKFLOWS > Automations | `AutomationsSettingsView` | Event-triggered workflow runs (stays separate) |

No real users have dictionary entries or context rules in the wild. This is a clean-slate reorganization, not a migration.

### Key Files

```
apps/macos/Talkie/Views/Settings/
├── ContextRulesSettingsView.swift      # App-specific rules → becomes Apps tab
├── ContextRulesListColumn.swift        # 3-column list variant — delete
├── ContextRulesDetailColumn.swift      # 3-column detail variant — delete
├── DictionarySettings.swift            # Multi-dictionary UI (~1600 lines)
│   └── DictionarySettingsContent       # Embeddable content view → reuse as tab
│   └── TransformRulesContent           # Symbolic mapping section → reuse in Processing tab
├── TransformsSettings.swift            # Engine picker + symbolic mapping wrapper
│   └── EnginePickerSection             # STT model picker → reuse in Processing tab
├── ActionsSettingsView.swift           # Quick actions + assistant personality
├── AutomationsSettings.swift           # Stays separate
└── SettingsColumns.swift               # Sidebar enum + layout
```

### Model Files (unchanged)

```
apps/macos/TalkieKit/Sources/TalkieKit/ContextRule.swift
apps/macos/TalkieKit/Sources/TalkieKit/ContextRulePreset.swift
apps/macos/Talkie/Services/DictionaryManager.swift
apps/macos/TalkieEngine/TalkieEngine/TextPostProcessor.swift
```

## New Design

### Sidebar

```
DICTATION (1 item)
├── voiceIO          "UX"

CONTEXT (new section, 1 item)
├── context          "CONTEXT"

AUTOMATION (1 item, renamed from WORKFLOWS)
├── automations      "AUTOMATIONS"
```

### Tab Structure

```
┌──────────────────────────────────────────────────────┐
│  CONTEXT                                              │
│  "What happens to your text, and where"               │
├──────────────────────────────────────────────────────┤
│  [Apps]  [Processing]  [Dictionary]  [Actions]        │
└──────────────────────────────────────────────────────┘
```

**Apps** — Per-app profiles (evolution of context rules)
**Processing** — Engine picker, symbolic mapping, filler removal
**Dictionary** — Existing multi-dictionary UI
**Actions** — Existing quick actions + assistant personality

### Apps Tab (Default)

The hero. Each app gets an expandable profile card. Only one card expanded at a time.

```
┌──────────────────────────────────────────────────────┐
│ Master toggle: Enable app-specific processing        │
├──────────────────────────────────────────────────────┤
│                                                      │
│ ┌──────────────────────────────────────────────────┐ │
│ │ [icon] Slack                          [on/off] ▼ │ │
│ │ REFINE · Default model                           │ │
│ │ "Make casual and conversational..."              │ │
│ │                                                  │ │
│ │ ▸ Expand: prompt editor, behavior picker,        │ │
│ │   LLM override, per-app actions, per-app dict    │ │
│ └──────────────────────────────────────────────────┘ │
│                                                      │
│ ┌──────────────────────────────────────────────────┐ │
│ │ [icon] Mail                           [on/off] ▼ │ │
│ │ REFINE · GPT-4                                   │ │
│ │ "Professional, polished tone..."                 │ │
│ └──────────────────────────────────────────────────┘ │
│                                                      │
│ ┌──────────────────────────────────────────────────┐ │
│ │ [icon] Terminal                        [on/off] ▼ │ │
│ │ PROCESSOR · Symbolic mapping ON                  │ │
│ └──────────────────────────────────────────────────┘ │
│                                                      │
│ [+ Add App Profile]   [Templates ▼]                  │
│                                                      │
│ ── TEMPLATES ──────────────────────────────────────── │
│ Casual (Slack) · Professional (Email) · Technical    │
│ Light cleanup · Bash Dictation                       │
└──────────────────────────────────────────────────────┘
```

Expanded card shows inline editing (no modal sheet):
- Rule name
- App picker grid (running apps)
- Behavior: Refine / Edit / Protocol Processor
- Prompt editor with template menu
- LLM override (provider + model)
- Future: per-app quick actions, per-app dictionary

### Processing Tab

Embeds existing components, no rewrite:
- `EnginePickerSection` (from TransformsSettings.swift)
- `TransformRulesContent` (from DictionarySettings.swift) — symbolic mapping toggle + rules
- Filler removal toggle
- Dictionary processing master toggle (with link to Dictionary tab)

### Dictionary Tab

Embeds `DictionarySettingsContent` directly. No changes to the dictionary UI.

### Actions Tab

Embeds existing `ActionsSettingsView` content. Extract inner content from its `SettingsPageContainer` wrapper into `ActionsSettingsContent`.

## Implementation

### Step 1: Create ContextSettingsView with tabs

New file `ContextSettingsView.swift`:
- `ContextTab` enum: `.apps`, `.processing`, `.dictionary`, `.actions`
- `@State private var selectedTab: ContextTab = .apps`
- Segmented `Picker` at the top
- Switch on `selectedTab` to show each tab's content

### Step 2: Wire existing content as tabs

- **Apps tab**: Embed current `ContextRulesSettingsView` body content (strip its `SettingsPageContainer`)
- **Processing tab**: Embed `EnginePickerSection` + `TransformRulesContent`
- **Dictionary tab**: Embed `DictionarySettingsContent`
- **Actions tab**: Extract `ActionsSettingsView` body into `ActionsSettingsContent`, embed it

### Step 3: Update sidebar + routing

In `SettingsColumns.swift`:
- Add `.context` to `SettingsSection` enum
- Point `.dictionary`, `.rules`, `.actions`, `.contextRules` canonical → `.context`
- Sidebar: single CONTEXT section with one item
- Rename WORKFLOWS section header → AUTOMATION (just automations left)
- `SettingsContentColumn`: route `.context` → `ContextSettingsView()`

### Step 4: Inline app profile cards

Replace modal `ContextRuleEditorSheet` with inline expandable cards:
- `@State private var expandedRuleID: UUID?` — only one expanded at a time
- Collapsed: icon cluster + name + behavior badge + toggle + summary
- Expanded: full editor (name, app picker, behavior, prompt, LLM override)
- Expanding one card collapses the previous
- Delete `ContextRulesListColumn.swift` and `ContextRulesDetailColumn.swift`

### Step 5: Clean up dead settings pages

- `TransformsSettings.swift` — `RulesSettingsView` wrapper no longer routed, can delete
- Old `SettingsSection` cases (`.dictionary`, `.rules`, `.actions`, `.contextRules`) become legacy redirects in `canonicalSection` only

**Files created:** `ContextSettingsView.swift`
**Files modified:** `SettingsColumns.swift`, `ActionsSettingsView.swift`, `ContextRulesSettingsView.swift`
**Files deleted:** `ContextRulesListColumn.swift`, `ContextRulesDetailColumn.swift`, `TransformsSettings.swift`

## Future (Phase 2)

- Per-app quick action pinning
- Per-app dictionary selection
- "Catch-all" default profile for apps without a specific rule
- App profile import/export
