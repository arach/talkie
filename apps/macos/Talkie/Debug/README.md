# Debug Commands

Talkie supports headless debug commands for automation and testing.

## Usage

```bash
/Applications/Talkie.app/Contents/MacOS/Talkie --debug=<command> [args...]
```

## Available Commands

### onboarding-storyboard
Generate a storyboard image of all onboarding screens.

```bash
# Save to Desktop (default)
--debug=onboarding-storyboard

# Save to custom path
--debug=onboarding-storyboard ~/Documents/my-storyboard.png
```

**Output:** Wide PNG image with all onboarding screens side-by-side with arrows.

### help
Show help for all debug commands.

```bash
--debug=help
```

## Adding New Commands

To add a new debug command:

1. Add your command logic to `DebugCommandHandler.swift`:

```swift
case "my-new-command":
    await myNewCommand(args: args)
```

2. Implement the command method:

```swift
private func myNewCommand(args: [String]) async {
    print("🚀 Running my new command...")
    // Your logic here
    exit(0)
}
```

3. Update the help text in `printHelp()`.

## Examples

### CI/CD Integration
```bash
#!/bin/bash
# Generate fresh onboarding screenshots for docs
./Talkie.app/Contents/MacOS/Talkie --debug=onboarding-storyboard ./docs/assets/onboarding.png
```

### Xcode Run Script
```bash
# Build Phase: Generate docs
"$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/MacOS/$PRODUCT_NAME" --debug=onboarding-storyboard
```
