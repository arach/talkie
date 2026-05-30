# Mac Capture Markup — Decisions Log

## What this study renders

A single MacWindowFrame at 1180 hosting four stacked sections:

1. **A · Receipt bay** — ephemeral WKWebView mounts over the desktop the
   moment a capture lands. Image-first composition; agent prompt in the
   foot; layer list in a right rail; tool-call ticker inline.
2. **B · Agent attachment** — the capture is attached to an existing
   agent session (dark AMBER bay, mirroring the live agent surface).
   The transcript stays in its own window. The webview is a focused
   image preview lane next to it.
3. **C · Voice-during-dictation** — Walkie is mid-record. The bay
   mounts in the lower-right, smaller, with a "listening" pulse. No
   focus steal from the recording HUD.
4. **Coda · Touch-up mode** — two tiles showing the secondary manual
   surface: inline layer popover (nudge / re-label / delete) and an
   opt-in primitives rail (rect / arrow / text / blur).

No Swift source yet — this study is upstream of any port.

## The exploration that produced this

- Capture pipeline is mature (Hyper+S, tray, ScopeCaptureDetailView).
  Markup is delegated to CleanShot X / ScreenshotX today via
  `TrayViewer.swift:1090` (`pencil.tip.crop.circle` opens the external
  editor). The goal: an in-house surface that's agent-first, with the
  external editor remaining as a Settings fallback.
- The agent vocabulary needs to be **structured tool calls over a
  sidecar**, not pixel mutations. The PNG is never re-encoded. Layers
  live in a `C-NNNN.markup.json` next to the image.
- Webview-as-bay was a deliberate architecture call by the operator
  (2026-05-24): spawn on demand, discard on Accept/Cancel. The pattern
  is already in-house — `HomeAppWidgetView` and `LearnKnowledgeWebView`
  both host WKWebView with a Swift bridge. The markup bay is the same
  shape with a different payload.
- **Image-first**: the screenshot dominates every framing. Chrome,
  prompts, layer lists are all subordinate. The agent does most of the
  work; the surface should not feel like Figma.

## The tool vocabulary (mock)

Calls the agent emits. These show up in the inline ticker and in the
sidecar JSON. Same vocabulary across all framings.

```
markup.guide        orientation: 'h'|'v', anchor: <semantic> | y: <px>
markup.region.ocr   match: <regex|literal>          → returns geometry
markup.region.named name: <vlm-region-id>           → returns geometry
markup.rect         from: <region>|<box>, color, label?
markup.arrow        from: <anchor>, to: <anchor>, color, label?
markup.label        text, anchor: <anchor>, placement: above|below|…
markup.blur         from: <region>|<box>, intensity
```

Anchors are first-class — the agent says "from the first word of the
title", not "from x=12 y=30". The OCR/VLM layer resolves anchors to
geometry. This is what unlocks prompts like "draw a horizontal line
from the first word" working without the user dragging anything.

## Three framings — strengths / weaknesses

### A · Receipt bay (primary entry)

- **Strengths:** image dominates; tool-call ticker reads cause/effect;
  layer rail gives parity with the sidecar; Accept/Cancel is one
  reach. Closest to the "snap it, see what the agent did" loop the
  brief asks for.
- **Weaknesses:** the prompt strip is the only input affordance — if
  the agent gets it wrong twice in a row, the user feels stuck in a
  small text field. Voice mic is there but easy to miss.

### B · Agent attachment (transcript lives elsewhere)

- **Strengths:** proves the "transcript stays in agent surfaces"
  point — two windows, two lanes; no duplicated chat in the webview.
  Right framing when the user is already deep in an agent session and
  the screenshot is just one of several attached artifacts.
- **Weaknesses:** the user has to track two windows. Bay is narrower
  (split attention) so the image isn't as commanding as in A.

### C · Voice-during-dictation (peripheral)

- **Strengths:** zero context switch from the dictation. Tool calls
  land while voice is being parsed. The "listening" pulse is the only
  signal that markup is happening at all — visible peripheral, not
  demanding focus.
- **Weaknesses:** no real input surface — the user is committed to
  voice. If the agent misreads "circle the error" as something weird,
  recovery is awkward until dictation ends.

### Coda · Touch-up mode

- **Strengths:** stays out of the way until invoked. Layer popover is
  the right shape for the 80% case (nudge a misplaced rect, fix a
  label). Primitives rail handles the 20% (add a missed blur).
- **Weaknesses:** none structurally, but everything past the four
  primitives starts looking like a CleanShot clone. Need a discipline
  to keep this surface minimal.

## Phase 1 UX recommendation

**Ship Framing A first.** Reasons:

1. It's the most common entry — every Hyper+S that the user wants to
   annotate flows through it. B and C are derivative cases that
   require A's webview to exist anyway.
2. It contains the full vocabulary in one place: image, agent prompt,
   tool-call ticker, layer rail, accept/cancel. Once A is solid, B is
   "render the bay without the prompt strip" and C is "render the bay
   smaller and listen for events from Walkie."
3. Coda (touch-up) wires into A naturally — the popover and primitives
   rail belong to the bay regardless of how it was opened.

**Phase 1 scope (suggested):**
- Webview bay infra (WKWebView panel, sidecar JSON write).
- Tool vocabulary: `markup.rect`, `markup.arrow`, `markup.label`,
  `markup.guide`. Defer `markup.blur` and `markup.region.named` to
  Phase 2.
- Agent prompt + tool-call ticker.
- Layer rail with eye toggle, click-to-select.
- Inline layer popover (nudge / re-label / delete).
- Accept writes the sidecar + leaves the PNG untouched. Cancel
  discards everything.

**Phase 2:**
- B (agent attachment) — exposes markup tools to the Walkie / agent-bay
  session.
- C (voice-during-dictation) — peripheral bay + listening pulse.
- Opt-in primitives rail (rect / arrow / text / blur drawing).
- `markup.blur` and OCR-anchored regions resolved by VLM.

**Phase 3:**
- Markup history (revise / undo at the layer level, persistent).
- Export with burned-in markup (the sidecar gets rasterized to a copy).
- External-editor handoff stays in Settings as a fallback.

## Blocking UX questions for @art

1. **Voice trigger inside the bay.** Does the bay listen by default
   (the brief's "Voice-first" framing implies yes for C, ambiguous for
   A)? Or does the user have to press the mic chip? The current mock
   has voice as a chip you tap; the alternative — always-listening
   inside the bay — would change the foot strip considerably.

2. **Auto-show vs tray-only.** Today the tray catches the capture.
   Should Framing A's bay auto-mount on every capture (heavy: every
   Hyper+S grabs focus), or only when the user explicitly says "mark
   this up" / hits a different chord (e.g. Hyper+M)? Recommendation:
   gated by a Settings toggle, defaulting to **off** initially —
   captures go to tray, user invokes markup from the tray thumbnail or
   ScopeCaptureDetailView toolbar. But the brief's "post-capture entry
   point" suggests auto-mount is the intended primary. Need a call.

3. **OCR/VLM provider.** The anchors `match: 'Build failed'` and
   `anchor: 'first word'` require an OCR + VLM pass. On-device only
   (Vision framework + a local VLM), or cloud (Claude vision API)?
   This changes latency, cost, and the entire UX for the listening
   state in C.

4. **Sidecar vs embedded.** The mock uses a sidecar JSON. An alternate
   is embedding markup as PNG metadata (tEXt or XMP chunk). Sidecar is
   simpler to round-trip and version; embedded survives copy/paste to
   external apps. Pick one before infra lands.

5. **Markup ownership across kinds.** Captures live in the capture
   bucket today; the moment a caption lands they promote to Notes
   ([MacCaptureDetail.tsx#L4 file header](../../components/studies/MacCaptureDetail.tsx)).
   Does the markup sidecar travel with that promotion, or get folded
   into the Note's body? Current mock assumes it travels intact.

## Why these decisions

- **PEARL on FROST palette** matches MacCaptureDetail — captures
  belong to one visual family. Amber/brass reserved for agent voice
  (tool calls, listening pulse, primary action).
- **Same mock screenshot across framings** (a Talkie build-log window
  with a "Build failed" line). Proves the layer schema is
  size-independent — guide, rect, arrow, label render correctly at
  full / compact / miniature scales.
- **No SchemeCard wrapper.** Scope-language only; pre-Swift. If we
  ever ship a markup bay with scheme variants it would happen after
  Phase 1.
- **No width breakpoints.** The framing is the variable. Width-stamped
  studies (MacCaptureDetail, MacHome) wouldn't help here — the bay is
  a fixed-size floating panel regardless of host window width.
- **Agent provenance dot.** Small amber dot in the layer rail marks
  agent-authored layers. Day one this is information-only. If the
  user-and-agent mixed-author case gets messy in practice, this hooks
  into a "show only mine / show only the agent's" filter without
  changing the data model.

## Component map

- `app/mac-capture-markup/page.tsx` — route wrapper, single MacWindowFrame.
- `components/studies/MacCaptureMarkup.tsx` — composition root.
- Sub-components inline:
  - `StudyHeader`, `FramingBreak`, `StudyFooter`, `Surface`, `CaptionStrip`
  - `FramingA`, `BayBodyA`, `BayFootA`
  - `FramingB`, `BayBodyB`, `BayFootB`, `AgentTranscriptSurface`
  - `FramingC`, `BayBodyC`, `BayFootC`, `DictationHUDStrip`
  - `Coda`, `CodaTile`, `CodaLayerPopover`, `PopoverGlyph`, `CodaManualRail`
  - `WebviewBay` (shared shell)
  - `MockedScreenshotWithMarkup` (the screenshot + layers, size-aware)
  - `ToolTickerInline`, `ToolCallRow`
  - `LayerRail`, `LayerRow`
  - `DesktopBackdrop`, `PaneHeader`, `Chip`, `FootAction`, `ListeningPulse`

Promotion candidates if a second study needs them:
- `<WebviewBay>` — a generic ephemeral floating-window-as-webview shell.
  Would be reused by any future Talkie surface that wants the "open a
  panel, do a task, accept or cancel" pattern.
- `<ToolTickerInline>` — same vocabulary the Skill Forge console uses;
  worth unifying.

## Donor references

- `apps/macos/Talkie/Services/Tray/TrayViewer.swift:1090` — existing
  external-editor handoff (CleanShot X / ScreenshotX). The thing we're
  replacing as the primary path.
- `apps/macos/Talkie/Views/Home/HomeAppWidgetView.swift` — current
  WKWebView host pattern.
- `apps/macos/Talkie/Views/Learn/LearnKnowledgeWebView.swift` — same.
- `apps/macos/Talkie/Views/Notes/ScopeCaptureDetailView.swift` — the
  capture detail surface (study: MacCaptureDetail). Markup bay should
  be invocable from its toolbar.
- `apps/macos/Talkie/Views/RecordingCompanionSurface.swift` — the HUD
  Framing C must not steal focus from.
- `docs/specs/tlk-017-media-capture-quality.md` — agent-oriented
  capture presets. Markup belongs in the same conversation: lower-
  quality region captures + agent-driven annotation is the same arc.
