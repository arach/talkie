# Recording sheet — donor audit (RecordingView → RecordingSheetNext)

**Source:** `apps/ios/Talkie iOS/Views/RecordingView.swift` (1237 lines)
**Target:** `apps/ios/Talkie iOS/Views/Next/RecordingSheetNext.swift` (currently ~360 lines)
**Status:** done in this audit = ✅ already brought across; everything else is a gap.

Tags:
- **keep** — preserve in rebuild; behavior matters
- **port** — rewrite cleaner but preserve behavior (gap if missing)
- **drop** — was wrong / dead / hack; intentionally left out, with reason
- **defer** — good but out of scope this milestone; record where it lives

---

## Live recording

| # | Feature | Donor line | Tag | Status / Notes |
|---|---|---|---|---|
| 1 | `AudioRecorderManager.startRecording()` on appear | 119 | keep | ✅ done |
| 2 | `ParticlesWaveformView` driven by `recorder.audioLevels` | 196 | keep | ✅ done |
| 3 | `WaveformStyle` switcher (wave / spectrum / particles) in expanded mode | 385 | port | gap — expanded detent currently has no switcher |
| 4 | `RecordingPulse` (red dot, glow, scale animation) | 161 | keep | ✅ done |
| 5 | "REC" smallcap label next to pulse | 172 | port | gap — `· REC · HQ · 44.1k · MEMO` text exists but no pulse-paired REC chip |
| 6 | Live duration counter, monospaced, big | 208 | keep | ✅ done |
| 7 | Stop button: theme-accent ring + glow + filled square glyph | 224 | port | gap — my stop button is generic circle with `stop.fill` |
| 8 | Cancel (ESC) discards in-flight recording | 147 / 568 | keep | ✅ done as cancel button |
| 9 | `recPulse: Bool` ease-in-out repeat-forever | 164 | keep | ✅ done via `RecordingPulse` |

## Stopped / save

| # | Feature | Donor line | Tag | Status / Notes |
|---|---|---|---|---|
| 10 | Title TextField (optional, falls back to default) | 22 / 594 | keep | ✅ done |
| 11 | `defaultTitle` = `"Memo Apr 5 · 3:12 PM"` style | (helper) | keep | ✅ done |
| 12 | Trash / Delete after stop | 256 / 578 | keep | ✅ done as Discard |
| 13 | "READY" smallcap chip | 254 | keep | ✅ done as `· READY TO SAVE` |
| 14 | Save metadata: started / length / quality | (metadata block) | keep | ✅ done; added samples count |

## Save persistence (`saveRecording`)

| # | Feature | Donor line | Tag | Status / Notes |
|---|---|---|---|---|
| 15 | New `VoiceMemo` with id / title / createdAt / lastModified | 592 | keep | ✅ done |
| 16 | `duration`, `fileURL`, `isTranscribing=false`, `sortOrder` | 597 | keep | ✅ done |
| 17 | `originDeviceId = PersistenceController.deviceId` (CloudKit) | 601 | keep | ✅ done |
| 18 | `autoProcessed = false` (mac auto-run) | 602 | keep | ✅ done |
| 19 | Location tag (lat/lon/alt) IF `appSettings.tagLocationEnabled` | 605 | port | gap — not wired; user-gated, low risk |
| 20 | `timezone`, `deviceModel` | 611 | keep | ✅ done |
| 21 | Average + peak amplitude from levels | 615 | keep | ✅ done |
| 22 | `audioData` raw bytes loaded into the memo (CloudKit) | 623 | keep | ✅ done |
| 23 | Waveform data JSON-encoded into memo | 632 | keep | ✅ done |
| 24 | `viewContext.save()` with NSError logging | 661 | port | partial — saves but error path just dismisses; should log |

## Attachments — the big gap

| # | Feature | Donor line | Tag | Status / Notes |
|---|---|---|---|---|
| 25 | Photo attachments via `PhotosPicker` | 29 / 748 | **port** | **gap — substantial; recordings can carry visual context** |
| 26 | Camera attachment capture | 31 / 804 | port | gap — pairs with #25 |
| 27 | Recent visuals carousel (PHAsset thumbnails) | 32 / 694 | port | gap — frictionless attach UX |
| 28 | `PendingRecordingAttachment` (id / image / data / preferredName) | 833 | port | gap — model type, easy to bring |
| 29 | `MemoAttachmentStore.shared` persistence | 42 / (save flow) | port | gap — store exists, just hook it |
| 30 | Sidecar requests (`RecordingSidecarKind` queue) | 34 / 790 | port | gap — already in TalkieMobileKit, just UI wire |
| 31 | "X items queued" compact detail prompt | 403 / 459 | defer | only meaningful once #25–30 wired |
| 32 | `loadRecentVisualsIfNeeded` + `PHPhotoLibrary` auth dance | 677 / 37 | port | gap — needed by #27 |
| 33 | Haptic feedback on queue (`UIImpactFeedbackGenerator`) | 796 | port | gap — tiny but high-polish |

## Layout / chrome

| # | Feature | Donor line | Tag | Status / Notes |
|---|---|---|---|---|
| 34 | Two detents: compact 280 / expanded 600 | 39 / 40 | keep | ✅ done (mine is 280 / 560 — adjust to 600) |
| 35 | `presentationBackground(.transparent)` (uses `Color.clear`) | 53 | drop | replaced with `.regularMaterial` — better feel |
| 36 | Symmetric ESC placeholder for centered REC | 183 | drop | visual hack; my centered layout doesn't need it |
| 37 | `isCancelling` empty-state during dismiss | 27 / 66 | drop | brief flash; my animation handles it cleaner |
| 38 | Accessibility identifiers (`recording.cancel` / `recording.stop`) | 155 / 243 | port | gap — UI tests rely on these |
| 39 | "Starting" state copy ("· LISTENING") | 371 | keep | ✅ done as `· ARMING` |

## Settings / app state

| # | Feature | Donor line | Tag | Status / Notes |
|---|---|---|---|---|
| 40 | `TalkieAppSettings.shared` for location toggle | 28 | port | gap — tied to #19 |
| 41 | App audio session interruption handling (`isInterrupted`) | (recorder) | defer | recorder publishes it; Next sheet should react in M3 |

## Summary

- **Brought in this round** (commit `9b4fb88`): 14 features (mostly persistence + basic recording flow).
- **Real gaps to port next**: 13 (mostly attachments cluster #25–33 + accessibility IDs + waveform style switcher + themed stop button).
- **Deferred with reason**: 3 (compact attachment prompt, interruption handling, fancier error logging).
- **Intentionally dropped**: 3 (symmetric ESC hack, isCancelling flash, transparent background).

Next move: cluster the attachment work as one Codex flight (#25–33 + #19 location), and a small paint pass for #3 (style switcher), #5 (REC pulse pairing), #7 (themed stop button), #38 (accessibility IDs).
