# Talkie App Store product-page assets

This folder contains the English App Store screenshot sets for Talkie. The
product-page bundle combines six composed 6.9-inch iPhone images, six composed
13-inch landscape iPad images, and a native Apple Watch simulator capture.

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

## iPad campaign

The iPad set uses a consistent 2752x2064 landscape presentation so Talkie reads
large on the desktop App Store instead of appearing as a narrow portrait image.
Five frames use a quiet mineral studio treatment that keeps the real iPad UI in
the foreground. The Home Ask frame is the single instrument hero: a slim,
symmetrical mineral shell with one mirrored pair of machined encoders. Its
editorial caption floats above the enclosure as a visibly separate component,
and the real iPad capture remains in an exact 4:3 aperture. This keeps the
tactile hardware idea memorable without turning it into a visual gimmick across
the whole campaign.

The iPad capture harness selects Talkie's matching `Mineral` app theme, so the
blue-gray alloy, deep teal ink, recessed readouts, copper signal chrome, and the
custom Home keyboard continue inside the interface. The original graphite
treatment remains available as an alternate colorway.

1. Voice into action — the complete Talkie workspace
2. Talk at full speed — focused recording and live transcription
3. Finished writing, faster — dictation on the page
4. Ask Talkie anything — the Home command bar routes a plain-language prompt into AI
5. Approve every AI edit — visible diff review
6. Dictate anywhere — the Talkie keyboard

## Regenerate

Run from anywhere in the repository:

```bash
apps/ios/fastlane/marketing/compose.sh
apps/ios/fastlane/marketing/compose-ipad.sh
apps/ios/fastlane/marketing/compose-ipad.sh --theme graphite
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

The script prepares thirteen images per locale: six iPhone screenshots, six
13-inch landscape iPad screenshots, and one Apple Watch screenshot. The Deliver
configuration reads from `fastlane/marketing/.upload` by default.
Override it with `TALKIE_SCREENSHOTS_PATH` when needed. Uploads require the
gitignored App Store Connect API key at `apps/ios/fastlane/api_key.json`, or a
path supplied through `TALKIE_FASTLANE_API_KEY_PATH`.

Mineral is the default iPad upload set. Set
`TALKIE_IPAD_MARKETING_THEME=graphite` to stage the older dark treatment.

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
- `source/backgrounds/graphite-instrument-panel.png`: generated iPad instrument-panel art
- `source/backgrounds/mineral-instrument-panel-v7.png`: symmetrical mineral instrument hero used only for Home Ask
- `fastlane/screenshots/raw/en-US/`: iPhone 17 Pro Max simulator captures
- `fastlane/screenshots/iPad Pro 13-inch (M5)/`: 13-inch landscape iPad captures
- `fastlane/screenshots/Apple Watch Series 11 (46mm)/00_WatchHome.png`: required Watch capture

The generated background prompts intentionally exclude text, logos, devices,
and UI. All typography and real Talkie screenshots are composed locally for
accuracy and repeatability.
