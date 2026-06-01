# TLK-026 - Visual Context Capture for Agent Workflows

**Status**: Product/engineering proposal
**Owner**: Talkie macOS + agent runtime
**Date**: 2026-06-01
**Studio**: /eng/tlk-026
**Related**: [TLK-017](tlk-017-media-capture-quality.md) (capture quality), [TLK-022](tlk-022-media-augmentation-pipeline.md) (derived sidecars), [TLK-024](tlk-024-scopes-agent-context-model.md) (agent context), screen recording services in `apps/macos/Talkie/Services/ScreenRecording/`, tray assets in `apps/macos/Talkie/Services/Tray/`

## Summary

Talkie should let dictations and agent workflows carry **moving-picture context**
without forcing agents to ingest raw videos directly.

The core Talkie feature is a durable visual context bundle attached to a
recording: raw screen clip, capture metadata, and a stable on-disk contract.
Derived artifacts such as sampled frames, contact sheets, and Markdown
summaries are optional processors layered on top. The first processor can use
FFmpeg after recording stops, but Talkie proper must not depend on FFmpeg to
make visual context valid.

Working language:

```text
Talkie captures and indexes reality.
Context processors prepare it for agents.
Agents receive references, not a pile of frames.
```

## Motivation

Today Talkie can give agents static screenshots and text. That works for many
tasks, but agentic work often depends on motion:

- the user switches apps while explaining a task
- a menu appears and disappears
- a screen recording stop/control overlay is part of the bug
- a drag, resize, hover, or countdown matters
- the user narrates "this thing here" while the screen is changing

Raw video is not a good default prompt payload. It is large, opaque to many
agents, and expensive to inspect. The better primitive is a local bundle:

- the original clip is preserved
- metadata gives the narrative timeline
- optional processors create frames/contact sheets/summaries
- the agent gets a compact reference and drills in only when needed

## Product Boundary

This feature has two layers with different ownership.

### Talkie Proper

Talkie owns the source-of-truth capture and handoff contract:

- start/stop a visual context session tied to a dictation/capture session
- store the raw screen clip
- record capture metadata during the session
- persist the visual context bundle and status
- attach the bundle to `TalkieObjectAssets`
- expose the bundle path to agent handoffs and workflows

This layer must work without FFmpeg.

### Context Processor Layer

Processors produce derived, reproducible artifacts:

- run FFmpeg after stop
- sample frames using duration-aware heuristics
- build a contact sheet
- write `visual-context.json`
- write `visual-context.md`

This layer is intentionally idiosyncratic and replaceable. FFmpeg is one
processor, not a Talkie core dependency. Later processors could use AVFoundation,
OCR, a VLM captioner, or per-agent rules.

## Goals

- Make visual context a first-class recording asset.
- Preserve the raw clip and metadata even when derived processing fails.
- Keep dictation delivery fast; visual processing must never block normal paste.
- Give agents folder-level context instead of flooding prompts with images.
- Make Hyper+R as low-friction as Hyper+S: quick-start from a remembered target.
- Keep the v1 derived artifact set modest and inspectable.

## Non-Goals For V1

- No OCR.
- No perceptual dedupe/grouping.
- No frame captions from a vision model.
- No raw video upload by default.
- No 60 fps extraction or exhaustive timeline reconstruction.
- No hard dependency on FFmpeg for the core Talkie data model.

## User Experience

### Hyper+R Quick Start

Screen recording should have the same "get going immediately" quality as
Hyper+S.

When the user presses Hyper+R:

1. Talkie loads the last successful screen recording target.
2. Talkie shows a faint outline over that target.
3. A short countdown starts: `3 2 1`.
4. If uninterrupted, recording starts automatically.

During countdown:

| Input | Behavior |
| --- | --- |
| `Esc` | Cancel |
| `Return` | Start immediately |
| Drag/resize outline | Edit target and pause/arm countdown |
| Hyper+R again | Resume countdown or start from armed target |
| Mouse/key activity outside the outline | Pause/arm, so the user can arrange the screen |

The mental model:

```text
Hyper+R = record the thing I usually record.
Move/adjust = change the thing.
Esc = never mind.
Return = go now.
```

### Recording Target Memory

Store the default target as a Talkie preference, preferably per display:

```swift
struct ScreenRecordingPreset: Codable, Sendable {
    var mode: CaptureMode          // region, window, display
    var displayID: CGDirectDisplayID?
    var rect: CGRect?
    var windowTitle: String?
    var appName: String?
    var displayName: String?
    var capturedAt: Date
}
```

If the preset is invalid because the display/window disappeared, fall back to
the current region picker.

## Data Model

Add visual contexts to the existing consolidated asset blob:

```swift
public struct TalkieObjectAssets: Codable, Sendable {
    public var segments: TimedTranscription?
    public var screenshots: [RecordingScreenshot]?
    public var clips: [RecordingClip]?
    public var attachments: [RecordingAttachment]?
    public var visualContexts: [RecordingVisualContext]?
    public var textProvenance: [ProvenanceSegment]?
}
```

The asset pointer should stay small. The rich timeline lives in the manifest on
disk.

```swift
public struct RecordingVisualContext: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case recording
        case captured
        case processing
        case ready
        case failed
    }

    public var id: UUID
    public var recordingId: UUID
    public var relativeDirectory: String
    public var sourceClipFilename: String
    public var captureMode: String
    public var startedAt: Date
    public var endedAt: Date?
    public var durationMs: Int?
    public var width: Int?
    public var height: Int?
    public var displayName: String?
    public var manifestFilename: String?
    public var summaryFilename: String?
    public var contactSheetFilename: String?
    public var frameCount: Int?
    public var status: Status
    public var processorVersion: String?
    public var errorMessage: String?
}
```

### Folder Layout

```text
~/Library/Application Support/Talkie/VisualContexts/
  <recording-id>/
    <visual-context-id>/
      source.mov
      visual-context.json
      visual-context.md
      contact-sheet.jpg
      frames/
        frame-0001.jpg
        frame-0002.jpg
```

The directory is the stable unit of handoff. Agents should receive the folder
reference, not all frame images as individual prompt attachments.

## Manifest Shape

`visual-context.json` is the processor-owned machine-readable view:

```json
{
  "schema": 1,
  "recordingId": "UUID",
  "visualContextId": "UUID",
  "sourceClip": "source.mov",
  "durationSeconds": 64.2,
  "capture": {
    "mode": "region",
    "displayName": "Built-in Display",
    "width": 1565,
    "height": 1410
  },
  "frames": [
    { "index": 1, "t": 0.0, "path": "frames/frame-0001.jpg" },
    { "index": 2, "t": 2.0, "path": "frames/frame-0002.jpg" }
  ],
  "metadataEvents": [
    {
      "start": 0.0,
      "end": 12.4,
      "type": "activeWindow",
      "appName": "Codex",
      "windowTitle": "Talkie - Codex"
    }
  ],
  "processors": [
    {
      "kind": "ffmpeg-frame-sampler",
      "version": "v1",
      "command": "ffmpeg ...",
      "ranAt": "2026-06-01T00:00:00Z"
    }
  ]
}
```

## Summary Shape

`visual-context.md` should be compact and human/agent readable:

```md
# Visual Context

Duration: 01:04
Capture: region, Built-in Display, 1565x1410
Source clip: source.mov
Contact sheet: contact-sheet.jpg
Frames: frames/

## Timeline

00:00-00:12  Codex, window: "Talkie - Codex"
00:13-00:28  Talkie, screen recording controls visible
00:29-00:43  Talkie, settings/sidebar area active
00:44-01:04  Codex, dictation continued
```

The timeline is metadata-powered in v1. Do not pretend to understand visual
content unless a future OCR/VLM processor actually produced that signal.

## Metadata Sampler

During recording, sample cheap metadata at ~1 Hz and write only meaningful
changes:

- active app name
- bundle identifier
- window title
- display name / display ID
- capture bounds
- timestamp relative to recording start

Optional later:

- mouse position/clicks
- focused UI element from Accessibility
- screen-change hashes

This sampler is Talkie proper. It is cheap, deterministic, and useful even when
no derived frames exist.

## Processor V1: FFmpeg Frame Sampler

After the visual context stops, enqueue a background processor. It should:

1. run `ffprobe` for duration/size/codec metadata
2. extract a duration-aware frame set
3. build a contact sheet
4. write `visual-context.json`
5. write `visual-context.md`
6. update the `RecordingVisualContext` status

Sampling heuristic:

| Clip duration | Frame cadence |
| --- | --- |
| `<= 8s` | 3 fps |
| `<= 30s` | 1 fps |
| `<= 2m` | 1 frame / 2s |
| `<= 10m` | 1 frame / 5s |
| `> 10m` | 1 frame / 10s, capped |

Always include first and last frames.

The processor must be timeout-bounded and failure-tolerant. A failed FFmpeg run
marks derived artifacts as failed, but the raw visual context remains attached
and valid.

## Agent Handoff

Normal prompt/handoff text should include a compact reference:

```md
Visual context captured:
- Summary: /.../visual-context.md
- Contact sheet: /.../contact-sheet.jpg
- Frames folder: /.../frames/
- Source clip: /.../source.mov
```

Agents should inspect the summary/contact sheet first, then open specific
frames only when needed. The folder is the payload boundary.

## Implementation Plan

1. **Model**
   - Add `RecordingVisualContext` to TalkieKit.
   - Add `visualContexts` to `TalkieObjectAssets`.
   - Add `VisualContextStorage` for directory creation and path resolution.

2. **Quick-start recording UX**
   - Add `ScreenRecordingPresetStore`.
   - Add `ScreenRecordingArmController` for countdown/armed/cancel/start.
   - Update Hyper+R to use last target before falling back to selection.

3. **Capture lifecycle**
   - Tie visual context sessions to Agent `recordingId` / capture session ID.
   - Start screen capture in Talkie main app.
   - Sample metadata during recording.
   - Stop/finalize the clip when dictation stops or the user stops screen recording.

4. **Attachment contract**
   - Persist `RecordingVisualContext` in the visual context folder.
   - Merge the asset pointer into `TalkieObjectAssets`.
   - Extend agent/workflow delivery text to include compact visual context refs.

5. **Optional processor**
   - Add a `VisualContextProcessor` protocol.
   - Implement `FFmpegVisualContextProcessor`.
   - Run it after stop at utility priority.
   - Keep it out of the dictation critical path.

6. **UI polish**
   - Show visual context status in the tray/recording detail.
   - Add "Reveal Visual Context" and "Open Contact Sheet" actions when ready.

## Open Questions

- Should visual context recording be automatic for all agent-targeted dictations,
  opt-in per session, or scope/rule controlled?
- Should Hyper+R always record the last region, or should some scopes pin a
  preferred target?
- Should a visual context bundle be deleted with its recording, or retained as
  a separate user-facing asset?
- How long should Talkie wait for derived artifacts before an agent handoff
  proceeds with only raw clip + metadata?
- Should the FFmpeg processor live in-app, in a helper, or in an external
  context-rule runner?

## V1 Success Criteria

- Hyper+R can start recording the last region without mouse selection.
- A dictation can attach one visual context bundle.
- The raw clip and metadata are valid without FFmpeg.
- If FFmpeg exists, a small frame set, contact sheet, manifest, and summary are
  produced after stop.
- Agent handoff references the visual context folder without dumping every
  frame into the prompt.
