"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  Compose,
  COMPOSE_STATES,
  type ComposeState,
} from "@/components/studies/Compose";
import { IOS_THEMES } from "@/lib/themes";

export default function ComposeStudy() {
  const [state, setState] = useState<ComposeState>("empty");

  const toggles: Toggle[] = COMPOSE_STATES.map((s) => ({
    key: s.key,
    label: s.label,
    on: state === s.key,
    onClick: () => setState(s.key),
  }));

  return (
    <StudioPage
      eyebrow="· Compose · Theme + state study"
      title="Compose"
      help="edit components/studies/Compose.tsx · state picker drives all 4 phones at once"
    >
      <ToggleBar label="· State" toggles={toggles} variant="dark" />

      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <Compose state={state} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
