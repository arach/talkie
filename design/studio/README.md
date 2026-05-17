# Studio

Visual design exploration for native app treatments. Each study is a
self-contained HTML page that mirrors one Talkie surface — bay, notch,
readout, sheet, list row — closely enough to make committed palette and
material decisions without paying a Swift rebuild for every nudge.

## How studies work

A study is one directory: `studio/<study-name>/index.html`. Open it
directly in a browser (`file://...`) — no build step, no dev server.
Each study is **fully self-contained**: CSS in `<style>`, JS in
`<script>`, fonts loaded from a CDN. Reload on save.

A study renders the surface multiple ways in a single grid so the
designer is *comparing* variants, not flipping between them. This is
the key affordance — side-by-side rendering surfaces the difference
between schemes that are *designed* and schemes that are *interpolated*.

Each study has:
- `index.html` — the page itself
- `NOTES.md` — decisions log: what's in, what's out, why

The decisions log matters. A scheme that gets dropped during exploration
should leave a one-line trace of *why* it was dropped, so future studies
don't re-learn the same lesson.

## Conventions

- **Fonts.** Cormorant Garamond from Google Fonts for serif display;
  system mono for chrome. Renders close enough to SwiftUI for palette
  decisions; SwiftUI's anti-aliasing differs slightly but the
  comparative judgments hold.
- **Page canvas.** Light cream `#FBFBFA` — matches `ScopeCanvas.canvas`
  in `TalkieKit/UI/ScopeDesign.swift` so the studio bay sits in the
  same surrounding it will sit in once shipped.
- **Tokens.** Keep custom-property names aligned with Swift tokens
  where possible (e.g. `--bay-bg` ↔ `ScopePanel.bg`). When the SwiftUI
  ground-truth changes, mirror it in `_shared/` rather than copying ad
  hoc per study.
- **Scope.** Studio is for *palette / material / composition* — not for
  motion, gesture, or SwiftUI-specific rendering behavior. Anything
  depending on `compositingGroup`, `TimelineView`, real blur, etc.
  belongs in Swift.

## Workflow

1. **Open the study** in a browser. Tweak hex values inline. Reload.
2. **Compare variants** in the grid. Drop the ones that read as
   "filtered" / interpolated.
3. **Note the decisions** in `NOTES.md` — why a scheme survived, what
   the surviving accent says about the family.
4. **Port the winners** to Swift. The studio is for picking; Swift is
   for shipping.

## Current studies

| Study | What it explores |
|---|---|
| [`agent-bay/`](agent-bay/) | Color schemes and treatment toggles for the Home agent bay |
