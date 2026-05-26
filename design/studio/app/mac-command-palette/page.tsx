"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacCommandPalette } from "@/components/studies/MacCommandPalette";
import { MacWindowFrame } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Command Palette — reimagined.
 *
 * Donor: CommandPaletteView.swift + VoiceCommandOverlay.swift +
 * PaletteCommand.swift. Today's app ships two surfaces (text palette
 * + particle voice modal). The reimagining collapses them.
 *
 * Three new states, one shape:
 *   1. Resting   (text-focused, grouped list, mic primed)
 *   2. Speaking  (mic held inline, waveform strip, intent banner)
 *   3. In context (scope chip rides input, Here group pinned)
 *
 * Plus a donor strip at the bottom showing today's two surfaces side
 * by side for contrast.
 */
export default function MacCommandPaletteStudy() {
  return (
    <StudioPage
      eyebrow="Command Palette · macOS · Voice + text · One surface"
      title="Mac Command Palette"
      help="edit components/studies/MacCommandPalette.tsx · pre-Swift · collapses palette + voice overlay"
    >
      <div className="py-6">
        <MacWindowFrame
          size={{ width: 1180, label: "Default", note: "modal overlay · 3 states + donor contrast" }}
          title="Talkie · Command Palette"
        >
          <MacCommandPalette />
        </MacWindowFrame>
      </div>
    </StudioPage>
  );
}
