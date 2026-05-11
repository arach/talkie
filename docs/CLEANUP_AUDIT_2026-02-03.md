# Project Cleanup Audit
**Date:** 2026-02-03
**Branch:** feature/voice-nav

---

## 1. Untracked Files (not in git)

### Active Development (feature/voice-nav) - KEEP
| File | Purpose |
|------|---------|
| `apps/macos/Talkie/Services/MemorySampler.swift` | Memory diagnostics tool |
| `apps/macos/TalkieKit/Sources/TalkieKit/VoiceIntentRecognizer.swift` | NLEmbedding-based voice intent matching |
| `apps/macos/TalkieAgent/TalkieAgent/Services/VoiceNavigationHandler.swift` | XPC bridge for voice navigation |
| `docs/specs/ios-keyboard-ux-design.md` | iOS keyboard UX spec |
| `docs/specs/macos-distribution-telemetry-paywall.md` | Distribution/telemetry spec |

**Action:** Commit when feature is ready.

### Deployment Artifacts - DELETE
| Path | Notes |
|------|-------|
| `services/talkie-api/.vercel/` | Vercel local config - add `.vercel/` to .gitignore |

---

## 2. Gitignored Build Artifacts (safe to delete)

| Path | Size | Notes |
|------|------|-------|
| `build/` | 321 MB | Xcode Archives + Exports |
| `node_modules/` (root) | 132 MB | Only `@arach/speakeasy` |
| `packaging/macos/staging/` | 62 MB | Staging app bundle |
| `packaging/macos/releases/2.0.9/` | ~96 MB | Old DMG release |
| `Landing/.next/` | ~450 MB | Next.js build cache |
| `Landing/node_modules/` | ~50 MB | Landing page deps |
| `Landing/out/` | varies | Static export |

**Total recoverable:** ~1.1 GB

### Cleanup Command
```bash
rm -rf build/ node_modules/ packaging/macos/staging/ packaging/macos/releases/
rm -rf Landing/.next/ Landing/node_modules/ Landing/out/
rm -rf services/talkie-api/.vercel/
```

---

## 3. Suspect Committed Files

### Root-level Markdown Files
| File | Size | Last Modified | Status |
|------|------|---------------|--------|
| `AUDIT-2025-12-29.md` | 8 KB | Dec 30 | STALE - old audit |
| `ENVIRONMENT_PLAN.md` | 17 KB | Dec 30 | Possibly stale |
| `IMPLEMENTATION_PROGRESS.md` | 4 KB | Dec 30 | STALE - old tracker |
| `ONBOARDING_LAYOUT_FIXES.md` | 7 KB | Dec 30 | STALE - old fixes |
| `ONBOARDING_SPEC.md` | 76 KB | Dec 30 | Move to docs/? |
| `DEBUGKIT_INTEGRATION.md` | 3 KB | Dec 30 | Move to docs/? |
| `STAGING_SETUP.md` | 6 KB | Dec 30 | Move to docs/? |
| `XCODE_CONFIGURATION_STEPS.md` | 5 KB | Dec 30 | Move to docs/? |
| `AGENTS.md` | 12 KB | Dec 30 | Keep (AI context) |
| `CODEX.md` | 1 KB | Jan 19 | Keep (AI context) |

### Large Binary Files at Root
| File | Size | Last Modified | Recommendation |
|------|------|---------------|----------------|
| `image.png` | 1.1 MB | Dec 30 | Move to assets/ or delete |
| `Talkie-iOS-Default-1024x1024@1x.png` | 1.4 MB | Jan 25 | Move to assets/ |

### Unusual Directories
| Directory | Contents | Recommendation |
|-----------|----------|----------------|
| `draft-renderers/` | JS prototypes (tweet-composer, draft-link) | Archive or delete |
| `extensions/` | `talkie-sdk.js` (12 KB) | Clarify purpose or archive |
| `specs/` | Single architecture doc | Merge into docs/specs/ |
| `WFKit` → `../WFKit` | Symlink outside repo | Document or remove |

---

## 4. Analysis by Recency

### Files Not Modified Since Dec 30, 2025 (35+ days stale)

**Root level:**
- `AUDIT-2025-12-29.md`
- `DEBUGKIT_INTEGRATION.md`
- `ENVIRONMENT_PLAN.md`
- `IMPLEMENTATION_PROGRESS.md`
- `ONBOARDING_LAYOUT_FIXES.md`
- `ONBOARDING_SPEC.md`
- `STAGING_SETUP.md`
- `XCODE_CONFIGURATION_STEPS.md`
- `image.png`
- `WFKit` (symlink)

**Directories with stale content:**
- `draft-renderers/` (Jan 13 last touch, but content from earlier)
- `extensions/` (Jan 13)
- `docs/design-system-iterations/` (Dec 30)
- `docs/onboarding/` (Dec 30)
- `docs/settings-refinement/` (Dec 30)

### Recently Active (Jan-Feb 2026)
- `CLAUDE.md` - Feb 3 (active)
- `SHIPPING.md` - Feb 3 (active)
- `VERSION` - Feb 3 (active)
- `docs/specs/` - Feb 3 (new specs being added)
- `Talkie-iOS-Default-1024x1024@1x.png` - Jan 25

---

## 5. Recommended Actions

### Immediate (Safe)
1. Delete gitignored build artifacts (~1.1 GB)
2. Add `.vercel/` to .gitignore
3. Delete `services/talkie-api/.vercel/`

### Short-term (Review Required)
1. Archive or delete stale Dec 30 markdown files
2. Move `image.png` and iOS icon to `assets/`
3. Consolidate `specs/` into `docs/specs/`

### Discussion Needed
1. What is `draft-renderers/` for? Keep or archive?
2. What is `extensions/talkie-sdk.js` for? Keep or archive?
3. Is the `WFKit` symlink still needed? Document dependency?
4. Root `package.json` with single `@arach/speakeasy` dep - what's this for?

---

## 6. Full Recency Analysis

### Root-Level Files by Date

#### Active (Feb 2026)
| File | Date | Status |
|------|------|--------|
| `CLAUDE.md` | Feb 3 | Active - project instructions |
| `SHIPPING.md` | Feb 3 | Active - release process |
| `VERSION` | Feb 3 | Active - version tracking |

#### Recent (Jan 2026)
| File | Date | Status |
|------|------|--------|
| `Talkie-iOS-Default-1024x1024@1x.png` | Jan 25 | Move to assets/ |
| `CODEX.md` | Jan 19 | Keep - AI context |
| `package.json` | Jan 7 | Investigate - single dep |
| `package-lock.json` | Jan 7 | Tied to package.json |

#### Stale (Dec 2025 - 35+ days old)
| File | Date | Recommendation |
|------|------|----------------|
| `AUDIT-2025-12-29.md` | Dec 30 | DELETE - superseded by this audit |
| `IMPLEMENTATION_PROGRESS.md` | Dec 30 | DELETE - stale tracker |
| `ONBOARDING_LAYOUT_FIXES.md` | Dec 30 | DELETE - completed fixes |
| `ENVIRONMENT_PLAN.md` | Dec 30 | ARCHIVE to docs/ or DELETE |
| `ONBOARDING_SPEC.md` | Dec 30 | MOVE to docs/onboarding/ |
| `DEBUGKIT_INTEGRATION.md` | Dec 30 | MOVE to docs/engineering/ |
| `STAGING_SETUP.md` | Dec 30 | MOVE to docs/ |
| `XCODE_CONFIGURATION_STEPS.md` | Dec 30 | MOVE to docs/engineering/ |
| `AGENTS.md` | Dec 30 | KEEP - AI context (still relevant) |
| `image.png` | Dec 30 | DELETE or MOVE to assets/ |
| `README.md` | Dec 30 | KEEP - repo readme |
| `requirements.txt` | Dec 30 | KEEP - Python deps |
| `.swiftlint.yml` | Dec 30 | KEEP - linting config |

---

### docs/ Directory by Date

#### Active (Feb 2026)
- `docs/product/multi-backend-sync-plan.md` - Feb 3
- `docs/CLEANUP_AUDIT_2026-02-03.md` - Feb 3 (this file)

#### Recent (Jan 2026)
- `docs/specs/ios-keyboard-ux-design.md` - Jan 29 (untracked)
- `docs/specs/macos-distribution-telemetry-paywall.md` - Jan 28 (untracked)
- `docs/specs/text-to-speech.md` - Jan 25
- `docs/IDEAS.md` - Jan 25
- `docs/gemini-plans/*.md` - Jan 25 (6 files)
- `docs/engineering/TESTING_STRATEGY.md` - Jan 25
- `docs/engineering/ONBOARDING_EXPERIENCE.md` - Jan 25
- `docs/MEMORY_OPTIMIZATION_PLAN.md` - Jan 19
- `docs/DESIGN_EVALUATION.md` - Jan 16
- `docs/specs/python-pod-architecture.md` - Jan 7
- `docs/specs/dictionary-feature.md` - Jan 7
- `docs/review/*.md` - Jan 7 (active codebase review)
- `docs/context-capture-architecture.md` - Jan 7
- `docs/CODEBASE_ANALYSIS_PLAN.md` - Jan 7

#### Stale (Dec 2025)
| Directory | Files | Recommendation |
|-----------|-------|----------------|
| `docs/design-system-iterations/` | 4 iteration analyses | ARCHIVE - design completed |
| `docs/onboarding/` | 9 screen specs | ARCHIVE - onboarding shipped |
| `docs/settings-refinement/` | 12 iteration files | ARCHIVE - settings shipped |
| `docs/VALIDATION_REPORT.md` | 1 file | ARCHIVE |
| `docs/MILESTONE_DESIGN_SYSTEM_V1.md` | 1 file | ARCHIVE |

---

### scripts/ Directory by Date

#### Active (Feb 2026)
- `scripts/sync-version.sh` - Feb 3

#### Recent (Jan 2026)
- `scripts/ship.sh` - Jan 29
- `scripts/xcode-post-build.sh` - Jan 25
- `scripts/xcode-cleanup-url-schemes.sh` - Jan 25
- `scripts/test-lite-interstitial.sh` - Jan 25
- `scripts/run.sh` - Jan 25
- `scripts/cleanup-url-schemes.sh` - Jan 25
- `scripts/update-macos-app-icons.sh` - Jan 19
- `scripts/preview-macos-switcher.sh` - Jan 19
- `scripts/preview-macos-icon.sh` - Jan 19
- `scripts/capture-cmdtab-preview.sh` - Jan 19
- `scripts/sync-xcode-files.py` - Jan 7 (documented in CLAUDE.md)
- `scripts/top_hotspots.py` - Jan 7
- `scripts/extract_time_samples.py` - Jan 7
- `scripts/record_time_profiler.sh` - Jan 7

#### Stale (Dec 2025)
| Script | Purpose | Recommendation |
|--------|---------|----------------|
| `scripts/watch-icon-align.py` | Icon alignment dev | REVIEW - still needed? |
| `scripts/vlm-status.sh` | VLM status | REVIEW |
| `scripts/vlm-audit-screens.py` | VLM screen audit | REVIEW |

---

### Unusual Directories Summary

| Directory | Last Modified | Contents | Recommendation |
|-----------|---------------|----------|----------------|
| `draft-renderers/` | Jan 13 | JS prototypes | ARCHIVE - experimental |
| `extensions/` | Jan 13 | talkie-sdk.js | CLARIFY or ARCHIVE |
| `specs/` (root) | Jan 7 | Single .md file | MERGE into docs/specs/ |
| `tools/` | Jan 25 | TalkieRunner apps | KEEP - dev tools |
| `assets/` | Jan 11 | Screenshots + icons | KEEP |
| `AppIcon.appiconset/` | Jan 19 | App icons | KEEP |

---

## 7. Proposed Cleanup Plan

### Phase 1: Safe Deletions (no git impact)
```bash
# Delete gitignored build artifacts (~1.1 GB)
rm -rf build/ node_modules/ packaging/macos/staging/ packaging/macos/releases/
rm -rf Landing/.next/ Landing/node_modules/ Landing/out/
rm -rf services/talkie-api/.vercel/
```

### Phase 2: Git Additions
```bash
# Add .vercel to gitignore
echo ".vercel/" >> .gitignore

# Commit new voice-nav feature files
git add apps/macos/Talkie/Services/MemorySampler.swift
git add apps/macos/TalkieKit/Sources/TalkieKit/VoiceIntentRecognizer.swift
git add apps/macos/TalkieAgent/TalkieAgent/Services/VoiceNavigationHandler.swift
git add docs/specs/ios-keyboard-ux-design.md
git add docs/specs/macos-distribution-telemetry-paywall.md
```

### Phase 3: Consolidation (requires review)
```bash
# Move stale root docs to archive
mkdir -p docs/_archive/2025-12
mv AUDIT-2025-12-29.md docs/_archive/2025-12/
mv IMPLEMENTATION_PROGRESS.md docs/_archive/2025-12/
mv ONBOARDING_LAYOUT_FIXES.md docs/_archive/2025-12/
mv ENVIRONMENT_PLAN.md docs/_archive/2025-12/

# Move active docs to proper locations
mv ONBOARDING_SPEC.md docs/onboarding/
mv DEBUGKIT_INTEGRATION.md docs/engineering/
mv STAGING_SETUP.md docs/
mv XCODE_CONFIGURATION_STEPS.md docs/engineering/

# Consolidate specs
mv specs/multi-dictionary-architecture.md docs/specs/
rmdir specs

# Move images
mv image.png assets/ 2>/dev/null || rm image.png
mv Talkie-iOS-Default-1024x1024@1x.png assets/

# Archive stale doc directories
mv docs/design-system-iterations docs/_archive/2025-12/
mv docs/onboarding docs/_archive/2025-12/
mv docs/settings-refinement docs/_archive/2025-12/
```

### Phase 4: Decisions Needed
1. `draft-renderers/` - Archive or delete?
2. `extensions/talkie-sdk.js` - What is this for?
3. `WFKit` symlink - Still needed?
4. Root `package.json` with `@arach/speakeasy` - Purpose?
