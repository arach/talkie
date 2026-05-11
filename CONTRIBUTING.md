# Contributing

Talkie is being prepared for public source-available development. Contributions are welcome, but some release, signing, App Store, website, and account-specific paths are still private or maintainer-only.

## Ground Rules

- Keep changes focused and explain the user-facing or developer-facing reason.
- Do not commit secrets, local databases, build products, DerivedData, `.env` files, credentials, or generated release artifacts.
- Do not change signing, bundle identifiers, CloudKit containers, Fastlane metadata, or release automation unless the issue explicitly asks for it.
- Prefer root-cause fixes over workarounds.
- For SwiftUI, prefer current SwiftUI APIs and avoid deprecated modifiers when touching nearby code.
- For TypeScript packages, use Bun.

## Fresh Clone

```bash
git clone https://github.com/arach/talkie.git
cd talkie
```

Install dependencies per package:

```bash
(cd apps/macos/TalkieServer && bun install)
(cd packages/npm/cli && bun install)
(cd packages/npm/sdk && bun install)
```

Open the workspace or individual projects:

```bash
open TalkieSuite.xcworkspace
open apps/macos/Talkie/Talkie.xcodeproj
open apps/macos/TalkieAgent/TalkieAgent.xcodeproj
open apps/ios/Talkie-iOS.xcodeproj
```

## Build Commands

```bash
# macOS app
xcodebuild -project apps/macos/Talkie/Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' build

# macOS agent
xcodebuild -project apps/macos/TalkieAgent/TalkieAgent.xcodeproj \
  -scheme TalkieAgent \
  -destination 'platform=macOS' build

# iOS app
xcodebuild -project apps/ios/Talkie-iOS.xcodeproj \
  -scheme Talkie \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Test And Validation

```bash
# macOS app tests, if the scheme is configured locally
xcodebuild -project apps/macos/Talkie/Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' test

# iOS tests
xcodebuild -project apps/ios/Talkie-iOS.xcodeproj \
  -scheme Talkie \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# TalkieServer content validation
(cd apps/macos/TalkieServer && bun run agent-kit:validate)

# CLI and SDK builds
(cd packages/npm/cli && bun run build)
(cd packages/npm/sdk && bun run build)
```

Not every target is guaranteed to build on a fresh public clone without local signing, CloudKit, or maintainer credentials. If a command fails because of private configuration, say that in the PR and include the validation you could run.

For the supported no-private-CloudKit path, see [`docs/engineering/local-development-without-cloudkit.md`](docs/engineering/local-development-without-cloudkit.md).

## Local Server

For local development:

```bash
cd apps/macos/TalkieServer
bun run start:local
```

For paired-device work over Tailscale, use the default server mode. For explicit LAN testing:

```bash
bun run src/server.ts --nearby --allow-lan --require-approval
```

Do not expose LAN mode on untrusted networks.

Run the local security smoke test after changing TalkieServer auth, bind behavior, local CORS, Unix socket handling, or `/cli` routing:

```bash
(cd apps/macos/TalkieServer && bun run smoke:local-security)
```

## Pull Requests

Include:

- What changed and why
- Commands run, with failures called out
- Screenshots or short recordings for UI changes
- Any migration, pairing, or security impact

Keep documentation honest about public readiness. If a feature depends on private infrastructure, release signing, or maintainer-only setup, document that limitation instead of implying it works for everyone.
