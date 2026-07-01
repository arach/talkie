# Agent Home — Scout / HudsonKit "maximum adoption" review

**Date:** 2026-06-29
**Scope:** TalkieAgent Agent Home (`AgentHomeView` / `AgentHomeActivityStore` / node runtime / `AgentVoice*`)
**Question:** Should Agent Home move toward full parity / maximum adoption of Scout + HudsonKit native UI, and if so how — without duplicating Talkie's voice engine?
**Method:** First-principles review + direct inspection of four trees (TalkieAgent, TalkieKit, openscout/apps/macos, hudson/HudsonKit). No files edited; this report is the only new file.

---

## TL;DR / recommendation

**Do not invert the dependency by pulling HudsonKit/Scout native UI *into* TalkieAgent.** The premise of the ask ("depend directly on HudsonKit/Scout, stronger than visual borrowing") runs against a deliberate, documented architecture decision that is already mostly executed:

- TalkieAgent was **intentionally de-Hudson'd**. The shell is built on TalkieKit's `OpsKit`/`AgentOpsShell`, and the header states it outright: *"nothing Hudson, nothing copied"* (`AgentOpsShell.swift:7`).
- The intended dependency arrow is **Talkie → Hudson (donate up)**, not Hudson → Talkie. TalkieKit's sidebar primitives are explicitly written as **donation targets** for HudsonKit per **ADR-002** (`SidebarColumns.swift:20`, plus `TODO(donation)` markers in `SidebarLayout.swift:20`, `SidebarLabel.swift:17`, `SidebarRow.swift:18`).
- The single highest-value Scout UI surface for a chat/agent home — `ScoutSharedUI` — is **welded to a duplicate voice/transcription stack** (`HudsonVoice → VoxEngine + Speech + AVFoundation`). Adopting it directly violates the "keep Talkie's voice engine, don't duplicate" constraint.

**"Maximum adoption" should therefore be redefined as API/parity alignment, not linkage** (details in §1). The only HudsonKit targets that are genuinely safe to *link* are `HudsonUI` + `HudsonShell` (clean leaf libs), and even those create a second design-token system that collides with `OpsKit` and undermines the donation ADR. Linking Scout native UI is not recommended at all while its UI layer transitively pulls VoxEngine.

---

## Evidence map (where things live)

| Thing | Path | Key facts |
|---|---|---|
| Agent Home view | `apps/macos/TalkieAgent/TalkieAgent/Views/Home/AgentHomeView.swift` | imports only `SwiftUI` + `TalkieKit` (`:17-18`). No Hudson/Scout imports anywhere in target. |
| Activity store | `…/Views/Home/AgentHomeActivityStore.swift` | imports `Foundation/AppKit/SwiftUI/TalkieKit` (`:6-9`). Owns status normalization, continuation, wire-trace, live rows. |
| Voice session | `…/Views/AgentVoice/AgentVoiceSession.swift` | transcribes via `EngineClient.shared.transcribe()` (`:285-302`); orchestrates via `AgentVoiceOrchestrator.shared`. Talkie-native, no agent-framework imports. |
| Node runtime | `…/Runtime/node/index.mjs` | job store, status mapping (`:409-430`,`:715-737`), default effort `medium` (`:42-46`), live branch labels/continuation (`:636-671`). |
| Shared primitives | `apps/macos/TalkieKit/Sources/TalkieKit/UI/OpsKit.swift` | full token system + primitives (`OpsInk/OpsSpacing/OpsRadius/OpsType` + `OpsCard/OpsButton/OpsBadge/OpsStatusDot/…`). |
| Agent shell | `…/TalkieAgent/Design/AgentOpsShell.swift` | `OpsShell/OpsInspector/OpsManifest`, built on OpsKit; "nothing Hudson, nothing copied" (`:7`). |
| TalkieKit package | `apps/macos/TalkieKit/Package.swift` | only external dep is GRDB (`:20-22`). No Hudson/Scout. |
| Agent xcodeproj deps | `…/TalkieAgent.xcodeproj/project.pbxproj` | local pkgs DebugKit / TalkieEngineCore / TalkieKit + remote GRDB (`:214-219`,`:652-696`). macOS deploy target **15.0**, SWIFT_VERSION 5.0. |
| Scout pkg | `/Users/art/dev/openscout/apps/macos/Package.swift` | swift-tools **6.0**, macOS **14**. |
| Hudson pkg | `/Users/art/dev/hudson/Package.swift` | swift-tools **5.9**, macOS 14 / iOS 17. Voice/Terminal products are env-gated (`HUDSONKIT_WITH_VOICE`, `HUDSONKIT_WITH_TERMINAL`). |

---

## Findings by severity

### CRITICAL — premise conflicts with a standing, executed decision (ADR-002 / de-Hudson)
- Treating "maximum HudsonKit adoption" as **linking HudsonKit from TalkieAgent** reverses the documented arrow. TalkieKit primitives are donation sources *for* HudsonKit (`SidebarColumns.swift:20` "Donation target: HudsonSplitView in HudsonKit (per ADR-002)"; `SidebarLayout.swift:20`, `SidebarLabel.swift:17`, `SidebarRow.swift:18`). The project memory ("agent de-Hudson") and `AgentOpsShell.swift:7` confirm de-Hudson was deliberate and is done.
- **Action required before any code:** get the human to confirm whether ADR-002 still stands. If it does, this work is *parity alignment*, not linkage (see §1). If ADR-002 is being reversed, that reversal must be written down — silently re-adding Hudson would contradict the existing comments and memory.

### CRITICAL — the high-value Scout UI is voice-coupled (`ScoutSharedUI` → HudsonVoice → VoxEngine)
- `ScoutSharedUI` (openscout `Package.swift:48-55`) depends on `HudsonVoice`, and its sources import `Speech` + `AVFoundation` and wrap `HudDictation` (`ScoutVoiceService.swift`, `ScoutVoicePermissions.swift`). `HudsonVoice` pulls **VoxEngine** (hudson `Package.swift:144`).
- This is exactly the duplicate voice/transcription stack the constraint forbids. The Scout chat atoms you'd actually want (`MessageInputAtoms`, `MessageCodeBlock`, message bar) live in this voice-coupled target. **Do not link `ScoutSharedUI`.**

### HIGH — env-gated conditional products are fragile inside an Xcode project
- HudsonKit excludes voice/terminal via `ProcessInfo.environment["HUDSONKIT_WITH_VOICE"]`/`…WITH_TERMINAL` read at **manifest-evaluation time** (hudson `Package.swift:137,154`). SwiftPM honors the shell env; an **.xcodeproj** does not give you a reliable, per-scheme way to set the manifest-eval environment, and Xcode caches resolved package graphs aggressively. Risk: you intend a voice-free graph but Xcode resolves VoxEngine anyway, or it differs between CLI `xcodebuild` and the IDE.
- `HudsonUIAudio` is **always-on** (not gated) and imports `AVFoundation`/`Speech` directly (`HudAudioRecorder.swift:4`, `HudAudioTranscriber.swift:2`). Any dependency edge that reaches it brings audio code in regardless of the env flags.

### HIGH — a second design-token system collides with OpsKit and the donation ADR
- TalkieAgent already has a complete token/primitive system (`OpsKit.swift`) and `DesignSystem.swift`. Linking `HudsonUI` introduces a parallel token set (`HudTokens`, `HudButton`, `HudBadge`, …). You'd maintain two systems, risk visual drift, and **invalidate the donation direction** — you can't both donate `Sidebar*` up to HudsonKit *and* consume HudsonKit's tokens down without a circular conceptual dependency.

### MEDIUM — cross-repo source coupling and toolchain skew
- Hudson is consumed by openscout via a **path** dependency (`.package(path: "../../../hudson")`, env-overridable to git). For TalkieAgent to link it you'd add either a brittle absolute/relative path to `/Users/art/dev/hudson` or a pinned git tag. Path coupling is fragile given builds run in DerivedData under `~/Library/Caches/codex-builds`; a tag pin is safer but couples release cadence.
- Toolchain skew is **tolerable but real**: Agent deploy target macOS 15.0 ≥ Hudson/Scout's 14 (OK). swift-tools differ (Talkie pkgs vary, Hudson 5.9, Scout 6.0) — Xcode resolves per-package tools versions, so this is a yellow flag, not a blocker.
- Scout's app graph: `ScoutAppCore` is actually clean (depends only on `ScoutNativeCore`, openscout `Package.swift:31-38`; voice appears only as Decodable data, not service code). It is the one Scout target that *could* be linked — but its value is broker/tail/agent-store models, which overlap Talkie's own `AgentRuntimeClient`/node-dispatcher protocol (§3).

### LOW — vestigial Hudson archaeology in comments
- 8 comment-only Hudson references remain (e.g. `DesignSystem.swift:20,26`, `AgentServiceBridge.swift:5`, the 4 sidebar donation markers). No imports, no package edges. Harmless, but worth a cleanup pass so "de-Hudson" reads as complete.

---

## Answers to the five questions

### 1) What should "maximum adoption" mean concretely, without duplicating voice?
Redefine it as **parity/interface alignment, not linkage** — the donation model already in flight:
- **Shape OpsKit primitives to HudsonKit's public API contracts** (token names, component signatures, shell layout semantics) so Talkie's components are drop-in donatable and visually at parity. This is the `TODO(donation)` work already annotated in the sidebar files.
- **Adopt Scout's *protocol/UX conventions*, not its binaries:** status taxonomy, continuation/threading semantics, wire-trace vocabulary, effort hints — Agent Home already mirrors these in `AgentHomeActivityStore`/`index.mjs`. Closing remaining gaps here is the real "maximum adoption" with zero dependency risk and zero voice duplication.
- If linkage is truly wanted later, the **only** defensible link is `HudsonUI` + `HudsonShell` behind a thin Talkie adapter, with voice/terminal proven absent from the resolved graph (§5). Treat that as a separate, ADR-amending decision.

### 2) Which Scout/Hudson targets are safe / high-value to depend on?
| Target | Link-safe? | Verdict |
|---|---|---|
| `HudsonUI` | Safe leaf (no voice imports) | Linkable, but collides with OpsKit + breaks donation arrow → **avoid; align instead**. |
| `HudsonShell` | Safe leaf (deps: HudsonUI + Observability) | Same as above. Highest "real" candidate if linkage is ordered. |
| `ScoutAppCore` | Clean (only ScoutNativeCore) | Linkable, but **overlaps Talkie's runtime client** — low marginal value. |
| `ScoutSharedUI` | **Unsafe** (→ HudsonVoice → VoxEngine + Speech) | **Do not link.** This is where the desirable chat atoms live, which is the trap. |
| `HudsonVoice`, `HudsonUIAudio`, `HudsonTerminal`/`Vantage` | Voice/terminal/heavy | **Do not link** — duplicates Talkie voice / drags VoxEngine/Termini. |

### 3) What must remain Talkie-owned?
- **Entire voice path:** `EngineClient`/`AgentVoiceSession`/`AgentHomeVoiceCapture`/`AgentVoiceOrchestrator` and `EngineTranscriptionService` (Apple Speech / Parakeet). Non-negotiable per constraint.
- **Runtime contract:** the node dispatcher protocol + `AgentRuntimeClient` (job store, status normalization `index.mjs:409-430`, continuation/effort `:636-671`,`:42-46`).
- **Activity domain model:** `AgentHomeExecutorJob/Turn`, wire-trace syntax, continuation context — these are product logic, not chrome.
- **App shell composition:** `AppDelegate` pipeline (`AudioCaptureService → EngineTranscriptionService → TranscriptRouter → AgentController`).

### 4) Must-fix risks when adding these deps to an Xcode project
1. **Env-gated products won't gate reliably in .xcodeproj** (HIGH above). If you ever link Hudson, you must verify the resolved graph excludes VoxEngine/Termini — don't trust the env flag.
2. **`ScoutSharedUI`/`HudsonVoice` linkage = duplicate voice stack** (CRITICAL). Forbidden.
3. **Dual design systems** (`OpsKit` vs `HudTokens`) — maintenance + parity drift + ADR contradiction.
4. **Cross-repo source path** to `/Users/art/dev/hudson` is brittle in cached DerivedData builds; pin a git tag if linking at all.
5. **Package-graph cache/skew** in Xcode (tools 5.9/6.0, two new external pkgs) → "Resolve Package Versions" surprises, longer cold builds in `~/Library/Caches/codex-builds`.

### 5) Checks that would prove the result
- **No duplicate voice/transcription linked:** after any package change, `xcodebuild -showBuildSettings`/dependency graph must show **no VoxEngine, no `HudsonVoice`, no `HudsonUIAudio`, no Termini**. Grep the resolved `Package.resolved` and link map.
- **Build hygiene gate:** `apps/macos/run.sh TalkieAgent` builds signed (no `CODE_SIGNING_ALLOWED=NO`), DerivedData under `~/Library/Caches/codex-builds`; verify by **binary mtime**, then quit + relaunch.
- **TalkieKit still clean:** `Package.swift` external deps remain GRDB-only; verify via `xcodebuild` (not bare `swift build`, which skips `#if DEBUG`) per the TalkieKit verification reference.
- **Parity acceptance (the actual goal):** Agent Home status taxonomy, continuation labels, effort hints, and wire-trace match Scout's conventions — assert against `index.mjs` mappings and a visual parity walk (border/radius/inset/padding) vs the Scout reference, not "looks similar."
- **De-Hudson invariant holds:** `grep -rn "import Hudson\|import Scout" apps/macos/TalkieAgent` returns nothing unless ADR-002 was formally amended.

---

## Bottom line
The most valuable, lowest-risk reading of "maximum adoption" is to **finish the parity/donation alignment already in motion** (OpsKit ↔ HudsonKit API shapes; Scout status/continuation/effort/wire conventions) and keep TalkieAgent free of Hudson/Scout *linkage*. The one place direct linkage is even arguable — `HudsonUI`+`HudsonShell` — buys little (it duplicates OpsKit) and contradicts ADR-002; `ScoutSharedUI` is disqualified outright because it imports the voice stack. If the human wants true linkage, that is an explicit ADR-002 reversal and should be decided as such before any package is added.
