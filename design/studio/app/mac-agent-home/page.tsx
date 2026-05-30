"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { MacAgentHome } from "@/components/studies/MacAgentHome";

/**
 * Mac Agent Home — conversation as a linear feed.
 *
 * Each session is a conversation in the sidebar (auto-named). Follow-ups
 * are just the next message. Every Talkie message tucks its anatomy
 * (heard, ack, pipeline, full response, runtime) behind a quiet inline
 * "show work" disclosure — there for the curious, out of the way otherwise.
 */
export default function MacAgentHomeStudy() {
  const [live, setLive] = useState(true);
  const [openWork, setOpenWork] = useState(true);
  const [surface, setSurface] = useState<"active" | "new">("active");

  const liveToggles: Toggle[] = [
    { key: "on",  label: "Live",  on: live,  onClick: () => setLive(true) },
    { key: "off", label: "Quiet", on: !live, onClick: () => setLive(false) },
  ];

  const workToggles: Toggle[] = [
    { key: "open",   label: "Open",   on: openWork,  onClick: () => setOpenWork(true) },
    { key: "closed", label: "Closed", on: !openWork, onClick: () => setOpenWork(false) },
  ];

  const surfaceToggles: Toggle[] = [
    { key: "active", label: "Active",          on: surface === "active", onClick: () => setSurface("active") },
    { key: "new",    label: "New conversation", on: surface === "new",   onClick: () => setSurface("new") },
  ];

  return (
    <StudioPage
      eyebrow="Agent · macOS · Conversation surface · v6"
      title="Mac Agent Home"
      help="components/studies/MacAgentHome.tsx · linear conversation · work tucked behind 'show work'"
    >
      <div className="flex flex-col gap-3 py-2">
        <div className="flex flex-wrap items-center gap-3">
          <ToggleBar label="Surface"     toggles={surfaceToggles} variant="light" />
          <ToggleBar label="Latest turn" toggles={liveToggles}    variant="light" />
          <ToggleBar label="Show work"   toggles={workToggles}    variant="light" />
        </div>

        <p
          className="max-w-[860px] text-[12px] italic leading-relaxed"
          style={{ color: "var(--studio-ink-faint)" }}
        >
          Sessions are conversations, auto-named from the first ask. Follow-ups are
          just the next message — no threaded replies. Every Talkie message hides
          its anatomy behind a quiet show-work disclosure. A fresh conversation
          collapses the reader into an idle hero — one focal mic, an editorial
          question, a focused composer, and a few starter prompts.
        </p>

        <div className="py-4">
          <MacAgentHome
            liveTurn={live}
            expandedTurnId={openWork ? "T-184" : undefined}
            emptyState={surface === "new"}
          />
        </div>
      </div>
    </StudioPage>
  );
}
