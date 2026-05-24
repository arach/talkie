# TLK-003 — Keyboard Extension Remediation

**Status**: Draft
**Owner**: TBD

> Critical review of the keyboard extension architecture.
> Goal: identify design flaws, race conditions, unnecessary complexity, and paths to simplification.

## Summary

- **Three overlapping IPC channels** (SharedStore, StateMachine, Bridge) create a reconciliation burden that is the root cause of most bugs. Two of the three should be eliminated.
- **KeyboardViewController at 4,300 lines** is a monolithic god-class that mixes UI construction, dictation orchestration, state polling, slot configuration, and debug logging into a single file with no separation of concerns.
- **The read-modify-write pattern in `DictationSharedStore.update()`** is fundamentally non-atomic across processes: Process A reads, Process B reads (stale), Process A writes, Process B writes (clobbers A's changes). This is not a theoretical concern -- it happens whenever the keyboard and app poll within the same ~50ms window.
- **The `DictationStateMachine` is dead weight.** Every consumer already prefers SharedStore for active phases and only falls back to StateMachine for the `.ready` state. Adding `.ready` to SharedStore's Phase enum would eliminate an entire IPC channel, ~310 lines of code, and the reconciliation logic in `KeyboardActivationView`.
- **Memory pressure is underestimated.** The extension creates three `UIImpactFeedbackGenerator` instances, a `UINotificationFeedbackGenerator`, a `CompactKeyboardView` with ~50 `UIButton` subviews, accent popup infrastructure, multiple `CAGradientLayer` shimmer effects, and the full `VoiceEmojiOverlay` particle system -- all within a 48MB limit that also includes the host app's keyboard infrastructure.

## Critical issues (must fix)

### 1. Non-Atomic Read-Modify-Write in SharedStore

- **Where**: `DictationSharedStore.swift`, lines 63-67 (`update()` method)
- **What**: The `update()` method reads the full JSON blob, mutates it in-place, then writes it back. Between the read and write, the other process can also read-then-write, causing a lost update.
  ```swift
  public func update(_ block: (inout DictationSharedState) -> Void, updatedBy: String? = nil) {
      var state = read()   // <-- Process B reads here too
      block(&state)        // <-- Process B mutates its copy
      write(state, ...)    // <-- Whoever writes LAST wins; the other's changes are lost
  }
  ```
- **Impact**: The keyboard sends a start command (`keyboardRequestStart`), which calls `update()`. Simultaneously, the app's ready-poll calls `updateAppHeartbeat()` (which writes to a separate key, but the main `update()` also reads heartbeats into the blob and writes them back). The app's heartbeat write can clobber the keyboard's start command, making the start request vanish. The user taps dictate and nothing happens.
- **Suggested fix**: Either (a) use separate UserDefaults keys for each field instead of a single JSON blob (eliminates the atomicity issue entirely), or (b) add a CAS (compare-and-swap) mechanism using a version counter that rejects writes from stale reads. Option (a) is strongly preferred -- it also eliminates the JSON encode/decode overhead that the Bridge channel was created to avoid.

### 2. Duplicate SlotConfig Type Definition

- **Where**: `KeyboardViewController.swift`, lines 792-820 (local `SlotConfig` struct) vs. `TalkieMobileKit/KeyboardMode.swift`, lines 43-80 (`SlotConfig`)
- **What**: `KeyboardViewController` defines its own `SlotConfig` struct that is nearly identical to `TalkieMobileKit.SlotConfig`. There is an explicit `convertToLocalSlotConfig()` method (line 1003) that bridges between them. The local version is used for JSON decoding from App Group, creating a type mismatch: data written by the app using `TalkieMobileKit.SlotConfig` must be decoded by the extension using its local `SlotConfig`, and the two types must stay in sync manually.
- **Impact**: If a field is added to `TalkieMobileKit.SlotConfig` but not to the local one (or vice versa), JSON decoding fails silently (returns `nil`), and the slot falls back to defaults with no error message. This has likely already caused debugging confusion.
- **Suggested fix**: Delete the local `SlotConfig` entirely. Import and use `TalkieMobileKit.SlotConfig` directly. The `convertToLocalSlotConfig()` bridge method and the local `SlotContent` enum (which wraps SlotConfig a *third* time) should both be removed.

### 3. Triple State Reset Without Coordination

- **Where**: Multiple locations in `KeyboardViewController.swift` (lines 3004-3008, 3014-3021, 3050-3053, etc.) and `HeadlessDictationService.swift` (lines 337-339, 389, 417-419)
- **What**: Every timeout or error recovery path independently resets all three channels:
  ```swift
  stateMachine.forceReset(reason: "...")
  sharedStore.forceReset(reason: "...", ...)
  bridge.forceReset()
  ```
  There is no single `resetAll()` method. Each channel's `forceReset()` has different semantics (SharedStore preserves capability; Bridge clears everything; StateMachine only clears its own keys). Forgetting one of the three leaves stale state that triggers cascading bugs.
- **Impact**: If any one of the three reset calls is missed (or if a new reset path is added without all three), the channels diverge. This has already happened -- see `cleanupStaleState()` at line 3349-3353, which exists specifically to clean up Bridge state that wasn't properly reset. The existence of this cleanup function is itself evidence of the problem.
- **Suggested fix**: Create a single `DictationCoordinator.resetAll(reason:preserveCapability:)` method that atomically resets all channels. Better yet, eliminate channels 2 and 3 (see Simplification Opportunities).

### 4. UserDefaults.synchronize() Abuse

- **Where**: Throughout `DictationSharedStore.swift`, `KeyboardBridge.swift`, `DictationStateMachine.swift`
- **What**: `defaults?.synchronize()` is called after nearly every write. Apple has deprecated `synchronize()` since iOS 12 -- UserDefaults automatically synchronizes. More critically, `synchronize()` is a blocking disk I/O operation. In the keyboard extension, where responsiveness is paramount, calling it on every heartbeat update (every 1.0s), every audio level update (potentially 60 times/sec), and every state poll (every 0.2s) introduces unnecessary latency.
- **Impact**: On older devices or under memory pressure, `synchronize()` can take 10-50ms. During recording, the keyboard calls `updateKeyboardHeartbeat()` (sync), polls `sharedStore.read()` (sync), and updates UI -- all on the main thread. This can cause dropped frames and janky animations.
- **Suggested fix**: Remove all `synchronize()` calls. UserDefaults automatically coalesces writes. For the rare cases where cross-process freshness is critical (start/stop commands), the Darwin notification (`DictationNotificationCenter`) already provides an out-of-band signal that triggers an immediate read.

## Design concerns (should fix)

### 5. KeyboardViewController Uses ObjC Runtime Hack for URL Opening

- **Where**: `KeyboardViewController.swift`, lines 3148-3166 (`getSharedApplication()`)
- **What**: The extension uses Objective-C runtime introspection (`NSSelectorFromString("sharedApplication")`) to access `UIApplication.shared`, which is explicitly forbidden in keyboard extensions. This works today because Apple doesn't enforce the restriction at runtime, but it relies on a private API path that could break with any iOS update.
- **Impact**: If Apple starts enforcing the restriction (which they've hinted at in WWDC sessions), the deep link fallback path stops working entirely, and users who don't have "instant start" available will be unable to start dictation.
- **Suggested fix**: Document this as a known risk. Consider using `NSExtensionContext.open(_:completionHandler:)` as the sanctioned alternative, though it has its own limitations. At minimum, wrap it in a version check so it can be disabled quickly.

### 6. HeadlessDictationService is ObservableObject but Used as a Singleton

- **Where**: `HeadlessDictationService.swift`, line 17
- **What**: The service inherits from `NSObject` and conforms to `ObservableObject` via `@Published` properties. But it's used as `HeadlessDictationService.shared` -- a singleton. SwiftUI's `@ObservedObject` in `KeyboardActivationView` (line 14) observes it, which works, but the singleton pattern means the `ObservableObject` publisher fires for every observer simultaneously, and the service can never be deallocated or reinitialized.
- **Impact**: The `@Published` properties (`isActive`, `isRecording`, `isInReadyMode`) trigger SwiftUI view updates across all active views. Since this is a singleton, there's no lifecycle management -- if the service enters a bad state, the only recovery is force-quitting the app.
- **Suggested fix**: Migrate to `@Observable` (per the project's stated migration direction in CLAUDE.md). This would also eliminate the `NSObject` inheritance requirement, since `@Observable` doesn't need it for KVO.

### 7. Bridge Heartbeat vs SharedStore Heartbeat Redundancy

- **Where**: `KeyboardBridge.swift` has `setAppReady()` with a 30-second TTL timestamp. `DictationSharedStore.swift` has `updateAppHeartbeat()` / `updateKeyboardHeartbeat()` with separate timestamps. Both serve the same purpose: "is the other process alive?"
- **What**: Two independent liveness detection mechanisms with different thresholds (Bridge: 30s TTL for appReady; SharedStore: 6s for app heartbeat, 12s for keyboard heartbeat). The keyboard checks both -- `isAppHeartbeatFresh()` (SharedStore) AND `bridge.isAppReady()` (Bridge) -- and uses different thresholds for each.
- **Impact**: Confusion about which liveness signal to trust. `instantStartAvailable` (line 441-446) ORs both signals, meaning a fresh Bridge timestamp can override a stale SharedStore heartbeat (or vice versa). This creates edge cases where the keyboard thinks the app is alive when it isn't.
- **Suggested fix**: Consolidate to a single heartbeat mechanism in SharedStore. Remove `appReady` / `appReadyTimestamp` from Bridge. The SharedStore heartbeat already stores the timestamp with the same semantics.

### 8. Warm Recorder Audio File Grows Unbounded

- **Where**: `HeadlessDictationService.swift`, lines 1231-1262 (`startWarmRecorder()`)
- **What**: The warm recorder writes continuously to `warm-<uuid>.m4a` for as long as the app is in ready mode. At 128kbps AAC, this accumulates ~960KB/min or ~57MB/hr. The file is only cleaned up when recording stops (`endWarmSegmentAndTranscribe`) or ready mode exits.
- **Impact**: If the user enables keyboard mode and leaves Talkie in the background for hours, the warm recording file can grow to hundreds of megabytes. This is particularly concerning because the keyboard extension's 48MB limit doesn't apply to the app process, but the file I/O and disk space consumption are still real problems. On low-storage devices, this could trigger iOS storage warnings.
- **Suggested fix**: Implement a rolling window for the warm recorder. Either (a) restart the warm recorder every N minutes with a new file (deleting the old one), or (b) use a circular buffer approach. Option (a) is simpler -- a 5-minute rolling window would cap the file at ~4.8MB.

## Complexity hotspots

### Three IPC Channels -- Can We Consolidate?

The documentation openly acknowledges the overlap: "The keyboard extension and main app communicate through three overlapping channels in App Group UserDefaults. Each exists for a reason, but the overlap creates complexity."

The stated reasons are:
1. **SharedStore** (JSON blob): Rich structured data, epoch validation
2. **StateMachine** (individual keys): Fast reads, `.ready` state
3. **Bridge** (boolean flags): Fastest reads, zero decode overhead

But these reasons don't hold up under scrutiny:

- SharedStore's JSON decode overhead is the result of a design choice (stuffing everything into one blob), not an inherent requirement. Individual UserDefaults keys are just as fast as Bridge's boolean reads.
- StateMachine's `.ready` state could trivially be added to SharedStore's Phase enum.
- Bridge's "fast signals" for UI (LED color, button state) are derived from SharedStore's phase -- they're redundant computations stored separately for performance, but the performance gain is negligible (one JSON decode per 0.2s poll vs. one boolean read).

**Recommendation**: Eliminate StateMachine and Bridge entirely. Move to individual UserDefaults keys for each SharedStore field (eliminating the JSON blob and its atomicity issues). Add `.ready` to the Phase enum. This removes ~860 lines of code and the entire reconciliation layer.

### KeyboardViewController at 4,300 Lines -- What Can Be Extracted?

The file contains at least 8 distinct responsibilities:

| Responsibility | Approximate Lines | Extractable? |
|---|---|---|
| UI construction (LED bar, slot grid, mode knob) | ~800 | Yes -- `KeyboardLayoutBuilder` |
| Mode management (cycling, persistence, tile selector) | ~400 | Yes -- `KeyboardModeManager` |
| Dictation orchestration (recordTapped, polling, result handling) | ~600 | Yes -- `KeyboardDictationController` |
| Slot configuration (loading, defaults per mode, app-specific) | ~300 | Yes -- move to `KeyboardMode` in TalkieMobileKit |
| Compact keyboard management (show/hide, callbacks) | ~200 | Already partially extracted |
| Minimal layout management (show/hide, swipe gestures) | ~200 | Yes -- `MinimalLayoutController` |
| Visual effects (glass, shimmer, glow) | ~200 | Yes -- `KeyboardEffects` |
| Debug logging and diagnostics | ~300 | Yes -- `KeyboardDiagnostics` |
| Voice emoji orchestration | ~150 | Yes -- already partially in `VoiceEmojiOverlay` |

**Recommendation**: Extract at minimum the dictation orchestration into a `KeyboardDictationController` class. This is the highest-risk code (race conditions, timeout management, state transitions) and would benefit the most from isolation and testability.

### State Reconciliation -- Is It Necessary?

The reconciliation logic in `KeyboardActivationView.reconcileState()` exists because SharedStore and StateMachine can diverge. It prefers SharedStore for active phases and StateMachine for idle/ready.

If StateMachine is eliminated (by adding `.ready` to SharedStore's Phase), reconciliation becomes unnecessary. The single source of truth would be SharedStore, and all consumers would read from one place.

## Race conditions & timing issues

### Race 1: Simultaneous Start Command and Heartbeat Update

- **What**: Keyboard calls `keyboardRequestStart()` which does `update()` (read-modify-write). Simultaneously, the app's ready-poll calls `updateAppHeartbeat()` and also `sharedStore.read()` (which reads heartbeats) followed by `update()` in its processing path. If the app's write completes between the keyboard's read and write, the keyboard's start command is lost.
- **Likelihood**: Moderate. The keyboard's poll interval is 0.2s and the app's ready-poll is 1.0s, so there's a ~20% chance of overlap on any given second.
- **Impact**: User taps dictate, nothing happens. No error shown.
- **Fix**: Move to individual UserDefaults keys (eliminates read-modify-write) or use Darwin notifications as the primary command channel (they're already used as hints).

### Race 2: Extension Killed Between Insert and Consume

- **What**: `checkForDictationResult()` calls `insertTextReliably()`, then calls `sharedStore.keyboardConsumeResult()`. If iOS kills the extension between insert and consume, the result is never consumed. On next keyboard load, `loadState()` -> `checkForDictationResult()` finds the result again and inserts it a second time.
- **Likelihood**: Low but non-zero. iOS can kill extensions at any time.
- **Impact**: Duplicate text insertion. User sees the transcription twice.
- **Fix**: Consume the result BEFORE insertion, or mark it as "being inserted" with a separate flag. If insertion fails, re-read the result from the consumed archive.

### Race 3: Start Command During Transcription

- **What**: User taps dictate while a previous transcription is still in progress. `recordTapped()` checks `phase`, which may be `.transcribing`. The code falls through to `showProcessingUI()` (line 3062) and returns -- the new dictation request is silently dropped.
- **Likelihood**: Common in continuous dictation workflows.
- **Impact**: User thinks they've started a new dictation, but the keyboard is still showing processing for the old one. No feedback that the tap was ignored.
- **Fix**: Show explicit "Still processing..." status, or queue the start request to execute after transcription completes.

### Race 4: Bridge and SharedStore Phase Disagree

- **What**: The keyboard checks `bridge.isRecordingInProgress()` as a fast signal in `checkRecordingState()` (line 3398) and `pollForUpdates()` (line 4002). But it also checks `sharedState.phase`. These can disagree because they're written by the app at different times with no transactional guarantee. The code at line 3398-3406 handles this by force-syncing StateMachine state from Bridge, but this can incorrectly transition the state machine to `.recording` when the SharedStore is still `.idle` (the app hasn't written its phase yet).
- **Likelihood**: Happens regularly during the arming-to-recording transition, especially with the warm recorder path where the app writes Bridge state before SharedStore state.
- **Impact**: Brief UI flicker -- keyboard shows recording state, then flips back to arming when the next poll reads the actual SharedStore phase. Mostly cosmetic but contributes to perceived instability.
- **Fix**: Stop reading Bridge for state determination. Use SharedStore as the single source of truth. Bridge should only be used for fire-and-forget signals (start requested, stop requested).

### Race 5: `bumpEpoch` at Init Invalidates In-Flight Commands

- **Where**: `HeadlessDictationService.swift`, line 117
- **What**: `HeadlessDictationService.init()` calls `sharedStore.bumpEpoch(reason: "HeadlessDictationService init")`. This increments the epoch, which invalidates any command whose epoch doesn't match. If the keyboard sent a start command just before the app launched (which is the normal deep-link flow), the epoch bump causes `acceptStartCommandIfPresent()` to reject the command because `command.epoch != state.epoch`.
- **Likelihood**: Happens on every deep-link-triggered app launch.
- **Impact**: The keyboard's start command is silently rejected. The code recovers via the `handleDictationRequest()` path which creates a new session, but this adds 1-2 seconds of unnecessary delay and duplicates the start logic.
- **Fix**: Don't bump epoch on init. Epoch should only be bumped on explicit force-reset scenarios. The init is already a clean slate -- there's no zombie command to guard against.

## Simplification opportunities

### Can StateMachine Be Removed Entirely?

**Yes.** `DictationStateMachine` provides two things SharedStore doesn't:

1. The `.ready` state
2. Transition validation (e.g., can't go from `.idle` to `.stopping`)

Adding `.ready` to `DictationSharedState.Phase` is trivial. Transition validation is currently advisory (it logs warnings but proceeds anyway -- line 91-98), so it provides no safety guarantee and could be removed or moved into SharedStore.

Every call site that reads `stateMachine.state` also reads `sharedStore.read().phase` and reconciles them. Removing StateMachine would eliminate: 308 lines of `DictationStateMachine.swift`, the `reconcileState()` function in `KeyboardActivationView`, duplicate state writes in `HeadlessDictationService` (which currently writes to both StateMachine and SharedStore for every transition), and the "legacy fallback" path in `checkForDictationResult()` (lines 3254-3283).

### Can Bridge Signals Be Folded Into SharedStore?

**Partially.** Bridge serves three purposes:

1. **Fast boolean signals** (`isRecording`, `stopRequested`, `startRequested`, `appReady`): These duplicate SharedStore's phase and command fields. Fold them in.
2. **Audio level** (`audioLevel`): High-frequency writes (up to 60/s) that don't belong in a JSON blob. Keep this as a standalone UserDefaults key.
3. **Slot configuration**: Unrelated to dictation IPC. Keep in Bridge or move to a dedicated `KeyboardConfigStore`.
4. **Mode persistence** (`lastSelectedModeId`): Unrelated to dictation IPC. Keep.

After folding signals, Bridge becomes a grab-bag of configuration storage (slots, modes, layout). Rename it to `KeyboardConfigBridge` and remove all dictation-related methods.

### Can the 4,300-Line Controller Be Broken Up?

**Yes, and it should be.** The minimum viable extraction is:

1. **`KeyboardDictationController`**: Owns `recordTapped()`, `pollForUpdates()`, `checkForDictationResult()`, `checkRecordingState()`, `startPolling()`, `stopPolling()`, heartbeat management, and all SharedStore/Bridge interaction for dictation. ~600 lines. This is the highest-value extraction because it isolates the most complex and bug-prone logic.

2. **`KeyboardSlotManager`**: Owns slot configuration loading, mode-to-slot mapping, per-app overrides. ~300 lines. Currently deeply tangled with the view layer.

3. **`KeyboardLayoutBuilder`**: Owns `createLEDDisplayBar()`, `createSlotGridWithDictate()`, `createModeKnob()`. ~500 lines. Pure UIKit construction that doesn't need access to dictation state.

### Can Polling Be Replaced?

**Partially.** Darwin notifications (`DictationNotificationCenter`) already provide cross-process signals. The code already uses them (`handleStateSignal`, `handleCommandSignal`). But the notifications are "something changed" hints with no payload -- the receiver still has to read UserDefaults to know *what* changed.

The polling exists because:
1. Darwin notifications can be lost (iOS doesn't guarantee delivery).
2. The extension needs to catch up on state changes that happened while it was suspended.

**Recommended approach**: Use Darwin notifications as the primary trigger for reads (react immediately), but keep a slow background poll (every 2-5 seconds) as a fallback for missed notifications. The current 0.2s poll interval is unnecessarily aggressive -- it means 5 full JSON decode cycles per second during recording, which is wasteful.

## What's done well

### Warm Recorder Design
The warm recorder is genuinely clever. Keeping a continuously-running `AVAudioRecorder` and extracting segments via `AVAssetExportSession` achieves <100ms start latency without an app switch. The implementation correctly handles the tricky "start new warm recorder immediately after extracting a segment" pattern (line 1346), which is essential for continuous dictation. The capture of `sessionId` before async transcription (line 1390) correctly prevents a new recording from clobbering the old session.

### Timeout Safety Nets
The system has comprehensive timeout coverage. Every phase has an escape hatch: arming times out at 8-10s, recording at 60s, stopping at 15s, stale states at 30s. The keyboard's `pollForUpdates()` checks these consistently. This prevents the user from getting permanently stuck, which is critical for a keyboard extension where "force quit" isn't intuitive.

### Heartbeat Protocol
The dual-heartbeat system (keyboard heartbeat at 1.0s, app heartbeat refreshed during polls) is a solid approach to liveness detection in a cross-process architecture. The asymmetric thresholds (6s for app, 12s for keyboard) correctly account for the fact that the keyboard extension is more likely to be killed by iOS than the app.

### Performance Instrumentation
The `PerfTrace` wrapper around `os_signpost` (lines 18-56 of KeyboardViewController) is lightweight and well-designed. It provides real Instruments-compatible traces without requiring any third-party dependency. The "fast path" design in `viewDidLoad()` -- render UI immediately, defer state loading to after first paint -- shows genuine attention to keyboard extension startup performance.

### Command Protocol with Epoch Validation
The V2 command protocol in SharedStore (command + ack + epoch) is a well-designed IPC primitive. The epoch counter prevents zombie commands from surviving app crashes. The TTL on commands (10s for start, 15s for stop) prevents stale commands from being processed after long delays. The session ID tracking prevents cross-session confusion.

### Mode Persistence with TTL
Saving the last selected keyboard mode with a 24-hour TTL (line 181, `modePersistenceMaxAge`) is a good UX decision. Without it, the keyboard would reset to FN mode every time the extension reloads, which happens frequently. The TTL prevents infinitely stale mode selections.

### Darwin Notification Integration
Using `CFNotificationCenterGetDarwinNotifyCenter()` for cross-process notifications is the correct approach for iOS extensions. The implementation in `DictationNotifications.swift` is clean and handles the C callback bridge properly. Using this as a supplement to polling (rather than a replacement) correctly accounts for the unreliable delivery guarantees of Darwin notifications.
