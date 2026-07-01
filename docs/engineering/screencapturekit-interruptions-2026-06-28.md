# ScreenCaptureKit `SCStream` interruption research for Talkie

Date: 2026-06-28  
Scope: Talkie/TalkieAgent macOS screen recording, especially `SCStreamError.Code.systemStoppedStream` (`-3821`) during Chrome window capture with system audio + microphone.

## Incident facts

TalkieAgent log lines `1231–1236` show:

- `2026-06-28T15:47:13.043Z`: recording started, `3840x2130`, agent preset, `2 Mbps`, `12 fps`, `systemAudio=true`, `microphone=true`, mode `window`.
- `2026-06-28T15:47:29.455Z`: `SCStreamErrorDomain Code=-3821 "Stream was stopped by the system"`.
- Duration before interruption: about `16.4s`.
- Time-zone note: the log timestamp is `15:47Z` (11:47 EDT). The screenshot filename immediately above uses `11.43.47`, so if the remembered incident time was `15:47 ET`, also inspect system logs around `2026-06-28 19:47 UTC`.

Current machine state during this research: `/System/Volumes/Data` has only `6.8 GiB` available (`97%` used). If similar at incident time, low free space is a high-likelihood contributor because ScreenCaptureKit runs through `replayd`/ReplayKit infrastructure and OBS maintainers have repeatedly seen system stops under low disk/cache or memory pressure.

## What `-3821 systemStoppedStream` means

Apple’s public symbol is terse: in the macOS 26.5 SDK header, `SCStreamErrorSystemStoppedStream = -3821` is “The stream was stopped by the system” and is available from macOS 15.0. It is distinct from:

- `-3817` `userStopped`
- `-3818` failed to start audio capture
- `-3820` failed to start microphone capture

So this is not Talkie explicitly stopping, and not a start-time audio/mic failure. It is the system invalidating an already-running stream.

## Known and plausible causes

Ranked for this incident:

1. **Resource pressure in `replayd` (most likely).** OBS issue reports for `SCStreamErrorSystemStoppedStream (-3821)` tie the failure to low free main-disk/cache space and/or memory pressure. One OBS maintainer recommended checking `replayd` logs and later interpreted a user’s logs as macOS stopping streams after a memory-warning path (`stopAllStreamsWithError`). Our capture was large: `3840*2130` at default BGRA costs ~`31.2 MiB/frame`; ScreenCaptureKit’s default queue depth is 8, so just queued IOSurfaces can be ~`250 MiB`, with ~`374 MiB/s` of uncompressed frame traffic at `12 fps`, before encoder, writer, system audio, microphone, Chrome, and GPU sharing.
2. **Target window invalidation/recreation (possible).** Chrome can close/recreate windows during full-screen, tab detach, profile/window relaunch, Space changes, or some UI transitions. A desktop-independent window filter is still bound to an `SCWindow` identity. If all shared windows disappear, newer SDKs provide `streamDidBecomeInactive`; older behavior may surface as a stop/error. Reusable presets can make this worse if a stored `CGWindowID` is stale or has been reused.
3. **Window resize/content rect drift (possible/secondary).** OBS actively reads `SCStreamFrameInfoContentRect`/scale for window captures and calls `updateConfiguration` when the captured window size changes. Talkie currently sizes once at stream creation. Resizing should not normally produce `-3821`, but it can stress/edge the pipeline and is worth matching.
4. **Audio/mic pipeline instability (possible).** `captureMicrophone` is a newer SCK feature (macOS 15). A mid-stream mic device loss or HAL event may be reported as system-stopped rather than the start-time `-3820`. Test system audio only, mic only, and both.
5. **System/Control Center capture policy or concurrent capture (less likely).** Another capture app, Control Center picker state, permission changes, or screen lock/sleep can stop streams.

## What OBS / Chromium / other implementations do

### OBS Studio

OBS’s ScreenCaptureKit source is a useful benchmark:

- On `SCStreamDelegate.stream(_:didStopWithError:)`, it logs the error, marks `capture_failed = true`, and refreshes source properties. It does **not** automatically recover or salvage a recording; the UI exposes “Reactivate Capture”, which destroys and reinitializes the stream.
- It rebuilds shareable content lists when properties are shown/changed, not via a continuous `SCShareableContent` observer.
- It validates target window/display IDs against the latest `SCShareableContent` before creating the stream.
- For window capture, it watches per-frame `SCStreamFrameInfoContentRect`/scale and calls `updateConfiguration` when the frame size changes.
- It sets `queueDepth = 8` and `includeChildWindows = true` on macOS 14.2+.

### Chromium/WebRTC

Chromium’s ScreenCaptureKit device treats `didStopWithError` as a stream error and reports it upward. Chromium also notes that `contentSize` values can change between frames, e.g. after a window resize, and uses content size metadata as part of frame delivery.

### QuickTime / system recorder

QuickTime is closed-source, but user-visible behavior is consistent with writing a movie incrementally and finalizing on stop. The public SCK API equivalent is `SCRecordingOutput` (macOS 15+), which can be attached to an `SCStream` and exposes `recordedDuration`, `recordedFileSize`, and start/fail/finish delegate callbacks. Its configuration is less flexible than Talkie’s AVAssetWriter path (notably no explicit bitrate control), so I would evaluate it as a lab comparison or emergency fallback, not replace Talkie’s writer immediately.

## APIs Talkie is missing or underusing

1. **`SCStreamDelegate.streamDidBecomeInactive(_:)` / `streamDidBecomeActive(_:)`** (macOS 15.2+). Apple documents these as callbacks when all shared windows are exited and later re-opened. This is the closest API-level target invalidation signal; implement for window streams and log it separately from `-3821`.
2. **`SCFrameStatus` terminal/non-complete states.** We currently drop non-`.complete` frames. Add counters/logging for `.idle`, `.blank`, `.suspended`, `.started`, `.stopped`, plus last complete frame time.
3. **`SCStream.updateConfiguration(_:)` for dynamic window dimensions.** Match OBS: read `SCStreamFrameInfoContentRect`, `contentScale`, `scaleFactor`, and update width/height if a window capture’s content size changes materially.
4. **`SCStreamConfiguration.queueDepth`.** Default is 8. For AI-first clips, try `3` or `4` to reduce memory pressure.
5. **`SCStreamConfiguration.pixelFormat`.** Test `420v`/`420f` for lower surface memory and encoder-friendly YCbCr. At 3840x2130, 420v is ~`11.7 MiB/frame` vs BGRA ~`31.2 MiB/frame`.
6. **`SCShareableContent.info(for:)` / filter introspection.** Useful for logging filter style/content rect/scale. There is no public `SCShareableContent` observer; the observer API is on `SCContentSharingPicker`, not the content list itself.
7. **`SCRecordingOutput`.** Evaluate as a comparison path for interrupted-system behavior and file salvage; keep AVAssetWriter unless it proves materially more reliable.

## Ranked mitigations

### Prevent

P0. **Low disk / memory preflight.** Before start, log and optionally warn when main data volume free space is low. Given OBS history, use a conservative threshold for recording, e.g. warn below `25 GiB`, strongly warn/block below `10 GiB`, and include a debug-only note that OBS maintainers floated `50 GiB` for active screen capture. Also log physical memory, approximate process RSS if easy, target resolution, fps, queue depth, pixel format, audio toggles, and target metadata.

P1. **Reduce capture memory footprint for `agent` preset.** Cap native window capture dimensions (e.g. max long edge 2560 or 1920 for AI-first clips), set `queueDepth = 3 or 4`, and test `420v`. Bitrate is already low, but bitrate does not reduce SCK’s pre-encode IOSurface pressure.

P2. **Harden reusable window target resolution.** Store bundle ID/process ID/window ID/title/frame. On reuse, do not accept a matching `windowID` blindly unless app/title/frame are compatible; if not, re-resolve by bundle + title similarity + visible frame proximity, or ask for selection. Re-resolve once more after countdown immediately before `startCapture()`.

P3. **Fallback mode after repeated window failures.** If a window capture of the same app fails with `systemStoppedStream` within N seconds twice, offer/auto-select region capture over the last window frame. Region/display capture survives target window ID churn, though it records whatever is in that rectangle.

### Detect

D0. **Implement `streamDidBecomeInactive/Active`.** Treat inactive as target lost for window capture; stop gracefully and finalize instead of waiting for `-3821`.

D1. **Keep and improve the current 2s health monitor.** Poll `SCShareableContent`; for health diagnostics consider `onScreenWindowsOnly: false` so minimized/Stage Manager/offscreen state can be distinguished from destroyed. Log “missing”, “offscreen”, “inactive”, “size changed”, and “app mismatch” separately.

D2. **Sample watchdog.** If no `.complete` screen frame arrives for 3–5s while recording, log a warning with last frame/audio times and optionally stop/restart. This catches OBS-style frozen streams that do not call `didStopWithError`.

D3. **Collect `replayd` diagnostics on failure.** App cannot rely on reading system logs in production, but support debug instructions:

```bash
log show --predicate '(process == "replayd")' --debug \
  --start '2026-06-28 15:47:00 +0000' --end '2026-06-28 15:48:00 +0000'
```

If the incident was actually 15:47 EDT, use `2026-06-28 19:47:00 +0000`.

### Salvage

S0. **Finalize partial output on SCK stop.** Current tree already contains the right shape: `didStopWithError` calls `finalizeAfterInterruption()` instead of teardown, and controllers can persist interrupted clips. Keep that as P0.

S1. **Make writer finalization more robust.** Track first/last video PTS, call `endSession(atSourceTime:)` before `finishWriting`, and for video-only captures consider appending/repeating the last frame at stop time so the file duration matches wall-clock time when the screen was idle.

S2. **Avoid starting the asset-writer session on audio before video unless intentional.** Buffer/drop early audio or start on the first complete screen frame to reduce weird partial audio-only MP4s when SCK stops before a video frame.

S3. **Preserve forensic artifacts when salvage fails.** If the writer fails but the temp MP4 is non-empty, keep it under a debug folder and log path/size; do not silently delete.

## Reproduction hypotheses for the Chrome window case

1. **Low-space replayd stop.** With free space near `6.8 GiB`, repeatedly record a 3840x2130 Chrome window for 60s under system+mic, system-only, mic-only, and no-audio. Watch `replayd` logs and Activity Monitor memory pressure. Expected if true: failures cluster when free space/RAM pressure is low, independent of Chrome actions.
2. **Chrome window invalidation.** Start with reusable preset; during recording: close target window, detach tab, enter/exit full screen, move to another Space, minimize, switch Chrome profiles, toggle devtools. Expected if true: `streamDidBecomeInactive` or health poll reports missing/offscreen before `-3821`.
3. **Content rect resize.** Resize Chrome continuously and toggle bookmark bar/devtools while recording. Compare current Talkie vs a build that updates SCK config from `SCStreamFrameInfoContentRect`. Expected if true: fewer errors or fewer bad frames with dynamic config.
4. **Mic/system-audio path.** Use the fixed USB mic, then unplug/change default input during capture. Expected if true: failures correlate with audio device changes or only occur when `captureMicrophone=true`.
5. **Concurrent capture.** Run OBS/QuickTime/Control Center capture simultaneously. Expected if true: system policy/replayd limits show in `replayd` logs.

## Recommended PR plan

1. **Diagnostics PR (lowest risk, both TalkieAgent and Talkie):** classify `SCStreamError` code/domain; log volume free space, resolution/fps/queueDepth/pixelFormat/audio flags, target ID/title/app/bundle/frame, last complete frame/audio PTS, and time-zone-correct incident timestamps. Add debug command text for collecting `replayd` logs.
2. **Salvage hardening PR:** keep current `finalizeAfterInterruption`; add `endSession`, first/last PTS tracking, optional last-frame repeat, non-empty failed-temp preservation, and ensure interrupted clips are clearly marked in tray/library.
3. **Target invalidation PR:** implement `streamDidBecomeInactive/Active`; improve reusable preset matching; re-resolve after countdown; upgrade health monitor with reason-specific logs.
4. **Resource-footprint PR:** introduce SCK capture tuning per preset (`queueDepth`, resolution cap, pixel format). Start with `agent`: `queueDepth=3/4`, max long edge 1920/2560, test 420v. Add low-disk warning/block thresholds.
5. **OBS parity PR:** update window recording dimensions from `SCStreamFrameInfoContentRect`/scale using `updateConfiguration`, and set `includeChildWindows=true` for window captures where available.
6. **Lab-only comparison:** prototype `SCRecordingOutput` behind a flag and compare interruption behavior, duration/file size reporting, and audio muxing against AVAssetWriter.

## Sources

- Apple docs: `SCStreamError.systemStoppedStream`, `SCStreamDelegate.streamDidBecomeInactive(_:)`, `SCRecordingOutput`, `SCStream.addRecordingOutput`, `SCStream.updateConfiguration`, and WWDC22 “Take ScreenCaptureKit to the next level”.
- Local verification: Xcode macOS 26.5 SDK headers in `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/ScreenCaptureKit.framework/Versions/A/Headers/`.
- OBS source: `plugins/mac-capture/mac-sck-common.m` and `mac-sck-video-capture.m`.
- OBS issues: `#11864` and `#12380` discuss `SCStreamErrorSystemStoppedStream`, low disk/cache, memory pressure, and `replayd` diagnostics; older `#7663/#7237` show ReplayKit/ScreenCaptureKit freezes tied to `replayd`/memory pressure and later OS fixes.
- Chromium source: `content/browser/media/capture/screen_capture_kit_device_mac.mm`.
- Nonstrict blog: “Recording to disk with ScreenCaptureKit” for AVAssetWriter duration/final-frame handling.

Useful links:

- https://developer.apple.com/documentation/screencapturekit/scstreamerror/systemstoppedstream
- https://developer.apple.com/documentation/screencapturekit/scstreamdelegate/streamdidbecomeinactive%28_%3A%29
- https://developer.apple.com/documentation/screencapturekit/screcordingoutput
- https://developer.apple.com/videos/play/wwdc2022/10156/
- https://github.com/obsproject/obs-studio/blob/master/plugins/mac-capture/mac-sck-common.m
- https://github.com/obsproject/obs-studio/blob/master/plugins/mac-capture/mac-sck-video-capture.m
- https://github.com/obsproject/obs-studio/issues/11864#issuecomment-2659652531
- https://github.com/obsproject/obs-studio/issues/12380#issuecomment-3079528828
- https://github.com/obsproject/obs-studio/issues/12380#issuecomment-3146690882
- https://chromium.googlesource.com/chromium/src/+/739c542a4e758fd691a431d529bc8ce6a98deda7/content/browser/media/capture/screen_capture_kit_device_mac.mm
- https://nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit
