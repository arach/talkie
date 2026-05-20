"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import {
  Settings,
  SETTINGS_VARIANTS,
  CONSOLE_SECTIONS,
  type SettingsVariant,
  type ConsoleSection,
} from "@/components/studies/Settings";
import { IOS_THEMES } from "@/lib/themes";

export default function SettingsStudy() {
  const [variant, setVariant] = useState<SettingsVariant>("console");
  const [consoleSection, setConsoleSection] =
    useState<ConsoleSection>("hairline");

  const variantToggles: Toggle[] = SETTINGS_VARIANTS.map((v) => ({
    key: v.key,
    label: v.label,
    on: variant === v.key,
    onClick: () => setVariant(v.key),
  }));

  const sectionToggles: Toggle[] = CONSOLE_SECTIONS.map((s) => ({
    key: s.key,
    label: s.label,
    on: consoleSection === s.key,
    onClick: () => setConsoleSection(s.key),
  }));

  return (
    <StudioPage
      eyebrow="Settings · Pattern study"
      title="Settings"
      help="Console (dense scroll, 3 section treatments) · Stations (spatial grid) · Inspector (chips + panel, 6 real domains). Fresh exploration — no donor crutch."
    >
      <ToggleBar label="Pattern" toggles={variantToggles} variant="dark" />

      {variant === "console" && (
        <ToggleBar
          label="Sections"
          toggles={sectionToggles}
          variant="light"
        />
      )}

      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <Settings variant={variant} consoleSection={consoleSection} />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
