# Mac Home — Decisions Log

## What the study renders

The full macOS Home screen composition. Source of truth in Swift:
`apps/macos/Talkie/Views/Home/ScopeHomeView.swift`.

This is a **composition study**, not a scheme study. The page renders
one Mac Home at a realistic window width (~1100px) on the cream studio
canvas, with the embedded agent bay using the AMBER scheme.

## The simplification → reintegration arc

The Scope theme started as a deliberate over-simplification — strip
the original HomeGrid card system down to the editorial bone so a new
design language could form. That worked. The cream canvas + dark
instrument bay + editorial serif hero are the new vocabulary.

But the original component taxonomy in `HomeGrid.swift` had real
utility. The simplified Scope home lost too much:

**Original taxonomy (HomeGrid.swift):**
- Stats — today / memos / dictations / words
- Actions — record / helpers / workflows / settings
- Devices — bridge state
- Widgets — trending / shortcuts / activity / calendar
- Content — recent memos / recent dictations
- Features — captures / workflow runs / agent console
- System status — full-width status rail
- Brand hero, setup cards (situational)

**Simplified Scope home (current shipping):**
- Top band, Hero, Capture modes (3), Agent bay, Captures table, Ownership strip

So Workflows entry, Console quick-access, Discovery widgets (calendar /
shortcuts / trending), and a System status rail were all dropped.

## What this composition reintegrates

| Section | Status | Source in original taxonomy |
|---|---|---|
| Top band | Kept | (universal chrome) |
| Hero | Kept | (editorial flourish) |
| Capture modes | Kept | (Scope-era) |
| Agent bay | Kept | (Scope-era; bay polish branch) |
| **Routines strip** | **RESTORED** | `actionWorkflows` + `actionHelpers` + `featureAgentConsole` |
| Captures activity | Kept | `featureCaptures` / `recentMemos` + `recentDictations` |
| **Discovery row** | **RESTORED** | `widgetActivity` + `widgetShortcuts` + `widgetTrending` |
| **System status bar** | **RESTORED** | `systemStatus` + `devicesBridge` |
| Ownership strip | Kept | (Scope-era) |

## Design principles for the reintegration

1. **Cream stays the floor.** The bay is the one dark moment. All
   restored sections are light cards on the cream canvas — they should
   read as cousins of the Capture Mode cards, not competing dark slabs.

2. **Each section earns its eyebrow.** Every restored block carries a
   `· EYEBROW` label so the page reads as a clear sequence of named
   territories, not a scrollable grab-bag.

3. **Stats live in the bay, not above it.** The original had a stats
   row (today/memos/dictations/words) as separate cards. The bay
   already shows those — duplicating outside would dilute. Bay = stats.

4. **Routines pair as a 2-column strip, not 4 cards.** Workflows +
   Console are the two operational surfaces; pair them in a 2-col band
   so they read as a unit, not as scattered tiles.

5. **Discovery is a 3-col row at the same density as Capture modes.**
   Today (calendar) · Shortcuts · Trending. These are situational
   discovery surfaces; they should be present-and-useful, not loud.

6. **System status is a single thin rail, not cards.** A row of dot +
   label + detail entries. Reads as a health indicator, not as a
   feature surface.

## Theme → scheme bindings (light mode)

Decided 2026-05-17 — the two canonical light-mode bay schemes:

| Theme intent | Canonical bay | Family | Why |
|---|---|---|---|
| **Modern** | **PEARL** `#F5F8FA` | Cool light | Reads as clean, clinical, modern instrument panel — the "dashboard" register |
| **Scope** | **CHIFFON** `#FAF5E8` | Warm light | Reads as editorial cream, recedes into the page chrome — the "printed" register |

The canonical is the **lightest** scheme in each family — the recession is the point. Heavier siblings are available when the bay needs more presence:
- Modern (cool): **PEARL** (canonical, lightest) · PORCELAIN (mid) · ALUMINUM (saturated)
- Scope (warm): **CHIFFON** (canonical, lightest) · VELLUM (mid) · PAPER (saturated)

Use the canonical when the bay should melt into the page; use the heavier siblings when the bay needs to punctuate like the original dark AMBER did.

**AMBER** remains as the reference for the original "lit electronics bay" identity — kept in the picker so we can flip back and see what we moved away from.

**System Status rail follows the bay's scheme.** When the bay is PORCELAIN, the rail is also PORCELAIN-toned (cool light strip). When AMBER, the rail returns to its dark gunmetal-with-phosphor original. The rail and bay are now siblings wearing the same material — the two "instrument" ends of the same body, with the editorial cream content sitting between them.

## Open questions

- Whether the Mac Home should support a configurable card system (like
  the original HomeGrid) where users hide/reorder sections, or whether
  this composition is the canonical shape and Mac Home stops being
  configurable.
- Whether the bay should remain a separate section or absorb the
  Routines strip below it (instrument-bay + Workflows/Console as one
  larger console-style block).
- Whether Discovery widgets should be theme-aware (calendar shows
  different content density in Scope vs. Technical theme).
- How the Mac Home handles empty states for restored sections — what
  does Routines look like when no workflows have run yet?

## Component map

- `components/studies/MacHome.tsx` — composition root
- `components/studies/Bay.tsx` — agent bay artifact (shared with
  agent-bay study; rendered here with AMBER scheme vars applied
  inline)
- Sub-components inline in MacHome.tsx:
  `TopBand`, `Hero`, `CaptureModes`/`CaptureCard`, `BayBlock`,
  `RoutinesStrip`/`Panel`, `ActivitySignalTable`, `DiscoveryRow`/
  `WidgetCard`, `SystemStatusBar`/`StatusDot`, `OwnershipStrip`/
  `OwnershipCol`, `SectionBlock`
