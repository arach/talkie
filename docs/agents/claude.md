# Talkie

Voice-first productivity suite for macOS.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Talkie (Swift)                           │
│              UI • Workflows • Data • Orchestration          │
└────────────────┬────────────────┬────────────────┬──────────┘
                 │ XPC            │ XPC            │ HTTP
                 ▼                ▼                ▼
        ┌────────────────┐ ┌─────────────┐ ┌──────────────────┐
        │  TalkieAgent    │ │ TalkieEngine│ │  TalkieGateway   │
        │    (Swift)     │ │   (Swift)   │ │   (TypeScript)   │
        │  Ears & Hands  │ │ Local Brain │ │  External Brain  │
        └────────────────┘ └─────────────┘ └──────────────────┘
          Mic → Keyboard    Whisper         OpenAI, Anthropic
                            Transcription   Google, Groq
```

**Talkie** owns user intent — what to do and why.
**TalkieAgent** owns real-time I/O — listening and typing.
**TalkieEngine** owns local compute — on-device transcription.
**TalkieGateway** owns external APIs — protocol translation to cloud services.

### The Gateway Rule

> **Gateway translates protocols, not intent.**

- ✅ `POST /inference { provider, model, messages }` — generic, any app could use this
- ❌ `POST /polish-memo { memoId }` — Talkie-specific, belongs in main app

**Litmus test:** Could a different app use Gateway unchanged? If yes → Gateway. If no → Talkie.

## Projects

- **apps/macos/Talkie** - Main macOS app (SwiftUI)
- **apps/macos/TalkieAgent** - Background helper for live dictation
- **apps/macos/TalkieEngine** - Transcription engine service
- **apps/macos/TalkieGateway** - Web layer for external APIs (TypeScript/Bun)
- **apps/ios/Talkie iOS** - iOS companion app (SwiftUI)
- **packages/swift/** - Shared Swift packages (WFKit, TalkieKit, DebugKit)

## Web Services & Domains

### Domain Architecture: useTalkie.com

```
┌─────────────────────────────────────────────────────────────────┐
│                        useTalkie.com                            │
├─────────────────────────────────────────────────────────────────┤
│  go.useTalkie.com       │ Public: landing pages, marketing      │
│  clerk.useTalkie.com    │ Clerk Frontend API                    │
│  accounts.useTalkie.com │ Clerk Account Portal (sign-in UI)     │
│  my.useTalkie.com       │ User portal: account, devices, usage  │
│  cloud.useTalkie.com    │ Sync router: cloud services gateway   │
│  api.useTalkie.com      │ Backend API: auth, entitlements, data │
│  admin.useTalkie.com    │ Internal: admin dashboard             │
└─────────────────────────────────────────────────────────────────┘
```

| Subdomain | Infrastructure | Purpose |
|-----------|---------------|---------|
| `go.` | Static site | Landing pages, marketing, go-links |
| `clerk.` | **Clerk** | Frontend API (internal, used by SDKs) |
| `accounts.` | **Clerk** | Account Portal - sign-in/sign-up UI |
| `my.` | Next.js | User portal - account, devices, usage |
| `cloud.` | TBD | Sync orchestration, cloud gateway |
| `api.` | Hono/Vercel | Backend API for native apps |
| `admin.` | Next.js | Internal admin dashboard |

### Current Mappings

| Subdomain | Points To | Status |
|-----------|-----------|--------|
| `api.useTalkie.com` | `talkie-api.vercel.app` | ✅ Active |
| `clerk.useTalkie.com` | `frontend-api.clerk.services` | ✅ Verified |
| `accounts.useTalkie.com` | `accounts.clerk.services` | ✅ Verified |
| `my.useTalkie.com` | `talkie-portal.vercel.app` | 📋 New project needed |
| `cloud.useTalkie.com` | (TBD) | 📋 Planned |
| `go.useTalkie.com` | (TBD) | 📋 Planned |
| `admin.useTalkie.com` | `talkie-admin.vercel.app` | 📋 Planned |

### Auth Provider (Clerk)

| Environment | Account Portal | Notes |
|-------------|----------------|-------|
| Dev | `supreme-stallion-9.accounts.dev` | Clerk dev instance |
| Prod | `accounts.useTalkie.com` | Custom domain ✅ Verified |

### Auth Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. User taps "Sign In"                                         │
│     → Opens: https://accounts.useTalkie.com/sign-in             │
│              ?redirect_url=talkie://auth/callback               │
├─────────────────────────────────────────────────────────────────┤
│  2. Clerk auth completes                                        │
│     → Redirects: talkie://auth/callback?__session=<token>       │
├─────────────────────────────────────────────────────────────────┤
│  3. App fetches user info                                       │
│     → GET https://api.useTalkie.com/api/user                    │
│       Authorization: Bearer <token>                              │
└─────────────────────────────────────────────────────────────────┘
```

### URL Scheme

- `talkie://` - Registered in Info.plist for auth callbacks and deep links

### Environment Configuration

Swift clients use canonical domains:
- **API**: `https://api.useTalkie.com`
- **Auth**: `https://my.useTalkie.com` (when configured)

The Vercel URLs (`*.vercel.app`) are implementation details - always use `useTalkie.com` subdomains in client code.

See [docs/WEB_SERVICES.md](docs/WEB_SERVICES.md) for detailed architecture.

## Build & Dev Workflow

Use `talkie-dev` for building, restarting, and inspecting services. Run `talkie-dev --help`.

TalkieGateway (TypeScript/Bun) runs separately: `cd apps/macos/TalkieGateway && bun run src/server.ts`

## Scripts & Utilities

### Xcode Project Sync (`scripts/sync-xcode-files.py`)

Keeps Swift files in sync with Xcode project. Use when adding/moving files.

```bash
# Check what's missing
./scripts/sync-xcode-files.py --check

# Preview changes (no write)
./scripts/sync-xcode-files.py --diff

# Add missing files
./scripts/sync-xcode-files.py
```

The script:
- Finds .swift files not in project.pbxproj
- Adds them to the correct PBXGroup (preserves folder structure)
- Creates backup before changes

## Data Architecture: GRDB-Primary

**GRDB is the local source of truth. CloudKit is a sync layer.**

```
┌─────────────────────────────────────────────┐
│              App Layer (UI)                 │
│         reads/writes from GRDB only         │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│                  GRDB                       │
│         ~/Library/.../Talkie/*.sqlite       │
│            LOCAL SOURCE OF TRUTH            │
└─────────────────┬───────────────────────────┘
                  │ bridge sync (background)
┌─────────────────▼───────────────────────────┐
│            Sync Providers                   │
│  ┌────────────────────────────────────────┐ │
│  │ CloudKit (via Core Data bridge)        │ │
│  │ - NSPersistentCloudKitContainer        │ │
│  │ - Syncs changes TO GRDB                │ │
│  └────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────┐ │
│  │ Future: other sync providers           │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Evolution
Started with Core Data + CloudKit as source of truth, evolved to GRDB-primary for:
- **Performance**: GRDB is 10-20x faster for local queries
- **Flexibility**: Sync layer is now pluggable
- **Reliability**: App works offline-first, sync catches up

### Startup Order
1. **GRDB first** - App shows immediately with local data
2. **CloudKit deferred** - Syncs in background after UI is ready

### Key Files
- `Data/Database/DatabaseManager.swift` - GRDB database setup and migrations
- `Data/Database/RecordingRepository.swift` - Unified recordings table (memos + dictations)
- `Models/Persistence.swift` - Core Data + CloudKit bridge
- `Services/TalkieData.swift` - Bridge sync (CloudKit → GRDB)

### Unified Recordings
All recordings (voice memos and dictations) live in a single `recordings` table in `talkie.sqlite`. The `type` field distinguishes behavior:
- `memo` - Syncs to CloudKit, persists indefinitely
- `dictation` - Local only, subject to TTL cleanup

## Key Patterns

- **Observable migration** - Moving from ObservableObject to @Observable
- **Midnight theme** - Dark UI via SettingsManager color properties
- **XPC communication** - Talkie <-> TalkieAgent via TalkieAgentXPCProtocol

## Debug & Design Toolbars

Two overlay toolbars are available in DEBUG builds. Both follow the same philosophy:

> **Fast feedback loops for the thing you're working on right now.**

### Debug Toolbar
- **Location**: `apps/macos/Talkie/Views/DebugToolbar.swift`
- **Philosophy**: Context-specific dev utilities that surface internal state and provide escape hatches. Actions should be things you'd otherwise do via terminal or Xcode debugger.

### Design Toolbar (Design God Mode)
- **Toggle**: `⌘⇧D`
- **Location**: `apps/macos/Talkie/Debug/DesignMode/DesignOverlay.swift`
- **Philosophy**: Visual inspection and responsive testing without leaving the app. Chrome DevTools for native UI.
- **Key Features**:
  - **Viewport Presets**: Quick-resize to target device sizes
    - Compact: 800×500 (minimum viable)
    - Standard: 1000×700 (typical window)
    - Laptop: 1280×800 (MacBook Air baseline)
    - Expanded: 1400×900 (large display)
  - **Visual Decorators**: Grid, Rulers, Spacing guides
  - **Liquid Glass Tuning**: Real-time glass effect parameters
  - **Screenshot**: `⌘⇧⌥D`

## Logging

**ALWAYS use TalkieLogger, NEVER use os.log directly.**

```swift
import TalkieKit

private let log = Log(.database)  // or .system, .audio, .transcription, .xpc, .sync, .ui, .workflow

// Usage
log.info("Starting operation")
log.debug("Details: \(value)")
log.warning("Something unexpected")
log.error("Failed: \(error)")
```

Categories: `.system`, `.audio`, `.transcription`, `.database`, `.xpc`, `.sync`, `.ui`, `.workflow`

Do NOT use:
- `import os.log`
- `Logger(subsystem:category:)`
- `os_log()`

## Git Commits

Do NOT add `Co-Authored-By` lines to commit messages.

## Branch Management

**Branch Deletions:**
- **NEVER** delete branches without explicit user approval
- **NEVER** run `git branch -d`, `git branch -D`, or `git push origin --delete` automatically
- Branch cleanup is a deliberate action, not an automatic post-merge step

**Branch Discrepancies:**
- When local and remote diverge, **STOP and discuss**
- **NEVER** run `git reset --hard`, `git push --force`, or auto-resolve with rebases/merges
- Always show: what commits are local-only, what commits are remote-only
- Discuss: do we want local version, remote version, or a merge?
- Every resolution is a strategic decision, not a mechanical fix

## Git Safety Heuristics

**Core principle:** Big state changes deserve their own conversation, not a footnote.

When a git operation is a *means* to another goal (e.g., stashing to switch branches), it gets less scrutiny than when it's the primary action. This is where mistakes happen. Treat incidental git operations with the same care as intentional ones.

**Always stop and discuss before:**
- Stashing or discarding > 5 uncommitted files
- Switching branches with uncommitted work
- Rebasing across multiple commits
- Any operation where uncommitted work has never been pushed or committed anywhere

**When you encounter uncommitted work blocking an action, present options:**
1. Commit to current branch first (preserves history)
2. Commit + push (safest — work exists remotely)
3. Stash (recoverable but easy to forget)
4. Let the user decide — don't pick for them

**Never silently stash, reset, or discard work as a side effect of another goal.**

**Use `/git-check` before shipping, releasing, or any multi-step git workflow** to get a full situation report first.

A git safety hook enforces these rules automatically — it will block dangerous operations and prompt for discussion. But don't rely on the hook alone; internalize the heuristics.

## Dev CLI (`talkie-dev`)

CLI in `packages/npm/cli/`, built with Bun + Commander. After changing CLI code: `cd packages/npm/cli && bun run build`.

## Common Tasks

When moving/adding Swift files:
1. Move the file in Finder/Xcode
2. Run `./scripts/sync-xcode-files.py --check` to verify
3. Run `./scripts/sync-xcode-files.py` to add missing files

## Release & Shipping

See [SHIPPING.md](SHIPPING.md) for version management, build scripts, and release process.
