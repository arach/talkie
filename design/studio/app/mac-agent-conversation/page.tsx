"use client";

import { useEffect, useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import {
  MacAgentConversation,
  type ConversationSurface,
} from "@/components/studies/MacAgentConversation";

/**
 * Mac Agent Conversation — the Conversations tab, revamped.
 *
 * Strips the top status strip, demotes "new conversation" to a quiet "+"
 * that opens an agent picker, moves per-conversation settings to a
 * top-right gear, and brings the active agent down beside the input.
 * The adapter roster leaves the always-on sidebar for a subtle footer
 * settings entry kept apart from global Settings.
 */
export default function MacAgentConversationStudy() {
  const [surface, setSurface] = useState<ConversationSurface>("active");

  // Deterministic SSR defaults; sync from URL after mount so the states are
  // deep-linkable without a hydration mismatch.
  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const s = q.get("surface");
    if (s === "active" || s === "new") setSurface(s);
  }, []);

  const surfaceToggles: Toggle[] = [
    { key: "active", label: "Active", on: surface === "active", onClick: () => setSurface("active") },
    { key: "new", label: "New", on: surface === "new", onClick: () => setSurface("new") },
  ];

  return (
    <StudioPage
      eyebrow="Agent · macOS · Conversation surface · revamp v1"
      title="Mac Agent Conversation"
      help="components/studies/MacAgentConversation.tsx · ports to AgentHomeView.swift"
    >
      <div className="flex flex-col gap-3 py-2">
        <div className="flex flex-wrap items-center gap-3">
          <ToggleBar label="Surface" toggles={surfaceToggles} variant="light" />
        </div>

        <p
          className="max-w-[880px] text-[12px] italic leading-relaxed"
          style={{ color: "var(--studio-ink-faint)" }}
        >
          The conversation surface, decluttered. No top status strip and no adapter
          roster in the sidebar — just the conversation list and a quiet{" "}
          <strong>+</strong>. Starting one drops you straight into the main area; the
          agent is picked <strong>inside the input</strong>, beside what you type — no
          top-left pre-pick before "what are you working on?". The composer is{" "}
          <strong>one bar</strong>: agent selector on the left, <strong>mic + send</strong>{" "}
          grouped on the right. The reader's top-right holds a per-conversation{" "}
          <strong>gear</strong> and an agent-<strong>voice</strong> toggle (a speaker — read
          replies aloud, i.e. TTS — not a mic). Adapters become a subtle{" "}
          <strong>"Agents" footer entry</strong> (how many you've configured), kept apart
          from global Settings. Flip <em>Surface → New</em> for the idle hero.
        </p>

        <div className="py-4">
          <MacAgentConversation surface={surface} />
        </div>

        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

function NamesMarginalia() {
  const rows: { name: string; what: string }[] = [
    { name: "List header", what: "“Conversations” label + a quiet ＋ button. Replaces the big New-conversation button." },
    { name: "New ＋", what: "Drops you into the main area for a fresh conversation — no top-left pre-pick." },
    { name: "Agents footer", what: "Relocated adapter roster, now a subtle “N agents configured · Manage ›” settings entry." },
    { name: "Settings", what: "Global app settings, kept in the footer but separated from the Agents entry by a rule." },
    { name: "Reader gear", what: "Per-conversation settings, top-right of the reader (beside close)." },
    { name: "Voice toggle", what: "Agent voice / TTS — a speaker (not a mic). Reads replies aloud. Top-right beside the gear." },
    { name: "Agent chip", what: "The active, switchable agent — sits inside the input bar, and is how you pick one for a new conversation." },
    { name: "Input bar", what: "One bar: agent selector (left) · text · mic + send grouped together (right)." },
  ];
  return (
    <div
      className="mt-2 rounded-[10px] border px-5 py-4"
      style={{ borderColor: "var(--studio-edge)", background: "var(--studio-surface, #fff)" }}
    >
      <div
        className="mb-3 text-[9px] font-bold uppercase"
        style={{ color: "var(--studio-ink-faint)", letterSpacing: "0.18em" }}
      >
        Names · marginalia
      </div>
      <dl className="grid grid-cols-1 gap-x-8 gap-y-2 sm:grid-cols-2">
        {rows.map((r) => (
          <div key={r.name} className="flex gap-2 text-[12px]">
            <dt className="shrink-0 font-semibold" style={{ color: "var(--studio-ink)" }}>
              {r.name}
            </dt>
            <dd className="m-0" style={{ color: "var(--studio-ink-faint)" }}>
              — {r.what}
            </dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
