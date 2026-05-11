# Codex Notes

## packaging/macos/build.sh quick map

- Requires `VERSION` arg or env; exits if missing.
- Updates versions in:
  - `apps/macos/Talkie/Talkie.xcodeproj/project.pbxproj` (MARKETING_VERSION)
  - `apps/macos/TalkieAgent/TalkieAgent/Info.plist` (CFBundleShortVersionString)
  - `apps/macos/TalkieEngine/TalkieEngine/Info.plist` (CFBundleShortVersionString)
- Builds Release for:
  - TalkieEngine (`apps/macos/TalkieEngine`, derived data `build/TalkieEngine`)
  - TalkieAgent (`apps/macos/TalkieAgent`, derived data `build/TalkieAgent`)
  - Talkie core (`apps/macos/Talkie`, derived data `build/TalkieCore`)
- Embeds helpers into unified `Talkie.app/Contents/Library/LoginItems/`.
- Copies launch agents into `Talkie.app/Contents/Library/LaunchAgents/` from `packaging/macos/resources/`.
- Signs helper apps, then the unified bundle; creates + signs DMG.
- Notarizes unless `SKIP_NOTARIZE=1`.
- `SKIP_CLEAN=1` reuses existing core build if present.

## Common env flags

- `SKIP_NOTARIZE=1` skip notarization (local testing).
- `SKIP_CLEAN=1` incremental build.

## Local build caveat (Codex sandbox)

- SwiftPM/clang module cache writes may fail due to permissions when running here.
