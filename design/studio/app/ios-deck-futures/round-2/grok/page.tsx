"use client";

import { useState } from "react";

import { StudioPage } from "@/components/StudioPage";
import { ToggleBar } from "@/components/ToggleBar";

import { Aperture } from "./Aperture";
import { SCENARIOS } from "./content";

/**
 * Round 2 · Grok — The Aperture.
 *
 * One Codex task fills a framed reading aperture under hanging task tags.
 * The brass voice sill is both destination and hold-to-talk; speech rises
 * as amber breath into the plate.
 */
export default function ApertureAtBat() {
  const [scenario, setScenario] = useState(SCENARIOS[0].key);

  return (
    <StudioPage
      eyebrow="Round 2 · iPad at-bat · Grok"
      title="The Aperture"
      help="12.9″ iPad · landscape 1366 × 1024"
      back={{ href: "/ios-deck-futures", label: "Deck futures" }}
    >
      <ToggleBar
        label="State"
        toggles={SCENARIOS.map((v) => ({
          key: v.key,
          label: v.label,
          on: scenario === v.key,
          onClick: () => setScenario(v.key),
        }))}
      />

      <Aperture scenarioKey={scenario} />
    </StudioPage>
  );
}
