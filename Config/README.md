# Local Signing Configuration

Talkie keeps Apple signing identifiers out of source-controlled project files where possible. The checked-in defaults are intentionally inert so a public checkout cannot accidentally build or upload with the private production identifiers.

## Xcode Builds

Copy the example file and replace the placeholders:

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

Keep `Config/Signing.local.xcconfig` local. It is ignored by git.

## Release and App Store Tools

Copy `Config/signing.env.example` to a private location, fill in your identifiers, and source it before running release tooling:

```bash
source /path/to/private/talkie-signing.env
```

Secrets, API keys, and notarization credentials should stay in the keychain, `secret`, or App Store Connect configuration. This directory is only for identifiers and local wiring.

## CloudKit, App Groups, And App Store Continuity

CloudKit containers and app groups are namespace identifiers tied to an Apple Developer account. A public fork needs its own values before enabling CloudKit or shared app-group storage.

For Talkie's private production namespace, `to.talkie.app` is the intended root for new non-iOS app identities and services:

```xcconfig
TALKIE_APP_IDENTIFIER = to.talkie.app
TALKIE_MAC_CORE_BUNDLE_ID = to.talkie.app.mac
TALKIE_MAC_AGENT_BUNDLE_ID = to.talkie.app.agent
TALKIE_MAC_SYNC_BUNDLE_ID = to.talkie.app.sync
TALKIE_MAC_APP_GROUP = group.to.talkie.app.mac
TALKIE_MAC_SHARED_SETTINGS_SUITE = to.talkie.app.shared
TALKIE_CLOUDKIT_CONTAINER = iCloud.to.talkie.app
```

Treat the iOS App Store app as the continuity exception. For production iOS releases, keep the existing App Store bundle IDs, app group, and CloudKit container in `Signing.local.xcconfig`:

```xcconfig
TALKIE_IOS_APP_BUNDLE_ID = existing.ios.bundle.id
TALKIE_IOS_SHARE_BUNDLE_ID = existing.ios.bundle.id.share
TALKIE_IOS_KEYS_BUNDLE_ID = existing.ios.bundle.id.keys
TALKIE_IOS_WIDGET_BUNDLE_ID = existing.ios.bundle.id.widgets
TALKIE_IOS_APP_GROUP = group.existing.ios.bundle.id
TALKIE_IOS_CLOUDKIT_CONTAINER = iCloud.existing.ios.bundle.id
```

Fastlane and iOS entitlements read the iOS-specific values so the global `TALKIE_APP_IDENTIFIER` can move forward without changing the shipped iOS app identity.
