"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  TerminalStudy,
  TERMINAL_VARIANTS,
  type TerminalVariant,
} from "@/components/studies/TerminalStudy";
import { IOS_THEMES } from "@/lib/themes";

export default function Terminal() {
  const [variant, setVariant] = useState<TerminalVariant>("populated");

  const toggles: Toggle[] = TERMINAL_VARIANTS.map((v) => ({
    key: v.key,
    label: v.label,
    on: variant === v.key,
    onClick: () => setVariant(v.key),
  }));

  return (
    <StudioPage
      eyebrow="Terminal · Surface study"
      title="Terminal"
      help="edit components/studies/TerminalStudy.tsx · saved hosts list + empty state — mirrors iOS TerminalNext"
    >
      <ToggleBar label="State" toggles={toggles} variant="dark" />
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <TerminalStudy variant={variant} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
