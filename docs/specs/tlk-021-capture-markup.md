# TLK-021 — Agentic Capture Markup

**Status**: Draft
**Owner**: Talkie macOS
**Design study**: `design/studio/app/mac-capture-markup/` (Framing A — Receipt bay)

## Summary

Talkie-native screenshot markup where **natural language is primary** and **manual touch-up is secondary**. Overlays are non-destructive JSON sidecars; the source PNG is never re-encoded in place. Preview and touch-up run in an **ephemeral WKWebView bay** (spawn on demand, discard on Accept/Cancel).

External CleanShot X / ScreenshotX remain Settings fallbacks.

## Storage

Sidecar file next to the capture:

```
~/Library/Application Support/Talkie/Screenshots/<name>.png
~/Library/Application Support/Talkie/Screenshots/<name>.markup.json
```

`CaptureMarkupDocument` (TalkieKit) is the single schema shared by Swift export, the web bay, and agent tools.

## Tool vocabulary (Phase 1)

| Tool | Purpose |
|------|---------|
| `capture-markup-describe` | VLM + OCR scene description |
| `capture-markup-plan` | Instruction → layer ops JSON |
| `capture-markup-apply` | Merge ops into sidecar |
| `capture-markup-render` | Headless flatten to PNG |

Layer ops: `rect`, `arrow`, `label`, `guide` (horizontal/vertical grid). Phase 2: `blur`, OCR-anchored `region`.

## Bridge (WKWebView ↔ Swift)

| Message | Direction |
|---------|-----------|
| `markup.ready` | Web → Swift |
| `markup.update` | Web → Swift (debounced touch-up) |
| `markup.accept` | Web → Swift (final document) |
| `markup.cancel` | Web → Swift |
| `markup.push` | Swift → Web (agent iteration) |

## Entry points

1. Agent workspace tools (`Tools/capture-markup-*.sh`)
2. `talkie://capture/markup?path=…` (SystemRoutes)
3. Tray preview — "Mark up…"
4. Capture detail — "Annotate"
5. Walkie — `capture_markup` tool (opens Talkie via URL)

## Phase 1 UX

Ship **Framing A** (receipt bay): image-first web panel, agent prompt foot, layer rail, tool-call ticker. Gated launch from tray/detail — not auto-mount on every Hyper+S.

## Related

- [TLK-017 — Media Capture Quality](./tlk-017-media-capture-quality.md) — Agent capture preset
- Design NOTES: `design/studio/app/mac-capture-markup/NOTES.md`
