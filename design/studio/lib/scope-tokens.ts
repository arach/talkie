/**
 * Scope canon tokens — single source of truth for the macOS Scope substrate.
 *
 * Why this file exists
 * --------------------
 * Before this module, every Mac*.tsx file declared its own `const T = {...}`
 * with hex codes copied from neighbouring files. Canon shifts (like the
 * 2026-05-21 cool-gray pivot) meant chasing 20+ hexes across 24 files with
 * grep + replace. That's the wrong shape for a design system.
 *
 * Now every Mac surface imports `SCOPE` from here and the substrate is one
 * file edit. Local files can still alias `const T = SCOPE` for terse usage.
 *
 * What lives here
 * ---------------
 * - Substrate ladder (canvas → pane → chrome → rail)
 * - Ink ladder (ink → inkMid → inkFaint → inkFainter)
 * - Rule + edge values (semantic ScopeRule colors)
 * - Warm accents (brass, amber — instrument metal against cool case)
 * - Kind tints (dictation, memo, note, capture, alert)
 * - Selection lift + pure white
 *
 * What does NOT live here
 * -----------------------
 * - iOS phone theme bundles → `globals.css` `[data-theme="X"]` blocks
 * - Dark instrument scheme cards (AMBER, CARBON, etc.) → `lib/schemes.ts`
 * - Tailwind chrome tokens (`text-studio-ink` etc.) → `tailwind.config.ts`
 *   (those are kept in sync with this file by hand — see SCOPE values below)
 *
 * Canon history
 * -------------
 * - 2026-05-21 — pivot from warm cream (#FBFBFA / #2A2620) to cool gray
 *   (#F8F8F7 / #232423). Icy, not blue. Frosted instrument case.
 *   Accents (brass/amber) stay warm — they read as metal.
 */

export const SCOPE = {
  // ── Substrate ladder ────────────────────────────────────────────────
  // Cool-neutral gray with slight cool lean (B channel ~+1 from R).
  // Frosted instrument case; never blue.
  canvas:      "#F8F8F7",  // page background
  canvasAlt:   "#ECECEB",  // alternate section bg
  pane:        "#F1F1F0",  // panel lifted off canvas
  paneLifted:  "#EFEFEE",  // hover lift / mild emphasis
  chrome:      "#E7E7E6",  // header strips, toolbar fills
  rail:        "#DCDCDB",  // deepest gray that's still "light"
  selection:   "#EAEAE9",  // selected row / cell

  // ── Ink ladder ──────────────────────────────────────────────────────
  // Cool dark; not warm-brown.
  ink:         "#232423",
  inkMid:      "#3A3A38",
  inkFaint:    "rgba(35,36,35,0.55)",
  inkFainter:  "rgba(35,36,35,0.32)",
  inkSubtle:   "rgba(35,36,35,0.22)",

  // ── Rules ───────────────────────────────────────────────────────────
  // Semantic ScopeRule treatments — see TalkieKit/UI/ScopeDesign.swift.
  rule:        "rgba(35,36,35,0.16)",  // .row
  ruleSubtle:  "rgba(35,36,35,0.10)",  // .subtle
  ruleSection: "rgba(35,36,35,0.22)",  // .section
  ruleSoft:    "#E6E6E5",              // light substrate edge

  // ── Edges ───────────────────────────────────────────────────────────
  edge:        "#DEDEDD",
  edgeSubtle:  "#E6E6E5",

  // ── Warm accents ────────────────────────────────────────────────────
  // These STAY warm against the cool substrate — instrument metal.
  brass:       "#9A6A22",   // secondary action, dictation channel
  amber:       "#C47D1C",   // primary action (ration carefully)
  amberDeep:   "#7A521A",   // hover/pressed amber
  amberFaint:  "rgba(196,125,28,0.08)",
  amberSoft:   "rgba(196,125,28,0.18)",
  alert:       "#C43A1C",   // danger / error
  alertSoft:   "#A0494D",   // muted danger

  // ── Kind tints ──────────────────────────────────────────────────────
  // Per-object-kind color stripes. Dictation/memo stay warm
  // (they're already amber/brass-family). Note/capture are cool gray.
  dictTint:    "#E89A3C",
  memoTint:    "#9A6A22",
  noteTint:    "#767674",
  captureTint: "#5C5E5C",

  // ── Pure ────────────────────────────────────────────────────────────
  white:       "#FFFFFF",
} as const;

/**
 * Mat palette — designer reference showing alternate mat tones with names.
 * Mostly historical / comparative; not used as substrate.
 *
 * If you're picking a substrate color, use SCOPE.* — not these.
 */
export const SCOPE_MATS = {
  paper:     { hex: "#F5F2E8", name: "Paper" },
  vellum:    { hex: "#E7E7E6", name: "Vellum" },
  chiffon:   { hex: "#DCDCDB", name: "Chiffon" },  // formerly warm; now cool canon
  porcelain: { hex: "#EAEEF1", name: "Porcelain" },
  pearl:     { hex: "#F5F8FA", name: "Pearl" },
  frost:     { hex: "#F9FBFC", name: "Frost" },
  bone:      { hex: "#F7F4EC", name: "Bone" },
  sand:      { hex: "#EFE9D8", name: "Sand" },
  cream:     { hex: "#F8F8F7", name: "Cream" },  // formerly warm; now cool canon
} as const;

/** Type-safe key list for components that iterate over the token vocab. */
export type ScopeToken = keyof typeof SCOPE;
