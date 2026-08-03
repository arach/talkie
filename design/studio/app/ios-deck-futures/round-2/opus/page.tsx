"use client";

import { useState } from "react";

import { StudioPage } from "@/components/StudioPage";
import { ToggleBar } from "@/components/ToggleBar";

import { StandingPage } from "./StandingPage";
import { SCENARIOS } from "./content";

export default function StandingPageAtBat() {
  const [scenario, setScenario] = useState(SCENARIOS[1].key);

  return (
    <StudioPage
      eyebrow="Round 2 · iPad at-bat · Opus"
      title="Standing Page"
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

      <StandingPage scenarioKey={scenario} />
    </StudioPage>
  );
}
