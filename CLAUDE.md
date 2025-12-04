# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

**Talkie** is a multi-platform communication application with:
- **iOS**: Primary mobile application (SwiftUI + Core Data)
- **macOS**: Desktop companion app (planned)
- **Backend**: API services for sync and communication (planned)
- **Shared**: Common code, protocols, and data structures

## Repository Structure

```
talkie/
├── iOS/                         # iOS Application
│   ├── talkie/                  # Main app target
│   │   ├── App/                 # App entry point (talkieApp.swift)
│   │   ├── Views/               # SwiftUI views
│   │   ├── Models/              # Data models, Core Data
│   │   ├── Resources/           # Assets, Info.plist, xcdatamodeld
│   ├── talkie.xcodeproj/        # Xcode project
│   ├── talkieTests/             # Unit tests
│   └── talkieUITests/           # UI tests
├── macOS/                       # macOS companion app (future)
├── Backend/                     # Backend services (future)
└── Shared/                      # Shared protocols and models
```

## Build Commands

### iOS Application

```bash
# Open in Xcode
cd iOS && open talkie.xcodeproj

# Build from command line
cd iOS
xcodebuild -scheme talkie -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run tests
xcodebuild -scheme talkie -destination 'platform=iOS Simulator,name=iPhone 15' test

# Build for release
xcodebuild -scheme talkie -configuration Release archive
```

### Backend (Future)

```bash
cd Backend
pnpm install      # Preferred package manager
pnpm dev         # Development server
pnpm build       # Production build
```

## Technology Stack

### iOS
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Data Persistence**: Core Data
- **Minimum Target**: iOS 16.0
- **Architecture**: MVVM with SwiftUI

### Backend (Planned)
- **Runtime**: Node.js with TypeScript
- **Package Manager**: pnpm (preferred)
- **Framework**: TBD (Express/Fastify/Next.js API routes)

### macOS (Planned)
- **Language**: Swift
- **UI Framework**: SwiftUI (shared with iOS)
- **Minimum Target**: macOS 13.0

## Development Guidelines

### Swift/iOS Code
1. **Naming Conventions**:
   - PascalCase for types (structs, classes, enums)
   - camelCase for properties, methods, variables
   - Folder names use PascalCase (App/, Views/, Models/)

2. **File Organization**:
   - Group by feature when app grows (e.g., `Views/Chat/`, `Views/Settings/`)
   - Keep views focused and composable
   - Extract reusable components

3. **SwiftUI Best Practices**:
   - Prefer `@State` for local view state
   - Use `@StateObject` for view-owned observable objects
   - Use `@ObservedObject` for passed-in observable objects
   - Keep view bodies small and readable

4. **Core Data**:
   - Models defined in `Resources/talkie.xcdatamodeld`
   - Persistence logic in `Models/Persistence.swift`
   - Use background contexts for heavy operations

### Backend Code (Future)
1. Use TypeScript with strict mode
2. Follow existing patterns from parent CLAUDE.md
3. Prefer pnpm for package management
4. Structure API routes logically

### Testing
- Write unit tests for business logic
- Write UI tests for critical user flows
- Keep tests focused and fast

## Git Conventions

- Add gitmoji to ALL commits (✨ new feature, 🐛 bug fix, 📝 docs, etc.)
- NEVER add "Generated with Claude Code" footers
- Keep commits atomic and focused
- Write clear, descriptive commit messages

## Common Tasks

### Adding a New iOS View
1. Create new Swift file in `iOS/talkie/Views/`
2. Define SwiftUI view struct
3. Add to navigation/view hierarchy
4. Write UI tests if user-facing

### Updating Data Model
1. Open `iOS/talkie/Resources/talkie.xcdatamodeld` in Xcode
2. Modify entities/attributes
3. Create new model version if needed
4. Update Persistence.swift if migration required

### Adding Dependencies

**iOS (Swift Package Manager)**:
```
File > Add Packages... in Xcode
```

**Backend (pnpm)**:
```bash
cd Backend
pnpm add <package-name>
```

## Xcode Project Notes

- The Xcode project file may show modifications after restructuring
- File references use groups, not folder references
- If files appear red in Xcode, re-add them from their new locations

## Talkie Workflow Format (TWF)

**CRITICAL**: All workflows MUST be represented in TWF - the source of truth for workflow logic.

### Format Overview

TWF is a JSON-based declarative format for defining automation workflows. It captures:
- Complete execution logic (prompts, configs, conditions)
- All step configurations with full fidelity
- Workflow metadata (name, icon, color, pinned status)

### Storage Requirements

1. **File-based storage**: Each workflow stored as `{uuid}.json` in `Documents/Workflows/`
2. **Append-only**: Never delete - archive old versions to `_archive/`
3. **Human-readable**: Pretty-printed JSON, always recoverable
4. **Schema-resilient**: Decode failures must NOT overwrite existing files

### TWF Structure

**IMPORTANT**: TWF uses human-readable slugs, NOT UUIDs. UUIDs are auto-generated at runtime.

```json
{
  "slug": "brain-dump-processor",
  "name": "Brain Dump Processor",
  "description": "What it does",
  "icon": "brain.head.profile",
  "color": "purple",
  "isEnabled": true,
  "isPinned": false,
  "autoRun": false,
  "steps": [
    {
      "id": "transcribe",
      "type": "Transcribe Audio",
      "config": { "model": "whisper-large-v3" }
    },
    {
      "id": "extract-ideas",
      "type": "LLM Generation",
      "config": {
        "prompt": "Extract ideas from: {{transcribe}}",
        "temperature": 0.7
      }
    },
    {
      "id": "check-actions",
      "type": "Conditional Branch",
      "config": {
        "condition": "{{extract-ideas.nextActions.length}} > 0",
        "thenSteps": ["create-reminder"]
      }
    },
    {
      "id": "create-reminder",
      "type": "Create Reminder",
      "config": { "title": "{{extract-ideas.nextActions[0]}}" }
    }
  ]
}
```

### ID Rules

- **Workflow slug**: kebab-case, unique across user's workflows (e.g., `brain-dump-processor`)
- **Step id**: kebab-case, unique within workflow (e.g., `extract-ideas`, `create-reminder`)
- **References**: Use step id for conditionals (e.g., `"thenSteps": ["create-reminder"]`)
- **Variables**: Reference step output by id (e.g., `{{transcribe}}`, `{{extract-ideas.field}}`)
- **NO UUIDs**: UUIDs are generated internally by Talkie at runtime for CloudKit sync

### Step Types

| Type | Config Key | Purpose |
|------|-----------|---------|
| `LLM Generation` | `llm` | AI text generation |
| `Transcribe Audio` | `transcribe` | Speech-to-text |
| `Transform Data` | `transform` | JSON/text manipulation |
| `Conditional Branch` | `conditional` | If/then/else logic |
| `Create Reminder` | `appleReminders` | Apple Reminders integration |
| `Run Shell Command` | `shell` | Execute CLI commands |
| `Save to File` | `saveFile` | Write to filesystem |
| `Notify iPhone` | `iOSPush` | Push notifications |
| `Trigger Detection` | `trigger` | Voice command detection |
| `Extract Intents` | `intentExtract` | NLP intent parsing |
| `Execute Workflows` | `executeWorkflows` | Run other workflows |

### Validation Rules

When modifying workflow code:
1. **Never add required fields** without migration logic
2. **Use `decodeIfPresent`** for new optional fields with defaults
3. **Preserve all existing fields** - no silent drops
4. **Test round-trip**: encode → decode must be lossless

### WFKit Integration

TWF is the source of truth. WFKit's visual format (nodes + connections) is derived from TWF for display only. The transformation is:
- TWF steps → WFKit nodes (one-to-one)
- Step order → visual connections (sequential flow)
- Step configs → node configuration fields

### Starter Workflows & LLM Generation

Starter workflows are production-ready TWF files bundled with the app:

```
macOS/Talkie/Resources/StarterWorkflows/
├── TWF_GENERATION_PROMPT.md      # LLM prompt for generating new workflows
├── brain-dump-processor.twf.json # Complex multi-step pipeline
├── extract-action-items.twf.json # Task extraction
├── hey-talkie.twf.json           # Voice command system workflow
├── key-insights.twf.json         # Insight extraction
└── quick-summary.twf.json        # Simple summarization
```

**To generate new workflows with an LLM:**
1. Read `TWF_GENERATION_PROMPT.md` for the system prompt
2. Replace `{{USER_DESCRIPTION}}` with what the user wants
3. LLM outputs valid TWF JSON ready to import

The prompt includes:
- All 14 step types with config examples
- 3 in-context learning examples (simple → medium → complex)
- Variable reference syntax (`{{step-id}}`, `{{step-id.property}}`)
- Best practices and guidelines

## Future Roadmap

1. **macOS App**: Native desktop companion with shared SwiftUI views
2. **Backend**: Node.js/TypeScript API for real-time communication
3. **Shared**: Common Swift package for iOS/macOS shared code
4. **Web**: Optional web client (React/Next.js)

## Useful Commands

```bash
# Check project structure
tree -L 3 -I 'xcuserdata|xcshareddata|DerivedData'

# Find Swift files
find iOS -name "*.swift"

# Run specific test
xcodebuild test -scheme talkie -only-testing:talkieTests/TestClassName

# Clean build folder
cd iOS && xcodebuild clean
```
