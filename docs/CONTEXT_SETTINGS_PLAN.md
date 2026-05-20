# Context Settings Redesign — Shipped

## Goal

Replace the scattered Context Rules / Dictionary / Rules / Actions settings with a single unified **Context** panel. One place to answer: "what happens to my text, and where?"

## Status: complete (2026-05-17)

The unified `ContextSettingsView` is live with six tabs (`overview`, `apps`, `processing`, `dictionary`, `actions`, `playground`) — broader than the original four-tab plan. Sidebar routes all legacy enums (`.dictionary`, `.rules`, `.actions`, `.contextRules`) to `.context` via `canonicalSection`. Inline app profile cards landed inside `ContextSettingsView.appProfileCard(_:)`, replacing the modal `ContextRuleEditorSheet`.

### Cleanup pass (2026-05-17)

Four files deleted now that nothing references them:

- `Views/Settings/TransformsSettings.swift` — held the dead `RulesSettingsView` wrapper. Its live export `EnginePickerSection` was lifted into its own file.
- `Views/Settings/ContextRulesListColumn.swift`
- `Views/Settings/ContextRulesDetailColumn.swift`
- `Views/Settings/ContextRulesSettingsView.swift`

Two survivor files extracted from the dying ones:

- `Views/Settings/EnginePickerSection.swift` — the STT model picker, embedded by the Processing tab.
- `Views/Settings/ContextRuleNotifications.swift` — holds the `Notification.Name.contextRulesDidChange` extension consumed by `ContextSettingsView` and `ScopeContextView`.

Build verified after delete + regen.

## Final shape

### Sidebar

```
DICTATION (1 item)
├── voiceIO          "UX"

PROCESSING (the section now hosts CONTEXT)
├── context          "CONTEXT"

AUTOMATION (renamed from WORKFLOWS, just automations left)
├── automations      "AUTOMATIONS"
```

### Tabs inside CONTEXT

| Tab | Source | Purpose |
|---|---|---|
| Overview | `ContextSettingsView` | Landing summary |
| Apps | inline `appProfileCard(_:)` | Per-app profiles (was `ContextRulesSettingsView`) |
| Processing | embeds `EnginePickerSection` + `TransformRulesContent` | Engine picker, symbolic mapping |
| Dictionary | embeds `DictionarySettingsContent` | Existing multi-dictionary UI |
| Actions | inline | Quick actions + assistant personality |
| Playground | inline | New — dictionary test playground (was a separate view) |

## Future (Phase 2)

- Per-app quick action pinning
- Per-app dictionary selection
- "Catch-all" default profile for apps without a specific rule
- App profile import/export
