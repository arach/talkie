"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  BridgeDetailStudy,
  BRIDGE_VARIANTS,
  type BridgeVariant,
} from "@/components/studies/BridgeDetailStudy";
import { IOS_THEMES } from "@/lib/themes";

export default function BridgeDetail() {
  const [variant, setVariant] = useState<BridgeVariant>("paired");

  const toggles: Toggle[] = BRIDGE_VARIANTS.map((v) => ({
    key: v.key,
    label: v.label,
    on: variant === v.key,
    onClick: () => setVariant(v.key),
  }));

  return (
    <StudioPage
      eyebrow="Mac Bridge · Surface study"
      title="Mac Bridge Detail"
      help="edit components/studies/BridgeDetailStudy.tsx · paired/unpaired states — mirrors iOS BridgeDetailNext"
    >
      <ToggleBar label="State" toggles={toggles} variant="dark" />
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <BridgeDetailStudy variant={variant} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
