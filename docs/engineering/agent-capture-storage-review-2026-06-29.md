# Review — Agent capture storage cleanup & video capture resilience

**Date:** 2026-06-29
**Reviewer:** Claude (Scout consult, review-only — no files edited)
**Base:** committed `b924618` + uncommitted cleanup on `codex/agent-quick-capture-markup`
**Scope:** the 9 cleanup files + directly related call paths
(`ScreenRecordingService.swift`, `CaptureMediaFileResolver.swift`, `MemoRecordingController.swift`)

---

## 1. First-principles model: tray vs durable captures

The correct model — and the one this change implements — is a **single canonical
store with a thin reference layer**:

- **Canonical durable media** = the file written once into Talkie's shared
  Library storage (`…/Talkie/Screenshots`, `…/Talkie/Videos`) plus a
  `TalkieObject` row in the unified DB. This is the source of truth and the only
  copy of the bytes.
- **Live tray** = an *index of recent references*. A tray row points at a
  canonical file (`filePath` + `ownsFile=false`); it owns the manifest row, not
  the bytes. Quick preview / drag-copy / "recent grabs" read through the
  reference; **drag-copy is non-destructive** (copies out of canonical).
- **Ownership is explicit and one-directional.** Deleting/dismissing/draining a
  *reference* row must never touch canonical bytes. Only rows the tray actually
  owns (`ownsFile=true`, i.e. legacy pre-change manifests) may delete their file.
- **Derived bundles reference, never re-copy.** A visual-context bundle for an
  Agent clip stores frames/contact-sheet/manifest but points its `source` at the
  canonical video instead of duplicating it.

The implementation matches this model. `ownsFile` defaults to `true` on decode
so legacy manifests keep self-owning behavior; new reference rows are `false`.

---

## 2. Does it satisfy one-write storage for new Agent captures? — YES

**Screenshot** (`AppDelegate.swift:1778-1818`):
1. `AgentCaptureLibraryWriter.persistScreenshot` → `ScreenshotStorage.save(data,…)`
   writes the file **once** + creates the `TalkieObject`.
2. `AgentLiveTrayAssetStore.registerScreenshot(fileURL:…)` adds a reference row
   (`ownsFile=false`) — **no second write**.

**Video** (`ScreenRecordingController.persistFinishedClip`):
1. `persistClip` → `VideoClipStorage.save(sourceURL, moveSource: true)` **moves**
   the temp to `Videos/` (one operation, no copy; same-path short-circuit at
   `VideoClipStorage.swift:57`).
2. `VisualContextStorage.createBundle(copiesSourceClip: false)` — bundle dir +
   manifest/summary written, **source clip NOT copied** (`RecordingVisualContext.swift:389`).
3. `registerClip(fileURL:…)` adds a reference row — **no write**.

Net: screenshot = 1 write; video = 1 move + 0 copies. The old double-write
(tray copy → Library copy, plus visual-context source copy) is gone. Verified no
remaining production callers of the file-owning `storeScreenshot`/`storeClip`.

---

## 3. Findings by severity

### HIGH

**H1 — Cross-object file aliasing: deleting the original capture orphans a drained dictation's media.**
A capture creates a canonical `TalkieObject` (id = `captureID`) whose clip file is
named from `captureID`. Draining the tray reference into a dictation does **not**
copy — `savedURL = item.fileURL` (the canonical file) for `!ownsFile`
(`AgentLiveTrayAssetStore.swift:790-792` screenshots, `:846-848` clips). So the
standalone capture object **and** the dictation now share **one** physical file.
`MemoRecordingController` deletes media by id via `ScreenshotStorage.delete(for:)`
/ `VideoClipStorage.delete(for:)` (`MemoRecordingController.swift:505-506,829-830`),
which removes files by filename prefix. Deleting the **original capture**
(`captureID`) removes the file the dictation still references → dictation media
orphaned. (Deleting the *dictation* is safe — its clip filename encodes
`captureID`, not the dictation id, so the prefix match misses. The risk is
**asymmetric**.)
*Evidence:* the file-owning copy on promote was removed; `persistClip` keys the
canonical object on `captureID`; deletion is filename/recordingId-prefix based.
*Recommend:* a product decision. Either (a) copy on promote for reference items
(sacrifices one-write only at drain, acceptable), (b) reference-count / scan for
other referrers before physical delete, or (c) document the shared-media
semantics and gate Library deletion accordingly. The two existing unit tests
cover tray-delete/drain but **not** subsequent Library-object deletion.

### MEDIUM

**M2 — Single persist path with no fallback surface; failures lose the capture silently.**
Because video now *moves* the temp and there's one persist path, if
`VideoClipStorage.save` (move) or the DB write fails, `persistClip` returns nil;
the controller logs `"Screen recording Library write failed"` and returns. There
is **no tray fallback** (old flow wrote the tray first) and **no error toast /
temp-path log** on the normal stop path, so a just-recorded clip can vanish with
only an orphaned temp file left behind.
*Recommend:* on persist failure, log the temp URL and/or show an error toast so
the recording is recoverable.

**H2/M3 — Interrupted-recording toast reports success regardless of outcome.**
`handleServiceInterruption` salvaged branch does `await persistFinishedClip(...)`
then **unconditionally** `showInterruptionToast(salvaged: true, …)` and logs
`"partial clip saved"`. `persistFinishedClip` returns `Void` and silently
returns early when persist fails. So the user can see *"macOS interrupted capture
— partial clip saved (Ns)"* when nothing was actually saved.
*Recommend:* `persistFinishedClip` should return `Bool`; the toast/log should
reflect the real result.

**M1 — Window-health monitor can falsely kill a valid recording.**
`isCaptureTargetStillValid` (window case) uses
`SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`
and treats absence from the on-screen list as invalid. Minimizing the recorded
window, moving it fully off-screen, or full occlusion can drop it from that list,
so the 2-second poll calls `stopRecording()` and ends an otherwise-capturable
recording.
*Recommend:* use `onScreenWindowsOnly: false` for liveness, require N
consecutive misses, or distinguish "closed" from "off-screen/minimized."

### LOW

- **L1 — Dead code / footgun.** `storeScreenshot`/`storeClip` (the file-owning
  write paths, ~130 lines) have **zero** production callers now. Leaving them
  invites reintroducing the double-write. Remove or mark deprecated.
- **L2 — `lastCaptureContext` not cleared on salvaged interruption.** The
  success path of `finalizeAfterInterruption` doesn't call `teardown()`, and
  `finishWriting()` doesn't null `lastCaptureContext` (only `teardown` does).
  Diagnostics-only; overwritten on next start.
- **L3 — Health monitor only guards `.window` targets.** Fullscreen/region
  display-disconnect mid-recording relies solely on the SCStream-error salvage
  path. Acceptable, but asymmetric — note it.
- **L4 — Region validation coordinate space.** `displayFrame(match).intersects(rect)`
  assumes `rect` and `displayFrame(match)` share a coordinate space; verify
  global-vs-display-local.

### Correctly handled (positives)

- **One-write verified** for both paths (see §2).
- **Tray delete & drain preserve canonical media** — `Manifest.removeFiles`
  guards `ownsFile` (`AgentLiveTrayAssetStore.swift:1165`); `deleteItem` guards
  the sidecar delete (`:751-753`). Covered by `AgentLiveTrayAssetStoreTests`
  (both reference-screenshot-delete and reference-clip-drain).
- **Backward compatible.** Old manifests decode `ownsFile=true` and `filePath=nil`
  → legacy directory-relative resolution preserved (`:1137-1145`).
- **Visual-context source lookup is robust.** `CaptureMediaFileResolver.visualContextSourceURL`
  searches bundle → Videos → tray → app-support; both `ScreenshotInserter` and
  `VisualContextFrameProcessor` migrated, with graceful `"Source clip missing"`.
- **Frame processor only reads the source**; it deletes only the contact sheet
  and `frame*` working files — **no risk of deleting the canonical video.**
- **Reentrancy is guarded** at three layers: `controller.stopRecording`
  (`isStoppingRecording`), `handleServiceInterruption` guard, and service
  `finalizeAfterInterruption` bailing when `stopContinuation != nil`. Max-duration
  valve and window-health stop both route through the guarded controller stop, so
  no double-persist.

---

## 4. Stress checks to prove video resilience

1. **Close the recorded window mid-recording** → graceful stop; one clip saved;
   toast "partial clip saved"; Library object + tray reference present; file in
   `Videos/`.
2. **Minimize (don't close) the recorded window** → expected: keep recording.
   *Currently at risk of false-stop (M1).*
3. **Revoke Screen-Recording TCC / sleep-wake / fullscreen display disconnect** →
   SCStream error → salvage path; verify a single clip, no orphan temp, and
   `ScreenRecordingService.state` returns to `.idle` so the next recording starts
   clean.
4. **Hit the 5-minute max-duration valve** → single clip, no double-persist.
5. **Race: press stop exactly as SCStream errors** → exactly one clip; no
   duplicate Library object / tray row. (Guards exist — prove empirically.)
6. **Make `Videos/` read-only or fill the disk so the move fails** → expect an
   honest failure toast + recoverable temp. *Currently missing on normal stop;
   false-success on interrupted (M2/H2).*
7. **Cross-volume temp → `Videos/` move** (`moveItem` across volumes) → verify
   clip integrity.
8. **Drain a reference clip into a dictation, then delete the original capture in
   Talkie main** → verify the dictation's media survives. *Currently at risk (H1).*
9. **Capture→register ×100** → exactly one file per capture (no dupes); tray rows
   `ownsFile=false`; manifests reload after app relaunch.
10. **Load a pre-change manifest** (no `ownsFile`/`filePath`) and delete → legacy
    items still delete their own files (backward-compat).

---

## Bottom line

The cleanup achieves the one-write goal and the tray-as-reference model is
implemented correctly and safely for the tray-side delete/drain paths (with unit
tests). The must-address items before shipping: **H1** (shared-media deletion
across capture↔dictation — needs a product decision), **H2/M2** (honest
failure/interruption reporting + recoverable temp on the now-single persist path),
and **M1** (don't kill a recording just because its window minimized).
