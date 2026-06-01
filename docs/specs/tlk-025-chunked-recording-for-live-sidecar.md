# TLK-025 - Continuous Recording with PCM Ring Buffer for Live Sidecar

**Status**: Engineering spike (recording primitive only)
**Owner**: Talkie iOS recording
**Date**: 2026-05-31 (rev 2 after codex review — see [Review history](#review-history))
**Related**: [TLK-022](tlk-022-media-augmentation-pipeline.md) (sidecars), recording-sidecar code in `apps/ios/Talkie iOS/Services/RecordingSidecar/`, on-device AI in `apps/ios/Talkie iOS/Models/OnDeviceAIService.swift`

## Summary

This spec describes a continuous-capture recording primitive for Talkie iOS that
makes it possible to snapshot a coherent audio chunk from an in-progress
recording **without interrupting the capture stream**. The motivating use case
is a live sidecar that generates AI feedback on bookmarked moments while the
user keeps talking; this spec scopes only the **recording primitive** that the
feature would sit on.

The design uses `AVAudioEngine` as the single capture client. A tap on the
input node delivers PCM buffers continuously; an in-memory ring buffer retains
the last N seconds of PCM; bookmark snapshots are cut from the ring buffer
without stopping or pausing capture. The long-form recording is written from
the same buffer stream — either directly as PCM during the session and exported
to AAC at finalize, or written compressed via `AVAssetWriter` in parallel.

The deliverable is a `TalkieRecordingKit` Swift Package plus a minimal iOS test
harness app that exercises the primitive on a physical device. No AI, no TTS,
no Talkie integration in this phase — those layers come after the primitive is
proven.

## Motivation

The recording sidecar today (`OnDeviceAIService.generateRecordingSidecarOutput`,
fired from `RecordingSidecarProcessor.processQueuedRequests`) runs *after* the
recording is finalized and transcribed. The user bookmarks moments during
recording, then waits for transcription to complete before any feedback exists.
The experience: silent during recording, batch-processed after.

We want to move feedback work earlier: when the user taps a bookmark
mid-recording, kick off transcription + AI generation **asynchronously** so the
result is ready (or already spoken) by the time the recording ends. The user
keeps talking; work happens in the background; the result is waiting when they
stop.

Doing that requires being able to extract a useful chunk of audio while the
session is still going. Today we can't — and the obvious-looking solution
(chunking the recorder) is structurally wrong, see below.

## The Recording Problem

`AudioRecorderManager` writes a single `.m4a` file via `AVAudioRecorder`
(`apps/ios/Talkie iOS/Models/AudioRecorderManager.swift:320`) using
`kAudioFormatMPEG4AAC` at 128 kbps. MP4 stores its metadata in a `moov` atom
that includes sample offsets, codec config, and duration. `AVAudioRecorder`
only writes the `moov` atom on `finalizeRecording()` (real stop), not on
`pause()`.

Consequence: an in-progress `.m4a` file on disk has all the audio bytes (in the
`mdat` atom), but no `moov`. Any reader — `AVAudioFile`, Parakeet, ffmpeg —
returns "no decodable streams" and refuses to load the file. So `cp` of the
running file gives us a truncated, unparseable MP4.

This is a hard property of the container format we picked, not an iOS quirk.

## Strategies Considered

| Strategy | Mid-recording readability | Audio loss at bookmark? | Production-fit |
| --- | --- | --- | --- |
| **Pause + copy** (no format change) | No — `pause()` does not flush `moov` | n/a (doesn't work) | ❌ |
| **Finalize-and-restart chunking** (AVAudioRecorder) | Yes — each chunk finalizes to readable `.m4a` | **Yes — at the bookmark moment**, ~100–300 ms of audio is dropped during finalize → new-recorder transition. This deletes the keyword/phrase the user just tapped on. | ❌ Drops audio exactly where it matters |
| **Parallel `AVAudioEngine.installTap` + AVAudioRecorder** | Yes — independent PCM stream in memory | No | ⚠️ Two simultaneous capture clients on the same hardware input is unnecessary, unverified across iOS/route combinations, and harder to debug |
| **Single-pipeline `AVAudioEngine` + PCM ring buffer** ← chosen | Yes — snapshot from in-memory ring buffer | No — capture is uninterrupted | ✅ One capture client, well-understood Apple pattern (Speech framework sample), no gap, no coexistence questions |

### What changed from rev 1

Rev 1 of this doc proposed finalize-and-restart as the production primitive.
Code review feedback ([Review history](#review-history)) pointed out two decisive
issues:

1. **It drops audio at the bookmark moment.** For a feature whose purpose is
   "AI feedback on this moment," dropping ~100 ms of audio at exactly that
   moment is structural defect, not a tunable. The keyword the user tapped on
   may be in the dropped frames.
2. **It can't reuse `AudioRecorderManager.finalizeRecording()`** because that
   method deactivates the audio session (lines 423-426). A split path would
   need a different "finalize chunk without deactivating session" method —
   functional but ugly.

Combined with the over-stated PCM file-size argument (real multiplier is ~2×
not 10× for speech-only 16 kHz mono PCM, not 10× as originally claimed), the
case for finalize-and-restart collapses.

## Chosen Approach: Single-Pipeline AVAudioEngine + PCM Ring Buffer

`AVAudioEngine` becomes the single audio capture client. Apple's
canonical pattern for live audio (see Speech framework's
`recognizing-speech-in-live-audio` sample) installs a tap on
`AVAudioEngine.inputNode` and receives `AVAudioPCMBuffer` callbacks at a
configurable cadence (typically 1024-frame buffers at 16–48 kHz). Each tap
callback delivers a fresh PCM buffer; we own what happens with it.

The data flow:

```
hardware mic
    │
    ▼
AVAudioEngine.inputNode  ──installTap──▶  PCMRingBuffer (last N seconds in RAM)
    │                                            │
    │                                            └──▶ snapshot()  ──▶  temp WAV
    │                                                                       │
    ▼                                                                       ▼
   File writer                                                         Parakeet / AI
   (PCM during session,                                                (async, no gap
    AAC export at finalize)                                             in capture)
```

The ring buffer is the load-bearing primitive. Bookmark = "copy the last N
seconds of samples out of the ring, write to a `.wav` in temp, hand to the
async transcribe + AI pipeline." Capture is never paused.

### Why this over the alternatives

- **vs. finalize-and-restart**: no audio loss at the bookmark moment; no
  audio-session deactivation footgun; one capture client, one set of failure
  modes.
- **vs. parallel tap + AVAudioRecorder**: avoids running two capture pipelines
  against the same hardware input — coexistence is undefined territory across
  iOS versions and audio routes. Single-pipeline removes a whole class of
  bugs.
- **vs. PCM/WAV as the recorder format**: this *is* effectively PCM as the
  intermediate format, but with the long-form file produced via an explicit
  export step (either streaming compression via `AVAssetWriter` or PCM-now /
  AAC-on-finalize). Same storage shape on disk; better instrumentation.

### Trade-offs accepted

- **Replaces `AVAudioRecorder` with `AVAudioEngine` + writer.** `AudioRecorderManager`
  today owns audio session, interruption handling, route changes, background
  task lifecycle, app lifecycle observers, and a Parakeet/CoreData integration
  surface. The single-pipeline replacement has to absorb all of that. It's a
  larger refactor than a chunking layer over the existing recorder.
- **Long-form file format decision deferred.** The spike will test PCM-during-
  session-then-AAC-on-finalize because it's simpler and recoverable. Whether
  production should write AAC live via `AVAssetWriter` instead is a follow-up
  decision; the chunk-snapshot mechanism is independent of that choice.
- **Memory budget.** A 60s PCM ring buffer at 16 kHz mono 16-bit is ~1.9 MB.
  At 44.1 kHz mono 16-bit it's ~5.3 MB. At 48 kHz stereo float32 (worst
  case) it's ~23 MB. Configurable; bounded; not a real constraint on modern
  iPhones.
- **Sample-rate / format negotiation.** The tap delivers buffers in whatever
  format the input node prefers (varies by route — built-in mic, AirPods,
  USB). Ring buffer and writer must handle (or normalize) format changes
  mid-session. This is real complexity that finalize-and-restart sidestepped.

## Module Layout

The strategy lives in a new Swift Package, decoupled from Talkie so the
load-bearing recording code can be exercised, tested, and replaced without
disturbing the live app.

```
apps/ios/TalkieRecordingKit/                  ← Swift Package
  Package.swift
  Sources/TalkieRecordingKit/
    ContinuousRecorder.swift                  ← AVAudioEngine setup, tap, lifecycle
    PCMRingBuffer.swift                       ← thread-safe ring of AVAudioPCMBuffers
    SnapshotExporter.swift                    ← cut N-second slice → temp .wav
    SessionFileWriter.swift                   ← long-form writer (PCM now → AAC on finalize)
    AudioFormatNegotiator.swift               ← canonical format + route-change handling
  Tests/TalkieRecordingKitTests/
    PCMRingBufferTests.swift                  ← capacity, wrap-around, snapshot bounds
    SnapshotExporterTests.swift               ← cut math (sample-accurate, CMTime-based)

apps/ios/TalkieRecordingKit-Harness/          ← Xcode project, runnable iOS app
  TalkieRecordingKitHarness.xcodeproj
  HarnessApp.swift
  RecordingHarnessView.swift                  ← record / bookmark / snapshot list / play / acoustic gap test
```

### Core API (sketch)

```swift
@MainActor
public final class ContinuousRecorder {
    public init(
        sessionDirectory: URL,
        bufferSeconds: TimeInterval = 60,
        outputFormat: OutputFormat = .pcmThenExportAAC
    )

    public func start() throws
    public func snapshot(lastSeconds: TimeInterval) async throws -> RecordingChunk
    public func finalize() async throws -> RecordingSession

    public var route: AVAudioSessionRouteDescription { get }
    public var currentLevel: Float { get }                  // for VU/meter UI
}

public struct RecordingChunk {
    public let url: URL                  // temp .wav
    public let startTime: CMTime         // session-relative
    public let duration: CMTime
    public let sampleCount: Int          // for assertions
}

public struct RecordingSession {
    public let finalAssetURL: URL        // the exported long-form file
    public let totalDuration: CMTime
    public let snapshots: [RecordingChunk]
}
```

Times are `CMTime` end-to-end. No `Double` accumulators (per reviewer guidance:
prevents drift across long sessions).

## Validation Plan

The harness must prove the primitive is fit for the live-sidecar use case
before we build on top of it. Validation has three layers:

### Layer 1 — Correctness claims (must pass)

1. **Mid-session readability of snapshots.** Tap "bookmark" while recording
   → confirm the emitted `.wav` opens via `AVAudioFile` and `AVAudioPlayer`
   plays it end-to-end without truncation.
2. **Sample-accurate snapshot cut.** Snapshot of "last 5 s" must return
   exactly 5 s ± 1 buffer of samples, measured by decoded sample count, not
   wall-clock duration.
3. **No capture interruption.** Continuous tone test: play a 1 kHz tone into
   the mic, record + take snapshots while it plays, decode both the snapshot
   and the long-form file — neither should have gaps, dropouts, or
   discontinuities at snapshot boundaries.
4. **Long-form file integrity.** Final exported file's decoded sample count
   equals (session duration) × (sample rate); no truncation, no padding.
5. **Bookmarked-keyword preservation** (the test the rev-1 plan was missing).
   Speak a known keyword right before tapping bookmark. Run Parakeet on the
   snapshot. Verify the keyword appears in the transcript.

### Layer 2 — Environment matrix (must run on physical device, not simulator)

Simulator audio latency is not representative. Per reviewer: validate on
real hardware across audio routes:

6. **Device matrix:** iPhone 15 / 17 Pro Max with: built-in mic, wired
   headphones with mic, AirPods Pro (Bluetooth HFP), USB-C mic (if
   available). Repeat Layer 1 claims on each.
7. **Route changes mid-session.** Connect/disconnect AirPods during
   recording and during a snapshot — verify sample rate / channel format
   changes don't corrupt the ring buffer or the long-form file.

### Layer 3 — Failure modes (must degrade safely)

8. **Audio interruptions.** Trigger a phone call / Siri / alarm at each
   phase (before snapshot, during snapshot, between snapshots). Verify the
   session resumes cleanly and no chunks are orphaned.
9. **App backgrounding.** App locks / backgrounds mid-recording — capture
   continues if entitled, otherwise pauses and resumes cleanly. No orphan
   ring-buffer state, no leaked tap.
10. **Rapid bookmarks.** Tap "bookmark" 5× in 2 s. Must serialize, debounce,
    or coalesce; no overlapping `snapshot()` operations corrupting the ring.
11. **Disk full mid-finalize.** Fill the simulator/device disk such that
    final export fails partway. Previous snapshots and ring buffer state
    must survive; user-facing error must be recoverable.
12. **Long-session soak.** 30–60 minute recording with periodic snapshots,
    screen locked, low battery. Watch for memory growth, tap latency drift,
    thermal pressure.
13. **Crash recovery.** Kill the app between a snapshot and its async
    consumer (transcribe + AI). On relaunch, the snapshot file is recoverable
    and the long-form recording can still be finalized from on-disk state.

### Validation surface (harness UI)

A single screen with:

- "Record / Stop" toggle button
- "Snapshot (last 5s / 10s / 20s)" buttons — runs `ContinuousRecorder.snapshot`
- Live snapshot list, each showing:
  `snap @ 00:23 · 5.00 s · 240,000 samples · ✓ decodes · gap-since-prev: 0 ms`
- "Play stitched" button — plays each snapshot back-to-back (visual stitching)
- "Play long-form" button — plays the full exported session file
- "Export long-form .m4a" — runs the AAC export step and saves
- "Acoustic gap test" — plays a known tone, records, takes snapshots, decodes
  and compares sample-by-sample for drops (Layer 1 claim 3)
- Live VU meter and route indicator (route changes are silent failures
  otherwise)

## Out of Scope (deliberately)

- Live transcription of snapshots (Parakeet, SpeechRecognizer)
- AI generation on snapshots (`OnDeviceAIService.generateRecordingSidecarOutput`)
- TTS playback of AI responses (`SidecarAnnouncer`)
- Audio session coordination with TTS
- Talkie integration (replacing `AudioRecorderManager`, wiring into
  `RecordingSheetNext` / `RecordingView`)
- Production decision between "PCM during session + AAC export" vs. "AVAssetWriter live AAC"

These all sit on top of a working continuous-capture + ring-buffer + snapshot
primitive. They're deliberately deferred.

## Open Questions

1. **Format negotiation across routes.** When AirPods connect mid-session,
   the input node's preferred format may shift (e.g., 16 kHz mono Bluetooth
   HFP). What does the ring buffer do? Options: normalize to a canonical
   format on ingest (cheap if the sample rates align, AVAudioConverter
   otherwise), or store the raw buffers with format-change markers and
   normalize on snapshot. The simpler answer (canonical format) likely wins
   but needs measurement.
2. **AVAssetWriter for live AAC vs. PCM-then-export.** PCM-then-export is
   simpler, recoverable, and lets us defer the format question. Live AAC via
   AVAssetWriter cuts disk I/O and avoids the export step but adds encoder
   complexity. Decide after the spike, when we have real numbers.
3. **Background entitlement.** Continuous capture in background requires
   the audio background mode. Talkie already has this for `AudioRecorderManager`;
   the new primitive needs the same treatment.
4. **Compatibility with Talkie's existing audio session config.** The new
   primitive must use the same session category options as `AudioRecorderManager`
   (`.allowBluetoothHFP, .allowBluetoothA2DP` per line 69) and respect the
   same interruption/route observers. Migration plan, not a primitive concern,
   but needs alignment.

## Next Steps

1. Scaffold `TalkieRecordingKit` package skeleton (Package.swift, empty
   modules).
2. Implement `PCMRingBuffer` first — pure-Swift, no audio dependencies,
   fully unit-testable.
3. Implement `ContinuousRecorder` with the `AVAudioEngine` tap.
4. Implement `SnapshotExporter` and `SessionFileWriter`.
5. Scaffold the harness Xcode project + minimal UI.
6. Run Layer 1 + Layer 2 + Layer 3 validation **on a physical iPhone**, not
   the simulator. Record numbers, fail loudly if any claim doesn't hold.
7. Document results in a follow-up section here. Then either: (a) start the
   layer-2 work (live transcription + AI + TTS), or (b) revise this approach
   if validation surfaces failures the design doesn't account for.

## Review history

### Rev 1 (2026-05-31, morning)

Proposed **finalize-and-restart chunked recording** as the production
primitive. Validation plan covered mid-session readability, gap budget,
stitching, and audio quality.

### Rev 2 (2026-05-31, after codex review)

A fresh codex sibling (`@tlk025-reviewer`) was asked for critical engineering
review. Decisive findings:

- Finalize-and-restart drops audio **at the bookmark moment** — structurally
  wrong for a feature about "AI feedback on this moment." The keyword the
  user tapped on may be in the dropped frames.
- The doc's `pause + copy` and `finalize + reuse AudioRecorderManager`
  paths reuse code that deactivates the audio session — would need a
  separate "split" method.
- The PCM file-size argument was off. Real numbers: AAC at 128 kbps is
  ~0.96 MB/min, 44.1 kHz mono 16-bit PCM is ~5.3 MB/min (~5.5× not 10×),
  and 16 kHz mono PCM is ~1.9 MB/min (~2× current AAC). PCM is much more
  defensible than rev 1 claimed.
- The proposed gap metric ("stop returned → record returned") is wall-clock,
  not acoustic-gap. Real measurement needs a tone/metronome and decoded-
  sample inspection.
- Simulator audio latency is not meaningful for this. Validation must use
  physical devices.
- Apple's canonical pattern for this class of feature is
  `AVAudioEngine.inputNode.installTap` (Speech framework sample). The
  primitive should *replace* `AVAudioRecorder`, not coexist with it.
- 13 validation additions, including the critical missing one: speak a
  known keyword before bookmarking, verify it survives in the snapshot
  transcript.

Rev 2 adopts the single-pipeline `AVAudioEngine` + PCM ring buffer approach
and folds in all 13 validation additions. Finalize-and-restart is no longer
in scope.
