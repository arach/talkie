# Codex Handoff — iOS Next Rebuild

Each surface listed below was painted by Claude in `feat/ios-shell-phase-0`
and ships with a **mocked store** or **declared contract**. Codex picks up
the implementation. Every item names the paint-side file (where the
contract is declared / consumed) and the expected impl location.

Read this with [`design/studio/components/studies/CompletionMap.tsx`](../../design/studio/components/studies/CompletionMap.tsx)
open — it's the milestone map; this is the implementation backlog.

---

## M3 · Integration polish (queued)

### P01 — ReadAloud real range callback
- **Contract:** `AVSpeechSynthesizerDelegate.speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)` drives chunk highlight.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/ReadAloudNext.swift` — currently uses a local timer shim to advance the highlight.
- **Impl location:** Likely `Services/ReadAloudPlayer.swift` (new). Owns the `AVSpeechSynthesizer` + delegate; publishes `currentRange: NSRange` for the view.
- **Why blocked:** Service bridge / `@StateObject` wiring is Codex-side per the rebuild-cascade workflow rule.

### P02 — AskAI multi-turn persistence
- **Contract:** Session state (turns + presets + last model) survives surface close + reopen.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/AskAINext.swift` — `AskAISession` is in-memory only.
- **Impl location:** Add `AskAISessionStore` (new, in `Services/`) backed by JSON on disk or Core Data. `AskAISession.init` reads, `send()` writes.
- **Notes:** Keep the session model unchanged; just thread persistence through it.

---

## M2 · Entry points (one item left)

### W01 follow-up — ReadAloudPlayer source binding
- **Contract:** `ReadAloudPlayer.bind(source: ReadAloudSource)` consumes `AppShellRouter.shared.pendingReadAloudSource` on appear, then clears it.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/AppShellNext.swift` — `@Published var pendingReadAloudSource: ReadAloudSource?` set by `openReadAloud(source:)`.
- **Impl location:** Inside the same `ReadAloudPlayer` you build for P01. View calls `.task { player.bind(router.pendingReadAloudSource); router.pendingReadAloudSource = nil }`.

---

## M4 · Missing surfaces (paint done, infra needed)

### M02 — OCR confidence (real Vision values)
- **Contract:** Replace `mockChunks(from:)` with real `VNRecognizedText.confidence` per observation.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/CameraCaptureNext.swift` — `processCapturedPhoto` calls `ScreenshotOCRService.extractText` then synthesizes mock chunks.
- **Impl location:** `Services/ScreenshotOCRService.swift` should return `[OCRChunk]` directly (already a paint-side struct).
- **Drop-in:** Once Vision returns real confidence, delete `CameraCaptureNextModel.mockChunks(from:)`.

### M03 — AI Credential Store
- **Contract:**
  ```swift
  @MainActor final class AICredentialStore: ObservableObject {
      static let shared: AICredentialStore
      @Published private(set) var setProviderIDs: Set<String>
      func key(for providerID: String) -> String?
      func set(_ key: String, for providerID: String) throws
      func clear(_ providerID: String) throws
  }
  ```
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/AICredentialsNext.swift` — keys live in `@State var keys: [String: String]`.
- **Impl location:** `Services/AICredentialStore.swift` (new). Keychain-backed, per-provider `kSecAttrService` like `"to.talkie.aikey.openai"`.
- **Cutover:** Replace `@State private var keys` with `@ObservedObject private var credentials = AICredentialStore.shared` and update `keys[provider.id]` / `keys.removeValue` to `credentials.key(for:)` / `credentials.clear(_:)`.

### M04 — Feedback submit
- **Contract:** `FeedbackService.submit(description: String, contact: String?) async throws -> String` returning the report ID.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/FeedbackNext.swift` — `submit()` sleeps 0.8s then returns a fake `FB-XXXXXXXX`.
- **Impl location:** `Services/FeedbackService.swift` (new). POSTs to `api.usetalkie.com/feedback` (or wherever) with `description`, `contact`, `appVersion`, `iosVersion`, `deviceModel`, `logDump` (call `LogStore.shared.recentEntries` if it still exists).
- **Returns:** server-assigned report ID string.

### M05 — Workflows Store
- **Contract:**
  ```swift
  @MainActor final class WorkflowsStore: ObservableObject {
      static let shared: WorkflowsStore
      @Published private(set) var templates: [WorkflowTemplate]   // built-ins + user
      @Published private(set) var schedules: [WorkflowSchedule]
      @Published private(set) var runs: [WorkflowHistoryEntry]
      func run(template: WorkflowTemplate, on target: WorkflowTarget?) async
      func schedule(_ template: WorkflowTemplate, cadence: WorkflowCadence)
      func unschedule(_ id: String)
  }
  ```
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/WorkflowsNext.swift` — `@State` arrays seeded from `builtInTemplates` / `mockRuns`. Run is a 0.6s sleep that appends a successful `WorkflowHistoryEntry`.
- **Impl location:** `Services/WorkflowsStore.swift` (new). Persist `runs` to Core Data; built-in templates are static; schedules need a `BGAppRefreshTask` hook (already registered in `talkieApp.registerBackgroundTasks`).
- **Reuse:** The paint-side structs `WorkflowTemplate`, `WorkflowSchedule`, `WorkflowHistoryEntry` are fine to keep; promote them out of `WorkflowsNext.swift` into the model layer.

---

## M5 · New scope (paint done, infra needed)

### N05 — Workspace Store
- **Contract:**
  ```swift
  @MainActor final class WorkspaceStore: ObservableObject {
      static let shared: WorkspaceStore
      @Published private(set) var identities: [WorkspaceIdentity]
      @Published private(set) var activeID: String?
      func activate(_ identity: WorkspaceIdentity) async throws
  }
  ```
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/WorkspaceSwitcherNext.swift` — `@State var identities = mockIdentities` + a 0.45s mock activate.
- **Impl location:** `Services/WorkspaceStore.swift` (new). Identities come from enumerating ASAuthorization records in Keychain. `activate(_:)` must atomically swap:
  1. iCloud zone (rebuild `NSPersistentCloudKitContainer` with new container identifier),
  2. Core Data store (separate `.sqlite` per workspace),
  3. `BridgeManager` pairing (per-workspace pairing list).
- **Risk:** xl/high — atomic store swap is the hard part. Use a launch-only swap if simpler (`UIApplication.terminate()` is not allowed; spin up a swap-then-restart UX).

### N06 — Sync Conflict Store
- **Contract:**
  ```swift
  @MainActor final class SyncConflictStore: ObservableObject {
      static let shared: SyncConflictStore
      @Published private(set) var pending: [SyncConflict]
      func resolve(_ conflict: SyncConflict, choice: SyncConflict.Resolution) async
  }
  ```
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/SyncConflictNext.swift` — `@State var pending = mockPending`.
- **Impl location:** `Services/SyncConflictStore.swift` (new). Hook into `NSPersistentCloudKitContainer`'s import notifications + `CKModifyRecordsOperation.modifyRecordsResultBlock` — when a `CKError.serverRecordChanged` arrives, surface both sides as a `SyncConflict`. `resolve(_:choice:)` writes the chosen `CKRecord` back via another `CKModifyRecordsOperation`.

---

## M6 · System polish

### S02 — Localization (first locale)
- **State:** `apps/ios/Talkie iOS/Resources/Localizable.xcstrings` is the modern String Catalog. Xcode auto-extracts `Text("...")` literals on each build.
- **Codex task:**
  1. Open Localizable.xcstrings in Xcode → it'll re-extract all `LocalizedStringKey` strings from the codebase.
  2. Review the extracted entries — channel labels like `"TALKIE · SETTINGS"` and `"· DICTATIONS"` are brand chrome and should stay untranslated (mark them `extractionState: manual` with `state: stale` to ignore).
  3. Add a first non-English locale (suggest Spanish or French as lowest-risk).
  4. Translations can be drafted via Apple's localization helper or a translation service.

### S03 — Launch performance (Instruments)
- **State:** `apps/ios/Talkie iOS/App/talkieApp.swift` now logs phase telemetry on init:
  ```
  📱  · bg-task-register: +Xms (t=Xms)
  📱  · app-settings-load: +Xms (t=Xms)
  📱  · workflow-mirror-sync: +Xms (t=Xms)
  📱  · theme-override-check: +Xms (t=Xms)
  📱 App.init: Xms
  📱 Database loaded in Xms
  📱 BOOT COMPLETE in Xs
  ```
- **Codex task:** Run a cold-launch Instruments trace (Time Profiler + App Launch template) and trim the slowest phase. Likely candidates: `synchronizePinnedWorkflowMirror` (sync work in init) and the 180ms intentional splash hold (`mainInterfaceVisible` guard in `body.task`).

### S04 — Offline reachability observer
- **Contract:** `NetworkReachability` shared observer publishing `.offline` / `.ok`.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/AskAINext.swift` — `networkStatus` only handles `.requestFailed` via `session.errorMessage`. The `.offline` branch on `NetworkStatusBanner` isn't fed.
- **Impl location:** `Services/NetworkReachability.swift` (new). `NWPathMonitor` wrapped in an `@MainActor` ObservableObject. AskAI subscribes via `@StateObject` and OR's into the `networkStatus` derivation.
- **Reuse:** `Views/Next/NetworkStatusBanner.swift` is the shared component — other surfaces (ReadAloud cloud TTS, ConnectionCenter) can subscribe similarly.

---

## Companion · Mac Command Deck mirror (new, M09)

### Bridge payload extension + `DeckMirrorStore` wiring
- **Paint side:**
  - `apps/ios/Talkie iOS/Models/DeckBoardSnapshot.swift` — declares `DeckBoardSnapshot { spaces: [DeckSpace], activeSpaceID }`, `DeckSpace { id, title, tiles: [DeckTile] }`, `DeckTile { id, slotID?, label, icon, hint? }`, plus `@MainActor final class DeckMirrorStore: ObservableObject` with `set(board:)`, `fire(slotID:)`, `firingSlotID`, `lastErrorMessage`.
  - `apps/ios/Talkie iOS/Views/Next/DeckMirrorNext.swift` — fully rendered grid + Space tabs reading from `DeckMirrorStore.shared.board`.
  - `apps/ios/Talkie iOS/Views/Next/HomeNextView.swift` — AmbientStatusRow grew a 4th "Mac deck" pixel (renders only when `bridgeManager.isPaired`).
  - Router entry: `Surface.deck`, `openDeck()`, `--deck` launch arg.
- **Codex impl tasks:**
  1. Extend the macOS companion event payload to ship the resolved shortcut board (spaces + tiles + display info). The slot-ID catalog is at `apps/macos/Talkie/Services/TalkieSettingsConfiguration.swift::defaultLegacyShortcutSlots`. The board structure is `ShortcutBoard` + `defaultDeviceShortcutBoard()` in the same file.
  2. In `BridgeManager` (likely in the existing `companionEventTask` / `companionEventSocket` handlers), when an event arrives with deck state, decode into `DeckBoardSnapshot` and call `await DeckMirrorStore.shared.set(board: snapshot)` on the main actor.
  3. Replace `DeckMirrorStore.fire(slotID:)` body — currently a 350ms paint-side mock — with a real call into `BridgeClient` that dispatches the matching slot ID. The receiving handlers on macOS are at `apps/macos/Talkie/Services/TalkieServer.swift` (search `case "deck-up":`, `case "talkie-dictate":`, etc.). On send failure, set `DeckMirrorStore.shared.lastErrorMessage`.
  4. Clear the mock board from `DeckMirrorStore.init` once the bridge is shipping real snapshots — until then leave the mock so the paint state isn't blank.
- **Capability:** Mac already advertises `commandDeck` in `NearbyBridgeAdvertiser.swift`; iOS doesn't yet read it but a `BridgeManager.macSupportsCommandDeck` boolean derived from the capabilities string would let Home hide the Deck pixel for older Mac builds.

## Workflow rules (recap)

From the saved Talkie workflow memory:
- Claude declares **contract + paints**. Codex builds **infrastructure**.
- iOS views should **not** contain `@StateObject` for new services, gesture-to-service bridges, or new singleton wiring — those are Codex.
- When porting a donor view, **read the donor first** (`git show e48c49c9^:path` for the Clerk-teardown drop).
- Pass `permissionProfile: "workspace-write"` when spawning Codex agents that need to write.

## Branch state at handoff

`feat/ios-shell-phase-0` is 17 commits ahead of `master`. All surfaces build and launch on iPhone 17 Pro Max simulator. Active codex card on this branch: `@talkie-drift-investigator` (codex harness).
