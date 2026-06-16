# Recording Button — Waveform Polish & Preparing State

**Date**: 2026-06-16
**Scope**: UI polish only. No memo recording safety / storage / transcription
logic touched (TLK-032 active diff respected).

## Goal

The waveform inside the recording button read as bland — a flat, even row of
bars that barely moved. Make it feel alive, intentional, and premium while
staying restrained enough for app chrome and fully deterministic/lightweight.
Also surface an immediate **preparing** state so the button does something the
instant the user clicks, before audio capture is actually live.

## What changed

### 1. `LiveWaveformBars` — richer, deterministic motion
`apps/macos/Talkie/Views/MacRecordingView.swift`

- Replaced the two-state `isRecording: Bool` with a three-state `Activity`
  enum — `.idle`, `.preparing`, `.recording`. A back-compat
  `init(audioLevel:isRecording:color:)` is kept so existing callers stay valid.
- **Center-weighted spatial shape**: bars now follow a `sin(π·position)`
  envelope — fuller in the middle, tapering at the ends — so the strip reads as
  one intentional waveform instead of a uniform block.
- **Deterministic traveling ripple**: two sines at different speeds and
  wavelengths beat against each other, driven by the `TimelineView` clock
  (`timeline.date`), not a timer or RNG. This gives organic shimmer that's alive
  even in silence, and resolves identically every frame.
- **Recording**: real audio history still scrolls in from the right and leads;
  a faint ambient ripple fills quiet moments so the strip never flatlines.
- **Preparing**: the ripple is squared into a soft moving crest — an
  anticipatory "warming up" sweep at low amplitude. Deliberately *not* the red
  REC cue, so it never reads as active capture.
- **Idle**: a low, calm drift — alive but clearly at rest.
- Per-bar opacity tracks level so quiet bars fade rather than going opaque-flat.

### 2. Chrome pill — immediate `preparing` feedback (main button)
`apps/macos/Talkie/Components/TalkieChromeBar.swift`

- Threaded `isPreparing` (`controller.state.isPreparing`) into `TalkieChromePill`.
- New transient branch between idle and recording: amber **STARTING** label +
  the `.preparing` waveform sweep in the accent color. The amber Talkie mark now
  also lights during preparing.
- Honest semantics: no REC text, no red, no timer — the recorder is not claiming
  to capture yet. Help text + accessibility label become "Preparing to record…".
- Added a spring animation on `isPreparing` so idle → preparing → recording
  cross-fades smoothly.

### 3. Modal & overlay surfaces — consistent state mapping
`apps/macos/Talkie/Views/MacRecordingView.swift` (`waveformContent`)
`apps/macos/Talkie/Views/RecordingOverlay.swift` (`waveformView`)

- Map controller state → `Activity`: recording → red, preparing → accent
  ("warming up"), idle → muted. Both surfaces now animate during preparing too.

## Why the preparing state was easy & safe

The TLK-032 safety diff already added `RecordingState.preparing` and
`startRecording()` already sets `state = .preparing` immediately before mic/engine
spin-up. So this was pure UI/state *wiring* — surfacing an existing honest state.
No new timing, no change to when capture actually goes live, and failures still
fall through to `.error` exactly as before.

## Performance / determinism

- One `Canvas` per strip (no per-bar views), ~30fps via
  `TimelineView(.animation(minimumInterval: 0.033))` — the pattern already used.
- Motion derives from the animation clock + a smoothed envelope follower. No new
  timers, no `Math.random`, no extra layout churn. Same redraw cadence as before.

## Acceptance criteria

1. **Idle / recording / (preparing) semantics clear** — idle = TALKIE, preparing
   = amber STARTING + sweep, recording = red REC + timer + live waveform. Distinct
   color and label per state. (Model uses `.processing` post-stop, unchanged.)
2. **Richer motion/shape** — center-weighted shape + dual-sine traveling ripple,
   no longer a static even row; still subtle for chrome.
3. **Deterministic & lightweight** — clock-driven, single Canvas, no heavy timers.
4. **Build** — `talkie-dev build talkie` → success (~180s). No new warnings from
   these files. (Pre-existing, untouched: `AppNavigation.swift:1272` deprecated
   `navigateLive`; `MacRecordingView.swift:363` unused `memo` in `.complete`.)

## Candidates considered, NOT touched

- **`InkFlourishShape`** (`RecordingCompanionSurface.swift`) — the large
  full-screen / PiP flowing-ink canvas. Already polished (60fps phase-based
  multi-frequency wave). Out of scope; it's the macro recording canvas, not the
  button.
- **`WaveformBarsView`** (`TalkieAgent/.../Overlay/RecordingOverlay.swift`) — the
  separate TalkieAgent overlay indicator, not the main Talkie memo flow.

## Verify live

Build only was run (to avoid interrupting any in-progress TLK-032 recording
test). To see it: `talkie-dev build talkie --restart`.
