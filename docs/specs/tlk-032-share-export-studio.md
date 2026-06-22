# TLK-032 - Screenshot Export Panel

**Status**: Revised draft for review (V1 scoped down from "Share / Export Studio")
**Owner**: Talkie product + macOS
**Date**: 2026-06-21
**Studio**: /eng/tlk-032
**Related**: [TLK-017](tlk-017-media-capture-quality.md), [TLK-018](tlk-018-media-surface-roundup.md), [TLK-026](tlk-026-visual-context-capture.md), `/mac-library-empty`
**Review**: [tlk-032-review-claude.md](tlk-032-review-claude.md) (governing critique for this revision)

## Summary

Talkie should add a small **Export Panel** for turning a captured **screenshot**
into a framed, correctly sized image ready to paste or save.

The V1 product job is narrow and precise:

> Take this screenshot, frame it so it doesn't look like a raw desktop fragment,
> size it correctly for where I'm pasting it, and give me a predictable Copy or
> Save As — with no accidental recompression.

Talkie is getting good at capture and collection. The missing layer is **output**.
A screenshot often needs one pass — breathing room, a background, rounded corners,
the right pixel size — before it's ready for Slack, a PR comment, or a doc. V1
delivers exactly that pass for screenshots and nothing else.

This doc is deliberately a V1 panel spec, not a roadmap. Later media types and
sharing integrations are described in **Later Tracks** and are explicitly out of
V1.

## What V1 Is Not (read this first)

V1 is **screenshots only**. The following are **out of V1**, called out here so
future work does not silently re-expand scope:

- **No video / clip export.** Styled framing around video is a full per-frame
  re-encode (no `AVMutableComposition` exists today). Deferred — see Later Tracks.
- **No recording / memo / dictation share cards.** A recording card synthesizes
  new pixels (waveform, transcript layout); that is a different render model from
  framing existing pixels. Deferred — see Later Tracks.
- **No user-facing "Private" mode.** A blur overlay does not make an artifact
  safe to share while metadata (browser URLs, terminal paths, window titles) is
  still embedded. Privacy is **out of scope** until a real metadata/source
  redaction subsystem exists — see Privacy (Out of Scope).
- **No universal "Share to <destination>" language.** No Slack/Linear/Notion
  integrations, no cloud links, no destination presets. V1 produces a good image
  and hands it to Copy or Save As; the OS handles the rest.
- **No batch export, no GIF, no watermarking, no WebP, no Markdown bundles.**

If you are tempted to add any of the above, it belongs in Later Tracks, not V1.

## User Job (V1)

**Send a framed screenshot quickly.**

"I captured the thing. I want it to look intentional and be the right size, then
drop it into Slack or a PR without fiddling — and I never want it silently
recompressed when I just wanted the original."

Two intents cover this:

1. **Original** — give me the source pixels, no styling, no recompression.
2. **Polished** — frame it (background, padding, corners) at a sensible size.

## Surface

A **right-side inspector panel** over the current detail view. Not a modal, not a
separate navigation destination. (Rationale: keeps the source screenshot in
context, owns its own preview state, dismisses cheaply.)

Layout:

- **Left / main**: large live preview of the framed screenshot, big enough to
  trust the output.
- **Right column**: preset chips at top, then compact controls grouped by intent.
- **Bottom of right column**: primary actions (Copy, Save As).

The user-facing surface is the **"Export Panel"**. The doc id stays TLK-032. We do
not call it a "Studio" — that oversells a single-media V1 panel and collides with
the design `studio/` route namespace.

The preview updates **synchronously** for every control change. Still-image
rendering is cheap enough to render on the main actor without a progress state.

## V1 User Flow

1. User has a screenshot in a Library row, the capture detail toolbar, or a tray
   hover action.
2. User triggers **Export…** (or **Copy Styled** for the one-click path). The
   Export Panel opens as an inspector over the current detail view.
3. Panel opens with the **Polished** preset pre-selected and the preview **already
   rendered** — the default that wins on open.
4. Left shows the framed screenshot; right column top shows preset chips:
   **Original · Polished**.
5. User optionally adjusts **background / padding / corner radius / shadow**; the
   preview updates instantly.
6. User picks **format** (PNG / JPEG) and, for JPEG, a **quality** tier. The panel
   shows the resulting **pixel dimensions** and an **estimated file size**.
7. User clicks **Copy** → styled image to the pasteboard, toast confirms "Copied."
   Or **Save As** → standard save panel → on success, offer **Reveal in Finder**.
8. The panel remembers the **last-used preset** so the next screenshot opens the
   same way.

One media type, one render path, no privacy claims, no video, no destinations.

## Entry Points

Command language (V1 subset):

- `Export…` — opens the Export Panel.
- `Copy Styled` — applies the last-used (or Polished) preset and copies without
  opening the panel.
- `Copy Original` — copies the source pixels with no styling, bypassing the panel.

V1 entry points:

- capture detail toolbar (`ScopeCaptureDetailView`)
- screenshot / media card context menu
- Library row context menu (`ScopeLibraryList` / `ScopeLibraryView`)
- tray item hover action

Deferred entry points: keyboard shortcut after selection; memo/dictation toolbar
(no recording export in V1).

## Export Controls (V1)

### Presets

Two presets only. Presets set the full control matrix; the individual knobs exist
for adjustment, not as the primary path.

**Original**
- background: none / transparent
- padding: none
- corner radius: preserve source
- shadow: none
- format: source format when possible (PNG); never recompress source pixels
- quality: N/A (lossless / source)

**Polished**
- background: theme surface
- padding: medium
- corner radius: subtle
- shadow: soft
- format: PNG (default) or JPEG
- quality: High when JPEG

### Background

- None / transparent
- Solid color
- Theme surface
- Soft gradient
- Blurred source backdrop

Default: Polished = theme surface; Original = none.

### Padding

- none · small · medium · large

Default: Polished = medium; Original = none.

### Corner radius

- square · subtle · rounded

Default: Polished = subtle; Original = preserve source.

### Shadow

Keep it — a soft shadow is most of what makes a framed screenshot read as
"intentional," and it's cheap to render on a still.

- none · soft · presentation

Default: Polished = soft; Original = none. (Note: a shadow needs the background to
not be transparent, or it must render onto the padded canvas; the renderer owns
that interaction.)

### Format

- PNG (default) — lossless; used for Original and Polished by default.
- JPEG — opt-in; exposes the quality tier below.

WebP and other formats are out of V1.

### Quality (JPEG only)

User-facing tiers, mapped to a JPEG compression quality by the renderer:

- Small — chat / quick send
- Medium — docs / issues
- High — presentations

PNG ignores this control. Codec/bitrate are never exposed. **Original never
recompresses**: choosing Original disables format/quality and emits source pixels.

### Actions

- **Copy** — writes the styled image to the pasteboard (see Pasteboard Contract).
- **Save As** — standard `NSSavePanel`; on success, offer Reveal in Finder.

## Privacy (Out of Scope for V1)

V1 ships **no** user-facing "Private" control. A cosmetic blur over a screenshot
does not make it safe to share while the artifact's metadata still embeds browser
URLs, terminal working directories, and window titles. A privacy mode that does
not strip those is a false promise.

When privacy is taken up (separate spec), it must, at minimum:

- strip / redact metadata and RichContext (`browserURL`, `terminalWorkingDir`,
  `windowTitle`, `appBundleID`) from the export,
- guarantee the exported file carries no residual source path or EXIF,
- default sensitive fields **off**, with explicit opt-in to include them.

Until that subsystem exists, do not surface a "Private" toggle. There is no
`private` field in the data model today, and we will not fake one with a blur.

## Rendering Model

Clean boundary, owned by the renderer:

- **input**: a resolved screenshot **file URL** + an `ExportRecipe`.
- **output**: an image (in-memory representation for Copy; a written file for
  Save As).
- **no direct UI state access** — the panel builds a recipe; the renderer renders
  it.

V1 rendering:

- Frame the screenshot with SwiftUI/AppKit and rasterize via `ImageRenderer`
  (macOS 13+) or AppKit `NSImage`/`bitmapImageRep` depending on the deployment
  target (see Open Questions).
- Render at the correct scale (see Color & Scale Defaults).

The panel previews the recipe; the renderer is the single source of truth for the
exact exported bytes.

## Implementation Touchpoints

### Existing files (V1 wiring)

- `apps/macos/Talkie/Views/Notes/ScopeCaptureDetailView.swift` — add `Export…`
  to the capture detail toolbar; currently uses `NSSharingServicePicker` for raw
  share (around line 777).
- `apps/macos/Talkie/Views/Library/ScopeLibraryView.swift` — Library row context
  menu entry point.
- `apps/macos/Talkie/Views/ScreenshotsScreen.swift` — screenshot grid context
  menu entry point.
- `apps/macos/TalkieKit/Sources/TalkieKit/CaptureMediaFileResolver.swift` —
  resolves a `TalkieObject` to a concrete media URL; the panel uses this to get
  the **resolved screenshot URL** (see Missing-File Behavior).
- `apps/macos/TalkieKit/Sources/TalkieKit/UI/ScopeLibraryList.swift` — shared
  row components, for the context-menu hook.
- `apps/macos/TalkieKit/Sources/TalkieKit/Data/TalkieObject.swift` — source of the
  stable `id: UUID` and metadata; no schema change needed for V1.

### New surfaces (V1)

- `ShareExportPanelView` (the inspector) — Talkie app target.
- `ScreenshotExportPreview` (the live framed preview) — Talkie app target.
- `ExportRecipe` (Codable value type) — **TalkieKit**.
- `ExportRenderer` (recipe + URL → image/file) — **TalkieKit**.

### Renderer ownership

`ExportRecipe` and `ExportRenderer` live in **TalkieKit**, not the Talkie app
target, so TalkieAgent can reuse the same renderer later without a second
implementation. The app-target views (`ShareExportPanelView`,
`ScreenshotExportPreview`) own UI state and build a recipe; TalkieKit owns
rendering.

### Resolved screenshot URL

The panel resolves the source through `CaptureMediaFileResolver` to a concrete,
validated file URL **before** opening. The recipe carries the resolved URL (plus
`artifactID: UUID` for reference), not a bare UUID, because media paths are
resolved by multi-directory search and are not guaranteed stable.

### Missing-file behavior

If the resolver returns no existing file (tray item evicted, file moved), the
panel does **not** open into a broken preview. It surfaces a clear
"original no longer available" state and disables Copy/Save As. Resolution
happens up front so this is a clean precondition, not a mid-export failure.

### Pasteboard contract (Copy)

`Copy` clears the pasteboard and writes, in order of richness:

- the rendered image as **PNG** (`NSPasteboard.PasteboardType.png`), and
- a **TIFF** representation for apps that prefer it,
- for JPEG-format exports, write the JPEG bytes; otherwise PNG is canonical.

It does **not** write a file URL for Copy (Copy is pixels, not a file). File
output is the Save As path. This keeps "paste into Slack/doc" predictable and
distinct from "save a file."

### Save panel (Save As)

Standard `NSSavePanel` with the default filename derived from the artifact
(title or timestamp) and the chosen extension (`.png` / `.jpg`). On success,
offer **Reveal in Finder**. No silent overwrite beyond the panel's own prompt.

### Color & scale defaults

- Export at **source-native scale** by default (a 2× Retina capture exports at its
  full pixel dimensions), so "correctly sized" matches what the user captured.
- Preserve the source color space; do not silently convert to sRGB unless required
  by the chosen format. The renderer is responsible for not introducing a color
  shift between preview and exported bytes.
- The panel displays the **resulting pixel dimensions** so size is never a
  surprise.

## Data Model Implications

V1 is **view/composition state only** — no schema migration.

```swift
struct ExportRecipe: Codable, Sendable {
    var preset: ExportPreset          // .original | .polished
    var artifactID: UUID              // reference only
    var sourceURL: URL                // resolved, validated screenshot file
    var background: ExportBackground
    var padding: ExportPadding
    var cornerStyle: ExportCornerStyle
    var shadow: ExportShadow
    var format: ExportFormat          // .png | .jpeg
    var quality: ExportQuality        // used only when format == .jpeg
}
```

There is **no** `privacy` or `metadata` field in the V1 recipe — both are out of
V1 (privacy is out of scope; per-type metadata toggles arrive with the
recording/bug-report work). Do not add a persisted `private` flag; that requires
its own data-model spec.

## Success Criteria (V1)

- A user can open a screenshot, get a framed result, and Copy it in **under five
  seconds**, where "framed" = the exact output of the **Polished** preset.
- **Copy** and **Save As** are predictable: Copy puts pixels on the pasteboard;
  Save As writes a file the user named and can reveal.
- **Original never recompresses** and never restyles — it emits source pixels.
- Exported pixel dimensions match what the panel displayed; no surprise resize or
  color shift between preview and output.
- The missing-file case degrades cleanly (no broken preview, no failed export
  mid-flight).

## Studio Visual Follow-up

Before Swift polish, create the Studio study:

- route: `/mac-share-export` under `design/studio/` (register canonically in the
  sidebar registry; mirror the sibling entry).
- show **screenshots only**: Original and Polished presets side by side.
- vary background (theme surface, solid, gradient, blurred backdrop), padding
  (none→large), corner radius (square→rounded), shadow (none/soft/presentation).
- show the panel layout: large preview left, preset chips + controls right,
  Copy / Save As at the bottom.
- include the resulting-dimensions / estimated-size readout.
- do **not** mock video, recording cards, or a Private toggle — those are not V1.

## Later Tracks (explicitly out of V1)

Described for context only. Each is a separate scope decision; none ships in V1.

- **Video / clip export.** Trim + quality tier first; styled framing around video
  only if the per-frame `AVMutableComposition` re-encode is justified.
- **Recording / memo / dictation share cards.** Card composition (title, waveform,
  duration, transcript excerpt, audio export). Sibling surface behind the same
  `Export…` entry point; a different render model from screenshot framing.
- **Privacy / redaction subsystem.** See Privacy (Out of Scope). Requires a
  data-model spec.
- **Bug Report preset.** Depends on a per-artifact-type metadata resolution layer
  (dimensions, app/source, timestamp, duration are fragmented across JSON blobs in
  the model).
- **Presentation preset, device frames, window chrome.**
- **Destination guidance.** Internal size/quality recommendations only — never
  surfaced as "Share to <destination>" without real integration.
- **Markdown / ZIP bundles, multi-asset contact sheets, agent-handoff recipes.**
- **WebP / GIF / additional formats.**

## Cut List (do not re-expand V1)

Removed from the original broad spec to keep V1 sharp:

- recording share cards → Later Tracks
- video / clip export and Milestone 2 video pipeline → Later Tracks
- user-facing **Private** preset and Private control → out of scope (no fake blur)
- Bug Report and Presentation presets → Later Tracks
- Chrome / device-frame controls → Later Tracks
- Destination Recipes table as a surface feature → internal guidance only
- WebP, GIF, Markdown/ZIP bundles, watermarking, batch export → Later Tracks
- universal "Share to <destination>" language → not in V1

## Open Questions (must answer before Swift)

1. **Minimum macOS deployment target?** Gates `ImageRenderer` (macOS 13+) vs an
   AppKit `NSImage`/`bitmapImageRep` rasterization path. **Answer first** — it
   shapes the renderer.
2. **Pasteboard richness.** Confirm the exact type set for Copy (PNG + TIFF;
   JPEG bytes when JPEG-format). Any consumer that needs a file URL on the
   pasteboard?
3. **Source-native vs. capped export scale.** Default is source-native; do we cap
   maximum dimensions for the Small quality tier, or only compress?
4. **Last-used preset scope.** Global single value (simplest) vs. per-artifact —
   recommend global for V1.
5. **Blurred-source-backdrop background** — is rendering a blurred copy of the
   source behind the framed image worth the extra pass in V1, or defer to keep the
   first render path minimal?

## Review Request

Reviewers should pressure-test:

- whether V1 is now genuinely screenshot-only and small enough to ship in a few
  weeks,
- whether the Original / Polished split and four controls (background, padding,
  corner radius, shadow) cover the job without re-expansion,
- whether the renderer boundary (TalkieKit-owned, resolved-URL input, defined
  pasteboard/save contract) is clean enough to implement,
- whether the Out-of-Scope and Cut List are firm enough to stop future scope
  creep.
