# File-Based Settings Inventory

## Goal

Move Talkie's settings and workflow configuration to human-editable files so agents can manage the product without driving UI-only settings screens.

This pass establishes declarative configuration files on macOS and a primary declarative app config on iPhone:

- `~/Library/Application Support/Talkie/settings/config.json`
- `~/Library/Application Support/Talkie/settings/overlay-indicators.json`
- `~/Library/Application Support/Talkie/workflows/config.json`
- `~/Library/Application Support/Talkie/context/rules.json`
- `App Group/Library/Application Support/Talkie/settings/config.json`

Both files are intentionally mirrored back to legacy `UserDefaults`, shared settings, and GRDB where needed so existing app behavior keeps working during the transition.

For the agent-facing map of these files and their owning stores, see `docs/specs/agent-manageable-configuration.md`.

## Source Of Truth

### macOS

- `settings/config.json`
  - General app settings
  - Appearance
  - Sync
  - Compose
  - Local files
  - Bridge/server toggles
  - Models
  - Audio
  - Capture
  - Camera
  - Settings UI layout
  - Surface settings under `notch`
  - Standalone tray settings under `tray`
  - Notch geometry lab settings under `notchLab`
  - App enablement
  - Developer thresholds

- `settings/overlay-indicators.json`
  - TalkieAgent-only overlay indicator appearance overrides
  - Top recording bar style override
  - Top recording bar width, height, corner radius, and background opacity
  - Floating pill width, expanded developer width, height, and hit width
  - Lives under the current `TalkieEnvironment` app-support directory, so dev/staging use `Talkie.dev` and `Talkie.staging`

- `workflows/config.json`
  - Workflow executor control-plane settings
  - Workflow preferences
  - Enabled/pinned/auto-run/sort order
  - Action-surface placement metadata
  - Shell step allowlist extensions
  - Default save/output directory
  - Save-file path aliases
  - Automation scheduler last-run timestamps

### iOS

- `settings/config.json`
  - Appearance and theme selection
  - Recording preferences
  - Keyboard preferences
  - Keyboard mode activation, active layout, last selected mode, and per-mode slot overrides
  - Transcription engine and preferred Parakeet model
  - iCloud sync toggle, preferred sync methods, and banner dismissal state
  - Developer reset flags
  - SSH connection preferences
  - SSH saved hosts and known-host trust map
  - Bridge pairing configuration and companion-follow preference
  - Cached pinned Mac workflow actions under `workflows.pinnedMacActions`

Legacy `UserDefaults` and app-group defaults are still mirrored from this file where extension compatibility or older code paths still depend on them.

## macOS Settings Screens

### Primarily backed by `SettingsManager` and now mirrored into `settings/config.json`

- `APISettings.swift`
- `AboutSettingsView.swift`
- `AppsSettingsView.swift`
- `HelperAppsSettings.swift`
- `HomeSettingsView.swift`
- `MemosSettings.swift`
- `ModeSettingsView.swift`
- `ModelLibrarySettings.swift`
- `ModelsSettings.swift`
- `NotchSettingsView.swift`
- `SurfaceSettingsView.swift`
- `OutputSettings.swift`
- `SyncProvidersView.swift`
- `TTSVoicesSettingsView.swift`
- `TransformsSettings.swift`
- `WorkflowSettings.swift`
- `iOSSettingsView.swift`

### Primarily backed by `WorkflowService` and now mirrored into `workflows/config.json`

- `ActionEditorSheet.swift`
- `AutomationsSettings.swift`
- `ContextSettingsView.swift`
- `OutputSettings.swift`
- `QuickActionsSettings.swift`
- `WorkflowSettings.swift`

### Operational / derived / auth-driven settings surfaces

These screens are settings-adjacent, but they are not simple preference storage and therefore are not fully represented in the new declarative config files yet:

- `AccountSettings.swift`
- `BridgeSettingsView.swift`
- `ConnectionCenterView.swift`
- `DebugSettings.swift`
- `FeedbackSettings.swift`
- `PermissionsSettings.swift`
- `ServerSettingsView.swift`
- `StorageSettings.swift`
- `UpdateSettingsView.swift`
- `VoiceIOSettings.swift`
- `ContextRulesSettingsView.swift`
- `ContextRulesDetailColumn.swift`
- `ContextRulesListColumn.swift`
- `DictionarySettings.swift`
- `DictionarySuggestionsView.swift`
- `DictionaryTestPlayground.swift`
- `DictionaryURLExtractModal.swift`
- `CloudInventoryView.swift`
- `DataInventoryView.swift`
- `AuditResultsView.swift`
- `MicTestView.swift`
- `DevControlPanel.swift`
- `ManagedAgentLabSection.swift`
- `TranscriptionModelsSettingsView.swift`
- `OnboardingSettings.swift`
- `QuickOpenSettings.swift`
- `AppearanceSettings.swift`
- `DictationSettings.swift`
- `LocalFilesSettings.swift`
- `SelectionSettingsView.swift`
- `ActionsSettingsView.swift`
- `SettingsColumns.swift`
- `SettingsSidebarState.swift`

## macOS Declarative Coverage

### `settings/config.json`

Current sections:

- `onboarding`
- `sync`
- `remoteEngine`
- `appearance`
- `home`
- `compose`
- `localFiles`
- `workflow`
- `bridge`
  - includes Bridge server toggles plus legacy `companionShortcutModeEnabled`
- `devices`
  - includes default shortcut board definition plus class/device overrides for paired iPhone and iPad surfaces
- `interstitial`
- `models`
- `audio`
- `capture`
- `camera`
- `ui`
- `notch`
- `tray`
- `notchLab`
- `apps`
- `developer`

### `settings/overlay-indicators.json`

Current sections:

- `version`
- `topBar`
- `pill`

`topBar` stores:

- `style`
- `width`
- `height`
- `cornerRadius`
- `backgroundOpacity`

`pill` stores:

- `width`
- `developerWidth`
- `height`
- `hitWidth`

### `workflows/config.json`

Current sections:

- `controlPlane`
- `workflowPreferences`
- `runtime`

Each workflow preference snapshot stores:

- `isEnabled`
- `isPinned`
- `autoRun`
- `autoRunOrder`
- `sortOrder`
- `showInInterstitial`
- `showInDrafts`
- `appBundleIDs`

The runtime section stores:

- `customAllowedExecutables`
- `defaultOutputDirectory`
- `pathAliases`
- `automationLastRunTimes`

### `context/rules.json`

Current sections:

- `isEnabled`
- `rules`

Each context rule stores:

- `name`
- `appBundleIDs`
- `isEnabled`
- `behavior`
- `prompt`
- `llmProviderId`
- `llmModelId`
- `selectionRoutine`
- `createdAt`
- `updatedAt`

## iOS Settings Surfaces

### Direct settings screens

- `SettingsView.swift`
  - `TalkieAppSettings`
  - `ThemeManager`
  - `TranscriptionService`
  - `BridgeManager`
  - SSH saved-host stores
  - Cached pinned Mac workflow actions mirrored from iCloud transport
  - Companion follow preference for Mac-requested shortcut mode

- `KeyboardSettingsView.swift`
  - `TalkieAppSettings`
  - `KeyboardBridge` compatibility mirrors

- `KeyboardConfiguratorView.swift`
  - `TalkieAppConfigurationStore`
  - `TalkieAppSettings` compatibility reload to mirror file edits into the keyboard extension bridge

- `BridgeSettingsView.swift`
  - `BridgeManager`

- `SSHTerminalView.swift`
  - `TalkieAppSettings`
  - SSH saved-host and private-key stores

### Related runtime surfaces that still read the same settings

- `ThemeManager.swift`
- `TranscriptionService.swift`
- `ConnectionManager.swift`
- `HeadlessDictationService.swift`
- `BridgeManager.swift`
- `KeyboardBridge.swift`
- `HomeView.swift`
- `RecordingView.swift`
- `ConnectionCenterView.swift`
- `iCloudStatusManager.swift`
- `talkieApp.swift`

## Migration Strategy

### Phase 1

- Establish human-editable file-backed source of truth on macOS
- Keep legacy mirrors in place
- Keep workflow preferences synchronized into GRDB and iCloud KVS
- Make executor settings editable without opening Settings UI

### Phase 2

- Extend the iOS declarative file to any remaining keyboard-extension runtime payloads that should become agent-managed
- Treat `NSUbiquitousKeyValueStore` pinned workflow payloads as transport-only and mirror them into `settings/config.json`
- Keep app-group defaults as compatibility mirrors only where keyboard extension compatibility requires it

Completed in this pass:

- Keyboard slot customization now persists into the declarative iPhone config.
- Keyboard mode activation now persists into the declarative iPhone config.
- Sync provider preference order and iCloud banner dismissal now persist into the declarative iPhone config.
- Pinned Mac workflow actions now cache into the declarative iPhone config, with iCloud reduced to a transport mirror that should not wipe cached file-backed state when unavailable.
- The remaining user-facing macOS sync/iPhone settings views that still used `@AppStorage` now read through `SettingsManager`, which mirrors to `settings/config.json`.
- Workflow shell allowlist extensions, default output directory, save-path aliases, and automation last-run timestamps now persist into `workflows/config.json`.
- Notch, tray, and notch geometry lab settings now persist into `settings/config.json` and only mirror back to legacy defaults/live suites for compatibility.

### Phase 3

- Remove stale UI-only assumptions
- Let Talkie Agent edit settings/workflow files directly
- Treat settings screens as viewers/editors for files, not the primary source of truth

## Notes

- `pendingWorkflowIds` remains intentionally inert compatibility ballast and is not part of the new control path.
- GRDB and iCloud KVS remain compatibility layers for workflow transport and presentation.
- iPhone pinned workflow presentation now reads its cached file-backed mirror; the authored source of truth still lives on the macOS side in workflow files.
- The remaining non-file-backed settings-adjacent cases are transport/runtime signals, not durable user preferences.
- Core Data and CloudKit schema changes are deliberately out of scope for this file-backed settings migration.
