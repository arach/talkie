# Swift handoff brief — Scope cool-gray canon

Mechanical refactor work to land the 2026-05-21 cool-gray canon in the macOS app. Scoped to **wiring/refactor only — no UX taxonomy, no visual judgment calls, no layout changes** (memory: `feedback_codex_wiring_only.md`).

Studio is the design source of truth (memory: `feedback_visual_iteration_html.md`). Swift catches up.

## Canon decision

**2026-05-21:** Scope substrate pivoted from warm cream to cool neutral gray. Icy, not blue, grayish. Frosted instrument case; brass + amber accents stay warm against the cool substrate.

Studio source of truth: `design/studio/lib/scope-tokens.ts` (`SCOPE` const). Studio convention doc: `design/studio/lib/AGENTS.md`.

Studio values (canonical):

| Token | Hex | Was (warm) |
|---|---|---|
| canvas | `#F8F8F7` | `#FBFBFA` |
| canvasAlt | `#ECECEB` | `#F2F2F1` |
| pane | `#F1F1F0` | `#FAF7EF` |
| paneLifted | `#EFEFEE` | `#EFEAE0` (warm chip) |
| chrome | `#E7E7E6` | `#F4F1EA` |
| rail | `#DCDCDB` | `#F2EDDE` |
| selection | `#EAEAE9` | `#F2EFE6` |
| ink | `#232423` | `#2A2620` |
| inkMid | `#3A3A38` | `#3F3A33` |
| edge | `#DEDEDD` | `#E0DCD3` |
| ruleSoft | `#E6E6E5` | `#ECE7DD` |
| noteTint | `#767674` | `#6B7A75` (teal-gray) |
| captureTint | `#5C5E5C` | `#5A7A86` (blue-teal) |

Ink rgba derivatives: `rgba(35,36,35,X)` (was `rgba(42,38,32,X)`).

Warm accents unchanged:
- brass `#9A6A22`
- amber `#C47D1C`
- amberDeep `#7A521A`
- dictTint `#E89A3C`

## Swift side — current state

`apps/macos/TalkieKit/Sources/TalkieKit/UI/ScopeDesign.swift` already documents itself as "cool-neutral chassis" but uses values that differ slightly from the studio canon:

| Token | Swift value | Studio canon | Action |
|---|---|---|---|
| `ScopeCanvas.canvas` | `#FBFBFA` | `#F8F8F7` | adjust to `#F8F8F7` |
| `ScopeCanvas.canvasAlt` | `#F2F2F1` | `#ECECEB` | adjust |
| `ScopeCanvas.surface` | `#EDEDEC` | (≈ paneLifted `#EFEFEE`) | adjust |
| `ScopeInk.primary` | `#0F1112` | `#232423` (studio) | **HOLD** — Swift's near-black is fine for "primary headline ink"; studio's `#232423` is the mid-dark used everywhere. Different scales. Don't force a change without visual review. |
| `ScopeInk.dim` | `#1F2123` | (≈ ink `#232423`) | adjust to `#232423` if you want closer studio parity |
| `ScopeAmber.solid` | `#C47D1C` | `#C47D1C` | match ✓ |
| `ScopeBrass` ladder | (varies) | `#9A6A22` brass | verify |

**Decision needed (don't make alone):** Should Swift's `ScopeInk` ladder collapse to match studio's single `ink` value, or should studio expand to match Swift's 5-step ladder? Surface this to the user before changing. For this Codex pass, only adjust `ScopeCanvas` and obvious off-canon values — leave `ScopeInk` alone unless audit findings demand it.

## Scope of work

### Phase 1 — Canon alignment

1. Adjust `ScopeDesign.swift` `ScopeCanvas` values to match studio canon (canvas/canvasAlt/surface) — three hex edits.
2. Verify other `ScopeDesign` enums (`ScopePanel`, `ScopeBrass`, `ScopeAmber`, `ScopeRule`, etc.) read as cool. Flag anything warm with file:line in a note.
3. Build verify: `talkie-dev dev rebuild Talkie` and `talkie-dev dev status`.

### Phase 2 — Inline hex hunt (mac surfaces)

Find inline hex codes in `apps/macos/Talkie/Views/` that bypass `ScopeDesign`. Targets:
- `Views/Home/ScopeHomeView.swift`
- `Views/Library/ScopeLibraryView.swift`
- `Views/TalkieObject/TalkieView.swift`
- `Views/Notes/ScopeNoteDetailView.swift`
- `Views/Notes/ScopeCaptureDetailView.swift`
- `Views/Skills/ScopeSkillsLandingView.swift`
- `Components/TalkieChromeBar.swift`

For each inline `Color.hex("XX")` or `Color(hex:)` literal:
- If it matches a ScopeDesign token → refactor to use the token
- If it's a stray warm value → map to closest cool canon value
- If unclear → leave + flag in a note

Do **not** edit layout, copy, spacing, or typography. Tokens only.

### Phase 3 — Audit-driven fixes (await findings)

The studio audit page lists 8 audited-and-shipped items as of 2026-05-21. Six Swift-side review agents are running now; their findings will land in `design/studio/data/audit/scope-2026-05-21.json` under IDs prefixed `sw-home-`, `sw-lib-`, `sw-dict-`, `sw-note-`, `sw-cap-`, `sw-sk-`.

For each landed Swift finding with severity `issue` or `blocker` that's mechanical (token swap, ScopeRule migration, inline hex elimination):
- Mark `status: "inflight"` in the audit JSON with your handle
- Apply the fix
- Mark `status: "shipped"` with a `landed` note + commit SHA ref

Skip any finding that requires:
- Visual judgment ("should this be brighter?", "does this read editorial?")
- Layout/composition changes (move blocks, restructure rails)
- Copy edits (anything in the surface's text)
- New taxonomic decisions

For those, post a `proposal` note flagging it as "needs claude/painter handoff."

## Protocol

- Read `design/studio/data/audit/AGENTS.md` for the audit worksheet protocol — same conventions as `data/parity/AGENTS.md`.
- Status file is `design/studio/data/audit/scope-2026-05-21.json`. Append notes; don't rewrite existing entries.
- One commit per Phase. Commit messages: `🎨 Sweep Swift canvas tokens to cool-gray canon` etc. (gitmoji per project convention).
- Per project convention, **don't co-author commits**.

## Build & verify

- Build: `talkie-dev dev rebuild Talkie` (do NOT use raw `xcodebuild`)
- Status: `talkie-dev dev status`
- Logs: `talkie-dev dev logs Talkie --since 5m`

## Synthesis from 6 Swift reviewers (2026-05-21)

48 findings across 6 surfaces. Pattern: **token adoption is the single highest-leverage move** — every surface declares a local token shadow that drifted from canon.

### Cross-cutting themes (fix once, pay everywhere)

| Theme | Hits | Severity | Fix |
|---|---|---|---|
| **Local token shadows** — `NoteToken`, `CapToken`, `SkillsToken`, and 40 inline `Color.hex(...)` calls in Home/Library duplicate ScopeDesign and drift warm | Note, Capture, Skills, Home, Library | blocker | Delete local tokens; bind to `ScopeCanvas` / `ScopeInk` / `ScopeBrass` / `ScopeAmber` / `ScopeRule` |
| **Warm tobacco ink `#2A2620` lingers in local tokens** even though `ScopeInk.primary` is cool `#0F1112` | Note, Capture, Skills | blocker | Use `ScopeInk.primary/dim/muted/faint` instead of local ink |
| **Hand-rolled `Rectangle().fill()` hairlines** bypass `ScopeRule(.section/.row/.subtle/.action)` | All 6 (Library 6+, Home 6+, Skills 12+) | issue | Replace each Rectangle hairline with `ScopeRule(...)` |
| **Marketing copy in chrome** — Home Did-you-know serif hooks, Library "Hyper+M to record." subtitle, Skills footer paragraph, Capture "promotes to a note" italic, Note fake "CH-04" channel | Home, Library, Skills, Note, Capture | issue | Strip narrative; let affordances speak |
| **Amber over-used** — Home brass 40 inline call sites; Library amber on filter underline + bucket eyebrow + selection + dividers + pagination + footer + mic; Skills amber on 12+ call sites | Home, Library, Skills | issue | Ration amber: one primary per zone; demote sibling CTAs to `ScopeInk.muted` |
| **Dead readout-bay scaffolding** in Library (~400 lines: `libraryReadoutPanel`, `ReadoutSurface`, `LibraryReadoutBodyVariant`, variant switcher) — already flagged dead at L731-739 | Library | issue | Delete; the inspector inherits the editorial document layout |

### Per-surface action checklist (mechanical)

**ScopeDesign.swift (canon source)**
- [ ] Adjust `ScopeCanvas.canvas` `#FBFBFA` → `#F8F8F7` (or hold if visually identical; verify)
- [ ] Adjust `ScopeCanvas.canvasAlt` `#F2F2F1` → `#ECECEB`
- [ ] Adjust `ScopeCanvas.surface` `#EDEDEC` → `#EFEFEE` (paneLifted)
- [ ] Add `ScopeBrass` enum mirroring studio brass (`#9A6A22` solid, `#7A521A` deep) — referenced by ~40 Home call sites
- [ ] Add `ScopeKind` enum mirroring studio kind tints: `memo #9A6A22`, `dict #E89A3C`, `note #767674`, `capture #5C5E5C` — used for kind stripes
- [ ] Leave `ScopeInk` 5-step ladder alone; it's cooler than studio's single `ink` value and serves a different layered purpose

**ScopeHomeView.swift (2308 lines)**
- [ ] Replace 40 inline `Color.hex("9A6A22")` / `Color.hex("7A521A")` calls with `ScopeBrass.solid` / `ScopeBrass.deep`
- [ ] Fix `RecentTwoPane.swift L88` `contentTint #6B7A75` → `ScopeKind.note`
- [ ] Replace 6+ `Rectangle().fill(ScopeEdge.faint).frame(height: 0.5)` with `ScopeRule(.section/.row/.subtle)`
- [ ] Drop leading `"· "` from `Eyebrow` in `ScopeComponents.swift L85` (or gate via `accent: Bool` param)
- [ ] Strip Did-you-know serif marketing hooks (L612-625) → neutral mono instrument labels
- [ ] Demote Routines + Did-you-know to borderless rows on canvas (keep Bay + Recent as cards) — **NEEDS painter review, don't apply alone**

**ScopeLibraryView.swift (1914 lines)**
- [ ] Delete dead readout-bay code: `libraryReadoutPanel`, `ReadoutSurface`, `LibraryReadoutBodyVariant`, `variantSwitcherStrip` (line range ~684–1880)
- [ ] Rewrite file header (L5-10) — no more "cream-phosphor" / "tape archive" / "amber 'ON FILE'"
- [ ] Promote inline hexes to `ScopeKind` enum and the readout-source-tint colors (`#6B4FBB`, `#0B1418`, `#15191E`, `#2A3138`, `#5FE3C9`) to a `ScopePanel` extension or `ScopeReadout` namespace
- [ ] Replace ~6 hand-rolled hairlines with `ScopeRule(...)`
- [ ] De-amber chrome: bucket eyebrows → `ScopeInk.muted`, dividers → `ScopeEdge.faint`, pagination dots → `ScopeInk.faint`
- [ ] Strip marketing subtitle (L632-641) "Hyper+M to record." etc. → single neutral label
- [ ] Wire `ScopeLibraryRow.channelColor` (L1485-1493) to `ScopeKind` instead of amber-only memo

**TalkieView.swift (1014 lines)**
- [ ] **HIGHEST PRIORITY:** Replace warm chiffon gradient (L287-297) `#FAF7EF → #FAF6EB → #F7F2E5` with `ScopeCanvas.canvas` — this is the visible "pale cream" issue user flagged
- [ ] Update stale comments (L118-120, L150, L283-286) — drop "chiffon paper" language
- [ ] Adopt `ScopeRule(.section/.row/.subtle)` in `TOHeaderSection` / `TOSharedComponents` for dividers
- [ ] Drop overlay (L259-277): use `ScopeAmber.solid/tint` + `ScopeType.eyebrow` instead of `settings.resolvedAccentColor` + `Theme.current.fontSM`
- [ ] Add `ScopeRule(.subtle, axis: .vertical)` between body and margin rail
- [ ] Replace `PageLayout.headerHeight + 18` magic number with `PageLayout.headerOverlayClearance`

**ScopeNoteDetailView.swift (423 lines)**
- [ ] Delete `NoteToken` enum entirely; bind to `ScopeCanvas` / `ScopeInk` / `ScopeEdge` / `ScopeBrass` / `ScopeAmber`
- [ ] Body `ink.opacity(0.88)` → `ScopeInk.dim` directly (no more opacity layering on warm ink)
- [ ] Attachment rail bg `#F2EDDE` → `ScopeCanvas.surface` (#EFEFEE) or `ScopeRule(.row)` for top hairline
- [ ] Strip fake `"CH-04 · NOTE"` channel label — show real `note.source.displayName` or nothing — **NEEDS painter call**
- [ ] Replace synthetic `N-####` sequence from hashValue — use real persistent ID or drop chip — **NEEDS painter call**
- [ ] Empty-state italic serif "none yet" → mono 9pt at `ScopeInk.faint`

**ScopeCaptureDetailView.swift (549 lines)**
- [ ] Delete `CapToken` enum; bind to `ScopeCanvas` / `ScopeInk` / `ScopeEdge`
- [ ] Image mat `#F2EDDE` → `ScopeCanvas.surface` (#EFEFEE); drop the warm `matAlt #E8DFC8`
- [ ] Promote `captureTint #5A7A86` to `ScopeKind.capture` (#5C5E5C) — currently a local one-off
- [ ] Strip "promotes to a note" italic narration; keep "+ ADD CAPTION" with ⌘N hint
- [ ] Promote `derivedCaption` to serif headline; demote filename to mono byline — **NEEDS painter review for visual treatment**
- [ ] Fix stray hairline inside eyebrow row (Rectangle inside HStack stretches incorrectly)
- [ ] Foot action `tone.opacity(0.75)` → drop the 0.75 multiplier; use `ScopeInk.muted` for neutral

**ScopeSkillsLandingView.swift (1777 lines)**
- [ ] Delete `SkillsToken` enum; bind to `ScopeCanvas` / `ScopeInk` / `ScopeAmber` / `ScopePanel`
- [ ] voicePreview hardcoded `#0E1518` / `#F4F1EA` → `ScopePanel.bg` / `ScopePanel.ink` / `ScopePanel.trace`
- [ ] Replace 12 hand-rolled `Rectangle().fill(SkillsToken.inkRuleSoft).frame(height: 1)` with `ScopeRule(.subtle)` / `ScopeRule(.row)`
- [ ] **Ration amber:** demote AGENT eyebrow, console arrows, miniChip borders, mic hover, and one of RUN/SAVE to ink/brass — **NEEDS painter review for which 3 stay amber**
- [ ] Standardize section gaps to a `SkillsSpacing.sectionGap` token (currently 14 vs 32 inconsistent)
- [ ] Cut footer paragraph (marketing copy) to a one-line italic byline or remove
- [ ] Add `.accessibilityLabel` to inlineMic and submitButton

### Codex execution order

1. **ScopeDesign.swift adjustments** (highest leverage, single file)
2. **TalkieView warm gradient** (most visible UI regression)
3. **Delete local token enums** in order: NoteToken → CapToken → SkillsToken (cleanest mechanical refactor)
4. **Delete dead Library readout-bay code** (~400 lines removed; nothing else breaks)
5. **Promote brass + kind tints to ScopeDesign** (then propagate through Home + Library)
6. **ScopeRule sweep** across the 6 surfaces (mechanical pattern: Rectangle hairline → ScopeRule)
7. **Marketing copy strips** — only the trivially-removable ones (footer paragraphs, italic narrations); flag the rest for painter
8. **Build verify** after each phase: `talkie-dev dev rebuild Talkie`

### Items needing painter (claude) before Codex acts

- `sw-home-card-equal-weight` — demote which sections to borderless rows? Visual judgment.
- `sw-note-channel-label-marketing` — "CH-04 · NOTE" replacement: show real source or nothing? Decision.
- `sw-note-sequence-fake-id` — show real persistent ID or drop chip? Decision.
- `sw-cap-filename-headline` — visual reweighting of derivedCaption vs filename hierarchy.
- `sw-sk-amber-flood` — choose 3 amber slots that stay; demote the rest. Needs painter eye.

These are listed as `proposal` notes in `data/audit/scope-2026-05-21.json` for Codex to acknowledge but not act on.

## Out of scope

- iOS app (`apps/ios/`) — separate canon question, deferred
- iPhone Scope theme bundle in `globals.css` — shares the name, different concept
- `lib/schemes.ts` dark instrument bay schemes — separate concept
- Studio (`design/studio/`) — already migrated, source of truth
- New audit findings discovery — that's claude/painter work
