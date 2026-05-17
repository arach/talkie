"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { SchemeCard } from "@/components/SchemeCard";
import { Bay, type BayTreatments } from "@/components/studies/Bay";
import { SCHEMES } from "@/lib/schemes";

export default function AgentBayStudy() {
  const [t, setT] = useState<BayTreatments>({
    sparkline: true,
    compact: true,
    heatmap: false,
    timeline: false,
    brackets: false,
    bezel: false,
    graticule: false,
  });

  const toggle = (key: keyof BayTreatments) => () =>
    setT((prev) => ({ ...prev, [key]: !prev[key] }));

  const toggles: Toggle[] = [
    { key: "sparkline", label: "Sparkline", on: t.sparkline, onClick: toggle("sparkline") },
    { key: "compact", label: "Compact", on: t.compact, onClick: toggle("compact") },
    { key: "heatmap", label: "Heatmap", on: t.heatmap, onClick: toggle("heatmap") },
    { key: "timeline", label: "Timeline", on: t.timeline, onClick: toggle("timeline") },
    { key: "brackets", label: "Brackets", on: t.brackets, onClick: toggle("brackets") },
    { key: "bezel", label: "Bezel", on: t.bezel, onClick: toggle("bezel") },
    { key: "graticule", label: "Graticule", on: t.graticule, onClick: toggle("graticule") },
  ];

  return (
    <StudioPage
      eyebrow="· Agent Bay · Scheme Lab"
      title="Material study"
      help="edit schemes in lib/schemes.ts · hot-reload in browser"
    >
      <ToggleBar label="· Treatments" toggles={toggles} variant="dark" />

      <div className="grid grid-cols-1 gap-[22px] md:grid-cols-2 xl:grid-cols-3">
        {SCHEMES.map((scheme) => (
          <SchemeCard key={scheme.key} scheme={scheme}>
            <Bay treatments={t} />
          </SchemeCard>
        ))}
      </div>
    </StudioPage>
  );
}
