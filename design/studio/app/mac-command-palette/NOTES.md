# Mac Command Palette — Reimagining Log

## What this study renders

Single MacWindowFrame at 1180, four stacked sections:

1. **Resting** — palette open, no input, grouped list visible, mic primed.
2. **Speaking** — mic held, waveform strip inline, voice-intent banner pinned above the list with confidence bar, matched row highlighted.
3. **In context** — palette opened from a Recording. Scope chip rides the input; HERE group pins context-specific actions; the rest of the list is dimmed so the scoped commands read first.
4. **Donor (before)** — side-by-side tiles showing today's `CommandPaletteView` (Raycast clone) and `VoiceCommandOverlay` (particle modal). Two surfaces, one job — what the reimagining consolidates.

## Donor walk — keep / port / drop / defer

Walked `CommandPaletteView.swift`, `PaletteCommand.swift`, `VoiceCommandOverlay.swift`, `VoiceCommandService.swift` (per the donor-audit rule). Tagged each feature:

### CommandPaletteView.swift (456 LOC)

| Feature                                  | Decision  | Reason |
| ---------------------------------------- | --------- | ------ |
| ⌘⇧K trigger                              | KEEP      | Established muscle memory |
| Hero search field, autofocus             | KEEP      | Core gesture |
| Debounced filtering (120ms)              | KEEP      | Right cadence |
| ↑↓ navigate, ↵ execute, ⎋ close          | KEEP      | Standard |
| Footer with key hints + brand chip       | KEEP      | Discoverability |
| Click + hover-to-select                  | KEEP      | Standard |
| Spring scale/opacity entry animation     | KEEP      | Polish |
| Self-recovering focus on drift           | KEEP      | Pragmatic |
| Centered upper-third position            | KEEP      | Convention |
| Empty state ("No commands found")        | KEEP      | Polish |
| Flat ScrollView, no grouping             | **DROP**  | Eye lands on a wall. Grouping by section is the move. |
| Dark glass background                    | **PORT**  | Stays dark — but adopt Talkie's AMBER agent-bay tint, not generic Raycast. |
| `Color.accentColor` highlight            | **DROP**  | Swap for `SCOPE.amber`. The palette is Talkie's voice; system accent is wrong family. |
| Two-line rows (icon, title, subtitle, shortcut) | KEEP | Right density |
| 32×32 icon tiles with gradient bg        | KEEP, retune | Drop the gradient sheen; use a flat amber tile when selected. |

### PaletteCommand.swift (369 LOC)

| Feature                                  | Decision  | Reason |
| ---------------------------------------- | --------- | ------ |
| `PaletteCommand` struct (title/subtitle/icon/shortcut/keywords/action) | KEEP | Good shape |
| `matches()` multi-word AND filter         | KEEP, EXTEND | Add fuzzy + recency boost in Phase 2 |
| `PaletteRegistrable` protocol             | KEEP      | Auto-registration is elegant |
| NavigationSection auto-registration       | KEEP      | Already shipped |
| SettingsSection auto-registration         | KEEP      | Already shipped |
| Hardcoded Voice / Sidebar / Keyboard / Camera / Report / Perf | KEEP, GROUP | Currently flat; group under "Actions". |
| `Voice Command` as a row (opens overlay)  | **DROP**  | Voice is no longer a row — it's the mic on the input bar. No more "open second modal" command. |
| `CommandRegistry.shared` (built-once)     | KEEP, ADD context | Add a `commandsFor(scope: PaletteScope?)` overload that prepends context-specific commands. |

### VoiceCommandOverlay.swift (675 LOC)

| Feature                                  | Decision  | Reason |
| ---------------------------------------- | --------- | ------ |
| Separate ⌘⇧V modal surface               | **DROP**  | Voice is a mode of the palette, not a sibling surface. |
| `VoiceCommandState` machine (idle / recording / processing / result / navigating / error) | KEEP | Reuse inside the palette; the same states drive the input bar's mic + intent banner. |
| `ParticleSystemView` (300×160 canvas)     | **DROP, REPLACE** | Particle viz is beautiful but too big for an inline strip. Replace with a 34px waveform/bars row beneath the input. |
| `IntentResult` + confidence threshold auto-commit | KEEP | The "release the mic to commit if high confidence" loop is the whole point. |
| `audioLevel` polling 30fps + bar drive    | KEEP      | Reuse for the inline waveform strip. |
| Toast view for "navigating" success       | DEFER     | Nice polish; not needed Phase 1. |
| Backdrop scrim + tap-to-dismiss           | KEEP      | Same convention as today's palette overlay. |
| `actionHint` / `statusText` copy          | KEEP, retune | Tighter copy in the inline mode. |

### VoiceCommandService.swift (297 LOC)

| Feature                                  | Decision  | Reason |
| ---------------------------------------- | --------- | ------ |
| Audio capture pipeline                    | KEEP      | Untouched; the palette consumes the same API. |
| `startCapture()` / `stopAndRecognize()`   | KEEP      | Surface-agnostic |
| `audioLevel` Observable                   | KEEP      | Bind to inline waveform |
| Persistent engine pattern                 | KEEP      | Already debugged |

## Three reimagining moves

### 1. One surface

The palette has the mic inside its input row. Hold to speak (or click and hold, or press `♪`). The same surface handles text typing and voice dictation — they share the same target (the command list), the same scope (the scope chip), the same commit gesture (`↵`). No `VoiceCommandOverlay` modal.

This mirrors the markup study's input-bar pattern: voice and text are equal-weight affordances, not modes.

### 2. Grouped results

Today's list is flat. With ~20+ commands, the eye lands on a wall. Grouping by section ("Navigation", "Settings", "Actions") with small mono headers lets the eye land on the kind first, then the command. Each group preserves the auto-registration pattern from `PaletteRegistrable`.

When voice is active, a **VOICE INTENT** banner pins above the groups with the best match + confidence bar. Release the mic with high confidence → auto-commit. The matched row in the list is also highlighted, so the user sees both the banner (commit) and the row (location) at once.

### 3. Scope chip

When the palette opens from a specific context — a Recording, a Note, the Canvas — a chip rides the input next to the cursor (same shape as the markup study's selection chip):

> `↳ Recording · Q1 plan · 12:42 ×`

A **HERE** group pins at the top with context-specific actions (open, copy link, share, delete). The general groups follow below, dimmed slightly. The scope is dismissible (`×`) — clicking the chip reverts to the global palette.

The bridge from caller → palette is a `PaletteScope` value:

```swift
struct PaletteScope {
    let kind: String            // "Recording", "Note", "Canvas"
    let label: String           // user-facing name
    let id: String              // for action wiring
    let commands: [PaletteCommand]  // context-specific
}
```

`NavigationState.showCommandPalette(scope:)` is the new entry point; the bare `showCommandPalette` keeps working for the global case.

## Visual family

Dark glass stays — modal overlays should feel like focus mode, distinct from in-app surfaces. But adopt Talkie's AMBER agent-bay treatment: the same dark surface used by `AgentTranscriptSurface` in `MacCaptureMarkup` Framing B. Amber replaces `Color.accentColor`. The palette reads as the agent's voice — which is what it is.

Token reference: `lib/schemes.ts` `AMBER` scheme bg `#14181A`, amber `#E89A3C`. Inline tokens in this study under `const P = {…}`.

## Phase 1 / Phase 2 / Phase 3

**Phase 1 — Consolidation**
- Inline mic + waveform inside the palette input row.
- Drop `VoiceCommandOverlay` as a separate surface; route `⌘⇧V` to "open palette with mic engaged."
- Group commands by section in `CommandList`.
- Repaint palette in AMBER family tokens.
- Add `PaletteScope` plumbing; HERE group renders when scope is present.

**Phase 2 — Smarter matching**
- Fuzzy matcher (replace `.contains()`).
- Recent-commands boost (last 7 days).
- Acronym matching ("gtd" → "Go to Dictations").

**Phase 3 — Workflows**
- Custom user-defined commands.
- Workflow runner inline (multi-step commands that show progress in the banner).
- Plugin commands from `TalkieAgent`.

## Open UX questions for @art

1. **Mic press-and-hold vs press-once.** Today's voice overlay has a "press Return to commit" model — you tap to start, tap to stop. The new design's mic chip implies hold-to-speak. Both are valid; hold-to-speak is more direct, tap-to-start is friendlier for long commands. Which?

2. **Scope chip lifecycle.** When the user types after the scope chip is set, does the search filter only the HERE group, only the global groups, or both? Default leaning: both, with HERE results boosted to the top.

3. **Confidence threshold for auto-commit.** Currently `SettingsManager.voiceCommandConfidenceThreshold`. Should the palette show the threshold visually on the confidence bar (a tick mark at the cutoff)? Or stay hidden?

4. **Empty state for voice.** What happens when voice is active but nothing is recognized yet? Today the state machine shows "Listening…". The reimagining shows the waveform strip + transcript blank. Probably right; worth confirming.

## Why these decisions

- **Dark glass survives** because the palette is a modal overlay; switching to PEARL would lose the focus-mode reading. But the family changes to Talkie's amber-bay.
- **Grouping** earns its keep at 15+ commands. Below that it's overkill; above it the flat list is the wall.
- **Scope chip** is the only durable place to put context — putting it in a sidebar or footer fights for attention with the list. Riding the input means it's exactly where the next command is being typed.
- **Particle viz dropped** because the inline mode can't afford 300×160. The waveform bars are smaller and read as "I'm listening" just as clearly.

## Component map

- `app/mac-command-palette/page.tsx` — route wrapper, single MacWindowFrame.
- `components/studies/MacCommandPalette.tsx` — composition root.
- Sub-components inline:
  - `StudyHeader`, `SectionBreak`, `StudyFooter`, `Surface`, `CaptionStrip`
  - `RestingState`, `SpeakingState`, `ContextState`, `DonorStrip`
  - `PaletteWindow` (shared dark-glass shell)
  - `InputBar`, `ScopeChip`
  - `VoiceVisualizer` (inline waveform)
  - `VoiceIntentBanner` (best match + confidence bar)
  - `CommandList`, `Group`, `Row` (grouped results)
  - `ScopedHereGroup` (context-specific pinned)
  - `KeyHintsFooter`, `KeyHint`
  - `DesktopBackdrop` (faux dimmed Talkie app behind)
  - `DonorTile`, `DonorPalette`, `DonorVoiceOverlay`
  - `Chip`, `PaneHeader`

## Donor references

- `apps/macos/Talkie/Views/CommandPalette/CommandPaletteView.swift` — Raycast-style palette being replaced.
- `apps/macos/Talkie/Views/CommandPalette/PaletteCommand.swift` — command model + registry. Kept; extended with `PaletteScope`.
- `apps/macos/Talkie/Views/CommandPalette/VoiceCommandOverlay.swift` — particle voice modal being folded in.
- `apps/macos/Talkie/Services/VoiceCommandService.swift` — audio + intent service. Unchanged.
- `design/studio/components/studies/MacCaptureMarkup.tsx` — the input-bar pattern (mic + scope chip + text, equal weight) that the palette inherits.
