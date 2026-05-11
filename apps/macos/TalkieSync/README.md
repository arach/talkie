# TalkieSync

Dedicated sync helper service for Talkie. Handles Core Data + CloudKit sync in a separate process to reduce main app memory footprint.

## Architecture

```
┌──────────────────────────────┐    ┌──────────────────────────────┐
│      Talkie (~60MB)          │    │    TalkieSync (Helper)       │
│  ├── GRDB (reads/writes)     │    │  ├── Core Data + CloudKit    │
│  ├── UI                      │◄──►│  ├── Bridge Sync (CD → GRDB) │
│  └── SyncClient (XPC)        │XPC │  ├── Future: S3, Dropbox     │
└──────────────────────────────┘    │  └── Sync Scheduling         │
                                    └──────────────────────────────┘
```

## Setup

### 1. Create Xcode Project

1. Open Xcode
2. File → New → Project
3. Choose macOS → App
4. Product Name: `TalkieSync`
5. Team: Your team
6. Organization Identifier: `jdi.talkie`
7. Bundle Identifier: `jdi.talkie.sync.dev` (for development)
8. Interface: SwiftUI
9. Language: Swift
10. Storage: None (we manage Core Data manually)

### 2. Configure Build Settings

1. Set deployment target to macOS 13.0
2. Add TalkieKit package dependency
3. Add GRDB package dependency
4. Enable CloudKit capabilities
5. Add iCloud container: `iCloud.com.example.talkie`
6. Add App Group: `group.example.talkie`

### 3. Add Files

Copy all files from `TalkieSync/` folder to your Xcode project:
- `App/TalkieSyncApp.swift`
- `Core/CoreDataStack.swift`
- `Core/BridgeSync.swift`
- `Core/SyncScheduler.swift`
- `Providers/SyncProvider.swift`
- `Providers/CloudKitProvider.swift`
- `XPC/TalkieSyncXPCService.swift`
- `Models/talkie.xcdatamodeld` (Core Data model)
- `Assets.xcassets`
- `Info.plist`
- `TalkieSync.entitlements`

### 4. Configure Entitlements

Ensure these entitlements are set in `TalkieSync.entitlements`:
- `com.apple.developer.icloud-container-identifiers`: `iCloud.com.example.talkie`
- `com.apple.developer.icloud-services`: `CloudKit`
- `com.apple.security.application-groups`: `group.example.talkie`
- `com.apple.security.app-sandbox`: `true`
- `com.apple.security.network.client`: `true`

### 5. Register XPC Service

For development, install the launchd plist:

```bash
# Update the path in the plist to match your DerivedData location
# Then install:
cp jdi.talkie.sync.xpc.dev.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/jdi.talkie.sync.xpc.dev.plist
```

## Build & Run

```bash
cd apps/macos/TalkieSync
xcodebuild -scheme TalkieSync -configuration Debug build
```

## Testing

1. Build and run TalkieSync
2. Check logs: `tail -f /tmp/jdi.talkie.sync.xpc.dev.stdout.log`
3. Launch Talkie main app
4. Verify XPC connection in logs

## Integration with Main Talkie App

### Add SyncClient

A `SyncClient.swift` has been created at `apps/macos/Talkie/Services/Sync/SyncClient.swift`. To use it:

1. Add the file to your Xcode project (it may already be in the Sync folder)
2. In your AppDelegate, connect to TalkieSync:

```swift
// In AppDelegate.swift applicationDidFinishLaunching:
SyncClient.shared.connect()

// In applicationWillTerminate:
SyncClient.shared.disconnect()
```

3. Listen for sync notifications:

```swift
// In a view or service that needs to refresh when data arrives:
NotificationCenter.default.addObserver(
    forName: .syncDataAvailable,
    object: nil,
    queue: .main
) { _ in
    // Refresh UI from GRDB
}
```

4. Trigger manual sync:

```swift
Task {
    try await SyncClient.shared.syncNow()
}
```

### Phase 2: Remove Core Data from Main App

After TalkieSync is working reliably:

1. Remove `Persistence.swift` initialization from AppDelegate
2. Remove `CloudKitSyncManager` initialization
3. Remove Core Data context passing to views
4. Update `TalkieData.swift` to use SyncClient instead of direct Core Data

This reduces main app memory from ~130MB to ~60MB.

## Files

```
TalkieSync/
├── App/
│   └── TalkieSyncApp.swift      # App entry point, XPC service startup
├── Core/
│   ├── CoreDataStack.swift      # NSPersistentCloudKitContainer management
│   ├── BridgeSync.swift         # Core Data → GRDB sync
│   └── SyncScheduler.swift      # Periodic sync scheduling
├── Providers/
│   ├── SyncProvider.swift       # Protocol for sync providers
│   └── CloudKitProvider.swift   # iCloud sync implementation
├── XPC/
│   └── TalkieSyncXPCService.swift  # XPC service implementation
├── Models/
│   └── talkie.xcdatamodeld      # Core Data model (shared with Talkie)
├── Assets.xcassets/             # App icons
├── Info.plist
├── TalkieSync.entitlements
└── jdi.talkie.sync.xpc.dev.plist  # launchd service definition
```
