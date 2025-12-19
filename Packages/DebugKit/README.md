# DebugKit

A comprehensive debugging toolkit for macOS SwiftUI applications.

## Features

### 1. Debug Toolbar
Floating debug toolbar with customizable position, sections, actions, and controls.

```swift
import DebugKit

struct MyApp: View {
    @State private var showDebug = false

    var body: some View {
        ContentView()
            .debugToolbar(
                isVisible: $showDebug,
                sections: [
                    DebugSection("App Info", [
                        ("Version", "1.0.0"),
                        ("Build", "42")
                    ])
                ],
                actions: [
                    DebugAction("Reset", icon: "trash", destructive: true) {
                        // Reset app
                    }
                ]
            )
    }
}
```

### 2. Debug Shelf
Sliding debug shelf for step-based flows (onboarding, wizards, etc.).

```swift
import DebugKit

enum OnboardingStep: Int, CaseIterable {
    case welcome, setup, complete
}

struct OnboardingView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @State private var showDebugShelf = false

    var body: some View {
        VStack {
            // Your onboarding content
        }
        .overlay(alignment: .bottom) {
            if showDebugShelf {
                DebugShelf(
                    colors: myColors,
                    currentStep: $currentStep,
                    onClose: { showDebugShelf = false },
                    stepName: { step in
                        switch step {
                        case .welcome: return "Welcome"
                        case .setup: return "Setup"
                        case .complete: return "Complete"
                        }
                    },
                    additionalActions: [
                        DebugShelfAction(
                            icon: "camera",
                            label: "Screenshot"
                        ) {
                            // Take screenshot
                        }
                    ]
                )
            }
        }
    }
}
```

### 3. Layout Grid Overlay
Visual grid overlay for debugging layouts and spacing consistency.

```swift
import DebugKit

struct MyView: View {
    @State private var showGrid = false

    var body: some View {
        VStack {
            // Your content
        }
        .layoutGrid(
            zones: [
                .header(height: 44),
                .content(topOffset: 44, bottomOffset: 60),
                .footer(height: 60)
            ],
            showGrid: true,
            gridSpacing: 8
        )
        .opacity(showGrid ? 1 : 0)
    }
}
```

Perfect for:
- Ensuring consistent spacing across screens
- Debugging layout issues
- Documenting UI structure

### 4. Storyboard Generator
Generate screenshot storyboards of multi-step flows with optional layout grid overlay.

```swift
import DebugKit

enum OnboardingStep: Int, CaseIterable {
    case welcome, setup, complete
}

// Create generator
let generator = StoryboardGenerator<OnboardingStep>(
    config: .init(
        screenSize: CGSize(width: 680, height: 560),
        showLayoutGrid: true,
        layoutZones: [
            .header(height: 44),
            .content(topOffset: 44, bottomOffset: 60),
            .footer(height: 60)
        ]
    ),
    viewBuilder: { step in
        AnyView(OnboardingView(step: step))
    }
)

// Generate in-app
let image = await generator.generateImage()

// Or generate headlessly via CLI
await generator.generate(outputPath: "~/Desktop/onboarding.png")
```

### 5. CLI Command Handler
Execute debug commands headlessly from the command line.

```swift
import DebugKit

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let cliHandler = CLICommandHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register commands
        cliHandler.register(
            "screenshot",
            description: "Take app screenshots"
        ) { args in
            await takeScreenshots(outputPath: args.first)
        }

        // Handle CLI commands
        Task { @MainActor in
            if await cliHandler.handleCommandLineArguments() {
                return // Command executed, app will exit
            }
        }

        // Normal app launch continues...
    }
}
```

**Usage:**
```bash
MyApp.app/Contents/MacOS/MyApp --debug=screenshot ~/output.png
MyApp.app/Contents/MacOS/MyApp --debug=help
```

## Installation

### Swift Package Manager (Local Package in Monorepo)

Add to your Xcode project:
1. File → Add Package Dependencies
2. Click "Add Local..."
3. Select `Packages/DebugKit`

Or add to Package.swift:
```swift
dependencies: [
    .package(path: "../Packages/DebugKit")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["DebugKit"]
    )
]
```

### Swift Package Manager (Remote)

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/DebugKit.git", from: "1.0.0")
]
```

## Requirements

- macOS 13.0+
- Swift 5.9+

## License

MIT
