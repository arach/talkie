# TLK-030: Modular Build Architecture

**Status**: Draft
**Date**: 2026-06-13
**Studio**: /eng/tlk-030

## Summary

Talkie should move toward smaller Swift modules so stable feature areas can stay
built while active feature work rebuilds only the module being changed and the
thin app composition layer.

The current macOS app already has some modularization through local packages
such as `TalkieKit`, `WFKit`, `DebugKit`, and `TalkieEngineCore`, but the main
`Talkie` app target is still large enough that a small overlay change can make
Xcode re-typecheck and compile hundreds of unrelated files. `TalkieKit` is also
broad, so simply moving more app code into that one package would create a new
large module rather than solving the build granularity problem.

The goal is to make the build unit closer to the change unit.

## Current Shape

Observed on 2026-06-13:

- `apps/macos/Talkie` contains roughly 485 Swift files in the app target tree.
- `apps/macos/TalkieKit` contains roughly 131 Swift files in one package target.
- `apps/macos/TalkieAgent` contains roughly 158 Swift files.
- The main app target depends on local packages including `TalkieKit`, `WFKit`,
  and `DebugKit`.
- The repo already has a fast incremental path:
  `cd apps/macos && ./run.sh Talkie --no-launch`, which reuses
  `apps/macos/build/macos/Talkie` as DerivedData when `--clean` is omitted.
- Initial implementation has begun by adding a `TalkieCore` package target
  inside `apps/macos/TalkieKit` and moving small stable utilities such as
  `TalkieDate` and `CaptureFilenameFormatter` into it. `TalkieKit` re-exports
  `TalkieCore` as a compatibility facade so existing app and agent imports do
  not need to change yet.

The problem is not only cache reuse. The deeper problem is that many stable
features live in the same Swift module as frequently edited UI and overlay code.

## Desired Architecture

Use a small set of local Swift package targets with explicit dependency
direction. Start inside existing local packages where practical, then split into
separate packages only when package-level ownership or dependency resolution
needs it.

Proposed first-level graph:

```text
TalkieApp
  -> TalkieFeatureModules
  -> TalkieCaptureKit
  -> TalkieWorkflowKit
  -> TalkieDataKit
  -> TalkieDesignKit
  -> TalkieCore

TalkieAgent
  -> TalkieCaptureKit
  -> TalkieDesignKit
  -> TalkieCore

TalkieCaptureKit
  -> TalkieDataKit
  -> TalkieDesignKit
  -> TalkieCore

TalkieWorkflowKit
  -> TalkieDataKit
  -> TalkieCore
  -> WFKit

TalkieDataKit
  -> TalkieCore

TalkieDesignKit
  -> TalkieCore

TalkieCore
  -> external dependencies kept minimal
```

This can start as multiple targets in `apps/macos/TalkieKit/Package.swift`:

- `TalkieCore`: logging, environment, helper identity, date/path utilities,
  shared protocols, small pure utilities.
- `TalkieDataKit`: shared models, recording visual context models, capture
  markup document types, sync-safe DTOs.
- `TalkieDesignKit`: reusable SwiftUI/AppKit controls with no app singleton
  dependencies.
- `TalkieCaptureKit`: screenshot selection, recording selection overlays,
  capture markup rendering/session primitives, capture target types.
- `TalkieMediaKit`: clip metadata, attachment storage, thumbnails, media
  sidecar primitives.

The app target should become the composition layer: app delegate, navigation,
feature registration, singleton wiring, and user-facing screens that genuinely
depend on app-only services.

## Build Rules

1. Stable code should live in lower modules.
   Lower modules should compile once and change rarely.

2. Active UI experiments should live in small leaf modules.
   Capture overlay work should not rebuild workflow settings, onboarding, or
   database screens.

3. Dependencies point inward and downward.
   `TalkieCore` must not know about the app, capture, workflows, or agent.
   `TalkieDataKit` must not import app services.

4. Avoid a second mega-module.
   `TalkieKit` should become a package namespace containing smaller targets,
   not the place where every extracted file lands.

5. Prefer static Swift package targets first.
   They give typecheck and compile isolation with less signing and embedding
   complexity. Consider dynamic frameworks only if link time remains painful
   after module splitting.

6. Public APIs should be intentionally narrow.
   Make the module boundary force small contracts. Avoid exporting app
   singletons or concrete storage services through lower modules.

## First Extraction Candidates

Start with stable, low-dependency utility code rather than the capture overlay.
The first bite should prove that:

- The package can contain multiple static library targets.
- `TalkieKit` can remain a compatibility facade while lower targets split out.
- Existing app and agent files can continue importing `TalkieKit` during the
  migration.
- Lower-level files rebuild only when their own target changes.

The safest first target is `TalkieCore`, beginning with pure utilities such as
`TalkieDate`. This code has no app singleton, resource, AppKit windowing,
workflow execution, or persistence dependency, so it is a good low-risk compile
boundary test.

Workflow is the more valuable medium-term extraction, but it should be split by
role rather than moved as one block:

- `TalkieWorkflowModels`: workflow definitions, step configuration models,
  simple file format decoding, validation, and lossless round-trip tests.
- `TalkieWorkflowRuntime`: execution contracts and portable runtime context.
- App-side workflow orchestration: `WorkflowExecutor.shared`, concrete LLM
  provider wiring, credentials, Core Data/SwiftData/CoreData model access,
  notifications, UI polling, and app singleton integration.

Capture should be treated as a later beneficiary of the same pattern. The
capture markup models/rendering are good candidates once the core split is
proven, but controllers that depend on app services should remain app-side
until their dependencies are deliberately inverted.

## Phased Plan

### Phase 0: Faster Local Loop

Use incremental builds while iterating:

```bash
cd apps/macos
./run.sh Talkie --no-launch
```

Reserve fresh per-run DerivedData builds under `~/Library/Caches/codex-builds/`
for final verification or suspicious cache states.

### Phase 1: Measure

Add lightweight build timing notes before and after each extraction:

- clean build time
- no-op build time
- build time after touching one capture overlay file
- build time after touching one workflow file
- build time after touching one data model file

The success metric is not just clean build time. It is "touch one overlay file
and rebuild quickly."

### Phase 2: Split TalkieKit Targets

Update `apps/macos/TalkieKit/Package.swift` to introduce:

- `TalkieCore`
- `TalkieDataKit`
- `TalkieDesignKit`
- `TalkieCaptureKit`

Keep the existing `TalkieKit` product temporarily as a compatibility facade if
needed. Move files in small batches and keep old imports working until app and
agent targets are migrated.

### Phase 3: Extract Workflow Models

Move the stable workflow schema/model layer before the executor:

- `WorkflowDefinition`
- `WorkflowStep`
- `StepConfig`
- step configuration value types
- simplified workflow file decoding
- skill file parsing, if it can remain free of app-only services

The model layer should be serializable and testable without the app target.
Keep current encoded JSON compatibility as a hard requirement.

### Phase 4: Move Capture Model and Rendering

Move stable capture markup data/rendering into `TalkieDataKit` or
`TalkieCaptureKit`, depending on dependency needs. The current capture markup
document and renderer are good candidates because they already live under
`TalkieKit`.

### Phase 5: Move Capture Overlay UI

Move overlay UI that only depends on AppKit, ScreenCaptureKit, and shared
capture contracts into `TalkieCaptureKit`. Keep app-specific orchestration in
the app target.

### Phase 6: Extract Runtime and Data

After the model split proves the pattern, extract workflow execution contracts
and stable repository/model contracts. This is likely a larger move because
current workflow code touches app services, credentials, file repositories, and
UI.

## Risks

- Too many tiny modules can increase mental overhead and link complexity.
- Public APIs can become leaky if modules export app internals to avoid
  untangling dependencies.
- Moving SwiftUI views into packages can expose resource and localization
  assumptions.
- Dynamic frameworks would introduce embedding, signing, and runtime loading
  complexity. Use them only after measuring static target results.

## Recommendation

Start with `TalkieCore` as a small static Swift package target inside the
existing `TalkieKit` package. Move one or two pure utilities first, keep
`TalkieKit` as the compatibility facade, and verify that the app and agent still
build with existing imports.

Then extract workflow models before workflow execution. This should give a
larger build-cache payoff than capture-specific work while also improving the
shape of the codebase: stable schema and serialization code becomes a quiet
lower module, while the app target keeps fast-changing UI and orchestration.
