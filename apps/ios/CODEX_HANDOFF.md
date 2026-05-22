# Codex Handoff — iOS Next Rebuild

Each surface listed below was painted by Claude on `feat/ios-shell-phase-0`
and ships with a **mocked store** or **declared contract**. Codex picks up
the implementation. Every item names the paint-side file (where the
contract is declared / consumed) and the expected impl location.

Read this with [`design/studio/components/studies/CompletionMap.tsx`](../../design/studio/components/studies/CompletionMap.tsx)
open — it's the milestone map; this is the implementation backlog.

---

## ✅ Done — for the record

| Item | Commit | What landed |
|---|---|---|
| M02 OCR confidence | `e7b9881` | Real `VNRecognizedText.confidence` per chunk; mock removed |
| M04 FeedbackService | `2a1d91b` | POST to `api.usetalkie.com/api/report` + app/iOS/device meta + last 50 LogStore entries |
| M03 AICredentialStore | `cae9706` | Keychain-backed per-provider service identifier; reactive `setProviderIDs` |
| M05 WorkflowsStore | `802e043` | JSON-persistent `templates/schedules/runs`; promoted models out of view |
| Bridge approval fix | `ccb40f6` | Pending-approval monitor reconciles `status`/`awaitingPairingApproval` after Mac approval |
| M09 Deck mirror wiring | `54708c8` | Companion events ship `snapshot.commandDeck`; iOS taps call `/companion/trigger` |

---

## Still open

### M3 · Integration polish

#### P01 — ReadAloud real range callback
- **Contract:** `AVSpeechSynthesizerDelegate.speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)` drives chunk highlight.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/ReadAloudNext.swift` — currently uses a local timer shim to advance the highlight.
- **Impl location:** Likely `Services/ReadAloudPlayer.swift` (new). Owns the `AVSpeechSynthesizer` + delegate; publishes `currentRange: NSRange` for the view.

#### P02 — AskAI multi-turn persistence
- **Contract:** Session state (turns + presets + last model) survives surface close + reopen.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/AskAINext.swift` — `AskAISession` is in-memory only.
- **Impl location:** Add `AskAISessionStore` (new, in `Services/`) backed by JSON on disk or Core Data. `AskAISession.init` reads, `send()` writes.

### M2 follow-up

#### W01 — ReadAloudPlayer source binding
- **Contract:** `ReadAloudPlayer.bind(source:)` consumes `AppShellRouter.shared.pendingReadAloudSource` on appear, then clears it.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/AppShellNext.swift` — `@Published var pendingReadAloudSource: ReadAloudSource?` set by `openReadAloud(source:)`.
- **Impl location:** Inside the same `ReadAloudPlayer` you build for P01. Bundle with P01.

### M5 · New scope

#### N05 — WorkspaceStore (xl/high risk)
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
  1. iCloud zone (rebuild `NSPersistentCloudKitContainer` with new container identifier)
  2. Core Data store (separate `.sqlite` per workspace)
  3. `BridgeManager` pairing (per-workspace pairing list)
- **Risk:** Atomic store swap is the hard part. Could use a swap-then-restart UX since `UIApplication.terminate()` isn't allowed.

#### N06 — SyncConflictStore
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

### M6 · System polish

#### S02 — First non-English locale
- **State:** `apps/ios/Talkie iOS/Resources/Localizable.xcstrings` is the modern String Catalog; Xcode auto-extracts on build.
- **Codex task:**
  1. Open Localizable.xcstrings in Xcode → it'll re-extract all `LocalizedStringKey` strings.
  2. Review extracted entries — channel labels like `"TALKIE · SETTINGS"` and `"· DICTATIONS"` are brand chrome and should stay untranslated.
  3. Add a first non-English locale (Spanish or French lowest-risk).

#### S03 — Instruments cold-launch trim
- **State:** `apps/ios/Talkie iOS/App/talkieApp.swift` logs phase telemetry on init:
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

#### S04 — NetworkReachability observer
- **Contract:** `NetworkReachability` shared observer publishing `.offline` / `.ok`.
- **Paint side:** `apps/ios/Talkie iOS/Views/Next/AskAINext.swift` — `networkStatus` only handles `.requestFailed` via `session.errorMessage`. The `.offline` branch on `NetworkStatusBanner` isn't fed.
- **Impl location:** `Services/NetworkReachability.swift` (new). `NWPathMonitor` wrapped in an `@MainActor` ObservableObject. AskAI subscribes via `@StateObject` and OR's into the `networkStatus` derivation.
- **Reuse:** `Views/Next/NetworkStatusBanner.swift` is the shared component — other surfaces (ReadAloud cloud TTS, ConnectionCenter) can subscribe similarly.

---

## Workflow rules (recap)

From saved Talkie workflow memory:
- Claude declares **contract + paints**. Codex builds **infrastructure**.
- iOS views should **not** contain `@StateObject` for new services, gesture-to-service bridges, or new singleton wiring — those are Codex.
- When porting a donor view, **read the donor first** (`git show e48c49c9^:path` for the Clerk-teardown drop).
- Pass `permissionProfile: "workspace-write"` when spawning Codex agents that need to write.

## Branch state

`feat/ios-shell-phase-0` is 26+ commits ahead of `master`. All surfaces build and launch on iPhone 17 Pro Max simulator. Active codex card on this branch: `@talkie-drift-investigator` (codex harness, codex_app_server).
