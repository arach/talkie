"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  CameraStudy,
  CAMERA_VARIANTS,
  type CameraVariant,
} from "@/components/studies/CameraStudy";
import { IOS_THEMES } from "@/lib/themes";

export default function Camera() {
  const [variant, setVariant] = useState<CameraVariant>("preview");

  const toggles: Toggle[] = CAMERA_VARIANTS.map((v) => ({
    key: v.key,
    label: v.label,
    on: variant === v.key,
    onClick: () => setVariant(v.key),
  }));

  return (
    <StudioPage
      eyebrow="Camera capture · Surface study"
      title="Camera"
      help="edit components/studies/CameraStudy.tsx · preview / captured / denied states — mirrors iOS CameraCaptureNext"
    >
      <ToggleBar label="State" toggles={toggles} variant="dark" />
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <CameraStudy variant={variant} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
