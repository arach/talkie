# Staging Environment Setup Guide

This guide helps you set up the **Staging** environment for Talkie, allowing you to run it alongside Production and Dev builds without conflicts.

## Overview

After completing these steps, you'll have:
- **Production** builds in `/Applications/` (public release)
- **Staging** builds in `~/Applications/Staging/` (your daily driver)
- **Dev** builds from Xcode DerivedData (active development)

Each environment runs independently with its own:
- Bundle IDs (`jdi.talkie.*.staging`)
- URL schemes (`talkie-staging://`)
- XPC services (`jdi.talkie.agent.xpc.staging`)

## Step 1: Build Staging Versions

### Build All Apps in Staging Configuration

```bash
# Build TalkieAgent (Staging)
cd /Users/example/dev/talkie/apps/macos/TalkieAgent
xcodebuild -project TalkieAgent.xcodeproj \
           -scheme TalkieAgent-Staging \
           -configuration Staging \
           -derivedDataPath ./build \
           clean build

# Build Talkie (Staging)
cd /Users/example/dev/talkie/apps/macos/Talkie
xcodebuild -project Talkie.xcodeproj \
           -scheme Talkie-Staging \
           -configuration Staging \
           -derivedDataPath ./build \
           clean build
```

## Step 2: Install to Staging Location

Create staging directory and copy built apps:

```bash
# Create staging directory
mkdir -p ~/Applications/Staging

# Copy built apps to staging
cp -R /Users/example/dev/talkie/apps/macos/TalkieAgent/build/Build/Products/Staging/TalkieAgent.app \
      ~/Applications/Staging/

cp -R /Users/example/dev/talkie/apps/macos/Talkie/build/Build/Products/Staging/Talkie.app \
      ~/Applications/Staging/
```

## Step 3: Launch Staging Apps

TalkieAgent now hosts the embedded local engine, so there is no separate
engine app or launch agent to stage.

```bash
# Launch TalkieAgent (Staging)
open ~/Applications/Staging/TalkieAgent.app

# Launch Talkie (Staging)
open ~/Applications/Staging/Talkie.app
```

## Step 4: Set Custom Keyboard Shortcuts (Optional)

To avoid conflicts with dev builds, set different hotkeys for staging:

1. Open **TalkieAgent** (Staging)
2. Go to Settings
3. Set hotkey to something like: `Cmd+Shift+Option+S`

This way:
- **Staging** TalkieAgent: `Cmd+Shift+Option+S`
- **Dev** TalkieAgent: `Cmd+Shift+Option+D` (or your dev hotkey)

## Verification

### Check Bundle IDs

```bash
# Staging should show .staging suffix
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    ~/Applications/Staging/Talkie.app/Contents/Info.plist
# Should output: jdi.talkie.core.staging

/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    ~/Applications/Staging/TalkieAgent.app/Contents/Info.plist
# Should output: jdi.talkie.agent.staging
```

### Check XPC Service

Verify the agent helper is providing the correct service:

```bash
# Should show jdi.talkie.agent.staging in the list
launchctl print gui/$(id -u) | grep talkie.agent
```

### Test Deep Links

Create a test deep link for staging:

```bash
# This should open Staging Talkie, not Production
open "talkie-staging://live"
```

## Running Multiple Environments

Once set up, you can run all three environments simultaneously:

1. **Production**: `/Applications/Talkie.app`
2. **Staging**: `~/Applications/Staging/Talkie.app`
3. **Dev**: Run from Xcode

Each will:
- Use its own XPC services (no collisions)
- Respond to its own URL schemes
- Have separate data storage (if configured)

## Updating Staging

When you're happy with a dev build and want to promote it to staging:

```bash
# Rebuild staging
cd /Users/example/dev/talkie/apps/macos/Talkie
xcodebuild -project Talkie.xcodeproj \
           -scheme Talkie-Staging \
           -configuration Staging \
           -derivedDataPath ./build \
           clean build

# Quit running staging apps
killall Talkie TalkieAgent

# Copy new builds
cp -R ./build/Build/Products/Staging/Talkie.app ~/Applications/Staging/

# Restart staging apps
open ~/Applications/Staging/Talkie.app
open ~/Applications/Staging/TalkieAgent.app
```

## Troubleshooting

### Embedded Engine Not Connecting

Check if TalkieAgent (the embedded engine host) is running:

```bash
launchctl list | grep talkie.agent.staging
```

If not running, relaunch the staged helper:

```bash
open ~/Applications/Staging/TalkieAgent.app
```

### Deep Links Go to Wrong App

Make sure the URL scheme is registered correctly:

```bash
# Check which app handles talkie-staging://
open "talkie-staging://test"
```

If it opens the wrong app, the bundle ID might be incorrect. Rebuild with Staging configuration.

### Multiple Instances Running

If you see duplicates:

```bash
# List all running Talkie processes
ps aux | grep -i talkie | grep -v grep

# Kill specific instances if needed
killall -9 Talkie TalkieAgent
```

## Uninstalling Staging

To remove the staging environment:

```bash
# Quit apps
killall Talkie TalkieAgent

# Remove files
rm -rf ~/Applications/Staging/
```

## Next Steps

- **Production**: Keep in `/Applications` for stable daily use
- **Staging**: Use as your primary driver while developing
- **Dev**: Use for active development and testing

You can now safely iterate on dev builds without breaking your working staging environment!
