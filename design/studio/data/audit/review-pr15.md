# PR #15 independent review — talkie-codex

Branch reviewed: `ui/scope-pass-may-20` at `f6e8191`, including local working-tree changes present on 2026-05-21.

Verdict: **HOLD**

The app builds, and the deleted Library readout-bay symbols are not referenced by live Swift. But I would not merge the PR as described yet: the local tree is dirty, two visible in-scope surfaces still carry warm/off-canon chrome, and the PR/audit claims are out of sync with local truth.

Validation run:

- `cd apps/macos && ./run.sh Talkie --clean --no-launch` → **BUILD SUCCEEDED**, dev app installed.
- `rg '\b(libraryReadoutPanel|ReadoutSurface|LibraryReadoutBodyVariant|variantSwitcherStrip)\b' . --glob '*.swift'` → no Swift references.

## Top findings

### 1. [blocker] PR branch is not merge-ready: local ground truth is dirty and not in GitHub PR

`git status --short --branch` shows local modifications/deletions/untracked files beyond `origin/ui/scope-pass-may-20`:

- Deleted starters: `apps/macos/Talkie/Resources/Starters/capture-thought.skill.md`, `daily-standup.skill.md`, `log-bug.skill.md`
- Added untracked starters: `monitor.skill.md`, `prepare.skill.md`, `research.skill.md`, `screenshot.skill.md`
- Modified Swift/project/audit files including `ScopeHomeView.swift`, `ScopeLibraryView.swift`, `ScopeSkillsLandingView.swift`, TalkieObject sections, `ScopeDesign.swift`, and `scope-2026-05-21.json`

If someone merges PR #15 as it exists on GitHub, they will not get the local "ground truth" reviewed here. Commit/push or intentionally discard these before merge.

### 2. [issue] Home still defaults to a warm CHIFFON bay despite the cool-gray canon claim

The local Home agent bay keeps a full warm family and defaults to it:

- `apps/macos/Talkie/Views/Home/ScopeHomeView.swift:84-91` defaults `scopeAgentBay.scheme` to `BayScheme.chiffon`
- `apps/macos/Talkie/Views/Home/ScopeHomeView.swift:1404-1417` documents Scope canonical as `CHIFFON (warm family)` with `vellum`/`paper` warm siblings
- `apps/macos/Talkie/Views/Home/ScopeHomeView.swift:1494-1532` uses warm fills/inks (`#FAF5E8`, `#F4EFE0`, `#EEE7D6`, warm espresso/brown label colors)
- `apps/macos/Talkie/Views/Home/ScopeHomeView.swift:1550-1581` keeps warm gradient strips for chiffon/vellum/paper

This undercuts the PR body's Stage 2 claim that substrate shifted from warm cream to cool neutral gray. It is not just stale comments: the default rendered Home bay remains warm for a fresh/default Scope user.

### 3. [issue] Memo/detail surfaces still have off-canon warm/inline chrome and hand-rolled rules

The ScopeDesign sweep did not cover all live detail chrome:

- `apps/macos/Talkie/Views/TalkieObject/Sections/TOPlaybackSection.swift:55-94` still renders the audio player rail as a warm cream band with `Color.hex("F2EDDE")` and a brown `Color.hex("1A1612")` 0.5pt hairline.
- `apps/macos/Talkie/Views/TalkieObject/Sections/TOHeaderSection.swift:126-132` maps kind tints through inline `Color.hex`, including stale note/capture colors `#6B7A75` / `#5A7A86` instead of `ScopeKind.note` / `ScopeKind.capture`.
- `apps/macos/Talkie/Views/TalkieObject/Sections/TOHeaderSection.swift:203-207` and `:403-405` still use inline brass/amber literals.
- `apps/macos/Talkie/Views/TalkieObject/Sections/TOMarginRail.swift:229-252` still uses `Color.hex("9A6A22")` for accent values.
- `apps/macos/Talkie/Views/TalkieObject/Sections/TOSharedComponents.swift:805-814` still has a hand-rolled `Rectangle().fill(...).frame(height: 0.5)` and inline brass; `:1308-1311` has another inline brass accent.

This is exactly the survivor pattern the review request asked us to hunt for (`Color.hex("9A6A22")` and `Rectangle().fill(...).frame(height: 0.5)`).

### 4. [issue] The brief was not exhaustive: other local token shadows remain, some on claimed/studio-backed surfaces

`SkillsToken`, `NoteToken`, and `CapToken` were deleted, but other local token shadows still duplicate pre-canon colors:

- `apps/macos/Talkie/Views/Onboarding/ScopeOnboardingView.swift:719-729` has `ScopeOnboardingTokens` with warm cream/paper/tobacco ink.
- `apps/macos/Talkie/Views/RecordingHUDView.swift:336-344` has `HUDTokens` with `#FBFBFA` surface and tobacco ink.
- `apps/macos/Talkie/Views/RecordingCompanionSurface.swift:614-621` has `RecordingCompanionTokens` with `#2A2620`, `#F4F1EA`, `#FBFBFA`.
- `apps/macos/Talkie/Views/Home/RecentTwoPane.swift:86-90` still has a small `RecentPaneTokens` local color enum; most values are now canonical, but it is still a local shadow.

This also exposes a PR-description mismatch: the PR body lists onboarding and RecordingHUD as Stage 1 Swift ports, while `design/studio/app/mac-coverage/page.tsx:108-124` explicitly marks Recording HUD and Onboarding as backlog/not latest.

### 5. [issue] Capture detail still generates a user-visible synthetic ID from `hashValue`

`apps/macos/Talkie/Views/Notes/ScopeCaptureDetailView.swift:79-82` computes `C-####` / `S-####` with `abs(capture.id.hashValue) % 10000`, and `:153-158` renders it in the eyebrow.

Swift `hashValue` is not a stable persistent identifier; this can change across launches/processes. It is the same class of bug the painter decision fixed for Note synthetic sequence IDs. Use a stable UUID prefix, or drop the chip until there is a real persistent ID.

## Other checks

- Deleted readout-bay safety: no live Swift references to `libraryReadoutPanel`, `ReadoutSurface`, `LibraryReadoutBodyVariant`, or `variantSwitcherStrip`.
- Painter decisions mostly landed: Home routines/tips are demoted to rule-separated rows; Note CH-04 and N-#### are gone; Capture caption/file hierarchy is applied; Skills amber is mostly rationed to RUN/SAVE/mic hover. Remaining issue: Capture still has its own hash-based sequence chip.
- Audit JSON honesty: local `scope-2026-05-21.json` is now **105 shipped / 1 skipped**, not the PR body's **47 → 100 shipped out of 106** (`/tmp/pr15_body.md:61`). PR body also says `40 commits · 143 files`; `gh pr view` reported 40 commits / 100 files, and local `git diff origin/master..HEAD --stat` showed 139 files. Update the PR body after committing the local state.
