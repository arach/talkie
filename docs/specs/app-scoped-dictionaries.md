# App-Scoped Dictionaries — Design Note

**Status:** proposal / consult
**Date:** 2026-06-08
**Context:** Dictionaries currently apply globally. We want context-driven dictionaries that
only activate for specific frontmost apps (e.g. aggressive `cloud code → Claude Code` fuzzy
matching in a dev terminal, dormant in Chrome).

## Current state (grounding)

- `TalkieDictionary` (`TalkieKit/Sources/TalkieKit/DictionaryTypes.swift`) is the unit of
  enable/disable, `source`, and grouping. `DictionaryEntry` is scope-free leaf data.
- `DictionaryManager.syncToEngine()` (`Talkie/Services/DictionaryManager.swift:263`) flattens
  `allEnabledEntries` from all enabled dictionaries and pushes them once via
  `EngineClient.updateDictionary([DictionaryEntry])`. The engine holds this as **global,
  app-unaware in-memory state** and persists it to its own file.
- The engine applies the dictionary **once per finalized transcript**
  (`EngineService.swift:622`, `TextPostProcessor.shared.process`). It is *not* streaming /
  per-partial — there is exactly one apply point, at finalization.
- The call site **already captures the frontmost app** at both ends of a dictation:
  `activeAppBundleID` (start) and `endAppBundleID` (finalize) in
  `DictationStore.swift`, plus a self-frontmost guard (`talkieAgentBundleID`, lines 226–231).

These two facts — *one apply point at finalization* and *target app already captured* — shape
the recommendation below.

## 1. Where the scope lives: dictionary level (not entry level)

Put scope on `TalkieDictionary`, not `DictionaryEntry`.

- Scope is a property of a *coherent set* of corrections ("my dev-terminal vocabulary"), which
  is exactly what a dictionary already models. The use case is inherently collection-shaped.
- It composes with the existing `isEnabled` toggle: scope is just a richer "is this dictionary
  active right now."
- Entry-level scope would explode the UI (an app picker per row) and force per-entry filtering
  on every utterance. The rare "mostly-global dict with a few app-specific entries" case is
  better served by splitting into two dictionaries. **Entry-level scope is a deliberate
  non-goal.**

Proposed model (back-compat via nil = global, mirroring how symbolic/filler defaults are
handled in `DictionaryManager.init`):

```swift
public enum DictionaryScope: Codable, Equatable, Sendable {
    case global                 // applies everywhere (default)
    case included([String])     // only these bundle IDs
    case excluded([String])     // everywhere except these
}

// On TalkieDictionary:
public var scope: DictionaryScope?   // nil == .global; decodeIfPresent → zero-friction migration
```

Active-set resolution for a given `bundleID`:

> active = (global dicts) ∪ (dicts whose `.included` contains bundleID)
>          minus (dicts whose `.excluded` contains bundleID)

Keep it a simple union; document the precedence so it's not ad-hoc.

## 2. How engine sync responds to frontmost-app changes

**Recommended: request-scoped resolution (bind scope to the transcript that produced it).**

- Change the sync payload from a flat `[DictionaryEntry]` to the full enabled set *with* scope
  (e.g. `[(scope, [DictionaryEntry])]`), pushed once on change as today. The engine stores the
  grouped set.
- Pass the **target bundleID along the existing transcribe/post-process request**. The engine
  resolves the active entry subset for that bundleID at finalization, immediately before
  `TextPostProcessor.process`.
- This is race-free: dictionary selection is bound to the same request that produced the
  transcript. The engine never has to observe app-switch events at all, and there is no extra
  XPC round-trip on the hot path — the bundleID rides the call that already exists.

**Alternative: push-on-switch.** Add an `NSWorkspace.didActivateApplicationNotification`
observer (in `DictionaryManager` or a small `AppScopeMonitor`); on each change recompute
`entries(for: bundleID)` and re-`updateDictionary`. Simpler engine (stays a flat list, no
protocol change) but: (a) the race below, and (b) redundant XPC churn on every app switch even
when not dictating. Only pick this if changing the transcribe signature is too invasive now.

**Pragmatic middle ground** if the transcribe signature is frozen short-term: push the full
scoped set once, and add a lightweight `setActiveContext(bundleID:)` XPC that the app fires
from the same place it already captures the target app at dictation start. Engine resolves from
last-set context. Smaller change than full request-scoping, but reintroduces a bounded race
window (see below).

## 3. Gotchas around mid-stream context switches

1. **Finalize app ≠ start app — and finalize wins.** Dictation can begin in Terminal and the
   user cmd-tabs to Chrome before release; the text lands wherever focus is *at injection
   time* = the end/finalize app. The metadata already records both (`activeAppBundleID` vs
   `endAppBundleID`). **Scope must resolve off the finalize app, not the start app**, or you'd
   apply Terminal's aggressive fuzzy matching to text typed into Chrome. This is the single
   most important correctness point.
2. **Push-on-switch race.** If sync is push-driven, an app-switch `updateDictionary` is an
   async XPC that can land *after* an in-flight transcript finalizes — applying the new app's
   dictionary to the old app's utterance (or vice versa). Request-scoped resolution eliminates
   this; the middle-ground `setActiveContext` only bounds it.
3. **Talkie's own window frontmost.** When the recording HUD / Talkie is frontmost,
   `NSWorkspace.frontmostApplication` transiently reports Talkie (already guarded at
   `DictationStore.swift:226–231`). Always resolve scope off the *captured target app*, never a
   live read at finalize.
4. **Unknown / nil bundleID.** Fall back to global-only dictionaries (apply `.global`, skip
   `.included`). Define this default explicitly.
5. **Engine restart / cold start.** The engine persists its dictionary to its own file. The
   persisted format must carry scope too, or scoping is lost across restarts until the next
   sync.
6. **Rapid cmd-tab.** If you go push-based, debounce the switch handler and never let it block
   dictation start.

## Recommendation summary

- Scope on `TalkieDictionary` as optional `DictionaryScope` (nil = global, clean migration).
- Engine holds the full scoped set; resolve the active subset **per request, off the finalize
  app**, immediately before `TextPostProcessor.process`.
- Treat the finalize-app-wins rule and the cold-start persistence format as the two things most
  likely to be gotten subtly wrong.

The main decision a Talkie owner needs to sign off on is **whether the transcribe/XPC request
signature can carry the target bundleID** (enables the clean race-free path) vs. staying with
push-on-switch + `setActiveContext`.
