# `jdi.` prefix retirement — review brief

**Date:** 2026-08-05
**Status:** reviewed; 8 files landed via `chore/retire-jdi-prefix`
**Requested by:** arach (via SpeakEasy session)
**Reviewed by:** session-msg92jf8-2cs3g6

> **Review outcome.** 8 of the 9 proposed changes shipped. The widget `kind`
> change was deferred — see "Deferred" below. Three items now need arach's
> decision, not two.

## Context

The bundle-ID prefix is `to.talkie.app` (`Config/Signing.defaults.xcconfig:22,31-32`).
The legacy `jdi.` prefix is retired and should not appear anywhere in the
codebase. This pass removes it.

Alongside the code change, 25 orphaned `~/Library` entries under
`jdi.talkie.*` (Caches, Preferences, HTTPStorages, WebKit — 438 MB) were
deleted from the developer machine. Their `to.talkie.*` counterparts already
existed, confirming the migration had happened and the `jdi.*` copies were
dead. That part is machine-local cleanup and is not part of this PR.

## Changes applied (8 files)

| File | Change | Rationale |
|---|---|---|
| `apps/ios/run.sh:6` | `BUNDLE_ID="jdi.talkie-os"` → `"to.talkie.app"` | **Live bug.** Script installed the app then launched a bundle ID that has not existed since the rename. |
| `packages/npm/cli/src/commands/app.ts:657` | `~/Library/Containers/jdi.Talkie/Data/Library/Application Support/Talkie` → `~/Library/Application Support/Talkie` | **Live bug.** `talkie app where` printed a sandbox container path, but the macOS app is `com.apple.security.app-sandbox = false` in *both* `Talkie.entitlements` and `Talkie.Release.entitlements`. No such container exists; the corrected path is the one on disk. |
| `apps/ios/Talkie iOS/Info.plist:42` | `CFBundleURLName` `com.jdi.talkie` → `to.talkie.app` | Informational key only. The scheme itself (`talkie`) is unchanged. |
| `apps/ios/TalkieMobileKit/.../Logging/TalkieLogger.swift:134,156` | queue label + os.Logger subsystem `jdi.talkie.*` → `to.talkie.app.*` | Cosmetic; affects Console.app filtering. |
| `apps/ios/TalkieMobileKit/.../Capture/Capture.swift:92` | `capturesDidChange` notification name | Single definition, referenced via the constant. |
| `apps/ios/Talkie iOS/Services/VoiceMemoStore.swift:153` | `voiceMemosDidChange` notification name | Same. |
| `apps/ios/Talkie iOS/Services/ComposeNoteNotifications.swift:9` | `composeNotesDidChange` notification name | Same. |
| `apps/ios/Talkie iOS/Bridge/BridgeManager.swift:16` | `bridgeDidConnect` notification name | Same. |

All four `Notification.Name` values were verified to have exactly one
definition each and no raw-string call sites, so renaming the string is safe.
Re-confirmed at review: every reference resolves through the constant
(`.capturesDidChange` &c.), across 30 call sites in `apps/`, `packages/`, and
`services/`. No string interpolation builds these names.

## Deferred at review — widget `kind`

`apps/ios/TalkieWidget/TalkieWidgetControl.swift:15` still reads
`com.jdi.talkie.record-control`. The rename was applied and then **reverted**.

WidgetKit identifies a widget by `kind`. Changing it orphans every already-placed
Talkie control — it stops resolving and must be re-added by hand. That is not
dev-machine-only: `.github/workflows/release-ios.yml` uploads to App Store
Connect, `TalkieWidgetExtension.appex` is in the app's Embed Foundation
Extensions phase, and the app is at `MARKETING_VERSION = 2.5.37` with 25
release tags. Real installs have this control placed.

Against that, the benefit is zero. `kind` is an opaque identifier — never shown
to a user, never required to match the bundle ID, and invisible to everything
except WidgetKit's own bookkeeping.

Deferring does not make the change cheaper — it costs the same whenever it
happens. What deferring buys is that it happens *deliberately*, in a release
whose notes can say "re-add your Talkie control," instead of riding along
silently in a string-hygiene PR nobody writes release notes for.

**Decision needed:** ship it in a future release with a release note, or accept
the one remaining `jdi` string indefinitely.

## Deliberately NOT changed — needs a decision

### 1. Keychain service names (2 files)

- `apps/ios/Talkie iOS/Bridge/BridgePrivateKeyStore.swift:15` — `service = "jdi.talkie-os.bridge"`
- `apps/ios/Talkie iOS/SSH/SSHPrivateKeyStore.swift:12` — `service = "jdi.talkie-os.ssh"`

A plain rename does not move the keys — it hides them. The app would query a
service name with nothing stored, silently behave as unpaired, and leave the
existing bridge/SSH private keys orphaned in the login keychain.

Two options:

- **Straight rename.** Clean, no lingering `jdi`, but the bridge must be
  re-paired and the SSH key re-added.
- **Rename + one-shot migration.** On first launch, read the old service, write
  to the new one, delete the old. Preserves keys, at the cost of a migration
  function that references `jdi` until it is removed in a later release.

Recommend the migration path if any non-developer build has ever shipped these
stores. Please confirm before touching them.

### 2. Docs URL (2 files)

- `apps/macos/Talkie/Views/Settings/StorageSettings.swift:218`
- `apps/macos/Talkie/Views/Settings/LocalFilesSettings.swift:93`

Both link `https://talkie.jdi.do/docs/file-format`. This is the only reference
to that host in the repo, and there is no unambiguous replacement:
`usetalkie.com` (20 refs), `talkie.to` (a backing service under
`services/talkie.to`), `talkie.dev`, and `talkie.ing` are all present. Guessing
would ship a dead link in Settings. **Needs the correct host from arach.**

## PR scope — important

The working tree on `master` also contains **6 files of unrelated in-progress
work** that predate this change and must NOT be included:

```
apps/macos/Talkie/Resources/Learn/Content/articles/llm-providers.md
apps/macos/Talkie/Views/Learn/ScopeLearnScreen.swift
apps/macos/Talkie/Views/Skills/ScopeSkillsLandingView.swift
design/studio/components/studies/MacAgentHome.tsx
design/studio/components/studies/MacLearn.tsx
design/studio/components/studies/MacWorkflows.tsx
```

These 6 were confirmed excluded from `chore/retire-jdi-prefix` — they remain
uncommitted in the working tree.

## Verification performed at review

- **Unsandboxed claim: confirmed.** `com.apple.security.app-sandbox` is
  `<false/>` in `Talkie.entitlements`, `Talkie.Release.entitlements`, and every
  other first-party macOS entitlements file. On disk,
  `~/Library/Application Support/Talkie` exists and
  `~/Library/Containers/jdi.Talkie` does not (nor any `to.talkie.*` container).
  The corrected path is the real one.
- **`run.sh` bundle ID: confirmed.** `TALKIE_IOS_APP_BUNDLE_ID = to.talkie.app`
  (`Config/Signing.defaults.xcconfig:23`), consumed by the Talkie target at
  `project.pbxproj:1038,1084`. The old `jdi.talkie-os` matched nothing.
- **Notification names: confirmed clean.** All 30 call sites reference the
  constants, not the strings. `docs/donors/` holds one archived copy
  (`command-deck-pre-ios-shell-rebuild/`), which is a frozen snapshot and
  correctly left alone.
- **Build: passes.** `xcodebuild -scheme Talkie -destination 'platform=iOS
  Simulator,name=iPhone 17 Pro'` → **BUILD SUCCEEDED**, covering the app, watch
  app, widget extension, keyboard extension, and share extension. Nothing
  referenced the old strings via interpolation.
- **CLI: passes.** `tsc --noEmit` clean; `bun run build` regenerates `dist/`
  with the corrected path.

## Follow-ups

1. **Keychain service names** — unchanged, needs the rename-vs-migration
   decision above.
2. **Docs URL** — unchanged, needs the correct host.
3. **Widget `kind`** — reverted at review, needs a deliberate release slot.
4. **Ship the CLI fix.** `packages/npm/cli/dist/` is gitignored, so the
   `talkie app where` correction only reaches users on the next npm publish.
   Until then, installed CLIs keep printing the dead container path.

## Unrelated staleness noticed in passing

`apps/ios/run.sh:5` pins `DEVICE="iPhone 16 Pro"`, which no longer exists in
this Xcode's simulator set (17 Pro / 17 Pro Max / Air / 17e are what ship).
`apps/ios/AGENTS.md:22,30` and `AGENTS.md:59,63` document `iPhone 16` for the
same reason. Both are stale in the same way the bundle ID was, but they are
not `jdi`-related, so they were left out of this PR.
