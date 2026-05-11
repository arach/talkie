# Agent-Manageable Configuration

## Purpose

Talkie's configuration is now designed to be manageable without driving settings UI. Agents should treat the code and the live configuration files as canonical, and treat this document as a map to the right files and stores.

For the embedded console workspace shape and memo/workflow inspection strategy, see `docs/specs/embedded-agent-workspace.md`.

## Canonical Sources

### macOS app settings

- Live file: `~/Library/Application Support/Talkie/settings/config.json`
- Schema: `apps/macos/Talkie/Services/TalkieSettingsConfiguration.swift`
- Store: `apps/macos/Talkie/Services/TalkieSettingsConfigurationStore.swift`

This file now owns the main macOS settings surface, including:

- appearance, sync, compose, local files, bridge, audio, capture, camera, apps, developer thresholds
- surface settings under `notch`
- tray settings under `tray`
- notch geometry lab settings under `notchLab`

### macOS TalkieAgent overlay indicators

- Live file: `~/Library/Application Support/Talkie/settings/overlay-indicators.json`
- Environment-specific path source: `TalkieEnvironment.current.appSupportDirectory/appendingPathComponent("settings/overlay-indicators.json")`
- Schema and store: `apps/macos/TalkieAgent/TalkieAgent/Models/LiveSettings.swift` via `OverlayIndicatorFileOverrides` and `OverlayIndicatorOverridesStore`

This file owns helper-only overlay presentation overrides that are intentionally not exposed in the settings UI:

- top recording bar style override
- top recording bar width, height, corner radius, and background opacity
- floating pill width, developer width, height, and hit width

### macOS workflow settings

- Live file: `~/Library/Application Support/Talkie/workflows/config.json`
- Schema: `apps/macos/Talkie/Workflow/WorkflowConfiguration.swift`
- Store: `apps/macos/Talkie/Workflow/WorkflowConfigurationStore.swift`

This file owns:

- workflow executor/control-plane settings
- workflow preference snapshots
- enabled, pinned, auto-run, order, and action-surface metadata
- shell/runtime settings like allowlisted executables, output directory, path aliases, and automation timestamps

### macOS context rules

- Live file: `~/Library/Application Support/Talkie/context/rules.json`
- Schema and store: `apps/macos/TalkieKit/Sources/TalkieKit/ContextRule.swift`

### iPhone app settings

- Live file: `App Group/Library/Application Support/Talkie/settings/config.json`
- Schema: `apps/ios/Talkie iOS/Services/TalkieAppConfiguration.swift`
- Store: `apps/ios/Talkie iOS/Services/TalkieAppConfigurationStore.swift`
- Convenience facade: `apps/ios/Talkie iOS/Services/TalkieAppSettings.swift`

This file owns iPhone-side appearance, keyboard, transcription, SSH, bridge, sync, and related app preferences.
It also caches pinned Mac workflow actions under `workflows.pinnedMacActions`, so agents have a file-backed representation on iPhone instead of editing iCloud transport payloads directly.

## Compatibility Mirrors

These are still used for transport or backward compatibility, but agents should not treat them as the editable source of truth:

- `UserDefaults.standard`
- shared/app-group defaults used by older runtime paths or extensions
- GRDB workflow preference rows that are synchronized from `workflows/config.json`
- `NSUbiquitousKeyValueStore` payloads such as `pinnedWorkflows`
- notch lab live-suite defaults under `jdi.talkie.notch.lab`

## Workflow Pinning Rule

Pinned workflow state is authored on the macOS side through `workflows/config.json`, under `workflowPreferences.<workflow-id>.isPinned`.

The iPhone keeps a cached file-backed copy in `settings/config.json`, under `workflows.pinnedMacActions`. The iCloud value is now just the transport mirror that refreshes that cache when available; missing transport data should not wipe the cached file-backed state.

## Agent Editing Rule

When an agent needs to change configuration:

1. Find the owning schema/store first.
2. Edit the canonical file-backed surface or the code that manages it.
3. Leave compatibility mirrors alone unless the store is responsible for updating them.
4. Reload/rebuild the relevant target and verify the live config file changes on disk when practical.

## Doc Update Rule

If a change adds, removes, or rehomes a configurable field:

1. Update the owning schema/store.
2. Update `docs/specs/file-based-settings-inventory.md`.
3. Update this document if the agent-facing map changed.

## Practical Starting Points

If the task mentions:

- app settings or settings screens:
  - start with `TalkieSettingsConfigurationStore`
- workflows, quick actions, or executor config:
  - start with `WorkflowConfigurationStore`
- context refinement rules:
  - start with `ContextRuleStore`
- iPhone keyboard, SSH, bridge, or recording preferences:
  - start with `TalkieAppConfigurationStore`

## What Still Is Not “Configuration”

Some state remains operational rather than declarative:

- auth/session state
- permissions state
- transient runtime signals like “start recording now”
- live inventory/debug views that derive from runtime services

Those should not be forced into config files unless they become durable product preferences.
