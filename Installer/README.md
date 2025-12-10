# Talkie Installer Build System

Build, sign, and notarize macOS installer packages for Talkie.

## Prerequisites

- Xcode Command Line Tools
- Developer ID Application certificate: `Arach Tchoupani (2U83JFPW66)`
- Developer ID Installer certificate: `Arach Tchoupani (2U83JFPW66)`
- Notarization credentials stored via: `xcrun notarytool store-credentials "notarytool"`

## Usage

```bash
./build.sh              # Build full installer (all 3 apps)
./build.sh core         # Build Talkie-Core (Engine + Core)
./build.sh live         # Build Talkie-Live (Engine + Live)
./build.sh all          # Build all 3 installers
```

## Environment Variables

```bash
VERSION=1.3.0 ./build.sh        # Set version (default: 1.3.0)
SKIP_NOTARIZE=1 ./build.sh      # Skip notarization (for testing)
```

## Targets

| Target | Package | Contents |
|--------|---------|----------|
| `full` (default) | Talkie-for-Mac.pkg | Engine + Live + Core |
| `core` | Talkie-Core.pkg | Engine + Core |
| `live` | Talkie-Live.pkg | Engine + Live |
| `all` | All 3 packages | Everything |

## What the Script Does

1. Verifies signing certificates exist
2. Builds TalkieEngine, TalkieLive, and Talkie (Core) from source
3. Signs each app with Developer ID Application certificate
4. Creates component packages (.pkg)
5. Creates distribution package(s) based on target
6. Signs distribution with Developer ID Installer certificate
7. Submits for Apple notarization and waits for approval
8. Staples notarization ticket to the package
9. Verifies Gatekeeper acceptance

## Distribution XML Files

- `distribution.xml` - Full installer with customizable install
- `distribution-core.xml` - Engine + Core only
- `distribution-live.xml` - Engine + Live only

## Output

Signed and notarized packages are created in the `Installer/` directory:
- `Talkie-for-Mac.pkg`
- `Talkie-Core.pkg`
- `Talkie-Live.pkg`

## Testing Installation

```bash
sudo installer -pkg 'Talkie-for-Mac.pkg' -target /
```

## Troubleshooting

Check notarization status:
```bash
xcrun notarytool history --keychain-profile notarytool
xcrun notarytool log <submission-id> --keychain-profile notarytool
```

Verify package signature:
```bash
pkgutil --check-signature Talkie-for-Mac.pkg
spctl --assess --type install Talkie-for-Mac.pkg
```
