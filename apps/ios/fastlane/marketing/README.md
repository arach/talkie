# Talkie App Store product-page assets

This folder contains the English 6.9-inch iPhone screenshot set for Talkie.
The exported PNGs are 1320 x 2868 pixels and use real simulator captures.

## Story order

1. Catch every thought while it's alive — home and capture overview
2. Talk naturally. Talkie keeps up — active voice recording
3. Turn speech into finished writing — live dictation and composition
4. See every edit. Keep the final say — AI diff review
5. Private by design. Flexible by default — engines and settings
6. Your voice works wherever you type — Talkie keyboard

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

The Deliver configuration reads from `fastlane/marketing/.upload` by default.
Override it with `TALKIE_SCREENSHOTS_PATH` when needed. Uploads require the
gitignored App Store Connect API key at `apps/ios/fastlane/api_key.json`, or a
path supplied through `TALKIE_FASTLANE_API_KEY_PATH`.

## Source material

- `source/backgrounds/ivory-waveform.png`: generated tactile ivory campaign art
- `source/backgrounds/charcoal-waveform.png`: generated dark tape-reel campaign art
- `source/backgrounds/paper-waveform.png`: generated layered-paper campaign art
- `fastlane/screenshots/raw/en-US/`: iPhone 17 Pro Max simulator captures

The generated background prompts intentionally exclude text, logos, devices,
and UI. All typography and real Talkie screenshots are composed locally for
accuracy and repeatability.
