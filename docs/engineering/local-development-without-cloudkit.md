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

Public defaults in `Config/Signing.defaults.xcconfig` use inert identifiers such as `com.example.talkie` and `iCloud.com.example.talkie`. They are safe for source checkouts, but they are not registered services.

Without a real Apple team and registered containers, these areas should be treated as unavailable:

- iCloud/CloudKit sync
- App Group sharing across installed device targets
- device builds that require provisioning profiles
- App Store, notarization, Fastlane, and release packaging

## Enabling CloudKit In A Fork

To test CloudKit in your own fork, create a private local config file:

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

Then set your own Apple team and identifiers in `Config/Signing.local.xcconfig`. Do not use the maintainer production identifiers, and do not commit the local config.

At minimum you need:

- `TALKIE_DEVELOPMENT_TEAM`
- `TALKIE_IOS_CLOUDKIT_CONTAINER` or `TALKIE_CLOUDKIT_CONTAINER`
- the matching `TALKIE_*_APP_GROUP` values for targets you run on device
- bundle identifiers registered to your Apple Developer team

Keep credentials, API keys, signing certificates, provisioning profiles, and App Store Connect keys outside the repo. Use Keychain, `secret`, or your CI secret store.

## Contributor Expectation

If a change does not touch sync, signing, entitlements, release tooling, or App Store behavior, validate it with the no-CloudKit path above. If a change requires real CloudKit or App Store infrastructure, call that out explicitly in the PR and include the validation you could run locally.
