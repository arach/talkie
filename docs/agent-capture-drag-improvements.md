# TalkieAgent — easier drag for image & video captures

Consult spec. Grounded in code on branch `codex/agent-quick-capture-markup` (Codex-held — no code or git changes made by this pass).

## What exists today

TalkieAgent already owns the capture→drag loop. Three draggable surfaces:

1. **Capture Island** — `Services/Capture/CaptureIslandController.swift`. Ephemeral top-center (or contextual) preview that drops in after a screenshot/clip lands in the live tray. The whole card is a drag handle; tap opens quick markup; auto-dismisses after `dismissSeconds` (default **6s**, min 2). Hover pauses dismissal. Drag begins after a 4pt slop.
2. **Quick Markup grip** — `Services/Capture/AgentCaptureMarkupController.swift:1293`. Drag-out from the markup panel.
3. **Quick-paste handle** — `Services/Paste/FileDragSource.swift` (`FileDragPanel`). Hyper+V floating handle at the cursor.

**The payload is identical and minimal across all three:**

```swift
NSDraggingItem(pasteboardWriter: url as NSURL)   // file-URL representation only
```

No image data, no file promise, no internal-drag marker. By contrast the **main app** already writes a richer item — `Talkie/Services/Tray/TrayDragSource.swift` (`TalkieInternalDrag.pasteboardItem`: fileURL + url + marker) and supports **multi-select drag with a count badge**. The agent has neither.

This honors the "minimal island" decision (don't rebuild markup/tray browsing into it — see memory `project-agent-capture-island`). Drag itself is explicitly the part the user values most ("the most important is the drag and drop, the preview and the drag and drop"), so **improving drag is in-scope**; rebuilding the tray is not.

## Friction (why dragging feels harder than it should)

1. **File-URL-only payload limits drop targets.** A bare `NSURL` drops fine into Finder and native file wells, but data-only targets (some web `<input>`/contenteditable fields, certain chat composers, design canvases) won't reliably accept it. This is the single biggest "drop into anything" gap.
2. **Short, unrecoverable grab window.** The island vanishes in ~6s and there is **no way to re-summon** a draggable handle for a recent capture short of re-capturing or opening Agent. You must spot it, reach it, and start the drag under time pressure.
3. **No multi-capture drag.** The island only shows `recentItems(limit: 1)`. Three shots = three separate trips, and only the newest is ever on screen. The main app's multi-drag has no agent equivalent.
4. **Video specifics.** Clips drag as a static poster frame (fine), but large clips drag as plain file URLs (flaky in promise-only targets), there's no scrub/confirm before committing, and no "still-encoding vs ready" signal.
5. **Tap/drag ambiguity.** The entire card is both tap (open markup) and drag. It mostly works via the 4pt slop, but the only "this is draggable" cue is a `drag anywhere ↗` hint that fades out with the card.

## Recommendations (prioritized)

### P0 — Richer drag payload (biggest win, smallest change)
Replace the three `NSDraggingItem(pasteboardWriter: url as NSURL)` sites with a shared helper in TalkieKit, e.g. `AgentDragPayload.draggingItem(for: item)`, that writes a multi-representation pasteboard item:
- `UTType.fileURL` (Finder, file wells) — keep.
- **Image data** (`public.png` / `public.tiff`) for screenshots, so data-only targets accept the drop.
- **`NSFilePromiseProvider`** keyed off the file's UTType — most robust for large files (video) and for promise-preferring targets (Mail, design tools).
- Mirror the main app's `TalkieInternalDrag` marker so internal drops can be recognized.
- Keep `.copy`.

One helper, three call sites (island, markup grip, FileDragPanel) → consistent, wide-compatibility drops everywhere. This alone resolves friction #1 and most of #4.

### P1 — Persist & re-summon (fix the short grab window)
A missed grab should be recoverable without re-capturing:
- **Re-summon hotkey / menu-bar item** that re-presents the last N captures' draggable handles on demand.
- And/or a "sticky until dismissed" island mode (toggle in the existing ISLAND settings tab), or freeze the dismiss timer while a modifier (e.g. ⌥) is held.

Resolves friction #2. Stays within "minimal island" — it's re-showing the same preview, not adding tray browsing.

### P2 — Multi-capture drag
Stack the last N captures (deck-of-cards offset, consistent with memory `feedback-hud-preview-deck-stack`) and drag the whole set with a count badge. Port the URLs+badge logic from `TrayDragSource`. Keep opt-in / collapsed by default to respect island minimalism. Resolves #3.

### P3 — Video niceties
Poster-frame scrub on hover before drag; "ready" state so you don't grab a still-encoding clip. (File-promise payload for big clips is already covered by P0.)

### P4 — Drag affordance clarity
A persistent corner grip drawn distinctly from the tap area so drag-vs-tap is unambiguous and doesn't rely on the fading hint. Resolves #5.

## Suggested sequencing
P0 first — it's a contained, shared-helper refactor with the highest payoff and touches no UX behavior. P1 next (recovers missed grabs). P2–P4 are polish, gate on user appetite.

## Boundary note
All of the above strengthen *drag*, which is the explicitly-valued core. None of it rebuilds markup, hover-expand, or full-tray browsing into the island (out of scope per `project-agent-capture-island`).
