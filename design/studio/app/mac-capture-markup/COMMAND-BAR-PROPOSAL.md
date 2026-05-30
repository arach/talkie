# Capture Markup — Bottom Command Section Proposal

**Owner:** Talkie macOS (chrome only — drawing toolbar/canvas owned elsewhere)
**Touches:** `CaptureMarkupPanelChrome.swift` (`CaptureMarkupInputBarView`,
`CaptureMarkupCommitBarView`), copy + state strings, optional CSS tweaks in
`markup.css` for the M-mode pill.
**Status:** Design only — no backend wiring, no toolbar changes.

---

## Why this pass

The bay currently ships:

- A 56pt composer row: `[HOLD TO SPEAK | selection chip + plain NSTextField | RUN ⌘↵]`
- A `· TRY …` row above with four static chips and a `GLOBAL · WHOLE IMAGE`
  scope tag.
- A 34pt commit bar at the foot with `Cancel · Accept` and a hint string.

What actually hurts in use:

1. **The text field is dead.** It's a borderless `NSTextField` against a flat
   pane — no caret prominence, no placeholder rhythm, no obvious focus state.
   You can type but it does not invite typing.
2. **Hold-to-speak is opaque.** You press, you wait, you release, you wait
   again for the transcript. Three silent states (`HOLD`, `LISTENING`,
   `TRANSCRIBING`) with only a label change. No waveform, no level meter, no
   sense the agent has heard anything.
3. **No keyboard mic.** Voice requires a mouse trip to the left edge. The
   loop the user is excited about is verbal — voice should be a held key,
   not a clicked button.
4. **Mode is invisible from the bottom.** If the user pressed `R` to draw a
   rect and now wants to commit, nothing in the foot tells them they are
   still in `rect` mode. The way back is `V` (or `Esc`), which is
   discoverable only via the top toolbar hint.
5. **Examples are static.** Four fixed strings, same in ASK as in TOUCH UP
   (just a different list). They don't track the active tool, the selection,
   the layer count, or the agent's last result.
6. **Run vs Accept ambiguity.** Two amber primary-feeling buttons live in
   adjacent strips. `RUN ⌘↵` dispatches the agent; `Accept` commits the
   sidecar. They share the same color and weight; the user can't tell at a
   glance which one is the "I'm done" button.

This proposal addresses 1–6 without touching the drawing toolbar.

---

## Proposed layout

One 70pt **talk bar** replaces today's 56pt composer + separate try row.
The commit bar stays 34pt but its copy + button hierarchy change.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   ┌──────────┐  ↳ L2 build failed line ×   move it down a touch a │         │
│   │ ▮▮▮  ●   │  ─────────────────────────────────────────────────  │  RUN ⏎ │
│   │  hold ⌥  │  · try  "rename to API error"  "tighten the box"   │        │
│   └──────────┘                                                               │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ · DRAW MODE · RECT  · press V to select · ⌘Z undo                Cancel  Accept │
└──────────────────────────────────────────────────────────────────────────────┘
```

Three lanes inside the bar, same physical row:

1. **Voice well** — left, ~118pt wide. Mag-tape waveform during listening
   (per `feedback-aesthetic-mag-tape-waveform`), a single VU bar at idle.
   Press-and-hold the button **or** press-and-hold the `⌥` key anywhere in
   the bay. Status pill below the well: `HOLD ⌥` / `LISTENING` / `…
   TRANSCRIBING`.
2. **Input well** — center, fluid. Selection chip pinned to the left of the
   field. Below the field, an inline ghost-chips strip — same height as the
   field's descender — for try-suggestions. Caret is amber, 2pt, blinking,
   visible even when the field is empty (the cursor *is* the affordance,
   per the study).
3. **Run** — right, ~96pt. Amber filled, `RUN ⏎` (no `⌘`, since the field
   has focus — Enter alone runs). Disabled = ghost-amber outline, no fill.

The commit bar (foot) becomes a **status strip + a quiet commit pair**:
`Cancel` is text-only. `Accept` is the only filled amber pill in this
strip — never the same weight as `RUN`. `RUN` is the action you take dozens
of times; `Accept` you take once at the end.

---

## Mode visibility — the missing back-to-select affordance

The commit-bar strip is also a **mode line**. Three states:

| Mode             | Foot strip text                                          |
|------------------|----------------------------------------------------------|
| Select (default) | `· SELECT · click a layer to scope the talk bar`         |
| Draw — `rect`    | `· DRAW MODE · RECT · press V or Esc to return to select` |
| Touching up      | `· TOUCH UP · L2 selected · ⌘Z undo · ⌘N another pass`   |

The hint is paired with a **small pill** to the right of the mode label
that the user can click to exit drawing mode. The pill is the same
mechanism `V` triggers — it just makes the exit visible without forcing
the user to read the top toolbar's hint row.

```
· DRAW MODE · RECT   [↩ SELECT]                  Cancel  ▮ Accept
```

This is the only request on the toolbar side: `markup.js` should emit a
new bridge message — `markup.mode { active: "rect" | null }` — every time
`setActiveTool()` flips. The chrome listens and updates the foot. No
toolbar redesign, no extra controls in the canvas region.

---

## Voice UX — what changes

The current `HOLD TO SPEAK` keeps its semantics. What changes is the
feedback:

1. **Push-to-talk key.** Holding `⌥` (Option) anywhere in the panel
   triggers the same start/stop the button does. The button label flips to
   `HOLD ⌥` when the panel becomes key, signalling the shortcut. Tap the
   key without the bay focused → no-op (we don't grab system-wide audio).
2. **Live waveform.** The well renders a tape-head VU strip in real time
   while `EphemeralTranscriber` is capturing. The renderer is reusable from
   the existing notch composer waveform — same look, smaller footprint.
3. **Streaming partials.** When the transcriber supports it, partials land
   in the field in a faded weight (35% opacity ink), finalize at full
   weight on release. If partials aren't available, the field shows an
   amber `…` placeholder while `isVoiceTranscribing` is true; the text
   replaces it.
4. **Tap-to-toggle fallback.** Click the well (rather than hold) starts a
   sticky recording — single click again to stop. For users who don't want
   to hold. This is a behavior toggle, not a separate button; the press
   gesture's threshold is "≥220ms = hold, <220ms = toggle".
5. **Submit-after-voice.** A subtle option, off by default: in `RUN` menu,
   "submit on release of `⌥⏎`" so the user can speak and dispatch in one
   gesture. Phase-2 polish.

These are all chrome changes; the agent pipeline is untouched.

---

## Text field — making it feel like an input

Specific changes to `CaptureMarkupInputBarView`:

- Field gets a real focus ring (amber, 1pt, inset 0.5pt). Default state
  shows the 2pt amber caret blink even when the field is empty.
- Placeholder copy gets two registers:
  - ASK · empty: `tell the agent what to mark up…`
  - TOUCH UP · empty, no selection: `pick a layer · or speak another pass`
  - TOUCH UP · layer selected: `modify {{layer.label}} · move it down, recolor, rename…`
- Font bumps to 14pt SF Pro Text. Mono-italic for the placeholder, regular
  for typed text. Distinguishes "the agent's voice" from "your typed
  command" without an icon.
- Selection chip moves from inline-with-field to **a pinned-left chip
  inside the same well**, with a 1pt amber rule between chip and field.
  This is what the study calls "select rides with the input".

---

## Suggestions strip — make it adaptive

Replace the static `askExamples` / `touchUpExamples` arrays with a
**context-driven feed** populated by the coordinator:

| Context                                  | Suggestions                                         |
|------------------------------------------|------------------------------------------------------|
| ASK, no layers                            | "circle the error and label it" · "blur the email" · "horizontal guide on first word" |
| Active tool = `rect`                      | (none — the user has decided)                       |
| TOUCH UP, no selection                    | "another pass · tighter labels" · "remove the guide" · "blur everything but the title" |
| TOUCH UP, selection.kind = `rect`         | "tighten the box" · "make it red" · "rename to '…'" · "delete" |
| TOUCH UP, selection.kind = `arrow`        | "curve it" · "swap endpoints" · "flip color" · "delete" |
| TOUCH UP, selection.kind = `label`        | "rename to '…'" · "move below the line" · "delete" |
| Run failed                                | "rephrase: '…'" (the last instruction, italicised, click to re-edit) |

Source: a `suggestionsForContext(...)` method on the coordinator that
returns at most three chips. Chips are dashed-border, italic, and visibly
clickable (cursor pointer). Truncate at one line.

Underlying data is local; nothing new on the agent side.

---

## State machine

| State                         | Voice well                | Field                                   | Right action      | Foot strip                                                  |
|-------------------------------|---------------------------|-----------------------------------------|-------------------|-------------------------------------------------------------|
| Idle · ASK                     | `HOLD ⌥`                  | placeholder · amber caret blink         | `RUN ⏎` ghost     | `· SELECT · click a layer to scope the talk bar`           |
| Typing                         | `HOLD ⌥`                  | live text · suggestions hide            | `RUN ⏎` filled    | (unchanged)                                                 |
| Listening                      | `● LISTENING` + waveform  | partials at 35% opacity                 | `RUN ⏎` disabled  | `· VOICE · release ⌥ to submit · Esc to cancel`            |
| Transcribing                   | `… TRANSCRIBING`           | `…` amber placeholder                   | `RUN ⏎` disabled  | (unchanged)                                                 |
| Drawing (e.g. rect)            | `HOLD ⌥`                  | placeholder · faded 60% opacity         | `RUN ⏎` ghost     | `· DRAW MODE · RECT · press V or Esc to return to select`  |
| Touching up · selection        | `HOLD ⌥`                  | layer-scoped placeholder · selection chip pinned left | `RUN ⏎` filled | `· TOUCH UP · L2 selected · ⌘Z undo · ⌘N another pass`    |
| Running                        | disabled                  | disabled (instruction visible greyed)   | `… RUNNING` shimmer | `· running agent markup…`                                   |
| Failed                         | `HOLD ⌥`                  | last instruction restored · highlighted | `RUN ⏎` filled    | `· {{error}} · rephrase or try a different angle`          |

Transitions are all already-wired callbacks on `CaptureMarkupPanelChromeDelegate`
plus the new `markup.mode` message. No new lifecycle.

---

## Copy register

Keep the existing all-caps mono tags (`·` prefix, 9pt mono, .22em
tracking) for status — they're already the system's eyebrow style. Body
voice (placeholders, suggestions) shifts to italic display, lowercase, no
period. Two registers: machine speaks in caps, agent speaks in italic.

| Was                                                              | Becomes                                                  |
|-------------------------------------------------------------------|----------------------------------------------------------|
| `· nothing applied yet · accept unlocks after the agent runs`     | `· SELECT · click a layer to scope the talk bar`         |
| `· running agent markup…`                                          | `· RUNNING · {{verb}} on {{scope}}…` (e.g. "circling the error on the whole image") |
| `tell the agent what to mark up…`                                  | (same; italic; appears on caret-blink not on hover)      |
| `modify this layer · or speak another pass…`                       | `modify {{layer.label}} · move it down, recolor, rename` |

`{{verb}}` derives from a regex on the instruction; falls back to "running".
`{{scope}}` is the selection label or "the whole image".

---

## Shortcuts (added)

| Key                 | Action                                          |
|---------------------|-------------------------------------------------|
| `⌥` (hold)          | Push-to-talk in the bay                         |
| `⏎`                 | RUN (when field is focused with text)           |
| `Esc`               | Cancel listening; then clear selection; then leave draw mode (cascading) |
| `⌘Z` / `⌘⇧Z`        | Undo / redo last applied layer pass (touch-up only) |
| `⌘N`                | Another pass — clear field, keep selection      |
| `⌘.`                | Stop a running agent                            |

`⌥` and `Esc` are the only ones new on the chrome side; the rest already
live in the coordinator's action surface or can be wired through it.

---

## Accessibility notes

- `voiceButton` already responds to mouse; add `keyEquivalent = "⌥"` so
  VoiceOver announces "hold to speak, push to talk option" instead of just
  "button".
- `promptField` gets `setAccessibilityRole(.textArea)` and
  `setAccessibilityLabel("Markup instruction")` (currently inherits the
  field default).
- The waveform and listening pulse are decorative; mark them
  `setAccessibilityElement(false)` and rely on the status pill text for
  VO.
- Suggestions chips are buttons with `setAccessibilityLabel("Try: '{{text}}'")`.
- Mode strip text is a live region. Update it via
  `NSAccessibility.post(element: hintLabel, notification: .announcementRequested,
  userInfo: [.announcement: ..., .priority: .medium])` so screen readers
  hear "draw mode rect" when the user enters drawing.
- Contrast: amber caret on `--pane` is currently 3.2:1 — keep amberDeep
  for the caret (4.6:1) and reserve amber for fills.

---

## What this requires from neighbouring code

| File                                                           | What                                                                 |
|----------------------------------------------------------------|----------------------------------------------------------------------|
| `markup.js`                                                    | Emit `markup.mode { active: "rect"\|null }` from `setActiveTool()`.  |
| `CaptureMarkupBridgeMessage`                                   | Add `mode: String?` to the parsed struct.                            |
| `CaptureMarkupCoordinator.handleBridge`                        | Route `markup.mode` to a new `inputBar.setDrawMode(_:)`.             |
| `CaptureMarkupInputBarView`                                    | Layout + state changes above. Largest delta of the proposal.         |
| `CaptureMarkupCommitBarView`                                   | Mode-aware copy + de-prominent `Cancel`; pinned-amber `Accept`.      |
| `EphemeralTranscriber`                                         | Expose a `levels` AsyncStream for the waveform. (Optional — falls back to a static VU.) |

No new files. No agent-pipeline code touched.

---

## Out of scope

- The top drawing toolbar (`tool-toolbar` in `index.html`). Including its
  layout, glyphs, tool palette, and click handlers. The mode hint pill in
  the foot is **read** by the toolbar (via `markup.mode`), not the other
  way round.
- Canvas hit-testing, drag-create, layer geometry, layer rail.
- Sidecar JSON shape and `CaptureMarkupDocument` schema.
- Agent LLM calls — instruction parsing, tool-call planning, model
  selection. Owned by codex-talkie.
- Provider configuration UI (`openAIProviderSettings` link stays as-is).
- Walkie / dictation / capture-during-record flows.
- New file-format work — embedded vs sidecar is settled (sidecar).

---

## Suggested rollout

1. **Tier 1 — copy + state (no layout change).** Rewrite hint strings,
   placeholders, suggestions data source. Wire `markup.mode`. Adds the
   "back to select" hint without touching layout. Maybe a half-day of
   chrome work; user-visible improvement is the mode hint + adaptive
   suggestions.
2. **Tier 2 — voice well + waveform.** Replace the button with the
   composite well; add the `⌥` push-to-talk monitor; add the level meter.
   Requires the transcriber levels stream; mock if needed at first.
3. **Tier 3 — adaptive suggestions feed + streaming partials + commit-bar
   rebalance.** The full vision above.

Each tier ships independently; Tier 1 alone closes the "back to select"
gap and the static-suggestions gap, which are the felt pains today.
