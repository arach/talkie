"use client";

import { StudioPage } from "@/components/StudioPage";
import { SchemeCard } from "@/components/SchemeCard";
import { MacWorkflows } from "@/components/studies/MacWorkflows";
import { MacWindowFrame } from "@/components/studies/primitives/MacWindowFrame";
import type { Scheme } from "@/lib/schemes";

/**
 * Mac Workflows — studio entry point.
 *
 * Custom schemes (defined here, not from lib/schemes.ts) so light
 * matches the studio's own canvas tokens (#F8F8F7 cool cream) and
 * dark sits at a breathable mid-slate (#20242A), not near-black.
 * The BONE/AMBER pairing we tried before read too heavy on both
 * sides — too warm-cream on light, too near-black on dark.
 *
 * Pre-Swift. Theme-awareness via `var(--scheme-*)` so adding a
 * third scheme later is a one-liner.
 */

// Tokens lifted from MacHome (the rest of the macOS studies):
//   bg     #F8F8F7   studio.canvas
//   ink    #232423   studio.ink
//   faint  #76767A   studio.ink-faint
//   edge   #DEDEDD   studio.edge (solid hairline, not alpha)
//   accent #9A6A22   brass — primary accent across MacHome
//   hover  #7A521A   brass-dark — used as hover/secondary
const PAPER_LIGHT: Scheme = {
  key: "paper-light",
  name: "PAPER",
  swatch: "#9A6A22",
  bgHex: "#F8F8F7",
  vars: {
    "--scheme-bg":          "#F8F8F7",
    "--scheme-ink":         "#232423",
    "--scheme-ink-faint":   "#76767A",
    "--scheme-ink-subtle":  "#A8A8AB",
    "--scheme-accent":      "#9A6A22",
    "--scheme-accent-ring": "rgba(154,106,34,0.06)",
    "--scheme-edge":        "#DEDEDD",
    "--scheme-edge-strong": "#C8C8C7",
    "--scheme-trace":       "#9A6A22",
    "--scheme-rec":         "#C43A1C",
  },
};

// Dark counterpart — same ink ladder structure, lighter slate than
// the donor's near-black. Amber on dark stays #E89A3C (brass loses
// too much luminance on a dark bg).
const SLATE_DARK: Scheme = {
  key: "slate-dark",
  name: "SLATE",
  swatch: "#E89A3C",
  bgHex: "#2A2D32",
  vars: {
    "--scheme-bg":          "#2A2D32",
    "--scheme-ink":         "#E8E5DE",
    "--scheme-ink-faint":   "#A2A4A8",
    "--scheme-ink-subtle":  "#74777C",
    "--scheme-accent":      "#E89A3C",
    "--scheme-accent-ring": "rgba(232,154,60,0.09)",
    "--scheme-edge":        "rgba(255,255,255,0.07)",
    "--scheme-edge-strong": "rgba(255,255,255,0.16)",
    "--scheme-trace":       "#E89A3C",
    "--scheme-rec":         "#FF5A4A",
  },
};

export default function MacWorkflowsStudy() {
  return (
    <StudioPage
      eyebrow="Workflows · macOS · Sheet + Inspector"
      title="Mac Workflows"
      help="edit components/studies/MacWorkflows.tsx · pre-Swift · theme-aware via scheme-* vars"
    >
      <div className="flex flex-col gap-8 py-6">
        <SchemeCard scheme={PAPER_LIGHT}>
          <MacWindowFrame
            size={{ width: 1280, label: "Default", note: "light · paper · studio canvas" }}
            title="Talkie · Workflows"
          >
            <MacWorkflows />
          </MacWindowFrame>
        </SchemeCard>

        <SchemeCard scheme={SLATE_DARK}>
          <MacWindowFrame
            size={{ width: 1280, label: "Default", note: "dark · slate · breathable" }}
            title="Talkie · Workflows"
          >
            <MacWorkflows />
          </MacWindowFrame>
        </SchemeCard>
      </div>
    </StudioPage>
  );
}
