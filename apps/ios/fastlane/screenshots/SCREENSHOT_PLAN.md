# App Store Screenshot Plan

## Narrative
A user opens Talkie, sees what it does (splash), sees their memos (home),
records a new one (recording), views the result (memo detail), configures
the app (settings), and uses the custom keyboard (keyboard).

## Screens (6 total, same across all devices)

| Slot | Name     | What to capture                                              | Nav steps                          |
|------|----------|--------------------------------------------------------------|------------------------------------|
| 00   | Splash   | VOICE + AI branding screen with logo, tagline, grid          | Launch app (shows on first load)   |
| 01   | Home     | Memos list with 3-5 nice titles, mic button, tab bar         | Dismiss splash / go to home        |
| 02   | Recording| Recording in progress — red waveform, timer, stop button     | Tap mic button, wait 3-5 seconds   |
| 03   | Detail   | Memo detail — title, audio player, transcript, quick actions | Stop recording, tap a memo         |
| 04   | Settings | Settings screen — themes, keyboard, engine, sync             | Tap gear icon                      |
| 05   | Keyboard | Talkie keyboard visible in a text field with shortcut row    | Open keyboard settings, show keys  |

## Devices (3 required)

- iPhone 17 Pro (6.3") — `iPhone 17 Pro-XX_Name.png`
- iPhone 17 Pro Max (6.9") — `iPhone 17 Pro Max-XX_Name.png`
- iPad Pro 13-inch (M5) — `iPad Pro 13-inch (M5)-XX_Name.png`

## Current status

### Pro Max (reference set from UI tests)
- 00_Splash: ❌ Shows Home, not Splash — NEEDS REDO
- 01_Home: ❌ Duplicate of 00 — same home screen
- 02_Recording: ✅ Good — recording sheet with waveform
- 03_MemoDetail: ✅ Good — transcript, player, actions
- 04_Settings: ✅ Good — full settings visible
- 05_Keyboard: ❌ Shows "Keyboard Mode" dictation view, not actual keyboard layout

### Pro (broken set)
- 00_Splash: ❌ Was VOICE+AI branding (actually correct content, wrong in old test)
                Now overwritten with bad home screen during debugging
- 01_Home: ❌ Has ugly "Quick memo" test data
- 02_Recording: ❓ Need to verify
- 03_MemoDetail: ❓ Need to verify
- 04_Settings: ❓ Need to verify
- 05_Keyboard: ❓ Need to verify

### iPad (from UI tests)
- All slots: ❓ Need to audit

## Keyboard extension setup

TalkieKeys is embedded inside `Talkie.app` as a plugin (`PlugIns/TalkieKeys.appex`).
Installing the app automatically installs the keyboard — but you must **enable it manually** on each simulator.

### Enable on a simulator
1. Open **Settings > General > Keyboard > Keyboards > Add New Keyboard**
2. Select **Talkie**
3. Tap it again and toggle **Allow Full Access**

There is no `simctl` command to automate this. Keyboard settings persist across app reinstalls
but reset if you erase the simulator.

### Simulator UDIDs
- iPhone 17 Pro: `2C26F160-15C8-4AA4-BC67-5EC8194AA1AB`
- iPhone 17 Pro Max: `8400B4A8-C924-44F9-8314-83CDEDF25E6A`
- iPad Pro 13-inch (M5): `4C4EB9A9-B408-4221-9DA9-23009825408F`

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
- All 3 simulators need the SAME seed data (nice memo titles, not "Quick memo")
- Status bar should show 9:41 (Apple standard) — use `xcrun simctl status_bar`
- No dialogs, no alerts, no charging indicator artifacts
- Talkie keyboard must be enabled on each simulator (see above)

## Capture method
For each device:
1. `xcrun simctl status_bar <UDID> override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4`
2. Navigate to screen
3. `xcrun simctl io <UDID> screenshot <path>`
4. Verify with Read tool
5. Move to next screen

## Principle
Nothing is more than 2 clicks away. If spinning > 2 minutes, stop and reassess.
