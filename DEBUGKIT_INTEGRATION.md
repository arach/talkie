# DebugKit Integration

✅ **Status: Fully Integrated and Working**

## Setup Summary

DebugKit has been successfully added as a local package in the Talkie monorepo and integrated into the app.

### Package Location
- **Monorepo Path**: `/Users/arach/dev/talkie/Packages/DebugKit`
- **Package Type**: Local Swift Package
- **Platform**: macOS 14.0+

## Usage

### CLI Command

```bash
# Generate storyboard to custom path
~/Library/Developer/Xcode/DerivedData/Talkie-*/Build/Products/Debug/Talkie.app/Contents/MacOS/Talkie \
  --debug=onboarding-storyboard ~/Desktop/onboarding-storyboard.png

# Show available debug commands
~/Library/Developer/Xcode/DerivedData/Talkie-*/Build/Products/Debug/Talkie.app/Contents/MacOS/Talkie \
  --debug=help
```

### Output

The generated storyboard shows:
- ✅ All 7 onboarding screens side-by-side
- ✅ **Blue** outline around HEADER zone (44px)
- ✅ **Green** outline around CONTENT zone (middle)
- ✅ **Orange** outline around FOOTER zone (40px)
- ✅ 8px cyan grid overlay across all screens
- ✅ White arrows between screens

**Result**: Layout inconsistencies are immediately visible, making it easy to spot alignment issues across the flow.

## Components Integrated

### DebugKit Package (`/Packages/DebugKit`)
- ✅ `CLICommandHandler.swift` - Generic debug command system
- ✅ `StoryboardGenerator.swift` - Multi-screen screenshot compositor
- ✅ `LayoutGrid.swift` - Visual grid overlay with zone labels
- ✅ `DebugShelf.swift` - Interactive step navigation UI
- ✅ `DebugToolbar.swift` - Floating debug toolbar

### Talkie Integration
- ✅ `AppDelegate.swift` - Registers `onboarding-storyboard` command
- ✅ `OnboardingStoryboardGenerator.swift` - Talkie-specific storyboard config

## Architecture

```swift
// In AppDelegate.swift
private let cliHandler = CLICommandHandler()

func applicationDidFinishLaunching(_ notification: Notification) {
    registerDebugCommands()

    Task { @MainActor in
        if await cliHandler.handleCommandLineArguments() {
            return // CLI mode - app exits after command
        }
    }
    // Normal app launch continues...
}

private func registerDebugCommands() {
    cliHandler.register(
        "onboarding-storyboard",
        description: "Generate storyboard of onboarding screens with layout grid"
    ) { args in
        let outputPath = args.first
        await OnboardingStoryboardGenerator.shared.generateAndExit(outputPath: outputPath)
    }
}
```

## Adding New Debug Commands

Register new commands in `AppDelegate.registerDebugCommands()`:

```swift
cliHandler.register(
    "screenshot-settings",
    description: "Generate settings screen screenshots"
) { args in
    await SettingsStoryboardGenerator.shared.generateAndExit(outputPath: args.first)
}
```

## Benefits

1. **Instant Visual Feedback**: Generate storyboards in seconds via CLI
2. **Layout Consistency**: Grid overlay reveals spacing issues immediately
3. **Documentation**: Auto-generated visual flow documentation
4. **CI/CD Ready**: Scriptable for automated screenshot generation
5. **Reusable**: Generic components work with any step-based flow
