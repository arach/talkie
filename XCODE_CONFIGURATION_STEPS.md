# Xcode Configuration Steps for Environment Separation

## Overview
This guide walks through adding Staging configuration to TalkieLive and TalkieEngine projects.

## Talkie (Already Done via XcodeGen)
✅ Updated `macOS/Talkie/project.yml`
- Run `xcodegen` to regenerate the project

## TalkieLive - Manual Xcode Steps

### 1. Duplicate Release Configuration
1. Open `macOS/TalkieLive/TalkieLive.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the project (not target) under PROJECT
4. Go to Info tab
5. Under Configurations, click the `+` button at the bottom
6. Select "Duplicate 'Release' Configuration"
7. Rename it to "Staging"

### 2. Update Bundle IDs for Staging
1. Select the **TalkieLive** target
2. Go to Build Settings tab
3. Search for "Product Bundle Identifier"
4. Expand it to show per-configuration settings
5. Set values:
   - **Debug**: `jdi.talkie.live.dev` (already set)
   - **Staging**: `jdi.talkie.live.staging` (NEW)
   - **Release**: `jdi.talkie.live` (already set)

### 3. Update URL Scheme
1. Still in TalkieLive target
2. Go to Info tab
3. Expand "URL Types"
4. You'll see `talkielive` scheme
5. We need to make this dynamic per-configuration

**Option A: Use build settings**
1. Go to Build Settings
2. Add custom setting `URL_SCHEME`:
   - Debug: `talkielive-dev`
   - Staging: `talkielive-staging`
   - Release: `talkielive`
3. Edit `Info.plist` to use `$(URL_SCHEME)` instead of hardcoded value

**Option B: Keep it simple**
- Just use `talkielive` for all (we primarily use Talkie's URL scheme anyway)

### 4. Create Staging Scheme
1. Product menu → Scheme → Manage Schemes
2. Click `+` to add new scheme
3. Name it "TalkieLive-Staging"
4. Set Build Configuration to "Staging"
5. Check "Shared" if you want it in version control

---

## TalkieEngine - Manual Xcode Steps

### 1. Duplicate Release Configuration
1. Open `macOS/TalkieEngine/TalkieEngine.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the project (not target) under PROJECTS
4. Go to Info tab
5. Under Configurations, click the `+` button
6. Select "Duplicate 'Release' Configuration"
7. Rename it to "Staging"

### 2. Update Bundle IDs for Staging
1. Select the **TalkieEngine** target
2. Go to Build Settings
3. Search for "Product Bundle Identifier"
4. Set values:
   - **Debug**: `jdi.talkie.engine.dev` (already set)
   - **Staging**: `jdi.talkie.engine.staging` (NEW)
   - **Release**: `jdi.talkie.engine` (already set)

### 3. Create Staging Scheme
1. Product menu → Scheme → Manage Schemes
2. Click `+` to add new scheme
3. Name it "TalkieEngine-Staging"
4. Set Build Configuration to "Staging"
5. Check "Shared"

---

## After Xcode Configuration

Once the Xcode projects are configured, you need to:

1. **Regenerate Talkie project:**
   ```bash
   cd macOS/Talkie
   xcodegen
   ```

2. **Build each app in Staging configuration** to verify bundle IDs are correct:
   ```bash
   # Check TalkieLive
   xcodebuild -project macOS/TalkieLive/TalkieLive.xcodeproj \
              -scheme TalkieLive -configuration Staging \
              -showBuildSettings | grep PRODUCT_BUNDLE_IDENTIFIER

   # Check TalkieEngine
   xcodebuild -project macOS/TalkieEngine/TalkieEngine.xcodeproj \
              -scheme TalkieEngine -configuration Staging \
              -showBuildSettings | grep PRODUCT_BUNDLE_IDENTIFIER
   ```

3. **Create staging launchd plists** (see `macOS/TalkieEngine/jdi.talkie.engine.staging.plist`)

4. **Test that all three environments can run simultaneously**

---

## Quick Reference: Bundle ID Matrix

| App           | Production (Release) | Staging             | Dev (Debug)          |
|---------------|----------------------|---------------------|----------------------|
| Talkie        | jdi.talkie.core      | jdi.talkie.core.staging | jdi.talkie.core.dev |
| TalkieLive    | jdi.talkie.live      | jdi.talkie.live.staging | jdi.talkie.live.dev |
| TalkieEngine  | jdi.talkie.engine    | jdi.talkie.engine.staging | jdi.talkie.engine.dev |

## Quick Reference: URL Schemes

| App           | Production  | Staging           | Dev            |
|---------------|-------------|-------------------|----------------|
| Talkie        | talkie://   | talkie-staging:// | talkie-dev://  |
| TalkieLive    | talkielive://| talkielive-staging:// | talkielive-dev:// |
| TalkieEngine  | talkieengine:// | talkieengine-staging:// | talkieengine-dev:// |

## Quick Reference: XPC Services

| Environment | Engine XPC Service |
|-------------|-------------------|
| Production  | jdi.talkie.engine.xpc |
| Staging     | jdi.talkie.engine.xpc.staging |
| Dev         | jdi.talkie.engine.xpc.dev |
