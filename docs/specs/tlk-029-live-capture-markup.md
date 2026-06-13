# TLK-029 - Live Capture Markup Overlay

**Status**: Draft
**Owner**: Talkie macOS
**Date**: 2026-06-13
**Studio**: /eng/tlk-029
**Related**: [TLK-021](tlk-021-capture-markup.md) capture markup, [TLK-022](tlk-022-media-augmentation-pipeline.md) sidecars, [TLK-026](tlk-026-visual-context-capture.md) visual context capture, screen recording services in `apps/macos/Talkie/Services/ScreenRecording/`, Preframe at `/Users/art/dev/preframe`

## Summary

Talkie should let users draw over the live desktop while dictating or recording.
The user sees the real app underneath, opens a pen extension from the capture
HUD, draws on a transparent overlay, and then Talkie saves that intent as visual
context.

There are two product modes:

1. **Draw then snap** for still capture: draw on the live screen, then commit a
   screenshot with the overlay layers attached.
2. **Draw while recording** for screen video: draw while recording, keep the
   base `.mp4` clean, and persist marks as timestamped vector data that can be
   previewed instantly or rendered into an annotated derivative later.

This is not a separate screenshot editor. It is an extension of the capture HUD.

## Product Decision

The canonical video artifact is always clean:

```text
source.mp4          clean screen/app capture
visual-context.json transcript, active-window events, screenshots, markup layers
preview overlay     player-only reconstruction from visual-context.json
annotated.mp4       optional derived export, generated only when requested
```

Talkie should never require a heavy render just to review "what did I say and
what did I draw?" The library player can draw the markup timeline over the clean
video in real time. Preframe, Remotion, or Hyperframes enter only when the user
wants a shareable artifact, a polished replay, or a demo variant.

## Motivation

Dictation often contains phrases like "this part", "the thing here", or "circle
this section". A screenshot after the fact loses the embodied gesture. A full
video can preserve the gesture but is heavier than necessary for many agent
tasks.

Live capture markup gives Talkie a middle primitive:

- the user points naturally while speaking
- the recording or screenshot keeps the visual reference
- agents receive structured coordinates and timestamps instead of guessing
- the capture HUD remains the single control surface

## UX Model

The capture HUD grows a markup wing.

```text
[ rec 0:42 ] [ stop ] [ pen ]
                     expands to:
              [ select ] [ pen ] [ circle ] [ arrow ] [ text ] [ undo ] [ done ]
```

For region capture, the wing may dock to the nearest edge of the capture frame.
For full-screen capture, it stays attached to the stop pill. The toolbar should
never become a separate toolbox that the user has to find.

### Still Capture Flow

```text
dictation is active
-> user opens pen mode from the HUD
-> transparent overlay receives drawing input
-> user clicks Done / presses Return
-> Talkie captures the underlying screen or region
-> overlay layers are normalized into screenshot coordinates
-> PNG + .markup.json are saved
-> screenshot is attached to the active dictation
```

The live desktop remains visible until commit. The saved artifact is still a
normal Talkie screenshot plus markup sidecar.

### Video Capture Flow

```text
screen recording is active
-> user opens pen mode from the HUD
-> transparent overlay receives drawing input
-> marks are visible to the user but excluded from the base recording
-> Talkie records timestamped markup events
-> stop saves the video and visual-context bundle
-> library preview replays the markup over the clean video without rendering
-> optional export produces an annotated video derivative
```

The v1 video path should explicitly exclude Talkie markup panels from
ScreenCaptureKit capture (`NSWindow.sharingType = .none`) while retaining the
timestamped vector event sidecar. If a raw "what the user saw live" archive is
ever useful, it should be a separate derived capture/export, not the source of
truth.

### Preview And Export Modes

Preview is lightweight and synchronous with playback:

- the clean video is decoded normally
- a transparent player overlay reads the markup event layers
- the overlay shows layers whose `startTime`/`endTime` include the current playhead
- scrubbing updates the overlay immediately
- transcript words and markup events can highlight each other

Export is deliberate and asynchronous:

- **clean export**: source video + audio, no overlay
- **raw annotated export**: source video + exact recorded markup timing
- **polished annotated export**: source video + normalized/redrawn markup
- **Preframe demo**: source video + transcript + markup sidecar become a
  production brief for Remotion or Hyperframes

## Architecture

Add a `LiveCaptureMarkupOverlayController` owned by the active capture session.
It presents a borderless transparent `NSPanel` on the target screen and hosts a
transparent `WKWebView` drawing surface.

```text
ScreenRecordingController / ScreenshotCaptureService
  -> Capture HUD / stop pill
  -> LiveCaptureMarkupOverlayController
  -> transparent WKWebView
  -> Swift bridge receives layers + timing
  -> screenshot sidecar or visual-context metadata
```

The existing capture-markup web bundle should be split into reusable core canvas
logic and surface modes:

```text
mode: editor
background: screenshot image
coordinates: image-normalized
storage: CaptureMarkupDocument beside PNG

mode: overlay
background: transparent
coordinates: target-rect-normalized
storage: pending live overlay session, then screenshot/video sidecar
```

The overlay mode should start smaller than the full editor. Required v1 tools:

- select
- pen/freehand
- ellipse/circle
- arrow
- undo/redo
- done/cancel
- stroke color and width

Text labels can follow after the pointer/shape loop feels good.

## Data Model

Extend `CaptureMarkupLayerKind` with:

```swift
case ellipse
case ink
```

Add optional point data for freehand strokes:

```swift
public var points: [CaptureMarkupPoint]?
```

All coordinates remain normalized. In overlay mode they are normalized to the
recording target rect. On still commit, Talkie converts them into screenshot
image coordinates before saving `CaptureMarkupDocument`.

For video, store timestamped events in the visual-context bundle:

```json
{
  "schema": 1,
  "kind": "capture-markup-events",
  "events": [
    {
      "id": "layer-id",
      "type": "add",
      "time": 12.4,
      "layer": {
        "kind": "ellipse",
        "frame": { "x": 0.32, "y": 0.28, "width": 0.18, "height": 0.08 },
        "color": "#D03A1C",
        "strokeWidth": 3
      }
    }
  ]
}
```

The recorded video must not depend on the visible overlay. The event sidecar is
the source of truth for agents, search, instant preview, future editing, and
annotated export.

`CaptureMarkupLayer.startTime` and `CaptureMarkupLayer.endTime` are seconds
relative to the clean video. For long-lived marks, `endTime` may be omitted or
set to the end of the recording. For telestrator-style marks, the overlay may
auto-fill a short default display window while keeping the raw stroke timing.

## Capture Behavior

The live markup overlay is intentionally different from passive capture HUDs:

- it receives pointer events while pen mode is active
- it should be visually transparent except for marks and controls
- for video capture it should be excluded from the recorded output
- for still capture it should be excluded from the base screenshot, then applied
  through `CaptureMarkupRenderer`

Still capture therefore needs an explicit commit step:

1. hide or exclude the overlay from the base screenshot
2. capture the underlying target
3. save the markup sidecar
4. render preview/export with the markup applied

Video capture follows the same principle: clean media first, replayable markup
second. The visible overlay is a live input surface, not the base recording.

## Integration Points

- `ScreenRecordingActiveOverlayController`: add a pen action next to the stop
  pill and own the live overlay lifecycle.
- `ScreenRecordingService`: preserve markup event sidecars in the visual-context
  bundle when clips are drained to recordings.
- `LiveCaptureMarkupOverlayController`: set the transparent panel's
  `sharingType = .none` so the overlay remains visible to the user without being
  baked into the source clip.
- Library clip player: render a transient markup overlay from
  `RecordingVisualContextEvent.markupLayers` for instant review.
- `ScreenshotCaptureService`: add draw-then-snap commit support for active
  dictations and standalone captures.
- `CaptureMarkupDocument`: add ellipse and ink support.
- `CaptureMarkupRenderer`: render ellipse and freehand ink.
- `Resources/CaptureMarkup`: factor shared drawing logic or add a lean overlay
  entry point that shares schema and bridge conventions.
- Workflow executor: add a "Send Walkthrough to Preframe" path that attaches
  the clean clip, transcript, and visual-context bundle to Preframe's agent
  intake API as local source files and attachments.

## Phasing

### Phase 1 - Draw Then Snap

- transparent overlay launched from capture HUD
- pen, ellipse, arrow, undo, done, cancel
- commit to screenshot + `.markup.json`
- attach screenshot to active dictation
- no text labels, no post-hoc video compositing

### Phase 2 - Video Event Sidecar And Instant Preview

- launch overlay during active screen recording
- record timestamped layer add/update/remove events
- include event sidecar in visual-context manifest
- keep source `.mp4` clean
- add library/player overlay preview from sidecar without re-rendering

### Phase 3 - Shared Editor Core

- factor web canvas tools so editor mode and overlay mode share implementation
- add text labels and selection editing
- add deterministic raw annotated video export that composites marks from the
  event sidecar

### Phase 4 - Preframe / Hyperframes Production Pass

- export a Preframe intake bundle:
  - clean video
  - transcript
  - visual-context manifest
  - markup layer summary as structured JSON and human-readable notes
- support Hyperframes output for animated SVG telestrator strokes, arrows,
  spotlight regions, and callouts
- support Remotion output for programmatic product-demo cuts, zooms, captions,
  and clean/annotated variant renders
- let workflows choose `clean`, `rawAnnotated`, `polishedAnnotated`, or
  `preframeDemo` as the requested output mode

## Workflow Pattern

A Talkie workflow can treat the combined verbal + visual stream as instructions:

```text
Trigger: recording stopped with screen video + markup
Inputs:
  - clean video clip
  - transcript
  - visual-context manifest
  - markup layers with timing
Do:
  - summarize "what the user explained"
  - convert drawn circles/arrows/notes into production notes
  - optionally submit to Preframe
Then:
  - attach produced outputs back to the Talkie recording
```

Example Preframe handoff:

```json
{
  "mode": "register",
  "compositionId": "feature-walkthrough-export-button",
  "name": "Feature Walkthrough - Export Button",
  "prompt": "Use the voice transcript and markup sidecar as production instructions. Keep the clean version available and produce an annotated demo variant.",
  "sources": [
    { "path": "/absolute/path/source.mp4", "role": "clip" }
  ],
  "attachments": [
    { "path": "/absolute/path/visual-context.json", "kind": "talkie-visual-context" },
    { "path": "/absolute/path/transcript.json", "kind": "talkie-transcript" }
  ]
}
```

## Acceptance Criteria

- A user can draw during an active screen recording.
- The saved source video does not contain Talkie markup UI or strokes.
- The visual-context manifest contains timestamped markup layers for the
  recording.
- Opening the clip in Talkie can show or hide the markup overlay immediately
  without invoking Preframe, Remotion, Hyperframes, or ffmpeg.
- Scrubbing the player updates visible markup according to layer timing.
- A workflow can access the clean clip and markup sidecar as separate inputs.
- An annotated video can be produced as a derived export without modifying the
  clean source clip.
- Preframe handoff can include the clean clip, transcript, and markup sidecar as
  attachments.

## Open Questions

- Should `Done` in video mode close only pen mode or also mark all current
  layers as persistent until the end of the clip?
- Should freehand strokes fade after a few seconds during video capture, or stay
  visible until cleared?
- Should still capture default to the current recording target, current window,
  or full screen when launched during plain dictation?
- Should agents receive flattened marked screenshots, vector sidecars, or both?
- Should the instant player preview show raw stroke timing, a prettified
  reconstruction, or a toggle between both?

## Studio Follow-Up

Create a Studio surface for the HUD markup wing before Swift polish. The design
study should compare stop-pill-attached controls against capture-frame-docked
controls across region, window, and full-screen captures.
