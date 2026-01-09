# iOS → Mac Audio Resilience Plan

**Problem**: The current system is fragile with too many failure points and no self-recovery.

## Current Chain (5 potential failure points)

```
iOS App
   ↓ HTTP (can fail: network, timeout)
TalkieServer (TypeScript :8765)
   ↓ HTTP (can fail: IPv4/6, connection refused, timeout)
Talkie (Swift :8766)
   ↓ XPC (can fail: not connected, invalidated, wrong service name)
TalkieLive
   ↓ Accessibility (can fail: no permission, wrong app, Enter not received)
Terminal
```

## Fixes Needed

### 1. Auto-Start Bridge on Talkie Launch
**File**: `macOS/Talkie/App/StartupCoordinator.swift`

Add Bridge auto-start as Phase 4:
```swift
// Phase 4: Background services
Task {
    await BridgeManager.shared.startBridge()
}
```

### 2. XPC Auto-Reconnect
**File**: `macOS/Talkie/Services/XPCServiceManager.swift`

Current: XPC connection invalidates and stays dead.
Fix: Add heartbeat + auto-reconnect:
```swift
private func setupHeartbeat() {
    Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        Task { @MainActor in
            if self?.connectionInfo.state == .disconnected {
                await self?.connect()
            }
        }
    }
}
```

### 3. TalkieServer HTTP Retry (Swift side)
**File**: `macOS/Talkie/Services/TalkieServer.swift`

Current: Single attempt to connect to TalkieLive XPC.
Fix: Retry XPC connection with backoff before failing.

### 4. Better Error Messages
Current: "TalkieLive not connected" (not helpful)
Fix: Show what to do:
```
"TalkieLive not connected. Check:
1. TalkieLive is running (menu bar icon)
2. Same build environment (both from Xcode or both from /Applications)
3. Accessibility permission granted"
```

### 5. Status Dashboard
**File**: `macOS/Talkie/Views/Settings/BridgeStatusView.swift` (new)

Show real-time status:
```
┌─────────────────────────────────────┐
│ iOS → Mac Audio Status              │
├─────────────────────────────────────┤
│ TalkieServer (TS)  ✅ Running :8765 │
│ Talkie HTTP        ✅ Running :8766 │
│ TalkieLive XPC     ❌ Disconnected  │
│ Terminal Match     ⚠️ No context    │
│ Last Message       "Hello" 2m ago   │
└─────────────────────────────────────┘
        [Reconnect All] [View Logs]
```

### 6. Health Check Endpoint
**File**: `macOS/Talkie/Services/TalkieServer.swift`

Add `/health/full` that checks entire chain:
```json
{
  "talkieHttp": { "status": "ok", "port": 8766 },
  "talkieLiveXpc": { "status": "error", "error": "not connected" },
  "terminalContext": { "status": "ok", "app": "iTerm2", "session": "..." },
  "lastMessage": { "text": "Hello", "ago": "2m", "success": true }
}
```

### 7. Enter Key Reliability
**File**: `macOS/TalkieLive/TalkieLive/Services/TextInserter.swift`

Current: CGEvent may not reach app.
Fix:
1. Ensure app is frontmost before Enter
2. Use AppleScript for more terminals (not just iTerm2)
3. Add verification (check if cursor moved to new line)

### 8. Graceful Degradation
If Enter fails, don't lose the text:
- Keep text in clipboard
- Show notification: "Text inserted but Enter failed. Press Cmd+V then Enter."

## Priority Order

1. **Auto-start Bridge** - Prevents "port 8766 not listening" after restart
2. **XPC auto-reconnect** - Prevents "TalkieLive not connected"
3. **Status dashboard** - User can see what's broken
4. **Better error messages** - User knows what to fix
5. **Enter key reliability** - The final mile works

## Quick Wins (Can do now)

1. Add Bridge auto-start to StartupCoordinator
2. Add XPC heartbeat/reconnect
3. Improve error messages with actionable steps
