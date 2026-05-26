# TLK-022 — Media Augmentation Pipeline

**Status**: Draft (Phases 1–4 landed · OCR + window-meta augmenters live · catch-up sweep running on launch)
**Owner**: Talkie macOS
**Related**: [TLK-017](tlk-017-media-capture-quality.md) (capture quality), [TLK-018](tlk-018-media-surface-roundup.md) (media surface unification), [TLK-021](tlk-021-capture-markup.md) (markup canvas — user-state sidecars)

## Summary

Background pipeline that runs derived analyses on captured assets (screenshots and audio) and persists results as **TK sidecars** — per-asset JSON files in a hidden `.tk/` subdirectory next to each primary asset. The pipeline is deliberately fire-and-forget so the critical capture and transcription paths stay fast.

Talkie has accumulated several "we'd like richer derived data" needs — OCR on screenshots, AX trees at capture time, voice-activity detection on audio, semantic-search embeddings, opportunistic re-transcriptions at higher quality — without a consistent place to put them. The result has been ad-hoc: a few text fields on the tray manifest (`ocrText`), heavyweight DB columns where they don't belong, or synchronous work on the critical path. This spec defines one home for all of it.

## The two protected paths

Two interaction paths are user-blocking and **must never be slowed by augmentation**:

1. **Screenshot → drag-handle ready.** When the user presses Hyper+S, the captured PNG must land in the tray and become draggable as fast as possible.
2. **Screenshot → insertion into a transcription.** When a dictation finishes and trailing tray screenshots get drained into the recording record, the attach step must not wait for OCR or AX analysis.

These two paths are the contract. Everything in this pipeline runs **after** they've done their work.

## Three-tier file layout

Consistent across both asset types:

| Tier | Where | Visible? | Owned by |
| --- | --- | --- | --- |
| Primary asset | `Audio/<UUID>.wav` · `Screenshots/<name>.png` | yes | User |
| User-state sidecar | `Screenshots/<name>.markup.json` (annotations, TLK-021) · future `Audio/<UUID>.json` for transcripts if/when file-based | yes (sibling) | User-created content |
| TK sidecar | `<asset-dir>/.tk/<basename>.json` | **no** (`.` prefix) | Background workers |

The TK sidecar is hidden because it's reproducible — if it's deleted, the catch-up sweep regenerates it. Users browsing `Screenshots/` to find a raw PNG should not see paired `.json` clutter.

`<filename>.markup.json` (user annotations from the markup tool) stays **visible** next to the PNG because it's user-meaningful content: if you export or share the screenshot, you probably want to bring the annotations along.

### Path resolution

```swift
extension URL {
    func tkSidecarURL() -> URL {
        deletingLastPathComponent()
            .appendingPathComponent(".tk", isDirectory: true)
            .appendingPathComponent(deletingPathExtension().lastPathComponent + ".json")
    }
}
```

Given any primary asset URL, this produces its sidecar path. Given a sidecar, the primary is `<parent>/../<basename>.<ext>`.

## Architecture

Three components in TalkieKit (`Sources/TalkieKit/MediaAugmentation/`):

| File | Role |
| --- | --- |
| `TKSidecar.swift` | Sidecar shape (Codable), augmenter-kind enum, JSON-AST round-trip helper for payload data |
| `TKSidecarStore.swift` | Disk read / write / delete · atomic writes · URL helpers |
| `MediaAugmentationService.swift` | Actor-isolated singleton · serial drain at `.utility` priority · `register(_:)` + nonisolated `enqueue(_:)` |

### Flow

```
[capture site]                    [pipeline]                       [disk]

ScreenshotTray.add ─────► enqueue(AugmentationTask) ─────► <dir>/.tk/<name>.json
   (returns immediately)         │
                                 ▼
                          serial queue, .utility
                                 │
                                 ▼
                  for each registered Augmenter:
                    if supports asset.kind:
                      try run(task)
                      → TKAugmentation
                      → upsert into sidecar
                      → write atomic
```

`enqueue(_:)` is `nonisolated` — safe to call from any actor / context, returns immediately. The caller does not `await`, does not receive a result, does not know if it succeeded. This is the whole point.

### Serial, not parallel

A burst of captures (user presses Hyper+S three times in 200ms) **must not** fan out into three parallel CPU-heavy OCR runs. The service holds a `pending` queue and a `draining` flag — one task at a time, in order. Augmenter implementations can use `async let` internally to run independent sub-analyses in parallel within a single task, but the service itself serializes.

### Failure tolerance

Augmenter throws → log and move on. Other augmenters in the same task still run. The sidecar gets only the augmentations that succeeded; absent kinds are graceful for all consumers.

Critically: a failure of one augmenter does NOT prevent the sidecar from being written. The pipeline writes whatever subset succeeded. The empty case ("sidecar exists with zero augmentations") is legal.

### Idempotent re-enqueue

Before invoking each augmenter, `runTask` reads the existing sidecar and skips any augmenter whose `(kind, version)` pair is already present. This makes:

- Catch-up sweep cheap — assets already at current versions skip work
- Accidental double-`enqueue` from a buggy call site no-op
- Forcing a re-run of an augmenter just a `version` bump away

To re-run an augmenter against existing data with new logic, bump its `version` string. The catch-up sweep will pick up the gap on next launch.

## Sidecar envelope

```json
{
  "schema": 1,
  "asset": {
    "kind": "image",
    "filename": "Talkie Capture - 2026-05-25 14.43.39 - Region - 1186x761 - cab17841.png"
  },
  "augmentations": [
    {
      "kind": "ocr",
      "version": "vision-v1",
      "ranAt": "2026-05-25T21:43:42Z",
      "data": { "observations": [...] }
    },
    {
      "kind": "ax-tree",
      "version": "macos-v1",
      "ranAt": "2026-05-25T21:43:41Z",
      "data": { "root": {...} }
    }
  ]
}
```

Two levels of versioning:

- **Envelope schema** (`TKSidecar.schema`) — bump when the outer shape changes.
- **Per-augmenter version** (`TKAugmentation.version`) — bump when an augmenter ships a better model or changes its payload schema. The catch-up sweep can then ask "do I have OCR at version `vision-v2`?" and re-run only what's stale.

Payload data is a JSON value — encoded via `TKAugmentationData` which round-trips arbitrary JSON through a `JSONValue` AST. This way each augmenter owns its own typed model file without forcing every augmenter through a single generic schema.

### Defined augmenter kinds

| `kind` | Asset | Payload (sketch) |
| --- | --- | --- |
| `ocr` | image | `[{ text, bounds, confidence }]` |
| `ax-tree` | image | `{ role, label, frame, identifier, children[...] }` recursive |
| `window-meta` | image | `{ title, bundleID, screenFrame, backingScale }` |
| `vad` | audio | `[{ start, end }]` (seconds) |
| `transcript` | audio | `{ text, segments[...], words[...] }` — opportunistic re-transcription |
| `diarization` | audio | `[{ speaker, start, end }]` |
| `embedding` | both | `{ model, vector[...] }` |

New kinds add an enum case; older readers see an unknown raw value and skip it (Codable behavior).

## Naming — why `.tk/`

This was bikeshedded. Settling here so the next change doesn't relitigate it:

- `.capture/` — screenshot-flavored, weird for audio
- `.augment/` — verb-flavored; some contents (e.g. a transcript) are the core product, not an augmentation
- `.derived/` — accurate but clinical
- `.tk/` — terse, Talkie-branded, noun-flavored, neutral about importance · **chosen**

Code-side naming:

- File: `<asset-dir>/.tk/<basename>.json`
- Type: `TKSidecar`
- Store: `TKSidecarStore`
- Service: `MediaAugmentationService` — keeps the verb where it belongs (the *process* is augmentation; the *outputs* are TK sidecars)
- Producer protocol: `Augmenter`

## Wiring

### Save sites (must call `enqueue` after user-blocking work):

| Site | Status |
| --- | --- |
| `ScreenshotTray.addReturningItem` (capture → tray) | **wired** |
| `ScreenshotTray.drainToRecording` (tray → transcription attachment) | **wired** |
| `ScreenshotTray.drainToCapture` (tray → standalone capture record) | **wired** |
| `MemoRecordingController.saveAudioFile` (audio finish) | **wired** (audio augmenters pending) |
| `AudioDropService.importAudioFile` (audio drag-drop import) | **wired** (audio augmenters pending) |

Every site does the same thing:

```swift
MediaAugmentationService.shared.enqueue(
    AugmentationTask(
        assetURL: fileURL,
        assetKind: .image,   // or .audio
        context: TKAugmentationContext([...])
    )
)
```

`context` is a string→string bag for hints the augmenter might want (window title, app bundle, capture mode, screen backing scale, recording ID). Augmenters read what they need and ignore the rest. Missing keys mean "fall back to discovery."

### Delete sites (must call `TKSidecarStore.delete`):

| Site | Status |
| --- | --- |
| `ScreenshotTray.remove` | **wired** |
| `ScreenshotTray.cleanBufferFiles` (covers `.clear` and drain cleanup) | **wired** |
| `TalkieObjectRepository.hardDeleteRecording` (audio + screenshots) | TODO |
| `AudioStorage.delete` (audio file removal) | TODO |

Sidecar cleanup is best-effort (`try?`) — orphan `.tk/` files don't break anything, and the catch-up sweep tolerates absence on both sides.

### Augmenter registration

Registration happens in `AppDelegate.setupMediaAugmentation()` at the end of `applicationDidFinishLaunching`. A single `Task` awaits registration of all augmenters, then kicks the catch-up sweep at `.background` priority:

```swift
private func setupMediaAugmentation() {
    Task {
        await MediaAugmentationService.shared.register(OCRAugmenter())
        await MediaAugmentationService.shared.register(WindowMetaAugmenter())
        Task.detached(priority: .background) { @MainActor in
            Self.runMediaAugmentationCatchUpSweep()
        }
    }
}
```

Each augmenter declares:

```swift
public protocol Augmenter: Sendable {
    var kind: TKAugmenterKind { get }
    var version: String { get }
    var supportedAssetKinds: Set<TKSidecarAssetKind> { get }
    func run(_ task: AugmentationTask) async throws -> TKAugmentation?
}
```

The service filters by `supportedAssetKinds` before invoking — `OCRAugmenter` never sees audio tasks.

Augmenter implementations belong in `apps/macos/Talkie/Services/Augmenters/` because most need AppKit / Vision / Accessibility APIs out of scope for the shared kit. **Temporary location note:** until the Talkie xcodeproj is converted to use file-system-synchronized groups, `OCRAugmenter` and `WindowMetaAugmenter` live as types at the bottom of `Services/Screenshots/VisionOCRService.swift` (the OCR augmenter naturally pairs with the service it wraps; the window-meta one is co-located for transport). Split them out into `Services/Augmenters/*.swift` when adding new file refs becomes ergonomic.

## Catch-up sweep

`AppDelegate.runMediaAugmentationCatchUpSweep()` runs on app launch at `.background` priority. It enumerates:

- `~/Library/Application Support/Talkie/Audio/` — `.wav`/`.m4a`/`.mp3`/`.aiff`/`.caf` → enqueue as `.audio`
- `~/Library/Application Support/Talkie/Screenshots/` — `.png` → enqueue as `.image`
- `~/Library/Application Support/Talkie/Tray/screenshots/` — `.png` → enqueue as `.image`

For each primary asset it enqueues an `AugmentationTask` with an empty context. The service's `runTask` then skips any `(kind, version)` pair already present in the sidecar (see Idempotent re-enqueue above), so already-augmented assets at current versions are nearly-free no-ops.

This solves several problems at once:

- Captures taken before the feature shipped get backfilled gradually.
- Crashes mid-augmentation leave the sidecar partial; sweep finishes the job on next launch.
- A new augmenter kind landing in a future build automatically catches up across the user's history without a migration script.
- Versioned augmenters can ship upgrades: bump the version, sweep re-runs everything still at the old version.

**Verified behavior** (initial launch with the screenshot OCR augmenter registered): the sweep processed ~282 historical screenshots at roughly 6/s, writing 60 sidecars in the first 10 seconds. Each sidecar contains the OCR observations, line clustering, and token anchors — ready for downstream consumers without further work.

**Known limitation:** the sweep enqueues with an empty `TKAugmentationContext`, so `WindowMetaAugmenter` returns nil for catch-up runs (it has no context source data to record). New captures going forward get a fully-populated context from the save site and produce `window-meta` entries. Backfilling window context for historical assets isn't possible without the original capture-time data.

## DB index (planned)

The sidecar JSON is canonical for the rich data. But the DB needs the queryable bits — full-text OCR, window title, app bundle — for fast filtering without parsing every sidecar at query time.

Plan: add `RecordingScreenshot` columns (or a side table) for the small, queryable, eventually-consistent subset:

```
ocr_text_short      TEXT     (~first 2KB of OCR text, for FTS)
window_title        TEXT
window_bundle_id    TEXT
augment_ran_at      TIMESTAMP
```

Augmenter `run` writes both — file sidecar (full) + DB columns (subset). Columns are nullable; queries degrade to "match by filename" when null.

This is a deliberate two-track persistence:

- **Sidecar = canonical, rich, file-portable**
- **DB columns = index, lossy, query-fast**

## Consumers

Once augmenters land, several things become much easier:

### Studio parity tool (`/mac-capture-markup-compare`, `/mac-home-compare`)

The compare page can read a screenshot's AX-tree sidecar to know exactly where named elements are in pixel space, then overlay the studio render anchored to those positions instead of guessing. Today the comparison anchors at `top-left` or `bottom-left` heuristically; AX metadata makes it deterministic.

### Markup agent (`CaptureMarkupCoordinator`)

The agent currently reasons about "circle the RUN button" by sending the whole image to an LLM and hoping it can localize. With AX sidecar data the localization is exact — the agent gets `{ role: "AXButton", label: "RUN", frame: [...] }` as ground truth.

### Search across captures

OCR text indexed in the DB means "show me captures from yesterday that mention 'Parakeet'" becomes a trivial query. The OCR sidecar is the index, the DB column is the lookup.

### Smarter dictation insights

VAD + diarization sidecars feed into recording analytics ("you talked 73% of the time", "two speakers detected") without putting per-frame data in the DB.

## Current state

What's in the tree as of this writing:

- ✅ TalkieKit types (`TKSidecar.swift`, `TKSidecarStore.swift`, `MediaAugmentationService.swift`)
- ✅ Save hooks: `ScreenshotTray.addReturningItem`, `drainToRecording`, `drainToCapture`, `MemoRecordingController.saveAudioFile`, `AudioDropService.importAudioFile`
- ✅ Delete hooks: `ScreenshotTray.remove`, `cleanBufferFiles`
- ✅ `OCRAugmenter` (wraps `VisionOCRService.recognizeTextWithGeometry`, full observations + line clustering + token anchors)
- ✅ `WindowMetaAugmenter` (records window title / app / display / capture mode / dimensions from save-site context)
- ✅ Augmenter registration in `AppDelegate.setupMediaAugmentation`
- ✅ Catch-up sweep on launch (`runMediaAugmentationCatchUpSweep`)
- ✅ Idempotent re-enqueue (service skips `(kind, version)` pairs already in sidecar)
- ⏳ Audio augmenters (VAD, transcript-upgrade, diarization, embedding)
- ⏳ Image AX-tree augmenter (design pending — captured AX context vs deferred query)
- ⏳ DB index columns
- ⏳ Markup-agent + studio-compare-page consumer wiring

The OCR augmenter shipped end-to-end; sidecars verified in `~/Library/Application Support/Talkie/Screenshots/.tk/`. The audio path is wired but produces empty sidecars today — adding an audio augmenter (e.g. VAD) is the next unit of work and changes no other code.

## Phases

- **Phase 1** ✅ Scaffolding: types, store, service, first save+delete hook.
- **Phase 2** ✅ First augmenter: OCR with geometry via `VisionOCRService`. Validates the schema end-to-end against real data.
- **Phase 3** ✅ Remaining save hooks (tray-drain ×2, audio finish, audio import), window-meta augmenter, idempotent re-enqueue.
- **Phase 4** ✅ Catch-up sweep at launch, registration in `AppDelegate`.
- **Phase 5** — AX-tree augmenter for images. Requires deciding between (a) snapshotting the AX tree at capture time and serializing into `TKAugmentationContext`, or (b) deferred AX query (which will return stale data if the window changed). Probably (a).
- **Phase 6** — Audio augmenters: VAD (cheap, useful), opportunistic re-transcription at higher quality, embeddings for semantic search, diarization.
- **Phase 7** — DB index columns mirroring queryable sidecar bits (full-text OCR, window title, app bundle, augment-ran-at). Search filters land on these without parsing every JSON.
- **Phase 8** — Consumer wiring: markup agent uses AX-tree sidecar for localization; studio compare pages snap to AX-named regions instead of visual-anchor heuristics.
- **Cleanup** — Remove the existing `ocrText` field on `TrayScreenshot` once consumers migrate to reading from sidecars + DB index.

## File index

```
apps/macos/TalkieKit/Sources/TalkieKit/MediaAugmentation/
  TKSidecar.swift                    — types, augmenter-kind enum, JSON AST
  TKSidecarStore.swift               — URL helpers, atomic disk I/O
  MediaAugmentationService.swift     — actor singleton, serial drain

apps/macos/Talkie/Services/Screenshots/
  VisionOCRService.swift             — OCR service + (temporary co-location)
                                       OCRAugmenter + WindowMetaAugmenter

apps/macos/Talkie/Services/Tray/Data/
  ScreenshotTray.swift               — enqueue at add + drainToRecording +
                                       drainToCapture; delete at remove +
                                       cleanBufferFiles

apps/macos/Talkie/Services/
  MemoRecordingController.swift      — enqueue at saveAudioFile
  AudioDropService.swift             — enqueue at importAudioFile

apps/macos/Talkie/App/
  AppDelegate.swift                  — register augmenters + run catch-up sweep
```

Future structure (once new file refs can be added to the xcodeproj ergonomically):

```
apps/macos/Talkie/Services/Augmenters/
  OCRAugmenter.swift                 — split from VisionOCRService.swift
  WindowMetaAugmenter.swift          — split from VisionOCRService.swift
  AXTreeAugmenter.swift              — Phase 5
  VADAugmenter.swift                 — Phase 6
  TranscriptAugmenter.swift          — Phase 6
```

## Open questions

1. **Sidecar hashing.** `TKSidecarAsset.sha256` is currently optional and unused. For sidecars to survive a primary-asset rename or move, we need either a stable identifier (capture UUID embedded in filename) or a content hash. Hashing large audio files is expensive; defer the decision.
2. **Sidecar export format.** When the user exports a capture for sharing, should the TK sidecar travel along? Currently they're hidden, so users won't even know they exist. For now: no — TK is internal. Revisit if external tools want to consume them.
3. **Sidecar size limits.** A long dictation's word-level transcript could be hundreds of KB. AX trees of complex windows could be similar. Soft-cap per kind? Compress on disk? Or accept that augmentation files for big assets are big.
4. **Cross-device sync.** Sidecars live on disk in Application Support. Should iCloud sync carry them? The capture-attached-to-recording case lives in the DB and syncs via CloudKit today; tray-only captures don't sync at all. Leave sidecars local for now; revisit when cross-device augmentation reuse becomes a need.

## Related work

- `LiveSidecar.swift` — pre-existing sidecar pattern in TalkieKit (per-recording metadata for the live transcription flow). Conceptually related but a different file format and lifecycle.
- [TLK-017](tlk-017-media-capture-quality.md) — capture-quality validation. The augmentation pipeline depends on the captures being well-formed; quality regressions there cascade here.
- [TLK-018](tlk-018-media-surface-roundup.md) — media-surface unification. Augmentation sidecars become a natural anchor for that unification ("show me captures with OCR matching X").
- [TLK-021](tlk-021-capture-markup.md) — markup canvas. `<name>.markup.json` is the user-state sidecar (Tier 2); TK sidecars are Tier 3. Both live in the same parent directory but serve different roles.
