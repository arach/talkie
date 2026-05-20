"use client";

/**
 * Architecture map v3 — Hudson workspace canvas.
 *
 * Temporary Hudson friction note: Hudson's public `hudsonkit` package currently
 * exposes the chrome/canvas/window primitives, but not `WorkspaceShell` or the
 * requested `createEmbedApp` helper as importable SDK subpaths. This file keeps
 * the Talkie-owned surface data intact and uses a tiny local embed adapter that
 * satisfies the passive `HudsonApp` contract until Hudson ships the official
 * primitive.
 */

import { useMemo, useState, type CSSProperties, type ReactNode } from "react";
import { AppWindow, CommandPalette, Frame, NavigationBar, StatusBar, TerminalDrawer } from "hudsonkit/shell";
import { ThemeProvider, type CommandOption, type HudsonApp, type StatusColor } from "hudsonkit";
import { AskAIStudy } from "./AskAIStudy";
import { BridgeDetailStudy } from "./BridgeDetailStudy";
import { CameraStudy } from "./CameraStudy";
import { Compose } from "./Compose";
import { Home } from "./Home";
import { Library } from "./Library";
import { ReadAloudStudy } from "./ReadAloudStudy";
import { Settings } from "./Settings";
import { TerminalStudy } from "./TerminalStudy";

type Domain = "root" | "capture" | "output" | "connect" | "system" | "dev";

interface Surface {
  code: string;
  name: string;
  domain: Domain;
  /** Sources that open this surface. "—" means no Next-surface entry. */
  inbound: string[];
  /** Destinations this surface opens. */
  outbound: string[];
  orphan?: boolean;
  deprecated?: boolean;
  devOnly?: boolean;
  note?: string;
}

const SURFACES: Surface[] = [
  { code: "S00", name: "Home", domain: "root", inbound: ["every back button", "voice cmd return"], outbound: ["Settings", "Library", "Compose", "CaptureDetail", "MemoDetail"] },
  { code: "S01", name: "Library", domain: "root", inbound: ["Home · ALL ›"], outbound: ["Compose", "CaptureDetail", "MemoDetail", "Home"] },
  { code: "S02", name: "Settings", domain: "root", inbound: ["Home · gear", "Chrome topTrailing", "Camera corner"], outbound: ["Home"] },
  { code: "S03", name: "Onboarding", domain: "root", inbound: ["App first-launch", "showOnboardingNotification"], outbound: ["Home"] },
  { code: "S04", name: "Compose", domain: "capture", inbound: ["Home · Recent (typed)", "Home · PICK UP Continue", "Library · row (typed)", "CaptureDetail · Refine", "VoiceMemoDetail · Refine", "DictationHistory · entry"], outbound: ["Home"] },
  { code: "S05", name: "Camera", domain: "capture", inbound: ["Chrome tray · Camera"], outbound: ["Home", "Settings", "CaptureDetail"] },
  { code: "S06", name: "Web Browser", domain: "capture", inbound: ["—"], outbound: ["Home", "CaptureDetail"], orphan: true, note: "Only reachable via --browser launch arg." },
  { code: "S07", name: "Capture Detail", domain: "capture", inbound: ["Home · Recent (link/scan)", "Library · row (link/scan)", "Camera · post-capture", "WebBrowser · post-capture"], outbound: ["Home", "Compose"] },
  { code: "S08", name: "Voice Memo Detail", domain: "capture", inbound: ["Home · Recent (dictation)", "Library · row (dictation)"], outbound: ["Home", "Compose"] },
  { code: "S09", name: "Dictation History", domain: "capture", inbound: ["—"], outbound: ["Home", "Compose"], orphan: true, note: "Only reachable via --dictations launch arg." },
  { code: "S10", name: "Read Aloud", domain: "output", inbound: ["—"], outbound: ["Home"], orphan: true, note: "Just landed. Needs Listen buttons on detail surfaces." },
  { code: "S11", name: "Ask AI", domain: "output", inbound: ["Chrome tray · Ask AI"], outbound: ["Home"] },
  { code: "S12", name: "Connection Center", domain: "connect", inbound: ["BridgeDetail · close (back)"], outbound: ["Home", "BridgeDetail"], orphan: true, note: "Only forward-reachable via --connection. Settings doesn't link to it." },
  { code: "S13", name: "Bridge Detail", domain: "connect", inbound: ["ConnectionCenter · Mac Bridge"], outbound: ["ConnectionCenter", "Terminal"] },
  { code: "S14", name: "Terminal", domain: "connect", inbound: ["BridgeDetail · Sessions"], outbound: ["Home"] },
  { code: "S15", name: "Sign In", domain: "connect", inbound: ["—"], outbound: ["Home"], orphan: true, note: "No Next surface opens it. Needs Settings CONNECT row." },
  { code: "S16", name: "Keyboard Activation", domain: "system", inbound: ["Chrome bottomTrailing · Keyboard"], outbound: ["Home"] },
  { code: "S17", name: "Appearance", domain: "system", inbound: ["—"], outbound: ["Home"], orphan: true, deprecated: true, note: "Replaced by Settings LOOK panel. Retire surface case + view." },
  { code: "S18", name: "Dictation Overlay Demo", domain: "dev", inbound: ["launch arg only"], outbound: ["Home"], devOnly: true },
];

const DOMAINS: { key: Domain; label: string }[] = [
  { key: "root", label: "ROOTS" },
  { key: "capture", label: "CAPTURE" },
  { key: "output", label: "OUTPUT" },
  { key: "connect", label: "CONNECT" },
  { key: "system", label: "SYSTEM" },
  { key: "dev", label: "DEV ONLY" },
];

const PROPOSED_WIRES = [
  { title: "Listen-anywhere", detail: "CaptureDetailNext · VoiceMemoDetailNext · AskAINext (post-response) → action chip → openReadAloud(). Closes S10's orphan status." },
  { title: "Sign in from Settings", detail: "SettingsNext CONNECT panel → 'Sign in with Apple' row when account empty → openSignIn(). Closes S15's orphan status." },
  { title: "Promote Web Browser to tray", detail: "ChromeOverlay tray → add 'Browse' slot (globe glyph) → openWebBrowser(). Tray becomes Browse · Camera · Mic · Ask AI · (Listen). Closes S06's orphan status." },
  { title: "Connection Center as Settings link", detail: "SettingsNext CONNECT panel → 'View connections detail ›' row → openConnectionCenter(). Closes S12's forward-link gap." },
  { title: "Dictation History in Library", detail: "LibraryNextView → add 'Dictations' filter tab → openDictationHistory(). Closes S09's orphan status." },
  { title: "Retire Appearance", detail: "Delete AppearancePickerNext.swift + remove .appearance from Surface enum + drop openAppearance() + --appearance launch arg. Settings LOOK panel covers it." },
];

const ORPHAN_TONE = "#d97757";
const NODE_W = 430;
const NODE_H = 560;
const POSITIONS: Record<string, { x: number; y: number }> = {
  S00: { x: 610, y: 410 }, S01: { x: 350, y: 400 }, S02: { x: 610, y: 130 }, S03: { x: 870, y: 130 },
  S04: { x: 920, y: 405 }, S05: { x: 1180, y: 260 }, S06: { x: 1180, y: 520 }, S07: { x: 920, y: 660 }, S08: { x: 660, y: 690 }, S09: { x: 1180, y: 780 },
  S10: { x: 925, y: 925 }, S11: { x: 660, y: 925 },
  S12: { x: 90, y: 365 }, S13: { x: 90, y: 635 }, S14: { x: 90, y: 905 }, S15: { x: 350, y: 690 },
  S16: { x: 1180, y: 35 }, S17: { x: 1180, y: 1035 }, S18: { x: 350, y: 940 },
};

type Bounds = { x: number; y: number; w: number; h: number };
type EmbedComponent = () => ReactNode;

interface TalkieEmbedApp extends HudsonApp {
  surface: Surface;
  initialBounds: Bounds;
}

function createLocalEmbedApp({ surface, component, initialPosition }: { surface: Surface; component: EmbedComponent; initialPosition: { x: number; y: number } }): TalkieEmbedApp {
  const Content = () => (
    <SurfaceWindowContent surface={surface}>
      {component()}
    </SurfaceWindowContent>
  );

  return {
    id: `talkie-${surface.code.toLowerCase()}`,
    name: `${surface.code} · ${surface.name}`,
    description: surface.note,
    mode: "panel",
    surface,
    initialBounds: { x: initialPosition.x, y: initialPosition.y, w: NODE_W, h: NODE_H },
    Provider: ({ children }) => <>{children}</>,
    slots: { Content },
    hooks: {
      useCommands: () => [],
      useStatus: () => statusForSurface(surface),
      useLayoutMode: () => "panel",
    },
  };
}

export function ArchitectureMap() {
  const [pan, setPan] = useState({ x: -720, y: -520 });
  const [scale, setScale] = useState(0.62);
  const [focusedAppId, setFocusedAppId] = useState("talkie-s00");
  const [bounds, setBounds] = useState<Record<string, Bounds>>({});
  const [query, setQuery] = useState("");
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [terminalOpen, setTerminalOpen] = useState(false);
  const [terminalHeight, setTerminalHeight] = useState(320);
  const [terminalMaximized, setTerminalMaximized] = useState(false);

  const apps = useMemo(() => SURFACES.map((surface) => createLocalEmbedApp({ surface, component: componentForSurface(surface), initialPosition: POSITIONS[surface.code] })), []);
  const visibleApps = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return apps;
    return apps.filter(({ surface }) => [surface.code, surface.name, surface.domain, surface.note ?? ""].join(" ").toLowerCase().includes(needle));
  }, [apps, query]);
  const orphanCount = SURFACES.filter((surface) => surface.orphan && !surface.devOnly).length;
  const focusedApp = apps.find((app) => app.id === focusedAppId) ?? apps[0];
  const commands: CommandOption[] = [
    { id: "talkie:palette", label: "Open command palette", shortcut: "⌘K", action: () => setPaletteOpen(true) },
    { id: "talkie:terminal", label: "Toggle architecture notes", shortcut: "⌃`", action: () => setTerminalOpen((value) => !value) },
    { id: "talkie:reset", label: "Reset viewport", action: () => { setPan({ x: -720, y: -520 }); setScale(0.62); } },
    ...apps.map((app) => ({ id: `focus:${app.id}`, label: `Focus ${app.name}`, action: () => focusApp(app) })),
  ];

  function focusApp(app: TalkieEmbedApp) {
    setFocusedAppId(app.id);
    setPan({ x: -app.initialBounds.x + 120, y: -app.initialBounds.y + 60 });
  }

  function appBounds(app: TalkieEmbedApp) {
    return bounds[app.id] ?? app.initialBounds;
  }

  return (
    <ThemeProvider defaultTheme="dark" defaultTemplate="hudson">
      <div className="fixed inset-0 bg-background text-foreground">
        <Frame
          mode="canvas"
          panOffset={pan}
          scale={scale}
          onPan={(delta) => setPan((current) => ({ x: current.x + delta.x, y: current.y + delta.y }))}
          onZoom={setScale}
          canvasProps={{ gridOpacity: 0.74 }}
          hud={
            <>
              <NavigationBar
                title="TALKIE"
                subtitle="ARCHITECTURE CANVAS"
                center={<HudsonSummary surfaceCount={SURFACES.length} orphanCount={orphanCount} focused={focusedApp?.surface.name} />}
                actions={<HudsonActions onPalette={() => setPaletteOpen(true)} onReset={() => { setPan({ x: -720, y: -520 }); setScale(0.62); }} />}
                search={{ value: query, onChange: setQuery, placeholder: "Filter surfaces…" }}
              />
              <StatusBar
                status={statusForSurface(focusedApp.surface)}
                left={<span className="truncate text-muted-foreground">{visibleApps.length}/{SURFACES.length} windows · {DOMAINS.length} domains · {PROPOSED_WIRES.length} proposed wires</span>}
                viewport={{ pan, zoom: scale, canvasSize: { w: 1940, h: 1700 } }}
                onToggleTerminal={() => setTerminalOpen((value) => !value)}
                isTerminalOpen={terminalOpen}
              />
              <CommandPalette isOpen={paletteOpen} onClose={() => setPaletteOpen(false)} commands={commands} />
              <TerminalDrawer
                isOpen={terminalOpen}
                onClose={() => setTerminalOpen(false)}
                height={terminalHeight}
                onHeightChange={setTerminalHeight}
                isMaximized={terminalMaximized}
                onToggleMaximize={() => setTerminalMaximized((value) => !value)}
                title={<span className="font-mono text-xs font-bold tracking-widest text-accent">TALKIE ARCHITECTURE NOTES</span>}
              >
                <ArchitectureTerminal surfaceCount={SURFACES.length} orphanCount={orphanCount} />
              </TerminalDrawer>
            </>
          }
        >
          {visibleApps.map((app) => {
            const Content = app.slots.Content;
            return (
              <AppWindow
                key={app.id}
                title={app.name}
                bounds={appBounds(app)}
                onBoundsChange={(next) => setBounds((current) => ({ ...current, [app.id]: next }))}
                isFocused={focusedAppId === app.id}
                onFocus={() => setFocusedAppId(app.id)}
                worldScale={scale}
                contextMenuItems={[{ id: `focus-${app.id}`, label: "Focus window", action: () => focusApp(app) }]}
              >
                <app.Provider visible focused={focusedAppId === app.id}>
                  <Content />
                </app.Provider>
              </AppWindow>
            );
          })}
        </Frame>
      </div>
    </ThemeProvider>
  );
}

function HudsonSummary({ surfaceCount, orphanCount, focused }: { surfaceCount: number; orphanCount: number; focused?: string }) {
  return (
    <div className="hidden items-center gap-2 rounded-full border border-border bg-card/70 px-3 py-1 font-mono text-[11px] uppercase tracking-[0.16em] text-muted-foreground md:flex">
      <span>{surfaceCount} surfaces</span><span>·</span><span className="text-warning">{orphanCount} orphans</span><span>·</span><span className="text-foreground">{focused}</span>
    </div>
  );
}

function HudsonActions({ onPalette, onReset }: { onPalette: () => void; onReset: () => void }) {
  return (
    <div className="flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.16em]">
      <button className="rounded border border-border bg-card px-2 py-1 text-muted-foreground transition hover:text-foreground" onClick={onPalette}>Cmd K</button>
      <button className="rounded border border-border bg-card px-2 py-1 text-muted-foreground transition hover:text-foreground" onClick={onReset}>Reset</button>
    </div>
  );
}

function SurfaceWindowContent({ surface, children }: { surface: Surface; children: ReactNode }) {
  const hasStudy = Boolean(componentForSurface(surface, false));
  const isOrphan = surface.orphan && !surface.devOnly;
  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden bg-[#f8f3eb] text-[#211d18]" style={previewVars}>
      <div className="flex items-start justify-between gap-3 border-b border-black/10 bg-white/70 px-3 py-2 font-mono">
        <div className="min-w-0">
          <div className="text-[9px] font-semibold uppercase tracking-[0.22em]" style={{ color: isOrphan ? ORPHAN_TONE : "rgba(33,29,24,0.48)" }}>{surface.code} · {domainLabel(surface.domain)}</div>
          <div className="truncate text-[14px] font-semibold">{surface.name}</div>
        </div>
        <Pill label={surface.devOnly ? "DEV" : surface.deprecated ? "DEPRECATED" : surface.orphan ? "ORPHAN" : "LIVE"} color={surface.devOnly || surface.deprecated ? "#7A746C" : surface.orphan ? ORPHAN_TONE : "#6f8a79"} />
      </div>
      <div className="min-h-0 flex-1 overflow-auto">
        {hasStudy ? <div className="mx-auto h-[700px] w-[340px] max-w-full">{children}</div> : <PlaceholderSurface surface={surface} />}
      </div>
      <div className="grid grid-cols-2 gap-2 border-t border-black/10 bg-white/70 px-3 py-2 font-mono text-[9px] uppercase tracking-[0.18em] text-[#7A746C]">
        <span>← {surface.inbound[0] === "—" ? 0 : surface.inbound.length}</span>
        <span className="text-right">→ {surface.outbound.length}</span>
      </div>
    </div>
  );
}

function PlaceholderSurface({ surface }: { surface: Surface }) {
  const isOrphan = surface.orphan && !surface.devOnly;
  return (
    <div className="flex h-full min-h-[420px] items-center justify-center p-8 text-center">
      <div className="max-w-[260px] rounded-2xl border border-dashed bg-white/40 p-6" style={{ borderColor: isOrphan ? "rgba(217,119,87,0.55)" : "rgba(37,31,24,0.14)" }}>
        <div className="font-mono text-[11px] font-semibold uppercase tracking-[0.22em]" style={{ color: isOrphan ? ORPHAN_TONE : "rgba(33,29,24,0.48)" }}>{surface.code}</div>
        <div className="mt-2 text-[20px] font-semibold">{surface.name}</div>
        <div className="mt-3 font-mono text-[10px] uppercase tracking-[0.18em] text-[#7A746C]">{surface.devOnly ? "dev-only surface" : surface.deprecated ? "retirement candidate" : surface.orphan ? "placeholder · orphan" : "placeholder · no study yet"}</div>
        {surface.note && <p className="mt-4 text-[12px] leading-relaxed text-[#5A5045]">{surface.note}</p>}
      </div>
    </div>
  );
}

function ArchitectureTerminal({ surfaceCount, orphanCount }: { surfaceCount: number; orphanCount: number }) {
  return (
    <div className="h-full overflow-auto bg-[#050607] p-4 font-mono text-[12px] leading-relaxed text-cyan-100/80">
      <div className="text-cyan-300">talkie architecture canvas v3</div>
      <div className="mt-2 text-cyan-100/60">Hudson primitives mounted: Frame · AppWindow · NavigationBar · StatusBar · CommandPalette · TerminalDrawer</div>
      <div className="mt-4 grid gap-1 text-cyan-100/75">
        <div>surfaces: {surfaceCount}</div>
        <div>domains: {DOMAINS.length}</div>
        <div>orphans: {orphanCount}</div>
        <div>source data: SURFACES · POSITIONS · PROPOSED_WIRES</div>
      </div>
      <div className="mt-5 text-cyan-300">proposed wires</div>
      <div className="mt-2 grid gap-3">
        {PROPOSED_WIRES.map((wire) => <div key={wire.title}><span className="text-cyan-200">{wire.title}</span><br /><span className="text-cyan-100/55">{wire.detail}</span></div>)}
      </div>
    </div>
  );
}

function componentForSurface(surface: Surface, fallback = true): EmbedComponent {
  switch (surface.name) {
    case "Home": return () => <Home />;
    case "Library": return () => <Library />;
    case "Compose": return () => <Compose state="idle" />;
    case "Settings": return () => <Settings variant="inspector" />;
    case "Terminal": return () => <TerminalStudy variant="populated" />;
    case "Bridge Detail": return () => <BridgeDetailStudy variant="paired" />;
    case "Camera": return () => <CameraStudy variant="preview" />;
    case "Ask AI": return () => <AskAIStudy variant="loop" />;
    case "Read Aloud": return () => <ReadAloudStudy variant="playing" />;
    default: return fallback ? () => null : (null as unknown as EmbedComponent);
  }
}

function statusForSurface(surface: Surface): { label: string; color: StatusColor } {
  if (surface.devOnly) return { label: "DEV", color: "neutral" };
  if (surface.deprecated) return { label: "DEPRECATED", color: "neutral" };
  if (surface.orphan) return { label: "ORPHAN", color: "amber" };
  return { label: "LIVE", color: "emerald" };
}

function Pill({ label, color }: { label: string; color: string }) {
  return <span className="shrink-0 rounded-full px-1.5 py-0.5 text-[8px] font-semibold uppercase tracking-[0.22em] font-mono" style={{ color, border: `1px solid ${color}` }}>{label}</span>;
}

function domainLabel(domain: Domain) {
  return DOMAINS.find((item) => item.key === domain)?.label ?? domain.toUpperCase();
}

const previewVars = {
  "--theme-canvas": "#f8f3eb",
  "--theme-surface": "#fffaf2",
  "--theme-edge": "rgba(37, 31, 24, 0.14)",
  "--theme-edge-faint": "rgba(37, 31, 24, 0.08)",
  "--theme-ink": "#211d18",
  "--theme-ink-dim": "rgba(33, 29, 24, 0.72)",
  "--theme-ink-faint": "rgba(33, 29, 24, 0.48)",
  "--theme-accent": "#d97757",
  "--theme-font-body": "var(--font-sans)",
  "--theme-font-mono": "var(--font-mono)",
} as CSSProperties;
