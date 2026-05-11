# Settings Audience Inventory

This document tracks what is visible by `SettingsAudience`:
- `simple`
- `advanced`
- `developer`

It is based on the current code paths in:
- `/Users/example/dev/talkie/apps/macos/Talkie/Views/Settings/SettingsColumns.swift`
- `/Users/example/dev/talkie/apps/macos/Talkie/Views/Settings/StorageSettings.swift`
- `/Users/example/dev/talkie/apps/macos/Talkie/Services/SettingsManager.swift`

## Summary

- `simple`: baseline Settings surface.
- `advanced`: currently has the same visibility as `simple`.
- `developer`: includes all `simple`/`advanced` surfaces plus developer-only sections and diagnostics.

## Section-Level Visibility (Sidebar / Main Settings Routing)

Section visibility is controlled by `SettingsSection.targetAudienceDetails`.

### Visible in `simple` and above

- `Account`
- `Appearance` (includes Home Layout customization)
- `Voice IO`
- `Dictionary`
- `Rules`
- `AI Providers`
- `Models`
- `Storage`
- `Sync`
- `Actions`
- `Automations`
- `About`
- `Feedback`

### Visible only in `developer`

- `Helpers`
- `Extensions` (Apps)
- `Dev Control` (debug builds)
- Legacy compatibility surfaces mapped as developer-only:
- `audio`
- `engine`

## In-Page Visibility Gates

### Storage Settings

Developer-only UI inside Storage:
- `MIGRATIONS` card/list (applied migrations from `grdb_migrations`)

Hidden for `simple` and `advanced`:
- Migrations list is not loaded/rendered.

## Current Behavior of `advanced`

`advanced` currently does not unlock any unique sections/cards beyond `simple`.

Practically:
- `simple` == `advanced` for visibility today.
- Only `developer` changes the visible surface area.

## Mode Selection Location

Settings mode selector is currently in:
- `Appearance` → `SETTINGS MODE` segmented control:
- `Simple` / `Advanced` / `Developer`

## Notes

- Legacy routes are canonicalized before visibility checks (for example, `home` routes to `appearance`).
- Visibility checks use rank-based access (`simple < advanced < developer`).
