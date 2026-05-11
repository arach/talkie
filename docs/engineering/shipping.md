# Release & Shipping

## Version Management

**Single source of truth:**
- `VERSION` in repo root: marketing version, e.g. `2.5.11`
- `BUILD_NUMBER` in repo root: global monotonically increasing build number, e.g. `4`

The same `VERSION` and `BUILD_NUMBER` are synced across iOS, macOS Talkie, TalkieAgent, and TalkieSync.

**Version locations (synced by script):**

| File | Format | App |
|------|--------|-----|
| `VERSION` | `2.5.11` | All |
| `BUILD_NUMBER` | `4` | All |
| `apps/ios/Talkie-iOS.xcodeproj/project.pbxproj` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | apps/ios/watchOS |
| `apps/macos/Talkie/Talkie.xcodeproj/project.pbxproj` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | macOS Talkie |
| `apps/macos/Talkie/project.yml` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | macOS Talkie |
| `apps/macos/TalkieAgent/TalkieAgent.xcodeproj/project.pbxproj` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | TalkieAgent |
| `apps/macos/TalkieSync/TalkieSync.xcodeproj/project.pbxproj` | `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | TalkieSync |
| macOS `Info.plist` files | `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)` | macOS apps |

**Sync versions:**
```bash
# Check current versions
./scripts/sync-version.sh --check

# Set and sync a new marketing version
./scripts/sync-version.sh 2.5.12

# Increment the global build number once for a new archive train
./scripts/sync-version.sh --bump-build

# Set a specific build number
./scripts/sync-version.sh --build 4
```

## macOS Release Build

GitHub Actions has a macOS-only release workflow:

```bash
# Build, sign, notarize, and upload a private workflow artifact only
gh workflow run release-mac.yml --repo arach/talkie --ref master \
  -f version=X.Y.Z \
  -f component=all \
  -f publish=false

# Publish publicly only when intentionally shipping
gh workflow run release-mac.yml --repo arach/talkie --ref master \
  -f version=X.Y.Z \
  -f component=all \
  -f publish=true
```

Tag pushes matching `v*` still build and publish the public DMG automatically.

The workflow expects GitHub release variables for the full macOS signing namespace, not just the bundle IDs:

- `TALKIE_TEAM_ID`
- `TALKIE_DEVELOPER_ID_APP`
- `TALKIE_APP_IDENTIFIER`
- `TALKIE_MAC_CORE_BUNDLE_ID`
- `TALKIE_MAC_AGENT_BUNDLE_ID`
- `TALKIE_MAC_SYNC_BUNDLE_ID`
- `TALKIE_MAC_APP_GROUP`
- `TALKIE_MAC_SHARED_SETTINGS_SUITE`
- `TALKIE_CLOUDKIT_CONTAINER`
- `TALKIE_MAC_CORE_PROFILE_NAME`
- `TALKIE_MAC_SYNC_PROFILE_NAME`

Required GitHub release secrets:

- `DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `DEVELOPER_ID_APPLICATION_CERT_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_P8`

`TALKIE_PROVISIONING_PROFILES_BASE64` is optional. When it is absent, the workflow relies on App Store Connect API auth plus Xcode `-allowProvisioningUpdates` to fetch or create the needed Developer ID profiles.

```bash
# Build signed & notarized DMG
./packaging/macos/build.sh

# Skip notarization for testing
SKIP_NOTARIZE=1 ./packaging/macos/build.sh

# Incremental build (faster, reuses existing)
SKIP_CLEAN=1 ./packaging/macos/build.sh

# Optionally bump the shared build number before building
./packaging/macos/build.sh --bump-build
```

**Output:** `packaging/macos/Talkie-for-Mac.dmg` + archived to `packaging/macos/releases/X.Y.Z/`

**Prerequisites:**
- Developer ID Application certificate
- Developer ID Installer certificate
- Notarization credentials: `xcrun notarytool store-credentials "notarytool"`

## iOS Release Build

iOS and watchOS use the shared root `VERSION` and `BUILD_NUMBER`, but shipping remains a local Xcode/App Store Connect path.

1. Run `./scripts/sync-version.sh --bump-build` once for the new archive train.
2. Open `apps/ios/Talkie-iOS.xcodeproj`.
3. Product → Archive.
4. Distribute App → App Store Connect.

## Release Tagging

```bash
# After successful build
git tag vX.Y.Z
git push origin vX.Y.Z
```

## Release Checklist

1. [ ] Sync version/build: `./scripts/sync-version.sh X.Y.Z --bump-build`
2. [ ] Verify: `./scripts/sync-version.sh --check`
3. [ ] Commit: `git commit -am "🔖 Bump version to X.Y.Z"`
4. [ ] Build macOS: `gh workflow run release-mac.yml --repo arach/talkie --ref master -f version=X.Y.Z -f component=all -f publish=false`
5. [ ] Build iOS: Xcode Archive → App Store Connect
6. [ ] Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
7. [ ] Publish to usetalkie.com: rerun the macOS workflow with `publish=true`, or push a `vX.Y.Z` tag once the release candidate artifact is verified.

## Website Publishing

Downloads are hosted via GitHub Releases on the usetalkie.com repo. The website uses GitHub's `/releases/latest/download/Talkie.dmg` redirect, so the release **must** include an asset named `Talkie.dmg` (no version suffix).

**Repo:** https://github.com/arach/usetalkie.com

```bash
# 1. Create both versioned and generic DMG copies
cp packaging/macos/Talkie-for-Mac.dmg packaging/macos/Talkie-X.Y.Z.dmg
cp packaging/macos/Talkie-for-Mac.dmg packaging/macos/Talkie.dmg

# 2. Create GitHub release with both assets
#    Talkie.dmg       → used by /releases/latest/download/Talkie.dmg (website)
#    Talkie-X.Y.Z.dmg → used for direct/versioned links
gh release create vX.Y.Z \
  packaging/macos/Talkie.dmg \
  packaging/macos/Talkie-X.Y.Z.dmg \
  --repo arach/usetalkie.com \
  --title "Talkie X.Y.Z" \
  --notes "Release notes here"
```

**Download URLs:**
- Latest (website): `https://github.com/arach/usetalkie.com/releases/latest/download/Talkie.dmg`
- Versioned: `https://github.com/arach/usetalkie.com/releases/download/vX.Y.Z/Talkie-X.Y.Z.dmg`

No website code changes needed — the `/latest` redirect automatically resolves to the newest release.
