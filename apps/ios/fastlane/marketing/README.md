# Talkie App Store product-page assets

This folder contains the English App Store screenshot sets for Talkie. The
product-page bundle combines six composed 6.9-inch iPhone images with native
13-inch iPad and Apple Watch simulator captures.

The companion 29-second App Preview, poster frame, capture harness, and
reproducible edit live under `app-preview/`.

## Campaign spine

**Voice into action.** Talkie catches an idea at speaking speed, turns it into
usable writing, and keeps the user in control of what happens next.

The first three frames sell momentum. The last three prove control: visible AI
edits, flexible processing, and dictation anywhere.

## Story order

1. Say it before it slips away — home and capture overview
2. Talk at full speed. Talkie keeps up — active voice recording
3. Go from voice to finished writing — live dictation and composition
4. Ask for the edit. Approve every word — AI diff review
5. Choose how Talkie gets it done — engines, providers, and Mac routing
6. Dictate anywhere. Keep moving — Talkie keyboard

The opening three carry the core capture-to-writing story because they may be
shown in App Store search results. The sequence alternates warm paper and dark
tape-machine surfaces while keeping the app UI itself unaltered.

## Regenerate

Run from anywhere in the repository:

```bash
apps/ios/fastlane/marketing/compose.sh
```

Requirements:

- macOS with Xcode command-line tools (the compositor uses AppKit)
- macOS system fonts (New York and SF)
- current simulator captures under `apps/ios/fastlane/screenshots/raw/en-US/`

Generated files are written to `output/`, with a campaign contact sheet at
`contact-sheet.png`.

## Prepare App Store Connect upload

Create the gitignored Fastlane upload bundle for both English localizations:

```bash
apps/ios/fastlane/marketing/prepare-upload.sh
```

The script prepares eight images per locale: six iPhone screenshots, one
13-inch iPad screenshot, and one Apple Watch screenshot. The Deliver
configuration reads from `fastlane/marketing/.upload` by default.
Override it with `TALKIE_SCREENSHOTS_PATH` when needed. Uploads require the
gitignored App Store Connect API key at `apps/ios/fastlane/api_key.json`, or a
path supplied through `TALKIE_FASTLANE_API_KEY_PATH`.

## Export the App Store build

After creating an Xcode archive, export its IPA with the checked-in App Store
options:

```bash
xcodebuild -exportArchive \
  -archivePath /path/to/Talkie.xcarchive \
  -exportPath /path/to/export \
  -exportOptionsPlist apps/ios/fastlane/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

The export keeps the repository version and build number unchanged, signs with
automatic distribution signing, uses the production iCloud environment, and
includes symbols for App Store Connect.

## Source material

- `source/backgrounds/ivory-waveform.png`: generated tactile ivory campaign art
- `source/backgrounds/charcoal-waveform.png`: generated dark tape-reel campaign art
- `source/backgrounds/paper-waveform.png`: generated layered-paper campaign art
- `fastlane/screenshots/raw/en-US/`: iPhone 17 Pro Max simulator captures
- `fastlane/screenshots/iPad Pro 13-inch (M5)/01_Home.png`: required 13-inch iPad capture
- `fastlane/screenshots/Apple Watch Series 11 (46mm)/00_WatchHome.png`: required Watch capture

The generated background prompts intentionally exclude text, logos, devices,
and UI. All typography and real Talkie screenshots are composed locally for
accuracy and repeatability.
