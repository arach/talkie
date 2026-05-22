"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacSkillForge } from "@/components/studies/MacSkillForge";
import { MacWindowFrame } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Skill Forge — three framings for the skill-authoring surface.
 *
 * No Swift source yet. This study is upstream of any port — it exists
 * to pick a shape for skill authoring before committing to a build.
 *
 * The exploration that produced this:
 *   - Skills (not workflows) — a semantic description of intent, not
 *     a wired-up graph of blocks. Voice-dictatable, diffable, agent-
 *     writable.
 *   - Markup is the source of truth. Other panes are lenses on it.
 *   - The console is already running; pipe a skill at it.
 *   - The editor is a WebKit-hosted CodeMirror — native code editing
 *     isn't worth the engineering cost for a side affordance.
 *
 * Three framings stacked:
 *   A. MARKUP-PRIMARY — editor + outline + console. IDE shape.
 *   B. CHAT-DRIVEN    — agent composes the markup, you tweak.
 *   C. TRIFOLD        — chat + markup + derived map. Three lenses.
 *
 * Rendered at 1180 (studio default). Width-stamps not used here —
 * the framing comparison is the variable, not viewport size.
 */
export default function MacSkillForgeStudy() {
  return (
    <StudioPage
      eyebrow="Skill Forge · macOS · Framing study · 3-up"
      title="Mac Skill Forge"
      help="edit components/studies/MacSkillForge.tsx · pre-Swift · framing study, not a width study"
    >
      <div className="py-6">
        <MacWindowFrame
          size={{ width: 1180, label: "Default", note: "framing comparison" }}
          title="Talkie · Skill Forge"
        >
          <MacSkillForge />
        </MacWindowFrame>
      </div>
    </StudioPage>
  );
}
