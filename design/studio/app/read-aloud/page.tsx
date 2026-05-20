"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  ReadAloudStudy,
  READALOUD_VARIANTS,
  SOURCE_KINDS,
  type ReadAloudVariant,
  type SourceKind,
} from "@/components/studies/ReadAloudStudy";
import { IOS_THEMES } from "@/lib/themes";

export default function ReadAloud() {
  const [variant, setVariant] = useState<ReadAloudVariant>("playing");
  const [sourceKind, setSourceKind] = useState<SourceKind>("text");

  const variantToggles: Toggle[] = READALOUD_VARIANTS.map((v) => ({
    key: v.key,
    label: v.label,
    on: variant === v.key,
    onClick: () => setVariant(v.key),
  }));

  const sourceToggles: Toggle[] = SOURCE_KINDS.map((s) => ({
    key: s.key,
    label: s.label,
    on: sourceKind === s.key,
    onClick: () => setSourceKind(s.key),
  }));

  return (
    <StudioPage
      eyebrow="Read Aloud · Surface study"
      title="Read Aloud"
      help="edit components/studies/ReadAloudStudy.tsx · idle / playing / queue states · text gets a chunked follow-along, image / url / pdf get a reference + Open link"
    >
      <ToggleBar label="State" toggles={variantToggles} variant="dark" />

      {variant !== "idle" && (
        <ToggleBar
          label="Source"
          toggles={sourceToggles}
          variant="light"
        />
      )}

      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <ReadAloudStudy variant={variant} sourceKind={sourceKind} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
