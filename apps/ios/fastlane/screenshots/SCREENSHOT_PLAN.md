# App Store Screenshot Plan

## Narrative

The iPhone sequence moves from capture through composition, review, control,
and the custom keyboard. The iPad sequence is landscape-first and emphasizes
the full voice workspace: Home, recording, dictation, Ask AI, edit review, and
dictation anywhere.

## Screens (6 total, same across all devices)

| Slot | Name     | What to capture                                              | Nav steps                          |
|------|----------|--------------------------------------------------------------|------------------------------------|
| 00   | Splash   | VOICE + AI branding screen with logo, tagline, grid          | Launch app (shows on first load)   |
| 01   | Home     | Memos list with 3-5 nice titles, mic button, tab bar         | Dismiss splash / go to home        |
| 02   | Recording| Recording in progress — red waveform, timer, stop button     | Tap mic button, wait 3-5 seconds   |
| 03   | Detail   | Memo detail — title, audio player, transcript, quick actions | Stop recording, tap a memo         |
| 04   | Settings | Settings screen — themes, keyboard, engine, sync             | Tap gear icon                      |
| 05   | Keyboard | Talkie keyboard visible in a text field with shortcut row    | Open keyboard settings, show keys  |

## Devices

- iPhone 17 Pro Max (6.9") — `apps/ios/fastlane/screenshots/iPhone 17 Pro Max/XX_Name.png`
- iPad Pro 13-inch (M5), landscape (2752x2064) — `apps/ios/fastlane/screenshots/iPad Pro 13-inch (M5)/XX_Name.png`
- Apple Watch Series 11 (46mm) — `apps/ios/fastlane/screenshots/Apple Watch Series 11 (46mm)/00_WatchHome.png`

## Current status

### iPhone 17 Pro Max
- 00_Splash: ✅ Modern splash screen
- 01_Home: ✅ Seeded home screen
- 02_Recording: ✅ Recording sheet with waveform
- 03_MemoDetail: ✅ Seeded memo detail
- 04_Settings: ✅ Direct settings route
- 05_Keyboard: ✅ Compose keyboard surface

### iPad Pro 13-inch (M5)

- 01_Home: ✅ Seeded landscape workspace
- 02_Recording: ✅ Recording sheet with waveform
- state-dictating: ✅ Live dictation on the Compose surface
- state-home-ask-ready: ✅ Populated Home Ask Talkie command bar
- state-diff: ✅ Visible AI edit review
- 05_Keyboard: ✅ Compose keyboard surface

The harness also captures splash, settings, and intermediate Compose / Ask AI
states for QA. `fastlane/marketing/compose-ipad.swift` selects the six frames
that belong on the product page.

### Apple Watch Series 11 (46mm)
- 00_WatchHome: ✅ Watch home screen

## Keyboard extension setup

TalkieKeys is embedded inside `Talkie.app` as a plugin (`PlugIns/TalkieKeys.appex`).
Installing the app automatically installs the keyboard — but you must **enable it manually** on each simulator.

### Enable on a simulator
1. Open **Settings > General > Keyboard > Keyboards > Add New Keyboard**
2. Select **Talkie**
3. Tap it again and toggle **Allow Full Access**

There is no `simctl` command to automate this. Keyboard settings persist across app reinstalls
but reset if you erase the simulator.

### Quick install (if not using Xcode Run)
```bash
# Build
xcodebuild -scheme Talkie \
    -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" \
    build

# Install (keyboard extension comes bundled)
xcrun simctl install <UDID> <path-to-Talkie.app>

# Launch
xcrun simctl launch <UDID> "$TALKIE_IOS_APP_BUNDLE_ID"
```

## Prerequisites
- iPhone and iPad screenshots use screenshot-mode seeded data.
- iPhone and iPad status bars should show 9:41, charged battery, and full signal.
- No dialogs, no alerts, no charging indicator artifacts
- The compose keyboard screenshot uses the in-app keyboard surface, so the keyboard extension does not need to be enabled for this set.
- Watch screenshots are captured with `simctl io`; watchOS Simulator does not support `simctl status_bar` overrides.

## Capture method
```bash
./scripts/screenshots.sh iphone
./scripts/screenshots.sh ipad
```

The script resolves simulator UDIDs by name, builds the screenshot UI test target,
runs the six App Store screenshot tests, copies images from the SnapshotHelper
cache, and verifies dimensions.

Watch screenshots are currently captured manually after building and installing
the `TalkieWatch Watch App` scheme on an Apple Watch Series 11 simulator:

```bash
xcrun simctl io <WATCH_UDID> screenshot "apps/ios/fastlane/screenshots/Apple Watch Series 11 (46mm)/00_WatchHome.png"
```

## Principle
Nothing is more than 2 clicks away. If spinning > 2 minutes, stop and reassess.
