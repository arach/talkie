/**
 * Theme contrast sweep — the state of the legibility work.
 *
 * The screenshots and numbers are captured artifacts, not live renders: every
 * theme was driven onto the simulator with the harness from f45b0f7e, shot at
 * 3x, and sampled with the same WCAG math the token audit uses. Regenerating
 * them means re-running that harness, not reloading this page.
 */

import { StudioPage } from "@/components/StudioPage";
import {
  ThemeContrastStudy,
  type Checkpoint,
  type ContrastData,
} from "@/components/studies/ThemeContrastStudy";
import data from "@/data/theme-contrast.json";

// Newest first — the order you would walk back through.
const CHECKPOINTS: Checkpoint[] = [
  {
    hash: "f52e579f",
    subject: "Make every word on the deck survive being read",
    note: "TALK's lettering moved outside its Button so the disabled fade stops halving it; the key goes unlit instead of dimming its word. The plate sheen stopped branching on color scheme — it was eating a fifth of every label on a light page.",
    measured: true,
  },
  {
    hash: "b58a99c4",
    subject: "Say quiet on the cockpit with a different ink, not less of it",
    note: "Alpha over a dark plate composites toward the plate. GAUGES read 1.96:1, graphite's DAY 1 read 1.20:1 — effectively invisible. Quiet is now a token choice, never an opacity.",
    measured: true,
  },
  {
    hash: "71c5e064",
    subject: "Paint the cockpit in the theme you just picked, not the last one",
    note: "A frame of lag meant half the captures were showing the previous theme. Everything measured before this is suspect.",
  },
  {
    hash: "f45b0f7e",
    subject: "Let a screenshot harness drive theme and mode without a tap",
    note: "40 captures — 10 themes × 2 modes × 2 surfaces — reproducible from one command. The measurements below all come from this.",
  },
  {
    hash: "dc461679",
    subject: "Add Ember — black and amber, played quietly",
    note: "Of the three sober pairs asked for, two already existed: Porcelain is porcelain and cobalt, and Vercel became a real black-and-gray once it got a light half. Ember is the one that didn't.",
  },
  {
    hash: "8e0cbbd8",
    subject: "Make every theme legible in both modes",
    note: "The token-level pass. 125 declared pairs failed 4.5:1 across 9 themes × 2 modes; this took it to 0 of 378.",
    measured: true,
  },
];

export default function ThemeContrastPage() {
  return (
    <StudioPage
      eyebrow="iOS · Legibility"
      title="Theme Contrast"
      help="10 themes · 2 modes · 2 surfaces"
      back={{ href: "/", label: "Studies" }}
    >
      <ThemeContrastStudy
        data={data as ContrastData}
        checkpoints={CHECKPOINTS}
      />
    </StudioPage>
  );
}
