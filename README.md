# Talkie

![Version](https://img.shields.io/badge/version-2.5.18-blue)
![macOS](https://img.shields.io/badge/macOS-in%20transition-blue?logo=apple)
![iOS](https://img.shields.io/badge/iOS-26%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-in%20transition-orange?logo=swift)
![Bun](https://img.shields.io/badge/Bun-1.3%2B-black?logo=bun)
![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-orange)

Talkie is a voice memo and dictation workspace for Apple platforms. The app records speech, syncs recordings, transcribes audio, and can run local or AI-assisted workflows against transcripts and live context.

This repository is being prepared for public source-available development. The macOS app, iOS app, TypeScript server, CLI, SDK, and internal packages are present, but some release, signing, App Store, website, and account-specific workflows are still owner-specific.

## What Is Here

- **macOS app**: SwiftUI desktop app in `apps/macos/Talkie/`
- **macOS agent**: companion app for capture and system integration in `apps/macos/TalkieAgent/`
- **TalkieServer**: Bun/Elysia local bridge and gateway in `apps/macos/TalkieServer/`
- **iOS app**: SwiftUI mobile app, extensions, and watch targets in `apps/ios/`
- **CLI**: `@talkie/cli` in `packages/npm/cli/`
- **TypeScript SDK**: `@talkie/client` in `packages/npm/sdk/`
- **Swift packages**: shared libraries in `packages/swift/`, `apps/macos/TalkieKit/`, `apps/macos/TalkieSpeech/`, and related package directories
- **Docs**: architecture notes, specs, audits, and plans in `docs/`

## Platform Notes

The public README used to describe older platform targets. Current public-readiness work is moving the app toward iOS 26 and macOS 26, while some project files still carry older deployment targets during the transition:

- The active iOS app target is moving with iOS 26 work; some extensions still declare lower deployment targets.
- macOS targets are being cleaned up for Tahoe-era SwiftUI and signing expectations.
- Swift package manifests are mixed across Swift tools 5.9 and 6.0.
- Bun packages declare Bun 1.0+ and should be installed per package directory; there is no root `package.json`.

Use the Xcode project settings as the source of truth while the public docs and signing configuration are catching up.

## Fresh Clone Setup

Prerequisites:

- macOS with a recent Xcode capable of opening the project targets in this repo
- Bun 1.0 or newer
- Tailscale if you want the paired-device bridge outside local development
- Optional provider keys for AI features: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, or `GROQ_API_KEY`

Clone the repo:

```bash
git clone https://github.com/arach/talkie.git
cd talkie
```

Install TypeScript package dependencies where needed:

```bash
(cd apps/macos/TalkieServer && bun install)
(cd packages/npm/cli && bun install)
(cd packages/npm/sdk && bun install)
```

Open the Apple projects:

```bash
open TalkieSuite.xcworkspace
open apps/macos/Talkie/Talkie.xcodeproj
open apps/macos/TalkieAgent/TalkieAgent.xcodeproj
open apps/ios/Talkie-iOS.xcodeproj
```

Run the local server for development:

```bash
cd apps/macos/TalkieServer
bun run start:local
```

Local mode binds to loopback and writes a short-lived bearer token under `~/Library/Application Support/Talkie/Bridge/.config/`. Default paired-device mode expects Tailscale; explicit LAN mode requires `--nearby --allow-lan`.

For public forks or fresh clones without private Apple signing and CloudKit access, see [Local Development Without CloudKit](docs/engineering/local-development-without-cloudkit.md).

## Build And Test

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

# TypeScript packages
(cd apps/macos/TalkieServer && bun run agent-kit:validate)
(cd packages/npm/cli && bun run build)
(cd packages/npm/sdk && bun run build)
```

Some schemes, signing identities, CloudKit containers, installer scripts, Fastlane metadata, and release automation are still private or release-specific. For public contributions, prefer focused changes that can be built or reviewed without those credentials.

## Repo Map

| Path | Purpose |
|------|---------|
| `apps/ios/` | iPhone, iPad, widget, share, keyboard, and watch targets |
| `apps/macos/Talkie/` | Main macOS SwiftUI app |
| `apps/macos/TalkieAgent/` | Companion agent for overlay/capture/system behavior |
| `apps/macos/TalkieServer/` | Bun/Elysia bridge, gateway, extensions, workflows, and pairing server |
| `apps/macos/TalkieKit/` | Shared macOS Swift package |
| `apps/macos/TalkieSpeech/` | Speech-related Swift package |
| `packages/swift/` | Shared Swift packages such as WFKit, DebugKit, and DemoKit |
| `packages/npm/cli/` | `talkie` command-line tool |
| `packages/npm/sdk/` | TypeScript client SDK |
| `packages/npm/companion/` | Terminal/SSH-side companion utilities |
| `docs/` | Public-facing and historical engineering docs |
| `services/` | Web/service projects related to the Talkie ecosystem |
| `skills/` | Optional agent guidance for Codex-style repository work |
| `scripts/` | Local maintenance, release, and utility scripts |
| `packaging/macos/`, `apps/ios/fastlane/`, `releases/` | Distribution assets; mostly owner/release-specific |

## Security

See [SECURITY.md](SECURITY.md) for the current local-auth, HMAC, Tailscale/LAN, and secret-handling model.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, build, test, style, and public-contribution guidance.

## License

Talkie is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE). You may use, study, modify, and share the software for noncommercial purposes. Commercial use, resale, hosted services, paid distribution, or App Store redistribution requires a separate written license from the copyright holder.

This is not an OSI open-source license because commercial use is restricted. The historical app EULA is kept separately at [docs/legal/app-eula.md](docs/legal/app-eula.md).
