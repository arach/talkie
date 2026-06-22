"use client";

import { StudioPage } from "@/components/StudioPage";
import { MacAgentHomeShell } from "@/components/studies/MacAgentHomeShell";
import { MacWindowFrame } from "@/components/studies/primitives/MacWindowFrame";

/**
 * Mac Agent Home (Shell) — the TalkieAgent home / library surface.
 *
 * Ports the surface we refined directly in AgentHomeShellView.swift:
 * Talkie-homepage eyebrow + serif headline, a lean KPI stat row in the
 * Stats vocabulary, and the recent-library list/detail split. Stamped
 * at the app's new default width (1040) in both content variants —
 * History (shared recordings) and Home (runtime overview) — so the
 * "same family, not a clone" relationship with Talkie reads at a glance.
 */
export default function MacAgentHomeShellStudy() {
  return (
    <StudioPage
      eyebrow="Agent · macOS · Home / Library surface · light OPS"
      title="Agent Home (Shell)"
      help="edit components/studies/MacAgentHomeShell.tsx · ports AgentHomeShellView.swift"
    >
      <div className="flex flex-col gap-8 py-6">
        <MacWindowFrame
          size={{
            width: 1040,
            label: "Home",
            note: "runtime overview · agent bay + recent library",
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
