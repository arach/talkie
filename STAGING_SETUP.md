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
- XPC services (`jdi.talkie.engine.xpc.staging`)

## Step 1: Build Staging Versions

### Build All Apps in Staging Configuration

```bash
# Build TalkieEngine (Staging)
cd /Users/arach/dev/talkie/macOS/TalkieEngine
xcodebuild -project TalkieEngine.xcodeproj \
           -scheme TalkieEngine-Staging \
           -configuration Staging \
           -derivedDataPath ./build \
           clean build

# Build TalkieLive (Staging)
cd /Users/arach/dev/talkie/macOS/TalkieLive
xcodebuild -project TalkieLive.xcodeproj \
           -scheme TalkieLive-Staging \
           -configuration Staging \
           -derivedDataPath ./build \
           clean build

# Build Talkie (Staging)
cd /Users/arach/dev/talkie/macOS/Talkie
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
cp -R /Users/arach/dev/talkie/macOS/TalkieEngine/build/Build/Products/Staging/TalkieEngine.app \
      ~/Applications/Staging/

cp -R /Users/arach/dev/talkie/macOS/TalkieLive/build/Build/Products/Staging/TalkieLive.app \
      ~/Applications/Staging/

cp -R /Users/arach/dev/talkie/macOS/Talkie/build/Build/Products/Staging/Talkie.app \
      ~/Applications/Staging/
```

## Step 3: Set Up TalkieEngine Daemon

Install the staging launchd plist:

```bash
# Copy plist to LaunchAgents
cp /Users/arach/dev/talkie/macOS/TalkieEngine/jdi.talkie.engine.staging.plist \
   ~/Library/LaunchAgents/

# Load the daemon
launchctl load ~/Library/LaunchAgents/jdi.talkie.engine.staging.plist

# Verify it's running
launchctl list | grep talkie.engine.staging
```

To check the engine logs:

```bash
# View stdout
tail -f /tmp/jdi.talkie.engine.staging.stdout.log

# View stderr
tail -f /tmp/jdi.talkie.engine.staging.stderr.log
```

## Step 4: Launch Staging Apps

```bash
# Launch TalkieLive (Staging)
open ~/Applications/Staging/TalkieLive.app

# Launch Talkie (Staging)
open ~/Applications/Staging/Talkie.app
```

## Step 5: Set Custom Keyboard Shortcuts (Optional)

To avoid conflicts with dev builds, set different hotkeys for staging:

1. Open **TalkieLive** (Staging)
2. Go to Settings
3. Set hotkey to something like: `Cmd+Shift+Option+S`

This way:
- **Staging** TalkieLive: `Cmd+Shift+Option+S`
- **Dev** TalkieLive: `Cmd+Shift+Option+D` (or your dev hotkey)

## Verification

### Check Bundle IDs

```bash
# Staging should show .staging suffix
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    ~/Applications/Staging/Talkie.app/Contents/Info.plist
# Should output: jdi.talkie.core.staging

/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    ~/Applications/Staging/TalkieLive.app/Contents/Info.plist
# Should output: jdi.talkie.live.staging

/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
    ~/Applications/Staging/TalkieEngine.app/Contents/Info.plist
# Should output: jdi.talkie.engine.staging
```

### Check XPC Service

Verify the engine daemon is providing the correct service:

```bash
# Should show jdi.talkie.engine.staging in the list
launchctl print gui/$(id -u) | grep talkie.engine
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
cd /Users/arach/dev/talkie/macOS/Talkie
xcodebuild -project Talkie.xcodeproj \
           -scheme Talkie-Staging \
           -configuration Staging \
           -derivedDataPath ./build \
           clean build

# Quit running staging apps
killall Talkie TalkieLive TalkieEngine

# Copy new builds
cp -R ./build/Build/Products/Staging/Talkie.app ~/Applications/Staging/

# Restart staging apps
open ~/Applications/Staging/Talkie.app
open ~/Applications/Staging/TalkieLive.app
```

## Troubleshooting

### Engine Not Connecting

Check if the staging daemon is running:

```bash
launchctl list | grep talkie.engine.staging
```

If not running, load it:

```bash
launchctl load ~/Library/LaunchAgents/jdi.talkie.engine.staging.plist
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
killall -9 Talkie TalkieLive TalkieEngine
```

## Uninstalling Staging

To remove the staging environment:

```bash
# Quit apps
killall Talkie TalkieLive TalkieEngine

# Unload daemon
launchctl unload ~/Library/LaunchAgents/jdi.talkie.engine.staging.plist

# Remove files
rm ~/Library/LaunchAgents/jdi.talkie.engine.staging.plist
rm -rf ~/Applications/Staging/
rm /tmp/jdi.talkie.engine.staging.*.log
```

## Next Steps

- **Production**: Keep in `/Applications` for stable daily use
- **Staging**: Use as your primary driver while developing
- **Dev**: Use for active development and testing

You can now safely iterate on dev builds without breaking your working staging environment!
