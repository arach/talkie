# Release & Shipping

## Version Management

**Single source of truth:** `VERSION` file in repo root.

**All version locations (must stay in sync):**

| File | Format | App |
|------|--------|-----|
| `VERSION` | `1.8.0` | All |
| `macOS/Talkie/Talkie.xcodeproj/project.pbxproj` | `MARKETING_VERSION` | macOS Talkie |
| `macOS/Talkie/project.yml` | `MARKETING_VERSION` | macOS Talkie |
| `macOS/TalkieLive/TalkieLive.xcodeproj/project.pbxproj` | `MARKETING_VERSION` | TalkieLive |
| `macOS/TalkieEngine/TalkieEngine/Info.plist` | `CFBundleShortVersionString` | TalkieEngine |
| `iOS/Talkie-iOS.xcodeproj/project.pbxproj` | `MARKETING_VERSION` | iOS Talkie |
| `iOS/TalkieWatch/TalkieWatch.xcodeproj/project.pbxproj` | `MARKETING_VERSION` | Watch |

**Sync all versions:**
```bash
# Check current versions
./scripts/sync-version.sh --check

# Set and sync a new version
./scripts/sync-version.sh 1.8.0
```

## macOS Release Build

```bash
# Build signed & notarized installer (unified bundle)
./Installer/build.sh --version 1.8.0 unified

# Build all installer variants
./Installer/build.sh --version 1.8.0 all

# Skip notarization for testing
SKIP_NOTARIZE=1 ./Installer/build.sh --version 1.8.0 unified

# Incremental build (faster, reuses existing)
SKIP_CLEAN=1 ./Installer/build.sh --version 1.8.0 unified
```

**Output:** `Installer/Talkie-Unified.pkg` + archived to `Installer/releases/X.Y.Z/`

**Prerequisites:**
- Developer ID Application certificate
- Developer ID Installer certificate
- Notarization credentials: `xcrun notarytool store-credentials "notarytool"`

## iOS Release Build

Archive and upload via Xcode:
1. Open `iOS/Talkie-iOS.xcodeproj`
2. Product → Archive
3. Distribute App → App Store Connect

## Release Tagging

```bash
# After successful build
git tag v1.8.0
git push origin v1.8.0
```

## Release Checklist

1. [ ] Sync version: `./scripts/sync-version.sh X.Y.Z`
2. [ ] Commit: `git commit -am "🔖 Bump version to X.Y.Z"`
3. [ ] Build macOS: `./Installer/build.sh --version X.Y.Z unified`
4. [ ] Build iOS: Xcode Archive → App Store Connect
5. [ ] Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
