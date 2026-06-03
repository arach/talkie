# TLK-024 - iOS Preview Build Target

**Status**: Draft
**Owner**: Talkie iOS
**Date**: 2026-05-31
**Related**: [TLK-019](tlk-019-ios-shared-components.md) (iOS shared components), [local development without CloudKit](../engineering/local-development-without-cloudkit.md)

## Summary

Create a lightweight Talkie iOS preview / dogfood build target for fast iteration on `Views/Next` app shell surfaces, especially `SettingsNext`.

The full signed Talkie iOS app remains the integration pass. The preview target exists so UI work on settings, app chrome, routing, and shared primitives can compile and launch without rebuilding the whole product graph every time.

This is a proposal for the Talkie team to follow up. It does not implement the target, change signing, or alter app runtime behavior.

## Problem / Context

Talkie iOS has a strong new settings direction in `SettingsNext`: a dense inspector-style surface with a left category rail, fixed-height rows, section dividers, inline actions, metric strips, and calm technical hierarchy. It is a good baseline for future settings and app shell work.

The problem is iteration cost. Small changes to settings presentation currently ride through the full Talkie iOS scheme, which is optimized for product integration, not surface-level UI development. That makes the edit-build-launch loop too expensive for the layer that should be quickest to refine.

The preview target should let engineers and design agents work on shell/settings surfaces in isolation, then validate the same code inside the signed production app before merging.

## Current Build Graph Observations

During the current investigation, a full Talkie iOS signed simulator build took about **471.79s**. That build is doing useful integration work, but it is far heavier than needed to preview `SettingsNext`.

The full scheme pulls in or touches:

- Watch app assets and companion packaging concerns.
- `TalkieKeys` keyboard extension build graph.
- Ghostty / terminal module compilation and warnings.
- Camera and AVFoundation-facing surfaces.
- FluidAudio and network/runtime dependencies in the NIO / SSH / Crypto family.
- CloudKit and CoreData setup paths.
- Production app signing and entitlement behavior.

Those are real product dependencies. They should remain covered by the full app. They should not be mandatory when the change is a row layout, section rhythm, settings tab, or shell presentation tweak.

## Proposal

Add a separate iOS simulator build target, tentatively named **Talkie iOS Preview**, that compiles a narrow UI host for `Views/Next` surfaces.

The preview app should:

- Use the same SwiftUI source files for `SettingsNext`, app shell chrome, design tokens, and shared `Next` primitives.
- Provide lightweight mock services for settings state, bridge status, sync health, permissions, and account state.
- Launch directly into selected surfaces via launch arguments, for example `--settings --inspectorTab voice`.
- Avoid production CloudKit/CoreData mirroring, keyboard extension, watch app, terminal/Ghostty, camera capture, and audio/network-heavy dependency chains.
- Be simulator-first and local-development-only.
- Keep the production Talkie iOS target as the required integration pass before merge.

The key idea is not to fork the UI. The preview target should reuse the same settings and shell code, with dependency boundaries arranged so non-critical runtime services can be swapped for mocks.

## Target Boundaries

Include in the preview target:

- `apps/ios/Talkie iOS/Views/Next/SettingsNext.swift`
- `Views/Next` app shell surfaces needed to host settings.
- Talkie design system and visual tokens needed by those surfaces.
- Small preview state stores and fixture data.
- Minimal routing needed for settings, shell, and selected detail surfaces.
- Optional screenshot routes for CI and design review.

Exclude from the preview target:

- Production persistence and CloudKit mirroring.
- Real account sync and entitlement-dependent services.
- Ghostty / terminal modules.
- `TalkieKeys` keyboard extension.
- Watch app targets and watch assets.
- Camera capture, microphone capture, FluidAudio, SSH, NIO, Crypto, and other heavy runtime modules unless a specific preview requires them.
- App Store, distribution, or production signing concerns.

If a surface needs one of the excluded systems, the preview should depend on a small protocol-shaped fixture instead of linking the real implementation.

## Non-goals

- Do not replace the full signed Talkie iOS build.
- Do not create a second product UI or divergent settings implementation.
- Do not weaken integration validation, signing validation, or CloudKit validation.
- Do not move core runtime code just to satisfy the preview target.
- Do not require every iOS feature to be previewable in the first slice.
- Do not solve all build performance issues in one step.

## Implementation Plan

### Phase 0 - Audit and Boundaries

- Measure the current full signed simulator build, incremental rebuilds, and launch time.
- Produce a dependency map for `SettingsNext` and its immediate shell host.
- Identify dependencies that can be protocolized or fixture-backed without changing product behavior.
- Decide whether the preview target lives in the existing Xcode project or a small adjacent preview project.

### Phase 1 - Minimal Preview Host

- Add `Talkie iOS Preview` with a tiny SwiftUI `App` entry point.
- Host `SettingsNext` with fixture state and launch-argument routing.
- Ensure `SettingsNext` compiles from the same source file used by the production app.
- Add a default route for the most useful settings tab.
- Keep the target simulator-only until there is a reason to run it on device.

### Phase 2 - Shell Surface Coverage

- Add routes for app shell, bridge detail, and any other `Views/Next` surfaces that are actively changing.
- Add fixture scenarios: connected Mac, disconnected Mac, CloudKit unavailable, permission missing, onboarding incomplete, and account signed out.
- Add screenshot commands for design review.

### Phase 3 - CI / Agent Loop

- Add a lightweight CI job or local script that builds the preview target and captures key screenshots.
- Use the preview target for design-agent loops: screenshot, critique, patch, rebuild, screenshot.
- Keep the full Talkie iOS target in CI as the integration gate for affected changes.

## Validation

The proposal is successful when:

- A settings-only UI change can build and launch through the preview target substantially faster than the full Talkie iOS scheme.
- `SettingsNext` is still compiled from the production source file.
- The preview target can render at least the primary settings tabs with realistic fixture states.
- The full signed Talkie iOS app still builds and runs as the integration pass.
- The preview target fails if a developer accidentally imports an excluded heavy runtime module into the settings/shell layer.

Suggested acceptance checks:

- Cold preview build time.
- Incremental preview build time after editing `SettingsNext`.
- Full signed Talkie iOS build time after the same edit.
- Screenshot comparison for default settings tabs.
- Launch with CloudKit unavailable fixture.

## Risks / Open Questions

- **Dependency creep**: the preview target can become another full app if boundaries are not enforced.
- **Mock drift**: fixtures can lie. The full app must remain the authority for integration behavior.
- **Project complexity**: an extra target adds maintenance overhead; the payoff depends on keeping it small.
- **Source ownership**: `Views/Next` may need small protocol boundaries so settings code does not import production services directly.
- **Signing behavior**: the preview target should not mask entitlement bugs; signed production builds remain required.
- **Placement**: decide whether this belongs in the existing Xcode project, an `.xcodeproj` generated by tooling, or a Swift Package demo-style host.
- **Naming**: choose whether user-facing local tooling says "Preview", "Dogfood", or "Surface Lab".

The recommended first slice is intentionally modest: make `SettingsNext` and its shell host previewable without CloudKit, terminal, keyboard, watch, camera, and audio/network-heavy modules. That gives the team a fast loop exactly where the current design work is happening.
