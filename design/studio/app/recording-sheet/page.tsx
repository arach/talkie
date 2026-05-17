"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { SchemeCard } from "@/components/SchemeCard";
import {
  RecordingSheet,
  type SheetTreatments,
  type WaveformMode,
} from "@/components/studies/RecordingSheet";
import { SCHEMES } from "@/lib/schemes";

const WAVEFORMS: { key: WaveformMode; label: string }[] = [
  { key: "sparkle", label: "Sparkle · baseline" },
  { key: "printout", label: "Printout" },
  { key: "brass", label: "Brass" },
  { key: "phosphor", label: "Phosphor" },
  { key: "hybrid", label: "Hybrid · graticule" },
];

export default function RecordingSheetStudy() {
  const [t, setT] = useState<SheetTreatments>({
    waveform: "printout",
    graticule: false,
    brackets: false,
    bezel: false,
    compact: false,
  });

  const setWaveform = (w: WaveformMode) => () =>
    setT((prev) => ({ ...prev, waveform: w }));

  const toggle =
    (key: Exclude<keyof SheetTreatments, "waveform">) => () =>
      setT((prev) => ({ ...prev, [key]: !prev[key] }));

  const waveformToggles: Toggle[] = WAVEFORMS.map((w) => ({
    key: w.key,
    label: w.label,
    on: t.waveform === w.key,
    onClick: setWaveform(w.key),
  }));

  const treatmentToggles: Toggle[] = [
    { key: "graticule", label: "Graticule", on: t.graticule, onClick: toggle("graticule") },
    { key: "brackets", label: "Brackets", on: t.brackets, onClick: toggle("brackets") },
    { key: "bezel", label: "Bezel", on: t.bezel, onClick: toggle("bezel") },
    { key: "compact", label: "Compact", on: t.compact, onClick: toggle("compact") },
  ];

  return (
    <StudioPage
      eyebrow="· Recording Sheet · Scheme Lab"
      title="Material study"
      help="edit schemes in lib/schemes.ts · hot-reload in browser"
    >
      <ToggleBar label="· Waveform" toggles={waveformToggles} variant="dark" />
      <ToggleBar
        label="· Treatments"
        toggles={treatmentToggles}
        variant="light"
        className="mb-5"
      />

      <div className="grid grid-cols-1 gap-[22px] md:grid-cols-2 xl:grid-cols-3">
        {SCHEMES.map((scheme) => (
          <SchemeCard key={scheme.key} scheme={scheme}>
            <RecordingSheet treatments={t} />
          </SchemeCard>
        ))}
      </div>
    </StudioPage>
  );
}
