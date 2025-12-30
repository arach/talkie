# App Module

`macOS/Talkie/App/` - Entry point, lifecycle, phased startup

---

## Files

### TalkieApp.swift (~210 lines)
SwiftUI @main entry point. Handles early theme init, navigation actions via FocusedValue, and migration gating.

**Discussion:**
- Clean entry point structure
- EarlyThemeInit pattern ensures theme loads before views render
- FocusedValue for sidebar/settings/live navigation actions
- MigrationGateView handles first-run migration flow
- OSSignposter integration for startup performance tracking

**Issues:**
- Theme parsing duplicated here AND in AppDelegate (both parse --theme=)

---

### AppDelegate.swift (~1092 lines)
NSApplicationDelegate - CLI commands, URL handling, CloudKit, phased init orchestration.

**Discussion:**
- Phased startup via StartupCoordinator (Critical → Deferred → Background)
- URL scheme handler for `talkie://` deep links
- CloudKit push notification handling
- Design God Mode (⌘⇧D) in DEBUG

**Issues:**
- **DUPLICATE**: `clear-pending` command registered twice (lines 522-532 and 534-544)
- Very large file (1092 lines) - debug commands could be split to separate file
- Theme parsing duplicated with TalkieApp.swift

---

### StartupCoordinator.swift (~204 lines)
Phased startup: Critical → Database → Deferred → Background

**Discussion:**
- Clean separation of startup phases
- Phase 1 (Critical): Window appearance only - sync, blocks UI
- Phase 2 (Database): Async, before main content
- Phase 3 (Deferred): 300ms delay - notifications, CloudKit, sync
- Phase 4 (Background): 1s delay - helper apps, XPC, monitoring
- OSSignposter for performance tracing

**Issues:**
- None identified - clean implementation

---

### DataLayerIntegration.swift
Integration helpers for data layer.

**Discussion:**

---

### BuildInfo.swift
Build metadata (version, commit).

**Discussion:**

---

## TODO

- [ ] Extract debug commands from AppDelegate to DebugCommandHandler
- [ ] Consolidate theme parsing (currently in both TalkieApp and AppDelegate)
- [ ] Update docs: BootSequence.swift doesn't exist in main app (only TalkieLive)

## Done

- Initial review pass complete
- Removed duplicate `clear-pending` command registration in AppDelegate
