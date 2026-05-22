"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  AskAIStudy,
  ASKAI_VARIANTS,
  type AskAIVariant,
} from "@/components/studies/AskAIStudy";
import { IOS_THEMES } from "@/lib/themes";

export default function AskAI() {
  const [variant, setVariant] = useState<AskAIVariant>("idle");

  const toggles: Toggle[] = ASKAI_VARIANTS.map((v) => ({
    key: v.key,
    label: v.label,
    on: variant === v.key,
    onClick: () => setVariant(v.key),
  }));

  return (
    <StudioPage
      eyebrow="Ask AI · Surface study"
      title="Ask AI"
      help="edit components/studies/AskAIStudy.tsx · idle / thinking / multi-turn states — drives iOS AskAINext"
    >
      <ToggleBar label="State" toggles={toggles} variant="dark" />
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <AskAIStudy variant={variant} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
