/**
 * The 9 anchor schemes used across every scheme-grid study.
 * Ported from `design/studio/agent-bay/index.html` (origin
 * `ui/instrument-bay-polish`) — anchored on AMBER + PAPER, with
 * a gradient through SLATE / OXIDE / CONCRETE / STEEL / ALUMINUM
 * / BONE so the picker reads as siblings, not jumps.
 *
 * Each scheme is one flat bag of CSS vars (semantic names —
 * `--scheme-bg`, `--scheme-accent`, etc.) applied via
 * <SchemeCard>'s inline style. Artifacts read `var(--scheme-*)`
 * directly in their styling.
 *
 * Adding a scheme: add an entry below, and that's it — every
 * scheme-grid study picks it up automatically.
 */

export interface Scheme {
  key: string;
  /** Display name shown in the card label. */
  name: string;
  /** Single swatch color for the card label dot. */
  swatch: string;
  /** Background hex shown in the label as a hint. */
  bgHex: string;
  /**
   * CSS variables applied to the artifact element. Keep names
   * stable across schemes; the artifact reads `var(--scheme-*)`.
   */
  vars: Record<string, string>;
}

export const SCHEMES: Scheme[] = [
  {
    key: "amber",
    name: "AMBER",
    swatch: "#E89A3C",
    bgHex: "#14181A",
    vars: {
      "--scheme-bg": "#14181A",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #1F2426 0%, #1A1F22 35%, #0F1416 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #0D1113 0%, #161B1E 55%, #1E2528 100%)",
      "--scheme-graticule": "rgba(232, 154, 60, 0.08)",
      "--scheme-ink": "#E89A3C",
      "--scheme-ink-faint": "#7A8B85",
      "--scheme-ink-subtle": "#6B7A75",
      "--scheme-accent": "#E89A3C",
      "--scheme-accent-glow": "rgba(232, 154, 60, 0.50)",
      "--scheme-accent-ring": "rgba(232, 154, 60, 0.06)",
      "--scheme-trace": "#E89A3C",
      "--scheme-rec": "#FF5A4A",
      "--scheme-rec-glow": "rgba(255, 90, 74, 0.55)",
      "--scheme-sparkle": "#FF5A4A",
      "--scheme-edge": "rgba(232, 154, 60, 0.10)",
      "--scheme-edge-strong": "rgba(232, 154, 60, 0.28)",
      "--scheme-details-bg": "rgba(232, 154, 60, 0.08)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.10)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.45)",
    },
  },
  {
    key: "carbon",
    name: "CARBON",
    swatch: "#FF9D33",
    bgHex: "#0E0F10",
    vars: {
      "--scheme-bg": "#0E0F10",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #1A1B1C 0%, #141516 45%, #08090A 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #060708 0%, #131415 55%, #1C1D1E 100%)",
      "--scheme-graticule": "rgba(255, 157, 51, 0.07)",
      "--scheme-ink": "#F0EDE6",
      "--scheme-ink-faint": "#B8B2A4",
      "--scheme-ink-subtle": "#8A8478",
      "--scheme-accent": "#FF9D33",
      "--scheme-accent-glow": "rgba(255, 157, 51, 0.40)",
      "--scheme-accent-ring": "rgba(255, 157, 51, 0.06)",
      "--scheme-trace": "#FF9D33",
      "--scheme-rec": "#FF5A4A",
      "--scheme-rec-glow": "rgba(255, 90, 74, 0.55)",
      "--scheme-sparkle": "#FF5A4A",
      "--scheme-edge": "rgba(255, 255, 255, 0.06)",
      "--scheme-edge-strong": "rgba(255, 157, 51, 0.32)",
      "--scheme-details-bg": "rgba(255, 255, 255, 0.04)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.08)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.55)",
    },
  },
  {
    key: "slate",
    name: "SLATE",
    swatch: "#E5B040",
    bgHex: "#363D45",
    vars: {
      "--scheme-bg": "#363D45",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #424A53 0%, #3A4148 45%, #2E343A 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #2A3036 0%, #353C44 55%, #404750 100%)",
      "--scheme-graticule": "rgba(229, 176, 64, 0.08)",
      "--scheme-ink": "#E5B040",
      "--scheme-ink-faint": "#8E9AA4",
      "--scheme-ink-subtle": "#7A8590",
      "--scheme-accent": "#E5B040",
      "--scheme-accent-glow": "rgba(229, 176, 64, 0.40)",
      "--scheme-accent-ring": "rgba(229, 176, 64, 0.06)",
      "--scheme-trace": "#E5B040",
      "--scheme-rec": "#FF6B5A",
      "--scheme-rec-glow": "rgba(255, 107, 90, 0.50)",
      "--scheme-sparkle": "#FF6B5A",
      "--scheme-edge": "rgba(255, 255, 255, 0.10)",
      "--scheme-edge-strong": "rgba(229, 176, 64, 0.36)",
      "--scheme-details-bg": "rgba(255, 255, 255, 0.05)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.10)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.40)",
    },
  },
  {
    key: "oxide",
    name: "OXIDE",
    swatch: "#D69862",
    bgHex: "#22344A",
    vars: {
      "--scheme-bg": "#22344A",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #2A3D54 0%, #233649 45%, #1A2B3E 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #182840 0%, #233649 55%, #2C405A 100%)",
      "--scheme-graticule": "rgba(214, 152, 98, 0.08)",
      "--scheme-ink": "#F0E5D0",
      "--scheme-ink-faint": "#8FA0B0",
      "--scheme-ink-subtle": "#7A8B9C",
      "--scheme-accent": "#D69862",
      "--scheme-accent-glow": "rgba(214, 152, 98, 0.40)",
      "--scheme-accent-ring": "rgba(214, 152, 98, 0.06)",
      "--scheme-trace": "#D69862",
      "--scheme-rec": "#E85A4A",
      "--scheme-rec-glow": "rgba(232, 90, 74, 0.50)",
      "--scheme-sparkle": "#E85A4A",
      "--scheme-edge": "rgba(214, 152, 98, 0.12)",
      "--scheme-edge-strong": "rgba(214, 152, 98, 0.36)",
      "--scheme-details-bg": "rgba(255, 255, 255, 0.04)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.08)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.40)",
    },
  },
  {
    key: "concrete",
    name: "CONCRETE",
    swatch: "#9A6A22",
    bgHex: "#B0ADA6",
    vars: {
      "--scheme-bg": "#B0ADA6",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #BAB7B0 0%, #ADAAA3 60%, #A09D96 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #A8A59E 0%, #B0ADA6 55%, #B6B3AC 100%)",
      "--scheme-graticule": "rgba(154, 106, 34, 0.10)",
      "--scheme-ink": "#3D3528",
      "--scheme-ink-faint": "#6B6356",
      "--scheme-ink-subtle": "#5E574B",
      "--scheme-accent": "#9A6A22",
      "--scheme-accent-glow": "rgba(154, 106, 34, 0.16)",
      "--scheme-accent-ring": "rgba(154, 106, 34, 0.05)",
      "--scheme-trace": "#9A6A22",
      "--scheme-rec": "#B23A20",
      "--scheme-rec-glow": "rgba(178, 58, 32, 0.30)",
      "--scheme-sparkle": "#B23A20",
      "--scheme-edge": "rgba(40, 30, 20, 0.16)",
      "--scheme-edge-strong": "rgba(40, 30, 20, 0.34)",
      "--scheme-details-bg": "rgba(40, 30, 20, 0.05)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.20)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.10)",
    },
  },
  {
    key: "steel",
    name: "STEEL",
    swatch: "#E89A3C",
    bgHex: "#BCC3C9",
    vars: {
      "--scheme-bg": "#BCC3C9",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #C6CCD2 0%, #BABFC5 60%, #ADB3B9 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #B4BAC0 0%, #BCC3C9 55%, #C2C8CE 100%)",
      "--scheme-graticule": "rgba(232, 154, 60, 0.10)",
      "--scheme-ink": "#2A2E32",
      "--scheme-ink-faint": "#5C6168",
      "--scheme-ink-subtle": "#4F545B",
      "--scheme-accent": "#E89A3C",
      "--scheme-accent-glow": "rgba(232, 154, 60, 0.18)",
      "--scheme-accent-ring": "rgba(232, 154, 60, 0.06)",
      "--scheme-trace": "#E89A3C",
      "--scheme-rec": "#C43A1C",
      "--scheme-rec-glow": "rgba(196, 58, 28, 0.30)",
      "--scheme-sparkle": "#C43A1C",
      "--scheme-edge": "rgba(20, 24, 28, 0.16)",
      "--scheme-edge-strong": "rgba(20, 24, 28, 0.34)",
      "--scheme-details-bg": "rgba(20, 24, 28, 0.04)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.30)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.10)",
    },
  },
  {
    key: "aluminum",
    name: "ALUMINUM",
    swatch: "#D49236",
    bgHex: "#D6DBE0",
    vars: {
      "--scheme-bg": "#D6DBE0",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #DFE3E8 0%, #D4D8DD 60%, #C8CDD2 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #CFD4D9 0%, #D6DBE0 55%, #DDE2E7 100%)",
      "--scheme-graticule": "rgba(212, 146, 54, 0.10)",
      "--scheme-ink": "#2A2E32",
      "--scheme-ink-faint": "#5C6168",
      "--scheme-ink-subtle": "#4F545B",
      "--scheme-accent": "#D49236",
      "--scheme-accent-glow": "rgba(212, 146, 54, 0.16)",
      "--scheme-accent-ring": "rgba(212, 146, 54, 0.05)",
      "--scheme-trace": "#D49236",
      "--scheme-rec": "#C43A1C",
      "--scheme-rec-glow": "rgba(196, 58, 28, 0.30)",
      "--scheme-sparkle": "#C43A1C",
      "--scheme-edge": "rgba(20, 24, 28, 0.14)",
      "--scheme-edge-strong": "rgba(20, 24, 28, 0.30)",
      "--scheme-details-bg": "rgba(20, 24, 28, 0.04)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.40)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.08)",
    },
  },
  {
    key: "bone",
    name: "BONE",
    swatch: "#9A6A22",
    bgHex: "#E8E2D2",
    vars: {
      "--scheme-bg": "#E8E2D2",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #ECE6D7 0%, #E5DECC 60%, #DDD5C0 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #E1DAC8 0%, #E8E2D2 55%, #EFEADC 100%)",
      "--scheme-graticule": "rgba(154, 106, 34, 0.10)",
      "--scheme-ink": "#2A2520",
      "--scheme-ink-faint": "#6B5D4F",
      "--scheme-ink-subtle": "#5C4F42",
      "--scheme-accent": "#9A6A22",
      "--scheme-accent-glow": "rgba(154, 106, 34, 0.14)",
      "--scheme-accent-ring": "rgba(154, 106, 34, 0.05)",
      "--scheme-trace": "#9A6A22",
      "--scheme-rec": "#B53620",
      "--scheme-rec-glow": "rgba(181, 54, 32, 0.30)",
      "--scheme-sparkle": "#B53620",
      "--scheme-edge": "rgba(60, 40, 20, 0.14)",
      "--scheme-edge-strong": "rgba(154, 106, 34, 0.38)",
      "--scheme-details-bg": "rgba(60, 40, 20, 0.04)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.45)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.08)",
    },
  },
  {
    key: "paper",
    name: "PAPER",
    swatch: "#9A6A22",
    bgHex: "#EEE7D6",
    vars: {
      "--scheme-bg": "#EEE7D6",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #F2ECDB 0%, #EAE3D0 60%, #E2DBC6 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #E6DFCC 0%, #EEE7D6 55%, #F4EEDE 100%)",
      "--scheme-graticule": "rgba(154, 106, 34, 0.10)",
      "--scheme-ink": "#2A2520",
      "--scheme-ink-faint": "#6B5D4F",
      "--scheme-ink-subtle": "#5C4F42",
      "--scheme-accent": "#9A6A22",
      "--scheme-accent-glow": "rgba(154, 106, 34, 0.14)",
      "--scheme-accent-ring": "rgba(154, 106, 34, 0.05)",
      "--scheme-trace": "#9A6A22",
      "--scheme-rec": "#B53620",
      "--scheme-rec-glow": "rgba(181, 54, 32, 0.30)",
      "--scheme-sparkle": "#B53620",
      "--scheme-edge": "rgba(60, 40, 20, 0.16)",
      "--scheme-edge-strong": "rgba(154, 106, 34, 0.42)",
      "--scheme-details-bg": "rgba(60, 40, 20, 0.04)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.45)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.08)",
    },
  },

  // ── Light-touch siblings ─────────────────────────────────────────
  // Two lineages of progressively-lighter surfaces designed to recede
  // into the cream canvas (#FBFBFA) without disappearing:
  //
  //   cool: ALUMINUM → PORCELAIN → PEARL
  //   warm: PAPER    → VELLUM    → CHIFFON
  //
  // Each step is ~15 units lighter than the previous on the bg axis.
  // Edges + glow soften proportionally so the surface stays a panel,
  // not a void. Use the lightest variants when the bay should *recede*
  // into the page rather than punctuate it.

  // PORCELAIN — ALUMINUM, ~15 units lighter.
  {
    key: "porcelain",
    name: "PORCELAIN",
    swatch: "#D49236",
    bgHex: "#EAEEF1",
    vars: {
      "--scheme-bg": "#EAEEF1",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #F2F5F7 0%, #E8ECEF 60%, #DCE0E4 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #E0E4E8 0%, #EAEEF1 55%, #F0F3F6 100%)",
      "--scheme-graticule": "rgba(212, 146, 54, 0.08)",
      "--scheme-ink": "#2A2E32",
      "--scheme-ink-faint": "#5C6168",
      "--scheme-ink-subtle": "#787D84",
      "--scheme-accent": "#D49236",
      "--scheme-accent-glow": "rgba(212, 146, 54, 0.14)",
      "--scheme-accent-ring": "rgba(212, 146, 54, 0.05)",
      "--scheme-trace": "#D49236",
      "--scheme-rec": "#C43A1C",
      "--scheme-rec-glow": "rgba(196, 58, 28, 0.28)",
      "--scheme-sparkle": "#C43A1C",
      "--scheme-edge": "rgba(20, 24, 28, 0.10)",
      "--scheme-edge-strong": "rgba(20, 24, 28, 0.24)",
      "--scheme-details-bg": "rgba(20, 24, 28, 0.03)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.55)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.06)",
    },
  },
  // VELLUM — PAPER, ~15 units lighter.
  {
    key: "vellum",
    name: "VELLUM",
    swatch: "#9A6A22",
    bgHex: "#F4EFE0",
    vars: {
      "--scheme-bg": "#F4EFE0",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #F8F3E5 0%, #F0EBDB 60%, #E8E2D0 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #ECE6D6 0%, #F4EFE0 55%, #F9F4E6 100%)",
      "--scheme-graticule": "rgba(154, 106, 34, 0.08)",
      "--scheme-ink": "#2A2520",
      "--scheme-ink-faint": "#6B5D4F",
      "--scheme-ink-subtle": "#857664",
      "--scheme-accent": "#9A6A22",
      "--scheme-accent-glow": "rgba(154, 106, 34, 0.12)",
      "--scheme-accent-ring": "rgba(154, 106, 34, 0.05)",
      "--scheme-trace": "#9A6A22",
      "--scheme-rec": "#B53620",
      "--scheme-rec-glow": "rgba(181, 54, 32, 0.28)",
      "--scheme-sparkle": "#B53620",
      "--scheme-edge": "rgba(60, 40, 20, 0.12)",
      "--scheme-edge-strong": "rgba(154, 106, 34, 0.36)",
      "--scheme-details-bg": "rgba(60, 40, 20, 0.03)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.55)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.06)",
    },
  },

  // PEARL — PORCELAIN, ~15 units lighter. The lightest cool surface we
  // ship — barely-there sheen on top of the cream canvas. Cool tint
  // distinguishes it from a near-white warm surface (CHIFFON).
  {
    key: "pearl",
    name: "PEARL",
    swatch: "#D49236",
    bgHex: "#F5F8FA",
    vars: {
      "--scheme-bg": "#F5F8FA",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #FBFCFE 0%, #F2F5F7 60%, #E5E9ED 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #ECEFF2 0%, #F5F8FA 55%, #FBFDFE 100%)",
      "--scheme-graticule": "rgba(212, 146, 54, 0.06)",
      "--scheme-ink": "#2A2E32",
      "--scheme-ink-faint": "#6E737B",
      "--scheme-ink-subtle": "#8A8F96",
      "--scheme-accent": "#D49236",
      "--scheme-accent-glow": "rgba(212, 146, 54, 0.12)",
      "--scheme-accent-ring": "rgba(212, 146, 54, 0.04)",
      "--scheme-trace": "#D49236",
      "--scheme-rec": "#C43A1C",
      "--scheme-rec-glow": "rgba(196, 58, 28, 0.24)",
      "--scheme-sparkle": "#C43A1C",
      "--scheme-edge": "rgba(20, 24, 28, 0.08)",
      "--scheme-edge-strong": "rgba(20, 24, 28, 0.18)",
      "--scheme-details-bg": "rgba(20, 24, 28, 0.02)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.65)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.04)",
    },
  },
  // CHIFFON — VELLUM, ~15 units lighter. The lightest warm surface we
  // ship — a creamy gauze just barely warmer than the canvas. Use when
  // the bay should melt into the page entirely.
  {
    key: "chiffon",
    name: "CHIFFON",
    swatch: "#9A6A22",
    bgHex: "#FAF5E8",
    vars: {
      "--scheme-bg": "#FAF5E8",
      "--scheme-strip-top":
        "linear-gradient(to bottom, #FDF8EB 0%, #F5F0E2 60%, #ECE7D6 100%)",
      "--scheme-strip-bottom":
        "linear-gradient(to bottom, #F0ECDE 0%, #F8F3E6 55%, #FDF9EC 100%)",
      "--scheme-graticule": "rgba(154, 106, 34, 0.06)",
      "--scheme-ink": "#2A2520",
      "--scheme-ink-faint": "#7B6E60",
      "--scheme-ink-subtle": "#928576",
      "--scheme-accent": "#9A6A22",
      "--scheme-accent-glow": "rgba(154, 106, 34, 0.10)",
      "--scheme-accent-ring": "rgba(154, 106, 34, 0.04)",
      "--scheme-trace": "#9A6A22",
      "--scheme-rec": "#B53620",
      "--scheme-rec-glow": "rgba(181, 54, 32, 0.24)",
      "--scheme-sparkle": "#B53620",
      "--scheme-edge": "rgba(60, 40, 20, 0.10)",
      "--scheme-edge-strong": "rgba(154, 106, 34, 0.32)",
      "--scheme-details-bg": "rgba(60, 40, 20, 0.02)",
      "--scheme-bezel-highlight": "rgba(255, 255, 255, 0.65)",
      "--scheme-bezel-shadow": "rgba(0, 0, 0, 0.04)",
    },
  },
];
