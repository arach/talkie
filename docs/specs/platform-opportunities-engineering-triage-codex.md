# Platform Opportunities Engineering Triage

**Date**: 2026-06-04  
**Owner lane**: Codex engineering triage  
**Sibling lane**: Talkie Scout product/spec synthesis (`docs/specs/platform-opportunities-review-talkie.md`)

This memo captures the current-code review behind the platform improvement split. It is intentionally scoped to what is live in this checkout, because several older Claude review findings have already been partially implemented.

## Task Split

### Codex Lane

1. Bridge hardening verification and targeted fix.
2. Action Workbench Phase 1a readiness check.
3. Agent Home runtime/activity boundary readiness check.
4. Fold Talkie's product/spec memo into a sequenced platform plan.

### Talkie Lane

1. Product/spec synthesis across TLK-020, TLK-021, TLK-022, TLK-023, TLK-024, TLK-026, and the Claude review notes.
2. Identify dependencies and sequencing across Agent Home, Action Workbench, media sidecars, visual context, and Scopes.
3. Produce a concise roadmap memo for Studio/spec review.

## Current-Code Findings

### Bridge Security

The older concern that WebSocket streams ignored sealed-frame negotiation appears fixed in current source:

- iOS appends `encStream=2` on screen and companion-event WebSocket requests when encrypted streams are required.
- iOS fail-closes encrypted stream payload handling through `openStreamFrame`.
- macOS bridge routes prepare a frame sealer through `prepareWsFrameSealer`.

The remaining live hardening gap was narrower: saved reconnects applied the per-Mac encryption pin before `connect()`, but QR/nearby pairing and credential-refresh pairing connected before checking any existing pin. A re-pair path that resolves to an already pinned Mac should require encryption before that initial pairing connect, then pin again after an approved encrypted pairing.

Implemented in `apps/ios/Talkie iOS/Bridge/BridgeManager.swift`:

1. QR/nearby pairing now resolves an existing paired Mac by active key, host/port, or stored server public key before connecting.
2. Pairing and credential-refresh pairing apply `client.setEncryptionRequired(existingPinned)` before their initial `connect()`.
3. Approved encrypted pairings pin the resolved/upserted Mac ID.

Verified with a per-run DerivedData directory under `~/Library/Caches/codex-builds/`:

```bash
xcodebuild -project apps/ios/Talkie-iOS.xcodeproj -scheme Talkie \
  -destination "platform=iOS Simulator,name=iPhone 17e" \
  -derivedDataPath "$DERIVED_DATA_DIR" build
```

### Action Workbench

Action Workbench Phase 1a is already substantially present:

- `ActionRunModel`, `ActionEventModel`, `ActionInputPackage`, and `ActionSubjectRef` are in the macOS target.
- Migration `v28_action_workbench` creates action run, subject, input package, and event tables with indexes.
- `LocalRepository` has create/fetch/append/update methods for action runs and events.
- `ActionWorkbenchView` is mounted on the Actions route.
- Workflow test panels and screenshot context-menu workflows already write `ActionRunModel` records and event timelines.

The next work is not "create the platform"; it is to broaden producers and tighten operator controls:

1. Add replay/rerun affordances that reuse `ActionInputPackage` instead of forcing users back through the original surface.
2. Ensure all action-origin surfaces write ActionRun records, not only workflow test and screenshot paths.
3. Add filtering/search and direct navigation to a run from workflow/screenshot completion notifications.
4. Decide whether agent commands should become ActionRuns now or wait until Agent Home's runtime boundary is stabilized.

### Agent Home Runtime Boundary

Agent Home and Walkie have the most concrete runtime-boundary issue:

- `TalkieAgentRuntime` implements a persistent Node sidecar with stdin/stdout request multiplexing, restart, and backoff.
- The UI paths still call `WalkieNodeRuntimeClient`, which spawns the Node runtime per request and polls status every few seconds.
- `AgentHomeActivityStore` invokes and refreshes via `WalkieNodeRuntimeClient.shared`.
- `WalkieSession` also waits for completion by polling `WalkieNodeRuntimeClient.shared.status()`.

Recommended Codex task: either route `WalkieNodeRuntimeClient` through `TalkieAgentRuntime.shared.request(...)` or remove the unused persistent sidecar. Keeping both creates a misleading architecture and leaves Agent Home paying process startup cost on status refresh/invoke paths.

### Sequencing Guidance

Talkie's product/spec memo owns the cross-feature sequencing. The engineering view agrees with its critical path:

1. Treat Bridge downgrade hardening as P0 done pending review and spec invariant updates.
2. Stabilize Agent Home runtime persistence before expanding agent-command ActionRuns.
3. Use Action Workbench as the shared observability layer once runtime activity records are stable.
4. Connect media sidecar and visual-context consumers through ActionRun inputs instead of inventing separate result histories.
