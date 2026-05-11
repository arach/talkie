# Xcode Configuration Steps for Environment Separation

## Overview
This guide walks through adding Staging configuration to the remaining macOS app targets.

## Talkie (Already Done via XcodeGen)
✅ Updated `apps/macos/Talkie/project.yml`
- Run `xcodegen` to regenerate the project

## TalkieAgent - Manual Xcode Steps

### 1. Duplicate Release Configuration
1. Open `apps/macos/TalkieAgent/TalkieAgent.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the project (not target) under PROJECT
4. Go to Info tab
5. Under Configurations, click the `+` button at the bottom
6. Select "Duplicate 'Release' Configuration"
7. Rename it to "Staging"

### 2. Update Bundle IDs for Staging
1. Select the **TalkieAgent** target
2. Go to Build Settings tab
3. Search for "Product Bundle Identifier"
4. Expand it to show per-configuration settings
5. Set values:
   - **Debug**: `jdi.talkie.agent.dev` (already set)
   - **Staging**: `jdi.talkie.agent.staging` (NEW)
   - **Release**: `jdi.talkie.agent` (already set)

### 3. Update URL Scheme
1. Still in TalkieAgent target
2. Go to Info tab
3. Expand "URL Types"
4. You'll see `talkieagent` scheme
5. We need to make this dynamic per-configuration

**Option A: Use build settings**
1. Go to Build Settings
2. Add custom setting `URL_SCHEME`:
   - Debug: `talkieagent-dev`
   - Staging: `talkieagent-staging`
   - Release: `talkieagent`
3. Edit `Info.plist` to use `$(URL_SCHEME)` instead of hardcoded value

**Option B: Keep it simple**
- Just use `talkieagent` for all (we primarily use Talkie's URL scheme anyway)

### 4. Create Staging Scheme
1. Product menu → Scheme → Manage Schemes
2. Click `+` to add new scheme
3. Name it "TalkieAgent-Staging"
4. Set Build Configuration to "Staging"
5. Check "Shared" if you want it in version control

---

## Embedded Engine Note

There is no standalone `TalkieEngine` app target anymore. The local engine now
lives inside `TalkieAgent`, so staging support only needs Talkie and TalkieAgent.

## After Xcode Configuration

Once the Xcode projects are configured, you need to:

1. **Regenerate Talkie project:**
   ```bash
   cd apps/macos/Talkie
   xcodegen
   ```

2. **Build each app in Staging configuration** to verify bundle IDs are correct:
   ```bash
   # Check Talkie
   xcodebuild -project apps/macos/Talkie/Talkie.xcodeproj \
              -scheme Talkie -configuration Staging \
              -showBuildSettings | grep PRODUCT_BUNDLE_IDENTIFIER

   # Check TalkieAgent
   xcodebuild -project apps/macos/TalkieAgent/TalkieAgent.xcodeproj \
              -scheme TalkieAgent -configuration Staging \
              -showBuildSettings | grep PRODUCT_BUNDLE_IDENTIFIER
   ```

3. **Test that all three environments can run simultaneously**

---

## Quick Reference: Bundle ID Matrix

| App           | Production (Release) | Staging             | Dev (Debug)          |
|---------------|----------------------|---------------------|----------------------|
| Talkie        | jdi.talkie.core      | jdi.talkie.core.staging | jdi.talkie.core.dev |
| TalkieAgent    | jdi.talkie.agent      | jdi.talkie.agent.staging | jdi.talkie.agent.dev |

## Quick Reference: URL Schemes

| App           | Production  | Staging           | Dev            |
|---------------|-------------|-------------------|----------------|
| Talkie        | talkie://   | talkie-staging:// | talkie-dev://  |
| TalkieAgent    | talkieagent://| talkieagent-staging:// | talkieagent-dev:// |

## Quick Reference: XPC Services

| Environment | Agent XPC Service |
|-------------|-------------------|
| Production  | jdi.talkie.agent.xpc |
| Staging     | jdi.talkie.agent.xpc.staging |
| Dev         | jdi.talkie.agent.xpc.dev |
