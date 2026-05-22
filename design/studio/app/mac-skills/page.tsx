"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacSkills } from "@/components/studies/MacSkills";
import { MacWindowFrame } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Skills — one tab, one surface, the whole loop.
 *
 * This is the committed direction for the macOS Skills section. The
 * adjacent mac-skill-forge study stays as a record of the framing
 * comparison that led here; this study is the destination.
 *
 * The composition shows the surface mid-iteration so the journey
 * reads at a glance: a starter is being edited (amber card border),
 * the editor bay above shows the chat exchange + markup, the console
 * shows the just-ran output, and "your skills" sits empty at the
 * foot waiting for the save. One page, top to bottom.
 *
 * Rendered at the studio standard 1180 width.
 */
export default function MacSkillsStudy() {
  return (
    <StudioPage
      eyebrow="Skills · macOS · Composition study · single-surface"
      title="Mac Skills"
      help="edit components/studies/MacSkills.tsx · pre-Swift · one tab, full loop"
    >
      <div className="py-6">
        <MacWindowFrame
          size={{ width: 1180, label: "Default", note: "studio standard" }}
          title="Talkie · Skills"
        >
          <MacSkills />
        </MacWindowFrame>
      </div>
    </StudioPage>
  );
}
