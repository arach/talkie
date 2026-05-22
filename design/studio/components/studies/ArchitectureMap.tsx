"use client";

/**
 * Architecture map — every routable surface in the Next shell,
 * grouped by domain, with inbound/outbound edge counts and orphan
 * flagging. v2: canvas-based UX journey map with embedded mini
 * surface views and SVG connection lines.
 *
 * Source-of-truth derived from grepping AppShellRouter.shared.openX
 * call sites across apps/ios/Talkie iOS/Views/Next. Update when
 * surfaces or edges change.
 */

import { useMemo, useRef, useState, type CSSProperties, type MouseEvent as ReactMouseEvent } from "react";
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
const NODE_W = 236;
const NODE_H = 236;
const BOARD_W = 1540;
const BOARD_H = 1180;

const POSITIONS: Record<string, { x: number; y: number }> = {
  S00: { x: 610, y: 410 }, S01: { x: 350, y: 400 }, S02: { x: 610, y: 130 }, S03: { x: 870, y: 130 },
  S04: { x: 920, y: 405 }, S05: { x: 1180, y: 260 }, S06: { x: 1180, y: 520 }, S07: { x: 920, y: 660 }, S08: { x: 660, y: 690 }, S09: { x: 1180, y: 780 },
  S10: { x: 925, y: 925 }, S11: { x: 660, y: 925 },
  S12: { x: 90, y: 365 }, S13: { x: 90, y: 635 }, S14: { x: 90, y: 905 }, S15: { x: 350, y: 690 },
  S16: { x: 1180, y: 35 }, S17: { x: 1180, y: 1035 }, S18: { x: 350, y: 940 },
};

type EdgeKind = "system" | "feature";
type Edge = { id: string; from: string; to: string; label: string; kind: EdgeKind };

export function ArchitectureMap() {
  const boardRef = useRef<HTMLDivElement>(null);
  const [transform, setTransform] = useState({ x: -80, y: -20, scale: 0.78 });
  const [drag, setDrag] = useState<{ sx: number; sy: number; x: number; y: number } | null>(null);
  const [hovered, setHovered] = useState<string | null>(null);
  const [selected, setSelected] = useState<Surface | null>(null);
  const orphanCount = SURFACES.filter((s) => s.orphan && !s.devOnly).length;
  const edges = useMemo(buildEdges, []);
  const activeEdges = hovered ? new Set(edges.filter((e) => e.from === hovered || e.to === hovered).map((e) => e.id)) : null;

  function onWheel(event: React.WheelEvent<HTMLDivElement>) {
    event.preventDefault();
    const rect = boardRef.current?.getBoundingClientRect();
    if (!rect) return;
    const pointX = event.clientX - rect.left;
    const pointY = event.clientY - rect.top;
    const nextScale = clamp(transform.scale * (event.deltaY > 0 ? 0.9 : 1.1), 0.42, 1.7);
    const worldX = (pointX - transform.x) / transform.scale;
    const worldY = (pointY - transform.y) / transform.scale;
    setTransform({ scale: nextScale, x: pointX - worldX * nextScale, y: pointY - worldY * nextScale });
  }

  function onMouseDown(event: ReactMouseEvent<HTMLDivElement>) {
    if (event.button !== 0) return;
    setDrag({ sx: event.clientX, sy: event.clientY, x: transform.x, y: transform.y });
  }

  function onMouseMove(event: ReactMouseEvent<HTMLDivElement>) {
    if (!drag) return;
    setTransform((current) => ({ ...current, x: drag.x + event.clientX - drag.sx, y: drag.y + event.clientY - drag.sy }));
  }

  return (
    <div className="flex flex-col gap-5">
      <div className="grid grid-cols-4 gap-4 border border-studio-edge rounded-md p-4">
        <Stat label="Surfaces" value={String(SURFACES.length)} />
        <Stat label="Domains" value={String(DOMAINS.length)} />
        <Stat label="Orphans" value={String(orphanCount)} warn />
        <Stat label="Edges" value={String(edges.length)} />
      </div>

      <div className="relative overflow-hidden rounded-lg border border-studio-edge bg-studio-canvas/60">
        <div className="absolute left-4 top-4 z-20 flex items-center gap-2 rounded-full border border-studio-edge bg-studio-canvas/90 px-3 py-2 text-[10px] font-mono uppercase tracking-eyebrow text-studio-ink-faint shadow-sm backdrop-blur">
          <span>drag to pan</span><span>·</span><span>wheel to zoom</span><span>·</span>
          <button className="text-studio-ink underline-offset-2 hover:underline" onClick={() => setTransform({ x: -80, y: -20, scale: 0.78 })}>reset</button>
        </div>

        <div
          ref={boardRef}
          className="relative h-[760px] cursor-grab select-none overflow-hidden active:cursor-grabbing"
          onWheel={onWheel}
          onMouseDown={onMouseDown}
          onMouseMove={onMouseMove}
          onMouseUp={() => setDrag(null)}
          onMouseLeave={() => setDrag(null)}
        >
          <div className="absolute left-0 top-0 origin-top-left" style={{ width: BOARD_W, height: BOARD_H, transform: `translate(${transform.x}px, ${transform.y}px) scale(${transform.scale})` }}>
            <BoardBackdrop />
            <DomainLabels />
            <svg className="pointer-events-none absolute inset-0 z-0" width={BOARD_W} height={BOARD_H}>
              <defs>
                <marker id="arrow-feature" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#7b8a98" /></marker>
                <marker id="arrow-system" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#d97757" /></marker>
              </defs>
              {edges.map((edge, index) => <EdgePath key={edge.id} edge={edge} index={index} active={!activeEdges || activeEdges.has(edge.id)} muted={Boolean(activeEdges && !activeEdges.has(edge.id))} />)}
            </svg>
            {SURFACES.map((surface) => <SurfaceNode key={surface.code} surface={surface} active={!hovered || hovered === surface.code || edges.some((e) => activeEdges?.has(e.id) && (e.from === surface.code || e.to === surface.code))} onHover={setHovered} onSelect={setSelected} />)}
          </div>
        </div>
        <Legend />
        {selected && <DetailDrawer surface={selected} onClose={() => setSelected(null)} />}
      </div>

      <div className="flex flex-col gap-4">
        <Eyebrow label="PROPOSED WIRES" count={PROPOSED_WIRES.length} />
        <div className="grid grid-cols-2 gap-3">{PROPOSED_WIRES.map((wire) => <WireCard key={wire.title} {...wire} />)}</div>
      </div>
    </div>
  );
}

function buildEdges(): Edge[] {
  const byKey = new Map(SURFACES.map((surface) => [surfaceKey(surface.name), surface]));
  return SURFACES.flatMap((surface) => surface.outbound.flatMap((name) => {
    if (name === "—") return [];
    const target = byKey.get(surfaceKey(name));
    if (!target) return [];
    return [{ id: `${surface.code}-${target.code}-${name}`, from: surface.code, to: target.code, label: name, kind: target.name === "Home" ? "system" : "feature" }];
  }));
}

function surfaceKey(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]/g, "").replace("capturedetail", "capturedetail").replace("webbrowser", "webbrowser").replace("connectioncenter", "connectioncenter").replace("bridgedetail", "bridgedetail").replace("dictationhistory", "dictationhistory").replace("memodetail", "voicememodetail");
}

function SurfaceNode({ surface, active, onHover, onSelect }: { surface: Surface; active: boolean; onHover: (code: string | null) => void; onSelect: (surface: Surface) => void }) {
  const isOrphan = surface.orphan && !surface.devOnly;
  const position = POSITIONS[surface.code];
  return (
    <div
      role="button"
      tabIndex={0}
      className="absolute z-10 flex flex-col overflow-hidden rounded-xl border bg-studio-canvas text-left shadow-[0_12px_34px_rgba(0,0,0,0.08)] transition duration-150 hover:-translate-y-0.5 hover:shadow-[0_18px_44px_rgba(0,0,0,0.12)]"
      style={{ left: position.x, top: position.y, width: NODE_W, height: NODE_H, borderColor: isOrphan ? "rgba(217,119,87,0.75)" : "var(--studio-edge, rgba(0,0,0,0.12))", opacity: active ? (surface.deprecated ? 0.72 : 1) : 0.28 }}
      onMouseEnter={() => onHover(surface.code)}
      onMouseLeave={() => onHover(null)}
      onClick={(event) => { event.stopPropagation(); onSelect(surface); }}
      onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") onSelect(surface); }}
    >
      <div className="flex items-start justify-between gap-2 border-b border-studio-edge px-3 py-2">
        <div className="min-w-0"><div className="font-mono text-[9px] font-semibold uppercase tracking-eyebrow" style={{ color: isOrphan ? ORPHAN_TONE : undefined }}>{surface.code} · {domainLabel(surface.domain)}</div><div className="truncate text-[14px] font-medium leading-tight text-studio-ink">{surface.name}</div></div>
        <StatusPill surface={surface} />
      </div>
      <SurfacePreview surface={surface} />
      <div className="grid grid-cols-2 gap-2 border-t border-studio-edge px-3 py-2 font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint"><span>← {surface.inbound[0] === "—" ? 0 : surface.inbound.length}</span><span className="text-right">→ {surface.outbound.length}</span></div>
    </div>
  );
}

function SurfacePreview({ surface }: { surface: Surface }) {
  const preview = renderPreview(surface.name);
  if (!preview) return <PlaceholderPreview surface={surface} />;
  return <div className="relative flex-1 overflow-hidden bg-black/[0.03]"><div className="absolute left-1/2 top-2 h-[520px] w-[240px] origin-top overflow-hidden rounded-[28px] border border-black/10 bg-white shadow-sm" style={{ transform: "translateX(-50%) scale(0.32)" }}><div className="h-full w-full" style={previewVars}>{preview}</div></div></div>;
}

function renderPreview(name: string) {
  switch (name) {
    case "Home": return <Home />;
    case "Library": return <Library />;
    case "Compose": return <Compose state="idle" />;
    case "Settings": return <Settings variant="inspector" />;
    case "Terminal": return <TerminalStudy variant="populated" />;
    case "Bridge Detail": return <BridgeDetailStudy variant="paired" />;
    case "Camera": return <CameraStudy variant="preview" />;
    case "Ask AI": return <AskAIStudy variant="loop" />;
    case "Read Aloud": return <ReadAloudStudy variant="playing" />;
    default: return null;
  }
}

function PlaceholderPreview({ surface }: { surface: Surface }) {
  const isOrphan = surface.orphan && !surface.devOnly;
  return <div className="flex flex-1 items-center justify-center bg-[radial-gradient(circle_at_30%_20%,rgba(255,255,255,0.75),rgba(0,0,0,0.025))] px-5"><div className="flex h-[118px] w-[150px] flex-col items-center justify-center rounded-lg border border-dashed text-center" style={{ borderColor: isOrphan ? "rgba(217,119,87,0.55)" : "var(--studio-edge)", color: isOrphan ? ORPHAN_TONE : undefined }}><div className="font-mono text-[10px] font-semibold tracking-eyebrow">{surface.code}</div><div className="mt-1 text-[13px] font-medium leading-tight text-studio-ink">{surface.name}</div><div className="mt-2 font-mono text-[8px] uppercase tracking-[0.2em] text-studio-ink-faint">thumbnail pending</div></div></div>;
}

const previewVars = { "--theme-canvas": "#f8f3eb", "--theme-surface": "#fffaf2", "--theme-edge": "rgba(37, 31, 24, 0.14)", "--theme-edge-faint": "rgba(37, 31, 24, 0.08)", "--theme-ink": "#211d18", "--theme-ink-dim": "rgba(33, 29, 24, 0.72)", "--theme-ink-faint": "rgba(33, 29, 24, 0.48)", "--theme-accent": "#d97757", "--theme-font-body": "var(--font-sans)", "--theme-font-mono": "var(--font-mono)" } as CSSProperties;

function EdgePath({ edge, index, active, muted }: { edge: Edge; index: number; active: boolean; muted: boolean }) {
  const from = center(POSITIONS[edge.from]);
  const to = center(POSITIONS[edge.to]);
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const sweep = ((index % 5) - 2) * 18;
  const c1 = { x: from.x + dx * 0.45, y: from.y + sweep };
  const c2 = { x: to.x - dx * 0.45, y: to.y - sweep + dy * 0.08 };
  const color = edge.kind === "system" ? ORPHAN_TONE : "#7b8a98";
  return <path d={`M ${from.x} ${from.y} C ${c1.x} ${c1.y}, ${c2.x} ${c2.y}, ${to.x} ${to.y}`} fill="none" stroke={color} strokeWidth={edge.kind === "system" ? 1.8 : 1.25} strokeOpacity={muted ? 0.08 : active ? 0.78 : 0.26} markerEnd={`url(#arrow-${edge.kind})`} strokeDasharray={edge.kind === "system" ? "5 6" : undefined} />;
}

function center(pos: { x: number; y: number }) { return { x: pos.x + NODE_W / 2, y: pos.y + NODE_H / 2 }; }
function BoardBackdrop() { return <div className="absolute inset-0 z-[-2]" style={{ backgroundImage: "linear-gradient(rgba(120,120,120,0.08) 1px, transparent 1px), linear-gradient(90deg, rgba(120,120,120,0.08) 1px, transparent 1px)", backgroundSize: "40px 40px" }} />; }
function DomainLabels() { return <><DomainCluster label="CONNECT" x={70} y={320} w={280} h={880} /><DomainCluster label="ROOTS" x={330} y={90} w={790} h={560} /><DomainCluster label="CAPTURE" x={640} y={250} w={800} h={660} /><DomainCluster label="OUTPUT" x={635} y={890} w={540} h={320} /><DomainCluster label="SYSTEM" x={1160} y={10} w={300} h={270} /><DomainCluster label="SYSTEM / DEV" x={330} y={900} w={1130} h={300} /></>; }
function DomainCluster({ label, x, y, w, h }: { label: string; x: number; y: number; w: number; h: number }) { return <div className="pointer-events-none absolute rounded-[28px] border border-studio-edge/70 bg-white/[0.18]" style={{ left: x, top: y, width: w, height: h }}><div className="absolute -top-3 left-5 rounded-full border border-studio-edge bg-studio-canvas px-2 py-1 font-mono text-[8px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">{label}</div></div>; }
function Legend() { return <div className="absolute bottom-4 left-4 z-20 flex gap-3 rounded-full border border-studio-edge bg-studio-canvas/90 px-3 py-2 text-[10px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint shadow-sm backdrop-blur"><span className="inline-flex items-center gap-1.5"><i className="h-px w-5 bg-[#7b8a98]" /> feature flow</span><span className="inline-flex items-center gap-1.5"><i className="h-px w-5 border-t border-dashed" style={{ borderColor: ORPHAN_TONE }} /> system / return home</span><span className="inline-flex items-center gap-1.5"><i className="h-2 w-2 rounded-full" style={{ background: ORPHAN_TONE }} /> orphan</span></div>; }

function DetailDrawer({ surface, onClose }: { surface: Surface; onClose: () => void }) {
  const isOrphan = surface.orphan && !surface.devOnly;
  return <div className="absolute right-4 top-4 z-30 w-[330px] rounded-xl border border-studio-edge bg-studio-canvas/95 p-4 shadow-2xl backdrop-blur"><div className="flex items-start justify-between gap-4"><div><div className="font-mono text-[9px] font-semibold uppercase tracking-eyebrow" style={{ color: isOrphan ? ORPHAN_TONE : undefined }}>{surface.code} · {domainLabel(surface.domain)}</div><div className="mt-1 text-[18px] font-medium leading-tight text-studio-ink">{surface.name}</div></div><button className="rounded-full border border-studio-edge px-2 py-1 text-[10px] text-studio-ink-faint" onClick={onClose}>Close</button></div><div className="mt-3"><StatusPill surface={surface} /></div>{surface.note && <div className="mt-3 rounded-md border border-studio-edge p-3 text-[11px] leading-snug text-studio-ink-faint">{surface.note}</div>}<div className="mt-4 flex flex-col gap-3"><EdgeRow arrow="←" items={surface.inbound} orphan={isOrphan && surface.inbound[0] === "—"} /><EdgeRow arrow="→" items={surface.outbound} /></div></div>;
}

function Stat({ label, value, warn }: { label: string; value: string; warn?: boolean }) { return <div className="flex flex-col gap-1"><span className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">{label}</span><span className="text-[26px] tabular-nums leading-none font-mono" style={{ color: warn ? ORPHAN_TONE : undefined }}>{value}</span></div>; }
function Eyebrow({ label, count }: { label: string; count?: number }) { return <div className="flex items-baseline gap-3 pb-1.5 border-b border-studio-edge"><span className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">· {label}</span>{count !== undefined && <span className="text-[10px] tabular-nums font-mono text-studio-ink-faint">{count}</span>}</div>; }
function StatusPill({ surface }: { surface: Surface }) { if (surface.devOnly) return <Pill label="DEV" color="var(--studio-ink-faint, #888)" />; if (surface.deprecated) return <Pill label="DEPRECATED" color="var(--studio-ink-faint, #888)" />; if (surface.orphan) return <Pill label="ORPHAN" color={ORPHAN_TONE} />; return <Pill label="LIVE" color="#6f8a79" />; }
function Pill({ label, color }: { label: string; color: string }) { return <span className="shrink-0 rounded-full px-1.5 py-0.5 text-[8px] font-semibold uppercase tracking-eyebrow font-mono" style={{ color, border: `1px solid ${color}` }}>{label}</span>; }
function EdgeRow({ arrow, items, orphan = false }: { arrow: string; items: string[]; orphan?: boolean }) { const count = items.length === 1 && items[0] === "—" ? 0 : items.length; return <div className="flex items-start gap-2"><span className="text-[10px] tabular-nums font-mono" style={{ color: orphan ? ORPHAN_TONE : undefined, minWidth: 22 }}>{arrow} {count}</span><span className="text-[10px] leading-snug text-studio-ink-faint" style={{ color: orphan ? ORPHAN_TONE : undefined }}>{items.join(" · ")}</span></div>; }
function WireCard({ title, detail }: { title: string; detail: string }) { return <div className="flex flex-col gap-1.5 rounded-md border border-studio-edge p-3"><div className="text-[13px] font-medium text-studio-ink">{title}</div><div className="text-[11px] leading-snug text-studio-ink-faint">{detail}</div></div>; }
function domainLabel(domain: Domain) { return DOMAINS.find((item) => item.key === domain)?.label ?? domain.toUpperCase(); }
function clamp(value: number, min: number, max: number) { return Math.min(max, Math.max(min, value)); }
