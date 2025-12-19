# Talkie Monorepo Packages

This directory contains reusable Swift packages developed primarily for Talkie but designed to be modular and potentially publishable.

## Packages

### DebugKit
**Location**: `/Packages/DebugKit`
**Purpose**: Comprehensive debugging toolkit for macOS SwiftUI applications

**Features**:
- 🪲 **DebugToolbar** - Floating debug toolbar with customizable sections, actions, and controls
- 📊 **DebugShelf** - Sliding shelf for step-based flows (onboarding, wizards)
- 📐 **LayoutGrid** - Visual grid overlay showing layout zones (header, content, footer) with spacing grid
- 📸 **StoryboardGenerator** - Multi-screen screenshot compositor with layout grid overlay
- ⚡️ **CLICommandHandler** - Generic `--debug=<command>` system for headless operations

**Used by**:
- Talkie (main app)
- WFKit (workflow editor)

**Example**:
```bash
# Generate onboarding storyboard with layout grid
Talkie.app/Contents/MacOS/Talkie --debug=onboarding-storyboard ~/Desktop/storyboard.png
```

---

### WFKit
**Location**: `/Packages/WFKit`
**Purpose**: Visual workflow editor component library for macOS SwiftUI apps

**Features**:
- 🎨 Canvas-based node editor with pan/zoom
- 🔗 Visual node connections (Bezier curves)
- 🎛️ Node property inspector
- 📊 Multiple layout modes (freeform, vertical)
- 💾 JSON export/import
- 🔍 Minimap overview
- 🪲 Built-in debug toolbar (via DebugKit)

**Used by**:
- Talkie (workflow visualization)

**Build & Run**:
```bash
cd Packages/WFKit
swift build
swift run Workflow  # Demo app
```

---

## Why Monorepo?

Both DebugKit and WFKit are:
- ✅ **Primarily for Talkie** - Developed alongside Talkie features
- ✅ **Modular** - Structured as packages for clean architecture
- ✅ **Fast iteration** - In monorepo = no context switching between repos
- ✅ **Potentially publishable** - Still proper SPM packages, could extract later

## Dependencies

```
Talkie
  ├─→ DebugKit
  └─→ WFKit
        └─→ DebugKit
```

Both packages are local dependencies referenced by relative path in their respective `Package.swift` files.

## Development Workflow

### Adding a new feature to DebugKit
1. Make changes in `/Packages/DebugKit/Sources/DebugKit/`
2. Test in Talkie immediately (no separate repo, no commits needed)
3. Build Talkie to verify integration

### Adding a new feature to WFKit
1. Make changes in `/Packages/WFKit/Sources/WFKit/`
2. Test with WFKit demo app: `cd Packages/WFKit && swift run Workflow`
3. Or test directly in Talkie's workflow viewer

### Updating DebugKit (used by both Talkie and WFKit)
1. Make changes in `/Packages/DebugKit/`
2. Both Talkie and WFKit automatically use the updated version (local reference)
3. Build both to verify no breaking changes

## Package Structure

### DebugKit
```
DebugKit/
├── Package.swift
├── README.md
└── Sources/
    └── DebugKit/
        ├── DebugToolbar.swift
        ├── DebugShelf.swift
        ├── LayoutGrid.swift
        ├── StoryboardGenerator.swift
        └── CLICommandHandler.swift
```

### WFKit
```
WFKit/
├── Package.swift
├── CLAUDE.md
└── Sources/
    ├── WFKit/              # Library
    │   ├── Models/
    │   ├── Canvas/
    │   ├── Inspector/
    │   ├── Toolbar/
    │   ├── Theme/
    │   └── WFWorkflowEditor.swift
    └── WorkflowApp/        # Demo app
        └── WorkflowApp.swift
```

## Publishing (Future)

If we want to extract and publish these packages:

1. Create separate repos (e.g., `github.com/user/DebugKit`)
2. Copy package contents
3. Update Talkie to reference remote package instead of local path
4. Tag releases

But for now, keeping them in the monorepo makes development much faster.
