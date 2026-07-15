# Signing Configuration

`Signing.defaults.xcconfig` is the checked-in source of truth for Talkie's bundle IDs, app groups, shared suites, CloudKit containers, and unsigned local build defaults.

`Signing.xcconfig` includes those defaults and then optionally includes ignored machine-local overrides from `Signing.local.xcconfig`.

For `apps/macos/run.sh`, prefer a user-global environment file so every Git
worktree uses the same signing identity:

```bash
mkdir -p ~/.config/talkie
$EDITOR ~/.config/talkie/signing.env
```

```bash
TALKIE_DEVELOPMENT_TEAM="D58PF38LQK"
TALKIE_CODE_SIGNING_ALLOWED="YES"
TALKIE_CODE_SIGNING_REQUIRED="YES"
TALKIE_CODE_SIGN_IDENTITY="Apple Development"
```

`run.sh` uses `TALKIE_SIGNING_ENV_FILE` when explicitly set, then the global
file above, then the checkout-local `Config/signing.env`. TalkieAgent builds
fail before install or launch when a stable development signature is not
available; an unsigned Agent is never installed over the stable dev app.

Use `Signing.local.xcconfig` for Xcode settings that should vary by machine or Apple account, such as:

```xcconfig
TALKIE_DEVELOPMENT_TEAM = D58PF38LQK
TALKIE_CODE_SIGNING_ALLOWED = YES
TALKIE_CODE_SIGNING_REQUIRED = YES
```

Do not create or maintain separate `.example` signing files. Identifiers are not secrets; credentials, certificates, provisioning profiles, API keys, and notarization profiles should live in Keychain, App Store Connect, `secret`, or CI secrets.

The canonical namespace is `to.talkie.app`:

```xcconfig
TALKIE_APP_IDENTIFIER = to.talkie.app
TALKIE_IOS_APP_BUNDLE_ID = to.talkie.app
TALKIE_MAC_CORE_BUNDLE_ID = to.talkie.app.mac
TALKIE_MAC_AGENT_BUNDLE_ID = to.talkie.agent
TALKIE_MAC_SYNC_BUNDLE_ID = to.talkie.app.sync
TALKIE_IOS_APP_GROUP = group.to.talkie.app
TALKIE_MAC_APP_GROUP = group.to.talkie.app.mac
TALKIE_CLOUDKIT_CONTAINER = iCloud.to.talkie
```
