"use client";

import { useState, type CSSProperties } from "react";
import { StudioPage } from "@/components/StudioPage";
import { ToggleBar, type Toggle } from "@/components/ToggleBar";
import { SchemeCard } from "@/components/SchemeCard";
import {
  AgentTray,
  AgentTrayCurrent,
  type CaptureLayout,
  type TrayTreatments,
} from "@/components/studies/AgentTray";
import { SCHEMES, type Scheme } from "@/lib/schemes";

/**
 * Mac Agent Tray — the menu-bar pop-out, reworked + theme-coordinated.
 *
 *   1. Collapse NOW + INPUT into one capture composer, split 50/50:
 *      Record / Stop on the left, mic picker on the right.
 *   2. Dress RECENT + TOOLS in scope language.
 *   3. Coordinate with the app theme. The studio AMBER scheme is a
 *      direct port of ScopePanel.* (bg #14181A, inkFaint #7A8B85,
 *      trace #E89A3C, strip gradients) — but ScopePanel.ink is near-
 *      white, so CARBON (near-white ink + orange) is the truer dark
 *      match. The panel follows the active app appearance:
 *        Carbon → Dark · Frost → Light (modern) · Paper → Warm.
 */

const getScheme = (key: string): Scheme => SCHEMES.find((s) => s.key === key)!;

/** The three appearance modes the panel coordinates with. */
const APP_THEMES: Array<{ key: string; mode: string; dark: boolean }> = [
  { key: "carbon", mode: "Dark", dark: true },
  { key: "frost", mode: "Light · modern", dark: false },
  { key: "paper", mode: "Warm", dark: false },
];

export default function MacAgentTrayStudy() {
  const [layout, setLayout] = useState<CaptureLayout>("split");
  const [recording, setRecording] = useState(false);
  const [graticule, setGraticule] = useState(false);
  const [strips, setStrips] = useState(true);

  const t: TrayTreatments = { layout, recording, graticule, strips };

  const layoutToggles: Toggle[] = [
    { key: "split", label: "Split", on: layout === "split", onClick: () => setLayout("split") },
    {
      key: "labeled",
      label: "Labeled",
      on: layout === "labeled",
      onClick: () => setLayout("labeled"),
    },
    { key: "stacked", label: "Stacked", on: layout === "stacked", onClick: () => setLayout("stacked") },
  ];

  const stateToggles: Toggle[] = [
    { key: "idle", label: "Idle", on: !recording, onClick: () => setRecording(false) },
    { key: "live", label: "Recording", on: recording, onClick: () => setRecording(true) },
  ];

  const materialToggles: Toggle[] = [
    { key: "strips", label: "Strip header", on: strips, onClick: () => setStrips((v) => !v) },
    { key: "grid", label: "Graticule", on: graticule, onClick: () => setGraticule((v) => !v) },
  ];

  return (
    <StudioPage
      eyebrow="Agent · macOS · Menu-bar pop-out"
      title="Mac Agent Tray"
      help="components/studies/AgentTray.tsx · 50/50 capture · scope-dressed · theme-coordinated"
    >
      <div className="flex flex-wrap items-center gap-3">
        <ToggleBar label="Capture" toggles={layoutToggles} variant="light" />
        <ToggleBar label="State" toggles={stateToggles} variant="light" />
        <ToggleBar label="Material" toggles={materialToggles} variant="light" />
      </div>

      <p className="mb-6 max-w-[840px] text-[12px] italic leading-relaxed text-studio-ink-faint">
        Record and the mic picker share one unit, split 50/50 —{" "}
        <strong>Record / Stop</strong> on the left, <strong>mic picker</strong> on
        the right; no shortcut keycaps (the chord lives in the header). While
        recording, the right half flips to a live level meter + timer. Recent +
        Tools take the scope language. The panel coordinates with the app
        appearance — the same accent, ink ramp, and hairlines as{" "}
        <code>ScopePanel</code> / <code>ScopePalette</code>.
      </p>

      {/* ── App themes ──────────────────────────────────────────────── */}
      <SectionHead
        title="App themes"
        note="panel follows the active appearance — Carbon · Frost · Paper"
      />
      <div className="mb-10 grid grid-cols-1 gap-5 lg:grid-cols-3">
        {APP_THEMES.map(({ key, mode, dark }) => {
          const scheme = getScheme(key);
          return (
            <ThemeCell key={key} name={scheme.name} mode={mode} dark={dark}>
              <div style={scheme.vars as CSSProperties}>
                <AgentTray treatments={t} />
              </div>
            </ThemeCell>
          );
        })}
      </div>

      {/* ── Before / After (dark) ───────────────────────────────────── */}
      <SectionHead title="Before / after" note="today's dark panel vs the Carbon rework" />
      <div className="mb-10 grid grid-cols-1 gap-5 lg:grid-cols-2">
        <ThemeCell name="Current" mode="shipping" dark>
          <AgentTrayCurrent />
        </ThemeCell>
        <ThemeCell name="Proposed" mode={`Carbon · ${layout}${recording ? " · rec" : ""}`} dark>
          <div style={getScheme("carbon").vars as CSSProperties}>
            <AgentTray treatments={t} />
          </div>
        </ThemeCell>
      </div>

      {/* ── Material grid ───────────────────────────────────────────── */}
      <SectionHead
        title="Across materials"
        note="every scheme — stress-test the rework against the full palette"
      />
      <div className="grid grid-cols-1 justify-items-center gap-x-6 gap-y-8 md:grid-cols-2 xl:grid-cols-3">
        {SCHEMES.map((scheme) => (
          <SchemeCard key={scheme.key} scheme={scheme}>
            <AgentTray treatments={t} />
          </SchemeCard>
        ))}
      </div>
    </StudioPage>
  );
}

function SectionHead({ title, note }: { title: string; note: string }) {
  return (
    <div className="mb-3 flex items-baseline gap-2 border-t border-studio-edge pt-5">
      <h2 className="font-display text-[18px] font-medium tracking-tight text-studio-ink">
        {title}
      </h2>
      <span className="text-[10px] tracking-ch text-studio-ink-faint">{note}</span>
    </div>
  );
}

function ThemeCell({
  name,
  mode,
  dark,
  children,
}: {
  name: string;
  mode: string;
  dark: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-2.5">
      <div className="flex items-baseline gap-2 text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        <span className="tracking-ch text-studio-ink">{name}</span>
        <span>{mode}</span>
      </div>
      <div
        className="flex justify-center rounded-[14px] p-8"
        style={{
          background: dark
            ? "radial-gradient(120% 120% at 50% 0%, #2A2C2F 0%, #1A1B1D 60%, #131416 100%)"
            : "radial-gradient(120% 120% at 50% 0%, #DDDEDD 0%, #CBCCCB 70%, #BCBDBC 100%)",
        }}
      >
        {children}
      </div>
    </div>
  );
}
