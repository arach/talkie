# Talkie App Preview

The final App Store Preview is a 29-second portrait edit built entirely from
the real Talkie iOS app. It covers capture, the live transcript, saving a memo,
inline dictation, and review of a voice-requested edit.

## Final assets

- `output/Talkie-App-Preview-6.9-inch.mp4` — 886×1920, H.264, 30 fps, AAC
- `output/poster-frame.png` — the recommended 5.2-second poster frame
- `output/contact-sheet.png` — 1.5-second visual QA intervals

The video is 29 seconds and comfortably below Apple's 500 MB limit.

## Capture the performances

Build the screenshot UI tests on the iPhone 17 Pro Max simulator, then start a
`simctl` recording in one terminal:

```bash
xcrun simctl io <simulator-udid> recordVideo \
  --codec=h264 --force \
  apps/ios/fastlane/marketing/app-preview/raw/capture-flow.mov
```

Run the performance in another terminal:

```bash
xcodebuild test-without-building \
  -project apps/ios/Talkie-iOS.xcodeproj \
  -scheme TalkieUITests \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -only-testing:TalkieUITests/TalkieUITestsScreenshots/testAppPreviewCaptureFlow \
  -parallel-testing-enabled NO \
  -derivedDataPath "$HOME/Library/Caches/codex-builds/deriveddata-ios-app-preview"
```

Stop `simctl` with Control-C so the QuickTime metadata is finalized. Repeat
with `testAppPreviewComposeFlow` and write the recording to
`raw/compose-flow.mov`.

## Rebuild the edit

```bash
apps/ios/fastlane/marketing/app-preview/compose.sh
```

The compositor trims away the test runner, conforms the variable-rate
simulator recordings to 30 fps, scales to Apple's 6.9-inch portrait preview
size, creates the review stills, and validates the export.
