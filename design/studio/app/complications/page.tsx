"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  Complications,
  COMPLICATION_VARIANTS,
  type ComplicationVariant,
} from "@/components/studies/Complications";
import { IOS_THEMES } from "@/lib/themes";

export default function ComplicationsStudy() {
  const [variant, setVariant] = useState<ComplicationVariant>("corners");

  const toggles: Toggle[] = COMPLICATION_VARIANTS.map((v) => ({
    key: v.key,
    label: v.label,
    on: variant === v.key,
    onClick: () => setVariant(v.key),
  }));

  return (
    <StudioPage
      eyebrow="Complications · Layout study"
      title="Complications"
      help="edit components/studies/Complications.tsx · variant picker drives all phones at once"
    >
      <ToggleBar label="Variant" toggles={toggles} variant="dark" />

      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <Complications variant={variant} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
