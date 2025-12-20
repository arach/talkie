# Talkie Environment Separation Plan

## Current State (As-Is)

### Component Overview
```
┌─────────────────┐
│  Talkie (Main)  │  - Main UI app
│  jdi.talkie.core│  - Handles history, settings
│  talkie://      │  - Receives deep links from TalkieLive
└─────────────────┘
         ↓ (uses XPC + deep links)
┌─────────────────┐
│  TalkieLive     │  - Menu bar quick capture
│  jdi.talkie.live│  - Sends deep links to Talkie
│                 │  - Connects to Engine via XPC
└─────────────────┘
         ↓ (uses XPC)
┌─────────────────┐
│  TalkieEngine   │  - Background transcription service
│  jdi.talkie...  │  - Runs as daemon or from Xcode
└─────────────────┘
```

### Current Run Modes

#### 1. Production Mode (Public release in /Applications)
**Install Location:** `/Applications/Talkie.app`, `/Applications/TalkieLive.app`, `/Applications/TalkieEngine.app`
**Purpose:** Official builds distributed to users via website/installer

| Component     | Bundle ID           | XPC Service Name        | URL Scheme   | Launch Method       |
|---------------|---------------------|-------------------------|--------------|---------------------|
| Talkie        | jdi.talkie.core     | N/A                     | talkie://    | User launches       |
| TalkieLive    | jdi.talkie.live     | N/A (client only)       | talkielive://| SMAppService login  |
| TalkieEngine  | jdi.talkie.engine   | jdi.talkie.engine.xpc   | talkieengine://| SMAppService login  |

**Connection Flow:**
- TalkieLive → Engine: XPC to `jdi.talkie.engine.xpc`
- TalkieLive → Talkie: Deep link `talkie://interstitial/{id}`
- Talkie → TalkieLive: Monitor via bundle ID `jdi.talkie.live`
- Talkie → Engine: XPC to `jdi.talkie.engine.xpc`

---

#### 2. Staging Mode (Daily driver / last stable build)
**Install Location:** `~/Applications/Staging/` or `~/dev/talkie/build/Staging/`
**Purpose:** Your personal stable build - last known good state for daily use while developing

| Component     | Bundle ID               | XPC Service Name            | URL Scheme       | Launch Method        |
|---------------|-------------------------|-----------------------------|------------------|----------------------|
| Talkie        | jdi.talkie.core.staging | N/A                         | talkie-staging://| User launches        |
| TalkieLive    | jdi.talkie.live.staging | N/A (client only)           | talkielive-staging://| SMAppService or manual|
| TalkieEngine  | jdi.talkie.engine.staging| jdi.talkie.engine.xpc.staging| talkieengine-staging://| launchd daemon  |

**Launchd plist:** `~/Library/LaunchAgents/jdi.talkie.engine.staging.plist`
```xml
<key>ProgramArguments</key>
<array>
    <string>/Users/arach/Applications/Staging/TalkieEngine.app/Contents/MacOS/TalkieEngine</string>
    <string>--daemon</string>
</array>
<key>MachServices</key>
<dict>
    <key>jdi.talkie.engine.xpc.staging</key>
    <true/>
</dict>
```

**Connection Flow:**
- TalkieLive → Engine: XPC to `jdi.talkie.engine.xpc.staging`
- TalkieLive → Talkie: Deep link `talkie-staging://interstitial/{id}`
- Talkie → TalkieLive: Monitor via bundle ID `jdi.talkie.live.staging`
- Talkie → Engine: XPC to `jdi.talkie.engine.xpc.staging`

**Custom Keyboard Shortcuts:** Different hotkeys from dev (e.g., Cmd+Shift+Option+S)

---

#### 3. Dev Mode (Active Xcode development)
**Install Location:** `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/*.app`
**Purpose:** Active development builds - potentially broken, comparing against staging

| Component     | Bundle ID           | XPC Service Name            | URL Scheme   | Launch Method        |
|---------------|---------------------|-----------------------------|--------------|----------------------|
| Talkie        | jdi.talkie.core.dev | N/A                         | talkie-dev://| Xcode Run/Debug      |
| TalkieLive    | jdi.talkie.live.dev | N/A (client only)           | talkielive-dev://| Xcode Run/Debug |
| TalkieEngine  | jdi.talkie.engine.dev| jdi.talkie.engine.xpc.dev  | talkieengine-dev://| Xcode Run/Debug or daemon|

**Launchd plist (optional):** `~/Library/LaunchAgents/jdi.talkie.engine.dev.plist`
```xml
<key>ProgramArguments</key>
<array>
    <string>/Users/arach/Library/Developer/Xcode/DerivedData/TalkieSuite-.../Build/Products/Debug/TalkieEngine.app/Contents/MacOS/TalkieEngine</string>
    <string>--daemon</string>
</array>
<key>MachServices</key>
<dict>
    <key>jdi.talkie.engine.xpc.dev</key>
    <true/>
</dict>
<!-- NO RunAtLoad, NO KeepAlive - manually controlled or Xcode manages -->
```

**Connection Flow:**
- TalkieLive → Engine: XPC to `jdi.talkie.engine.xpc.dev`
- TalkieLive → Talkie: Deep link `talkie-dev://interstitial/{id}`
- Talkie → TalkieLive: Monitor via bundle ID `jdi.talkie.live.dev`
- Talkie → Engine: XPC to `jdi.talkie.engine.xpc.dev`

**Custom Keyboard Shortcuts:** Different hotkeys from staging (e.g., Cmd+Shift+Option+D)

---

## Current Issues ⚠️

### Issue 1: Talkie Bundle ID Collision
**Problem:** All Talkie builds (prod/staging/dev) use `jdi.talkie.core`
- macOS can't distinguish between them
- Only one can be registered as the `talkie://` URL handler
- Running multiple environments simultaneously causes unpredictable behavior

### Issue 2: URL Scheme Collision
**Problem:** All Talkie builds respond to `talkie://`
- TalkieLive deep links (`talkie://interstitial/{id}`) go to whichever Talkie registered first
- Usually the production one in /Applications wins
- Staging/Dev Talkie don't receive the links meant for them

### Issue 3: AppLauncher Hardcoded Bundle IDs
**File:** `macOS/Talkie/Services/AppLauncher.swift:23-24`
```swift
static let engineBundleId = "jdi.talkie.engine"
static let liveBundleId = "jdi.talkie.live"
```
- Always looks for production bundle IDs
- Can't discover or launch staging/dev versions
- Has special logic for dev engine (line 221) but it's hardcoded

### Issue 4: Service Monitors Check Both Variants
**Files:**
- `macOS/Talkie/Services/TalkieServiceMonitor.swift:18-19`
- `macOS/Talkie/Services/TalkieLiveMonitor.swift:17-18`

```swift
private let serviceBundleIds = [
    "jdi.talkie.engine",      // Production
    "jdi.talkie.engine.dev"   // Development (Xcode builds)
]
```
- Monitors check for both prod and dev (doesn't know about staging)
- Can't control which one connects
- First one found wins

### Issue 5: Can't Run Multiple Environments Simultaneously
**Desired State:**
- Production suite in /Applications (public release)
- Staging suite in ~/Applications/Staging (your daily driver)
- Dev suite from Xcode (active development)
- All three running at the same time without interfering

**Current Reality:**
- Must choose one at a time
- URL schemes collide
- Service discovery is ambiguous
- Can't compare staging vs dev side-by-side

---

## Proposed Solution

### New Environment Model

```
Production Environment (Public release):
  Talkie          → jdi.talkie.core              → talkie://
  TalkieLive      → jdi.talkie.live              → talkie://
  TalkieEngine    → jdi.talkie.engine            → jdi.talkie.engine.xpc

Staging Environment (Your daily driver):
  Talkie          → jdi.talkie.core.staging      → talkie-staging://
  TalkieLive      → jdi.talkie.live.staging      → talkie-staging://
  TalkieEngine    → jdi.talkie.engine.staging    → jdi.talkie.engine.xpc.staging

Dev Environment (Active development):
  Talkie          → jdi.talkie.core.dev          → talkie-dev://
  TalkieLive      → jdi.talkie.live.dev          → talkie-dev://
  TalkieEngine    → jdi.talkie.engine.dev        → jdi.talkie.engine.xpc.dev
```

### Updated Bundle ID Mapping

| Component     | Production          | Staging                 | Dev (Xcode)             |
|---------------|---------------------|-------------------------|-------------------------|
| Talkie        | jdi.talkie.core     | jdi.talkie.core.staging | jdi.talkie.core.dev     |
| TalkieLive    | jdi.talkie.live     | jdi.talkie.live.staging | jdi.talkie.live.dev     |
| TalkieEngine  | jdi.talkie.engine   | jdi.talkie.engine.staging| jdi.talkie.engine.dev  |

### Updated URL Schemes

| Component     | Production          | Staging                 | Dev                     |
|---------------|---------------------|-------------------------|-------------------------|
| Talkie        | talkie://           | talkie-staging://       | talkie-dev://           |
| TalkieLive    | talkielive://       | talkielive-staging://   | talkielive-dev://       |
| TalkieEngine  | talkieengine://     | talkieengine-staging:// | talkieengine-dev://     |

**Note on URL Schemes:**
- URL schemes map to app bundles, so we can't use sub-paths like `talkie://staging`
- Each environment needs its own unique scheme
- macOS registers the scheme to the bundle, so `talkie-staging://` → Talkie.staging app

### Updated XPC Service Names

| Environment   | Engine XPC Service Name        | Notes                                   |
|---------------|--------------------------------|-----------------------------------------|
| Production    | jdi.talkie.engine.xpc          | Production builds from /Applications    |
| Staging       | jdi.talkie.engine.xpc.staging  | Your daily driver, fixed location       |
| Dev           | jdi.talkie.engine.xpc.dev      | Active development from Xcode           |

### Connection Matrix

#### Production Environment (All from /Applications)
```
Talkie (jdi.talkie.core)
  ├─→ Monitors TalkieLive: jdi.talkie.live
  ├─→ XPC to Engine: jdi.talkie.engine.xpc
  └─→ Receives deep links: talkie://

TalkieLive (jdi.talkie.live)
  ├─→ XPC to Engine: jdi.talkie.engine.xpc
  └─→ Sends deep links: talkie://interstitial/{id}

TalkieEngine (jdi.talkie.engine)
  └─→ Provides XPC: jdi.talkie.engine.xpc
```

#### Staging Environment (Your daily driver from ~/Applications/Staging)
```
Talkie (jdi.talkie.core.staging)
  ├─→ Monitors TalkieLive: jdi.talkie.live.staging
  ├─→ XPC to Engine: jdi.talkie.engine.xpc.staging
  ├─→ Receives deep links: talkie-staging://
  └─→ Custom hotkey: Cmd+Shift+Option+S (or your preference)

TalkieLive (jdi.talkie.live.staging)
  ├─→ XPC to Engine: jdi.talkie.engine.xpc.staging
  ├─→ Sends deep links: talkie-staging://interstitial/{id}
  └─→ Custom hotkey: Cmd+Shift+Option+S

TalkieEngine (jdi.talkie.engine.staging)
  ├─→ Provides XPC: jdi.talkie.engine.xpc.staging
  └─→ Runs as daemon via launchd
```

#### Dev Environment (Active development from Xcode)
```
Talkie (jdi.talkie.core.dev)
  ├─→ Monitors TalkieLive: jdi.talkie.live.dev
  ├─→ XPC to Engine: jdi.talkie.engine.xpc.dev
  ├─→ Receives deep links: talkie-dev://
  └─→ Custom hotkey: Cmd+Shift+Option+D (or your preference)

TalkieLive (jdi.talkie.live.dev)
  ├─→ XPC to Engine: jdi.talkie.engine.xpc.dev
  ├─→ Sends deep links: talkie-dev://interstitial/{id}
  └─→ Custom hotkey: Cmd+Shift+Option+D

TalkieEngine (jdi.talkie.engine.dev)
  ├─→ Provides XPC: jdi.talkie.engine.xpc.dev
  └─→ Runs from Xcode or daemon (your choice)
```

---

## Implementation Requirements

### 1. Xcode Build Configurations

Each app needs Debug/Release configurations that set:
- `PRODUCT_BUNDLE_IDENTIFIER`
- URL schemes in Info.plist
- Preprocessor macros for environment detection

**Example for Talkie:**
```
Debug:
  PRODUCT_BUNDLE_IDENTIFIER = jdi.talkie.core.debug
  URL_SCHEME = talkie-debug

Release:
  PRODUCT_BUNDLE_IDENTIFIER = jdi.talkie.core
  URL_SCHEME = talkie
```

### 2. Shared Environment Detection

Create `TalkieEnvironment.swift` in shared TalkieKit package:
```swift
enum TalkieEnvironment {
    case production
    case dev
    case debug

    static var current: TalkieEnvironment {
        // Detect based on bundle ID or build config
    }

    var talkieBundleId: String { ... }
    var liveBundleId: String { ... }
    var engineBundleId: String { ... }

    var engineXPCService: String { ... }

    var talkieURLScheme: String { ... }
    var liveURLScheme: String { ... }
}
```

### 3. Update All Connection Points

**AppLauncher.swift:**
```swift
static let engineBundleId = TalkieEnvironment.current.engineBundleId
static let liveBundleId = TalkieEnvironment.current.liveBundleId
```

**EngineClient.swift:**
```swift
let serviceName = TalkieEnvironment.current.engineXPCService
```

**Deep Link Generation (TalkieLive):**
```swift
let urlString = "\(TalkieEnvironment.current.talkieURLScheme)://interstitial/\(id)"
```

**Service Monitors:**
```swift
// Only monitor the current environment's services
private let serviceBundleIds = [TalkieEnvironment.current.engineBundleId]
```

### 4. Data Storage Separation (Optional)

Each environment could use separate data containers:
```
Production: ~/Library/Containers/jdi.talkie.core/
Dev:        ~/Library/Containers/jdi.talkie.core.dev/
Debug:      ~/Library/Containers/jdi.talkie.core.debug/
```

This prevents dev/debug from corrupting production data.

---

## Migration Path

### Phase 1: Add Dev Bundle IDs
1. Update Talkie Xcode project with Debug config
2. Update Info.plist with dev URL schemes
3. Test that dev builds get correct identifiers

### Phase 2: Create Environment Detection
1. Create TalkieEnvironment in TalkieKit
2. Add detection logic based on Bundle.main.bundleIdentifier
3. Add convenience accessors for all IDs/schemes

### Phase 3: Update Connection Logic
1. AppLauncher uses TalkieEnvironment
2. EngineClient uses TalkieEnvironment
3. Service monitors use TalkieEnvironment
4. Deep link generation uses TalkieEnvironment

### Phase 4: Test Simultaneous Running
1. Build production → /Applications
2. Run dev from Xcode
3. Verify no collisions
4. Verify correct connections within each environment

---

## Open Questions

1. **Should we have a separate Debug environment or just Dev?**
   - Debug (Xcode with breakpoints) vs Dev (daemon builds)
   - Currently Engine has both, but Talkie/Live don't distinguish

2. **Data storage separation?**
   - Should dev/debug use separate databases?
   - Pros: No risk of corrupting production data
   - Cons: Can't test with real production data

3. **Launchd plist management?**
   - How to keep dev/debug plists in sync with build locations?
   - Auto-generate them? Manual setup in docs?

4. **Visual indicators?**
   - How to tell which environment you're running?
   - Menu bar badge? Window title suffix?

5. **SMAppService for dev builds?**
   - Should dev TalkieLive/Engine use SMAppService login items?
   - Or just manual launch from Xcode?

---

## Testing Scenarios

### Scenario 1: Production Only
- Talkie (prod) → TalkieLive (prod) → Engine (prod)
- All via production bundle IDs and XPC services
- Deep links work: talkie://

### Scenario 2: Dev Only
- Talkie (dev) → TalkieLive (dev) → Engine (dev)
- All via dev bundle IDs and XPC services
- Deep links work: talkie-dev://

### Scenario 3: Production + Dev Simultaneously
- Production: Talkie (prod) → TalkieLive (prod) → Engine (prod)
- Dev: Talkie (dev) → TalkieLive (dev) → Engine (dev)
- No interference between environments
- Each uses its own URLs, XPC, bundle IDs

### Scenario 4: Mixed Environment (Intentional)
- Talkie (prod) + TalkieLive (dev) + Engine (dev)
- TalkieLive uses talkie:// to reach prod Talkie
- But engine.xpc.dev for transcription
- This should "just work" if we make it configurable

---

## Files to Modify

### Talkie
- `macOS/Talkie/Talkie.xcodeproj/project.pbxproj` - Add dev bundle ID config
- `macOS/Talkie/Talkie-Info.plist` - Add dev URL scheme
- `macOS/Talkie/Services/AppLauncher.swift` - Use TalkieEnvironment
- `macOS/Talkie/Services/TalkieServiceMonitor.swift` - Use TalkieEnvironment
- `macOS/Talkie/Services/TalkieLiveMonitor.swift` - Use TalkieEnvironment
- `macOS/Talkie/Services/EngineClient.swift` - Use TalkieEnvironment
- `macOS/Talkie/App/AppDelegate.swift` - Handle dev URL scheme

### TalkieLive
- `macOS/TalkieLive/TalkieLive.xcodeproj/project.pbxproj` - Already has dev config
- `macOS/TalkieLive/TalkieLive/Info.plist` - Add dev URL scheme
- `macOS/TalkieLive/TalkieLive/Services/EngineClient.swift` - Use TalkieEnvironment
- `macOS/TalkieLive/TalkieLive/App/LiveController.swift` - Generate dev URLs
- `macOS/TalkieLive/TalkieLive/Debug/DebugKit.swift` - Update bundle ID checks

### TalkieEngine
- Already has prod/dev/debug XPC services configured
- May need to align bundle ID for debug builds

### Shared (TalkieKit or new package)
- Create `TalkieEnvironment.swift` - Central environment detection

---

## Success Criteria

✅ Can run production Talkie suite from /Applications
✅ Can run dev Talkie suite from Xcode simultaneously
✅ Each environment's components only talk to each other
✅ Deep links work correctly for each environment
✅ No bundle ID or XPC service collisions
✅ Clear visual indication of which environment is running
✅ No manual configuration required (auto-detects environment)
