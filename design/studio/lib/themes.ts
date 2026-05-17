/**
 * The 4 iOS user-facing themes (+ Lift as an exploration variant).
 * Each is a coherent designed system — not just a color remap. Color,
 * behavior, material identity all bundle together.
 *
 * Type stack is shared across all themes, native Apple fonts:
 *   display = SF Pro Display (`-apple-system`)
 *   body    = SF Mono        (Talkie brand: bodies are monospaced —
 *                             matches iOS Typography.bodyMedium)
 *   chrome  = SF Mono        (channel labels, eyebrows, status pills)
 *
 * The studio runs on macOS so these resolve natively; no web font load.
 * Mocks render exactly what iOS will render.
 *
 * Themes differentiate via color, display weight + tracking, eyebrow
 * leader glyph, chrome corner radius, hairline weight, and glow halo.
 *
 * Token application: a `[data-theme="key"]` block in app/globals.css
 * remaps every `--theme-*` CSS var. Components read those vars via
 * `var(--theme-canvas)` / `var(--theme-amber)` / etc.
 */

export interface IOSTheme {
  key: "scope" | "midnight" | "tactical" | "ghost" | "lift";
  name: string;
  /** One-line identity. What does it FEEL like at a glance? */
  identity: string;
  /** Longer description for the theme card. */
  blurb: string;
  /** Hex of the theme's canvas — shown in the picker as a hint. */
  canvasHex: string;
  /** Hex of the accent color, for visual reference in tooling. */
  accentHex: string;
  /** Typographic variation per theme — face is shared (Newsreader),
   *  weight + tracking shift the editorial register. */
  display: {
    weight: 400 | 500 | 600;
    tracking: string;
    /** Use italic for accent words in headlines. */
    italicAccent: boolean;
  };
  /** Behavior flags — drive component-level conditional rendering. */
  behavior: {
    /** Phosphor glow on the accent (text-shadow / drop-shadow). */
    phosphorGlow: boolean;
    /** Faint graticule overlays behind heroes. */
    graticule: boolean;
    /** Dark background = inverted ink ladder. */
    darkSurface: boolean;
  };
  /** Quick palette preview, for the theme detail card on the gallery. */
  preview: { label: string; hex: string }[];
}

export const IOS_THEMES: IOSTheme[] = [
  {
    key: "scope",
    name: "Scope",
    identity: "Warm cream paper · brass amber phosphor",
    blurb:
      "The default. Vintage instrument panel without the parchment heat. Cool-slate cream canvas (re-grounded in commit 416fa35), brass amber accent, charcoal trace. Phosphor glow is subtle.",
    canvasHex: "#FBFBFA",
    accentHex: "#C47D1C",
    display: { weight: 500, tracking: "-0.018em", italicAccent: true },
    behavior: { phosphorGlow: true, graticule: true, darkSurface: false },
    preview: [
      { label: "canvas", hex: "#FBFBFA" },
      { label: "paper", hex: "#FFFFFF" },
      { label: "ink", hex: "#2A2620" },
      { label: "amber", hex: "#C47D1C" },
      { label: "screen", hex: "#0A0907" },
      { label: "trace", hex: "#E89A3C" },
    ],
  },
  {
    key: "midnight",
    name: "Midnight",
    identity: "Vercel-blue on near-black · em-dash eyebrows",
    blurb:
      "Dark chassis with vivid information-blue accent (NOT phosphor green). Mirrors iOS `midnightChrome`. Em-dash eyebrow leader, 2px chrome corners, glow radius 3. Reads as a confident dark dev tool, not a CRT.",
    canvasHex: "#0A0A0A",
    accentHex: "#0084FF",
    display: { weight: 500, tracking: "-0.018em", italicAccent: true },
    behavior: { phosphorGlow: true, graticule: false, darkSurface: true },
    preview: [
      { label: "canvas", hex: "#0A0A0A" },
      { label: "paper", hex: "#111111" },
      { label: "ink", hex: "#FAFAFA" },
      { label: "blue", hex: "#0084FF" },
      { label: "screen", hex: "#000000" },
      { label: "trace", hex: "#0084FF" },
    ],
  },
  {
    key: "tactical",
    name: "Tactical",
    identity: "Palantir-orange field unit · square corners",
    blurb:
      "Vivid orange accent (#FF8800) on near-black, Anduril/Palantir-inspired. Mirrors iOS `tacticalChrome`: SQUARE corners (0px), heavier 1px hairlines, near-zero glow halo, `›` eyebrow leader. Reads as utility hardware, not editorial.",
    canvasHex: "#0A0A0A",
    accentHex: "#FF8800",
    display: { weight: 500, tracking: "-0.015em", italicAccent: false },
    behavior: { phosphorGlow: false, graticule: false, darkSurface: true },
    preview: [
      { label: "canvas", hex: "#0A0A0A" },
      { label: "paper", hex: "#1A1A1A" },
      { label: "ink", hex: "#F0F0F0" },
      { label: "orange", hex: "#FF8800" },
      { label: "screen", hex: "#000000" },
      { label: "trace", hex: "#FF9020" },
    ],
  },
  {
    key: "lift",
    name: "Lift",
    identity: "Pure white · hierarchy via shadow elevation",
    blurb:
      "All surfaces are #FFFFFF — canvas, paper, sheet. No tonal differentiation between layers; hierarchy comes entirely from drop-shadow elevation. Indigo accent stays restrained. The cleanest theme; the one that asks the most from layout discipline.",
    canvasHex: "#FFFFFF",
    accentHex: "#6366F1",
    display: { weight: 400, tracking: "-0.02em", italicAccent: true },
    behavior: { phosphorGlow: false, graticule: false, darkSurface: false },
    preview: [
      { label: "canvas", hex: "#FFFFFF" },
      { label: "paper", hex: "#FFFFFF" },
      { label: "sheet", hex: "#FFFFFF" },
      { label: "ink", hex: "#1A1A1A" },
      { label: "accent", hex: "#6366F1" },
      { label: "shadow", hex: "elevation" },
    ],
  },
  {
    key: "ghost",
    name: "Ghost",
    identity: "Indigo stationery · diffuse 7px halo",
    blurb:
      "Near-white paper with INDIGO accent (#6366F1, NOT slate). Mirrors iOS `ghostChrome`: diffuse 7px glow halo (vapory), softer 5px chrome corners. Pure stationery base with a refined chromatic accent. The screen — when present — is deep indigo navy.",
    canvasHex: "#F5F5F5",
    accentHex: "#6366F1",
    display: { weight: 400, tracking: "-0.02em", italicAccent: true },
    behavior: { phosphorGlow: true, graticule: false, darkSurface: false },
    preview: [
      { label: "canvas", hex: "#F5F5F5" },
      { label: "paper", hex: "#FFFFFF" },
      { label: "ink", hex: "#2A2A2A" },
      { label: "indigo", hex: "#6366F1" },
      { label: "screen", hex: "#1E1B4B" },
      { label: "trace", hex: "#A5B4FC" },
    ],
  },
];
