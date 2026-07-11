"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacAgentHomeShell } from "@/components/studies/MacAgentHomeShell";
import { MacWindowFrame } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Agent Home (Shell) — the TalkieAgent home / library surface.
 *
 * Ports the surface refined in AgentHomeShellView.swift. Talkie's cool Scope
 * substrate and ink ladder establish the family; steel Agent chrome and one
 * signal-blue active color make the runtime legible as a sibling, not a clone.
 */
export default function MacAgentHomeShellStudy() {
  return (
    <StudioPage
      eyebrow="Agent · macOS · Cool Scope chassis · steel signal"
      title="Agent Home (Shell)"
      help="edit components/studies/MacAgentHomeShell.tsx · ports AgentHomeShellView.swift"
    >
      <div className="flex flex-col gap-8 py-6">
        <MacWindowFrame
          size={{
            width: 1040,
            label: "Home",
            note: "runtime overview · steel agent bay + recent library",
          }}
          title="Talkie Agent"
        >
          <MacAgentHomeShell variant="home" />
        </MacWindowFrame>

        <MacWindowFrame
          size={{
            width: 1040,
            label: "History",
            note: "read-only recordings list · no bay",
          }}
          title="Talkie Agent"
        >
          <MacAgentHomeShell variant="history" />
        </MacWindowFrame>
      </div>
    </StudioPage>
  );
}
