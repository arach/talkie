"use client";

import { useEffect, useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import {
  MacAgentShell,
  type ShellSurface,
  type RailMode,
  type SettingsHeader,
} from "@/components/studies/MacAgentShell";

/**
 * Mac Agent Shell — nav + IA study.
 *
 * Simplifies the far-left "main talkie agent bar" to a primary trio
 * (Agents · History · Permissions) + a "…" overflow + footer Settings,
 * makes the settings section-picker header read like a real header, and
 * lands Agents on a status strip over an assistant well.
 */
export default function MacAgentShellStudy() {
  // Deterministic SSR defaults; sync from URL after mount so deep-links work
  // without a hydration mismatch.
  const [surface, setSurface] = useState<ShellSurface>("agents");
  const [railMode, setRailMode] = useState<RailMode>("menu");
  const [settingsHeader, setSettingsHeader] = useState<SettingsHeader>("titled");

  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const s = q.get("surface");
    const o = q.get("overflow");
    const h = q.get("header");
    if (s === "agents" || s === "logs" || s === "settings") setSurface(s);
    if (o === "menu" || o === "group" || o === "tucked") setRailMode(o);
    if (h === "titled" || h === "segmented" || h === "breadcrumb") setSettingsHeader(h);
  }, []);

  const surfaceToggles: Toggle[] = [
    { key: "agents", label: "Agents", on: surface === "agents", onClick: () => setSurface("agents") },
    { key: "logs", label: "Logs", on: surface === "logs", onClick: () => setSurface("logs") },
    { key: "settings", label: "Settings", on: surface === "settings", onClick: () => setSurface("settings") },
  ];

  const railToggles: Toggle[] = [
    { key: "menu", label: "… flyout", on: railMode === "menu", onClick: () => setRailMode("menu") },
    { key: "group", label: "More group", on: railMode === "group", onClick: () => setRailMode("group") },
    { key: "tucked", label: "Tucked", on: railMode === "tucked", onClick: () => setRailMode("tucked") },
  ];

  const headerToggles: Toggle[] = [
    { key: "titled", label: "Titled", on: settingsHeader === "titled", onClick: () => setSettingsHeader("titled") },
    { key: "segmented", label: "Segmented", on: settingsHeader === "segmented", onClick: () => setSettingsHeader("segmented") },
    { key: "breadcrumb", label: "Breadcrumb", on: settingsHeader === "breadcrumb", onClick: () => setSettingsHeader("breadcrumb") },
  ];

  return (
    <StudioPage
      eyebrow="Agent · macOS · Navigation + IA · v1"
      title="Mac Agent Shell"
      help="components/studies/MacAgentShell.tsx · ports to AgentHomeShellView + SettingsView"
    >
      <div className="flex flex-col gap-3 py-2">
        <div className="flex flex-wrap items-center gap-3">
          <ToggleBar label="Surface" toggles={surfaceToggles} variant="light" />
          <ToggleBar label="Overflow" toggles={railToggles} variant="light" />
          <ToggleBar label="Settings header" toggles={headerToggles} variant="light" />
        </div>

        <p
          className="max-w-[880px] text-[12px] italic leading-relaxed"
          style={{ color: "var(--studio-ink-faint)" }}
        >
          The far-left rail drops from 10 destinations across 4 group headers to a{" "}
          <strong>primary trio</strong> — Agents · History · Permissions — with everything
          else demoted under a <strong>“…” overflow</strong> (kept as a stop-gap; those
          pages were never carefully designed and will be retired). Settings stays pinned in
          the <strong>footer</strong>. Flip <em>Surface → Settings</em> to compare the three
          section-picker header treatments; flip <em>Overflow</em> to compare how the demoted
          sections hang off the rail.
        </p>

        <div className="py-4">
          <MacAgentShell surface={surface} railMode={railMode} settingsHeader={settingsHeader} />
        </div>

        <NamesMarginalia />
      </div>
    </StudioPage>
  );
}

/**
 * NamesMarginalia — shared vocabulary so studio / Swift / chat agree on
 * what each part is called.
 */
function NamesMarginalia() {
  const rows: { name: string; what: string }[] = [
    { name: "Main rail", what: "Far-left primary nav (the “main talkie agent bar”). 40pt icon column + label column." },
    { name: "Primary four", what: "Agents · History · Permissions · Logs — the first-class destinations." },
    { name: "Overflow (“…”)", what: "Demoted, soon-to-retire sections (Capture, Tray, Dictation, Overlays, Server)." },
    { name: "Log feed", what: "Channel-tagged mono rows + level filters + Live tail; the first-class Logs surface." },
    { name: "Footer gear", what: "Settings, pinned to the bottom rail slot." },
    { name: "Section picker", what: "Settings’ secondary rail; its header is the “nicer” target." },
    { name: "Status strip", what: "Agents landing top band: runtime · adapters · jobs · bridge." },
    { name: "Assistant well", what: "Agents landing body: the conversation + composer." },
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
