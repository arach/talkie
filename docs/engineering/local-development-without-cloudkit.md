# Local Development Without CloudKit

Talkie can be built and reviewed from a public fork without access to the maintainer's Apple team, CloudKit containers, App Groups, App Store Connect account, or signing identities. That path is intended for local UI, server, CLI, SDK, and workflow work. Cloud sync and device release workflows require your own Apple Developer configuration.

## What Works Without Private Apple Configuration

- macOS and iOS simulator builds with `CODE_SIGNING_ALLOWED=NO`
- TalkieServer local mode on loopback
- TypeScript packages under `packages/npm`
- Swift package and app code review
- Local workflow and bridge security smoke tests

Recommended commands:

```bash
xcodebuild -project apps/macos/Talkie/Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project apps/ios/Talkie-iOS.xcodeproj \
  -scheme Talkie \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build

(cd apps/macos/TalkieServer && bun run smoke:local-security)
```

## What Is Intentionally Disabled Or Limited

Defaults in `Config/Signing.defaults.xcconfig` use the canonical Talkie identifiers such as `to.talkie.app` and `iCloud.to.talkie`. They still require a matching Apple team and registered services for signed device builds.

Without a real Apple team and registered containers, these areas should be treated as unavailable:

- iCloud/CloudKit sync
- App Group sharing across installed device targets
- device builds that require provisioning profiles
- App Store, notarization, Fastlane, and release packaging

## Enabling CloudKit With Local Overrides

To test CloudKit against a different Apple team or container set, create ignored local overrides in `Config/Signing.local.xcconfig`.

At minimum you need:

- `TALKIE_DEVELOPMENT_TEAM`
- `TALKIE_IOS_CLOUDKIT_CONTAINER` or `TALKIE_CLOUDKIT_CONTAINER`
- the matching `TALKIE_*_APP_GROUP` values for targets you run on device
- bundle identifiers registered to your Apple Developer team

Keep credentials, API keys, signing certificates, provisioning profiles, and App Store Connect keys outside the repo. Use Keychain, `secret`, or your CI secret store.

## Contributor Expectation

If a change does not touch sync, signing, entitlements, release tooling, or App Store behavior, validate it with the no-CloudKit path above. If a change requires real CloudKit or App Store infrastructure, call that out explicitly in the PR and include the validation you could run locally.
