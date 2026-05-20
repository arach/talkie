"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  ReadAloudStudy,
  READALOUD_VARIANTS,
  type ReadAloudVariant,
} from "@/components/studies/ReadAloudStudy";
import { IOS_THEMES } from "@/lib/themes";

export default function ReadAloud() {
  const [variant, setVariant] = useState<ReadAloudVariant>("playing");

  const toggles: Toggle[] = READALOUD_VARIANTS.map((v) => ({
    key: v.key,
    label: v.label,
    on: variant === v.key,
    onClick: () => setVariant(v.key),
  }));

  return (
    <StudioPage
      eyebrow="Read Aloud · Surface study"
      title="Read Aloud"
      help="edit components/studies/ReadAloudStudy.tsx · idle / playing / queue states · instrument-style transport with voice + rate + pitch controls"
    >
      <ToggleBar label="State" toggles={toggles} variant="dark" />
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <ReadAloudStudy variant={variant} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
