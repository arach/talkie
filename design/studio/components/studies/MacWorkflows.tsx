"use client";

/**
 * Mac Workflows — sheet + run inspector, theme-aware.
 *
 * v0.2 — lighter pass. Boxes-around-everything is what made v0.1
 * feel like a schematic; we want it to feel like a document with a
 * live inspector. Moves:
 *   - step cards lose their border; rule-separated rows instead
 *   - bindings read like one English line: `in  ← {token} · TXT · note`
 *   - drop status pills that all said "idle" (noise, not signal)
 *   - drop the column legend row
 *   - drop eyebrow ALL-CAPS on every block; one eyebrow per region
 *   - token chips lose background + border; just accent text
 *   - type chips lose border; small faint mono
 *   - WorkflowList rows lose fill and the accent left bar; an inset
 *     accent dot + accent name carries selection
 *   - product bar drops the v0.4 ID + counts strip
 *
 * Theme-aware via `var(--scheme-*)`. Route renders it under both
 * AMBER (dark) and BONE (light) so the calmer treatment can be read
 * in both registers.
 *
 * ─── NamesMarginalia ─────────────────────────────────────────────────
 *   WorkflowsShell      outer 3-col container
 *   ProductBar          top strip (breadcrumb · run)
 *   WorkflowList        left column
 *   WorkflowListRow     name + sub-meta · selected gets dot + accent
 *   WorkflowDetail      center column
 *   DetailHeader        crumb + actions
 *   DetailTitleBlock    title + one-line description
 *   StepRow             one step, no border — rule above
 *   StepHeadline        number · kind italic · name
 *   StepBindings        wrapped one-per-line binding lines
 *   Arrow               ← → glyph (replaces IN/OUT labels)
 *   Token               `{name}` in accent
 *   TypeTag             small faint mono uppercase
 *   RunInspector        right column
 *   InputPreviewBlock   selected input (thumbnail + meta)
 *   RunsList            run log (numbered, status word in faint)
 *   TraceBlock          selected run's trace
 */

import React from "react";

// ─── Tokens (scheme-* CSS vars, set by SchemeCard) ────────────────────

const BG          = "var(--scheme-bg)";
const INK         = "var(--scheme-ink)";
const INK_FAINT   = "var(--scheme-ink-faint)";
const INK_SUBTLE  = "var(--scheme-ink-subtle)";
const ACCENT      = "var(--scheme-accent)";
const EDGE        = "var(--scheme-edge)";
const EDGE_STRONG = "var(--scheme-edge-strong)";
const ACCENT_RING = "var(--scheme-accent-ring)";

// ─── Data ────────────────────────────────────────────────────────────

type WorkflowEntry = { code: string; name: string; subtitle: string };

const WORKFLOWS: WorkflowEntry[] = [
  { code: "WF-01", name: "Describe UI",   subtitle: "1 step · rev C" },
  { code: "WF-02", name: "Hey Talkie",    subtitle: "5 steps · rev 8" },
  { code: "WF-03", name: "Transcribe",    subtitle: "1 step · rev A" },
  { code: "WF-04", name: "Inbox Triage",  subtitle: "4 steps · draft" },
];

const ACTIVE = "WF-02";

type Binding = { dir: "in" | "out"; token: string; type: string; note?: string };

interface Step {
  n: string;
  kind: string;
  name: string;
  bindings: Binding[];
}

const STEPS: Step[] = [
  {
    n: "01",
    kind: "audio input",
    name: "Capture and resample the microphone stream",
    bindings: [
      { dir: "in",  token: "trigger.hotkey", type: "EVT"   },
      { dir: "out", token: "audio",          type: "PCM16", note: "16 kHz mono" },
    ],
  },
  {
    n: "02",
    kind: "transcribe",
    name: "Whisper.cpp on-device · medium.en",
    bindings: [
      { dir: "in",  token: "audio",      type: "PCM16", note: "from 01" },
      { dir: "out", token: "transcript", type: "TXT",   note: "lang en" },
    ],
  },
  {
    n: "03",
    kind: "llm",
    name: "Route intent — answer, call a tool, or escalate",
    bindings: [
      { dir: "in",  token: "transcript", type: "TXT",  note: "from 02" },
      { dir: "out", token: "intent",     type: "JSON", note: "action · tool · args" },
    ],
  },
  {
    n: "04",
    kind: "tool call",
    name: "Dispatch to local tool",
    bindings: [
      { dir: "in",  token: "intent.tool", type: "STR"  },
      { dir: "in",  token: "intent.args", type: "JSON" },
      { dir: "out", token: "toolResult",  type: "JSON", note: "or null" },
    ],
  },
  {
    n: "05",
    kind: "llm",
    name: "Compose spoken reply",
    bindings: [
      { dir: "in",  token: "transcript", type: "TXT"  },
      { dir: "in",  token: "intent",     type: "JSON" },
      { dir: "in",  token: "toolResult", type: "JSON", note: "may be null" },
      { dir: "out", token: "reply",      type: "TXT",  note: "→ TTS" },
    ],
  },
];

type RunStatus = "ok" | "running" | "queued";
interface RunRow {
  n: string;
  time: string;
  label: string;
  status: RunStatus;
}

const RUNS: RunRow[] = [
  { n: "1", time: "10:15:17", label: "Describe UI queued",  status: "ok" },
  { n: "2", time: "10:15:17", label: "Describe UI started", status: "ok" },
  { n: "3", time: "10:15:17", label: "Resolving capture",   status: "ok" },
  { n: "4", time: "10:15:17", label: "Inputs bound",        status: "ok" },
  { n: "5", time: "10:15:17", label: "Running Describe UI", status: "running" },
];

// ─── Agent turns + model picker data ─────────────────────────────────

type TurnRole = "user" | "agent";
interface Turn {
  id: string;
  role: TurnRole;
  time: string;
  body: string;
  applied?: string[]; // for agent turns: short summary of edits
}

const TURNS: Turn[] = [
  {
    id: "t1",
    role: "user",
    time: "10:34",
    body: "Add a fallback step that calls Claude if Whisper confidence is below 0.6.",
  },
  {
    id: "t2",
    role: "agent",
    time: "10:34",
    body: "Added a conditional step between 02 and 03.",
    applied: [
      "new step 03 · conditional",
      "when transcript.confidence < 0.6",
      "→ llm · claude-haiku-4-5",
    ],
  },
  {
    id: "t3",
    role: "user",
    time: "10:36",
    body: "Bump the LLM temperature on step 05 to 0.8.",
  },
  {
    id: "t4",
    role: "agent",
    time: "10:36",
    body: "Step 05 temperature → 0.8.",
    applied: ["step 05 · temp 0.6 → 0.8"],
  },
];

interface Model {
  id: string;
  name: string;
  family: string;
  hint?: string;
}

const MODELS: Model[] = [
  { id: "claude-sonnet-4-6", name: "sonnet-4-6", family: "Claude", hint: "default" },
  { id: "claude-opus-4-7",   name: "opus-4-7",   family: "Claude", hint: "max" },
  { id: "claude-haiku-4-5",  name: "haiku-4-5",  family: "Claude", hint: "fast" },
  { id: "gpt-5",             name: "gpt-5",      family: "OpenAI" },
];

// ─── Component ───────────────────────────────────────────────────────
//
// Inspector is resizable (drag the hairline divider). Edit in the
// header flips the inspector from Runs mode to Data mode — the data
// inspector reveals the workflow's underlying structure as a JSON
// tree, read-only. Switching modes keeps the same inspector width
// so devs who widen it once stay widened.

type InspectorMode = "runs" | "data";

const MIN_INSPECTOR = 280;
const MAX_INSPECTOR = 720;

export function MacWorkflows() {
  const [inspectorWidth, setInspectorWidth] = React.useState(360);
  const [mode, setMode] = React.useState<InspectorMode>("runs");
  const shellRef = React.useRef<HTMLDivElement | null>(null);
  const [containerWidth, setContainerWidth] = React.useState(1280);

  React.useEffect(() => {
    if (!shellRef.current) return;
    const ro = new ResizeObserver((entries) => {
      for (const e of entries) setContainerWidth(e.contentRect.width);
    });
    ro.observe(shellRef.current);
    return () => ro.disconnect();
  }, []);

  return (
    <div
      ref={shellRef}
      className="font-mono text-[11px]"
      style={{ background: BG, color: INK }}
    >
      <ProductBar />
      <div
        className="grid"
        style={{
          gridTemplateColumns: `192px 1fr 1px ${inspectorWidth}px`,
          minHeight: 760,
        }}
      >
        <WorkflowList />
        <WorkflowDetail
          onEdit={() => {
            setMode("data");
            // Auto-widen so the JSON has room to breathe.
            setInspectorWidth((w) => Math.max(w, 460));
          }}
        />
        <ResizeHandle
          width={inspectorWidth}
          halfWidth={containerWidth / 2}
          onWidthChange={setInspectorWidth}
        />
        <RunInspector mode={mode} onModeChange={setMode} />
      </div>
    </div>
  );
}

// Named widths the dev is likely to want. On pointer-up the handle
// soft-snaps if you're within 16px of any of these. The "half"
// target is half the container width — the dev's "split-pane,
// JSON next to workflow" configuration.
const FIXED_SNAPS = [360, 460, 600];
const SNAP_RADIUS = 16;

function snapWidth(value: number, halfWidth: number): number {
  const targets = [...FIXED_SNAPS, halfWidth];
  for (const target of targets) {
    if (Math.abs(value - target) <= SNAP_RADIUS) return target;
  }
  return value;
}

function ResizeHandle({
  width,
  halfWidth,
  onWidthChange,
}: {
  width: number;
  halfWidth: number;
  onWidthChange: (n: number) => void;
}) {
  const startX = React.useRef<number | null>(null);
  const startW = React.useRef<number>(width);

  function onPointerDown(e: React.PointerEvent) {
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    startX.current = e.clientX;
    startW.current = width;
  }
  function onPointerMove(e: React.PointerEvent) {
    if (startX.current == null) return;
    const dx = startX.current - e.clientX;
    const next = Math.min(MAX_INSPECTOR, Math.max(MIN_INSPECTOR, startW.current + dx));
    onWidthChange(next);
  }
  function onPointerUp(e: React.PointerEvent) {
    if (startX.current != null) {
      onWidthChange(snapWidth(width, halfWidth));
    }
    startX.current = null;
    (e.target as HTMLElement).releasePointerCapture(e.pointerId);
  }

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      className="relative cursor-col-resize select-none"
      style={{ background: EDGE }}
    >
      {/* widen the hit area without widening the visible hairline */}
      <div
        className="absolute top-0 bottom-0"
        style={{ left: -4, right: -4 }}
      />
    </div>
  );
}

// ─── ProductBar ──────────────────────────────────────────────────────

function ProductBar() {
  return (
    <div
      className="flex items-center px-5 h-11 border-b"
      style={{ borderColor: EDGE }}
    >
      <div className="flex items-center gap-2 text-[12px]" style={{ color: INK_FAINT }}>
        <span>Workflows</span>
        <Slash />
        <span>talkie</span>
        <Slash />
        <span style={{ color: INK }}>Hey Talkie</span>
      </div>
      <div className="ml-auto flex items-center gap-2">
        <RunButton />
      </div>
    </div>
  );
}

function Slash() {
  return <span style={{ color: INK_SUBTLE }}>/</span>;
}

// ─── Left: WorkflowList ──────────────────────────────────────────────

function WorkflowList() {
  return (
    <aside
      className="border-r py-4 px-2"
      style={{ borderColor: EDGE }}
    >
      <div className="flex flex-col">
        {WORKFLOWS.map((wf) => (
          <WorkflowListRow key={wf.code} wf={wf} active={wf.code === ACTIVE} />
        ))}
      </div>
      <button
        className="mt-3 px-3 py-2 w-full text-left text-[11px] rounded-md"
        style={{ color: INK_SUBTLE }}
      >
        + New workflow
      </button>
    </aside>
  );
}

function WorkflowListRow({
  wf,
  active,
}: { wf: WorkflowEntry; active: boolean }) {
  return (
    <button
      className="text-left px-3 py-2 rounded-md flex items-baseline gap-2"
      style={{ background: active ? ACCENT_RING : "transparent" }}
    >
      <span
        className="inline-block w-1 h-1 rounded-full mt-1.5"
        style={{ background: active ? ACCENT : "transparent" }}
      />
      <div className="flex-1">
        <div className="text-[12px]" style={{ color: active ? ACCENT : INK }}>
          {wf.name}
        </div>
        <div className="text-[10px] mt-0.5" style={{ color: INK_SUBTLE }}>
          {wf.subtitle}
        </div>
      </div>
    </button>
  );
}

// ─── Center: WorkflowDetail ──────────────────────────────────────────

function WorkflowDetail({ onEdit }: { onEdit: () => void }) {
  // Turns is conversational — it owns its own height. Drag the seam
  // above it to grow / shrink. Collapsed state hides it entirely.
  const [turnsCollapsed, setTurnsCollapsed] = React.useState(false);
  const [turnsHeight, setTurnsHeight] = React.useState(180);

  return (
    <section className="flex flex-col" style={{ minHeight: 760 }}>
      <DetailHeader onEdit={onEdit} />
      <div className="flex-1 flex flex-col" style={{ minHeight: 0 }}>
        <div className="flex-1 overflow-auto">
          <DetailTitleBlock />
          <StepList />
        </div>
      </div>
      {!turnsCollapsed && (
        <TurnsResizeHandle
          height={turnsHeight}
          onHeightChange={setTurnsHeight}
        />
      )}
      <TurnsBlock
        collapsed={turnsCollapsed}
        onToggle={() => setTurnsCollapsed((v) => !v)}
        height={turnsHeight}
      />
      <BuilderComposer />
    </section>
  );
}

const MIN_TURNS_HEIGHT = 80;
const MAX_TURNS_HEIGHT = 560;

function TurnsResizeHandle({
  height,
  onHeightChange,
}: {
  height: number;
  onHeightChange: (h: number) => void;
}) {
  const startY = React.useRef<number | null>(null);
  const startH = React.useRef<number>(height);

  function onPointerDown(e: React.PointerEvent) {
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    startY.current = e.clientY;
    startH.current = height;
  }
  function onPointerMove(e: React.PointerEvent) {
    if (startY.current == null) return;
    const dy = startY.current - e.clientY; // drag UP grows the panel
    const next = Math.min(MAX_TURNS_HEIGHT, Math.max(MIN_TURNS_HEIGHT, startH.current + dy));
    onHeightChange(next);
  }
  function onPointerUp(e: React.PointerEvent) {
    startY.current = null;
    (e.target as HTMLElement).releasePointerCapture(e.pointerId);
  }

  return (
    <div
      role="separator"
      aria-orientation="horizontal"
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      className="relative cursor-row-resize select-none"
      style={{ height: 1, background: EDGE }}
    >
      {/* Wider hit area */}
      <div
        className="absolute left-0 right-0"
        style={{ top: -4, bottom: -4 }}
      />
    </div>
  );
}

function DetailHeader({ onEdit }: { onEdit: () => void }) {
  return (
    <div
      className="px-6 h-11 flex items-center gap-3 border-b text-[11px]"
      style={{ borderColor: EDGE, color: INK_FAINT }}
    >
      <span>5 steps</span>
      <Dot />
      <span>rev 8</span>
      <Dot />
      <span>updated May 26</span>
      <div className="ml-auto flex items-center gap-1.5">
        <Btn onClick={onEdit}>Edit</Btn>
        <Btn>Duplicate</Btn>
      </div>
    </div>
  );
}

function Dot() {
  return (
    <span
      aria-hidden
      className="inline-block w-[3px] h-[3px] rounded-full"
      style={{ background: INK_SUBTLE }}
    />
  );
}

function DetailTitleBlock() {
  return (
    <div className="px-6 pt-6 pb-5">
      <div className="font-display text-[24px] leading-none" style={{ color: INK }}>
        Hey Talkie
      </div>
      <div className="mt-3 text-[12px] max-w-[640px] leading-relaxed" style={{ color: INK_FAINT }}>
        Voice command → resolve intent → execute. Multi-step chain across whisper,
        Claude, and the tool router.
      </div>
    </div>
  );
}

function StepList() {
  return (
    <div className="px-2 pb-6">
      {STEPS.map((s, i) => (
        <StepRow key={s.n} step={s} first={i === 0} />
      ))}
    </div>
  );
}

// ─── TurnsBlock ──────────────────────────────────────────────────────
//
// Conversational history with the builder agent. Sits between the
// step sheet and the composer — the dev sees what they asked, what
// changed, what to ask next. Auto-scrolls to bottom; collapsible
// when the dev wants just the workflow view back.
//
// Turn shape:
//   - user turns  : indented left, plain prose
//   - agent turns : indented right, optional 'applied' diff bullets
// Time stamps + role glyph at the head of each turn.

function TurnsBlock({
  collapsed,
  onToggle,
  height,
}: {
  collapsed: boolean;
  onToggle: () => void;
  height: number;
}) {
  return (
    <div
      style={{
        background: BG,
        height: collapsed ? undefined : height,
        overflow: "hidden",
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div
        className="px-6 pt-3 pb-2 flex items-baseline text-[10px]"
        style={{ color: INK_SUBTLE, background: BG, flexShrink: 0 }}
      >
        <span className="tracking-[0.18em] uppercase">turns</span>
        <span className="ml-2">· {TURNS.length}</span>
        <button
          onClick={onToggle}
          className="ml-auto"
          style={{ color: INK_SUBTLE }}
        >
          {collapsed ? "show" : "collapse"}
        </button>
      </div>
      {!collapsed && (
        <div className="px-6 pb-3 flex flex-col gap-3 overflow-auto">
          {TURNS.map((turn) => (
            <TurnRow key={turn.id} turn={turn} />
          ))}
        </div>
      )}
    </div>
  );
}

function TurnRow({ turn }: { turn: Turn }) {
  const isAgent = turn.role === "agent";
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-baseline gap-2 text-[10px]" style={{ color: INK_SUBTLE }}>
        <span
          aria-hidden
          className="inline-block w-[5px] h-[5px] rounded-full"
          style={{ background: isAgent ? ACCENT : INK_SUBTLE }}
        />
        <span style={{ color: isAgent ? ACCENT : INK_FAINT }}>
          {isAgent ? "builder" : "you"}
        </span>
        <Dot />
        <span>{turn.time}</span>
      </div>
      <div
        className="text-[12px] leading-relaxed"
        style={{
          color: isAgent ? INK : INK_FAINT,
          paddingLeft: 12,
          borderLeft: `1px solid ${isAgent ? "transparent" : EDGE}`,
        }}
      >
        {turn.body}
      </div>
    </div>
  );
}

// ─── BuilderComposer ─────────────────────────────────────────────────
//
// Chat input. Above: status row with agent identity + interactive
// model picker + turn count. Below: input row with brass prompt glyph,
// editable text, mic toggle, send button. Mic flips between idle
// (faint outline) and recording (brass-filled + brass underline).
// Model picker reveals a small menu of available models.

function BuilderComposer() {
  const [model, setModel] = React.useState<Model>(MODELS[0]);
  const [showModels, setShowModels] = React.useState(false);
  const [recording, setRecording] = React.useState(false);

  return (
    <div
      className="border-t"
      style={{ borderColor: EDGE, background: BG }}
    >
      {/* Status row */}
      <div className="px-6 pt-3 pb-2 flex items-baseline gap-2 text-[10px]" style={{ color: INK_SUBTLE }}>
        <span
          aria-hidden
          className="inline-block w-1.5 h-1.5 rounded-full"
          style={{ background: ACCENT }}
        />
        <span>builder · hudson</span>
        <Dot />
        <div className="relative">
          <button
            onClick={() => setShowModels((v) => !v)}
            className="flex items-baseline gap-1"
            style={{ color: INK }}
          >
            <span>{model.name}</span>
            <span style={{ color: INK_SUBTLE, fontSize: 9 }}>▾</span>
          </button>
          {showModels && (
            <ModelMenu
              current={model}
              onPick={(m) => {
                setModel(m);
                setShowModels(false);
              }}
              onDismiss={() => setShowModels(false)}
            />
          )}
        </div>
        <Dot />
        <span>{TURNS.length} turns</span>
        <span className="ml-auto">{recording ? "● listening…" : ""}</span>
      </div>

      {/* Input row */}
      <div className="px-6 pb-5">
        <div
          className="rounded-md flex items-start gap-2 px-3 py-2.5"
          style={{
            border: `1px solid ${recording ? ACCENT : EDGE_STRONG}`,
            background: ACCENT_RING,
          }}
        >
          <span
            aria-hidden
            className="text-[11px] mt-[1px]"
            style={{ color: ACCENT }}
          >
            ›
          </span>
          <span
            className="flex-1 text-[12px] leading-relaxed"
            style={{ color: recording ? INK_SUBTLE : INK }}
            role="textbox"
            aria-label="Message the builder"
          >
            {recording
              ? "(speak — release ⎇ to send, ⌘. to cancel)"
              : "Tell the builder what to change…"}
            {!recording && (
              <span
                aria-hidden
                className="inline-block w-[7px] h-[14px] align-middle ml-[2px]"
                style={{ background: ACCENT }}
              />
            )}
          </span>
          <MicButton
            recording={recording}
            onToggle={() => setRecording((v) => !v)}
          />
          <button
            className="text-[11px] px-2 py-[3px] rounded-md self-start"
            style={{ background: ACCENT, color: BG }}
          >
            send
          </button>
        </div>
        <div className="mt-2 flex items-baseline gap-3 text-[10px]" style={{ color: INK_SUBTLE }}>
          <span>↵ send</span>
          <Dot />
          <span>⇧↵ newline</span>
          <Dot />
          <span>⌥ hold to dictate</span>
          <Dot />
          <span>⌘K commands</span>
          <span className="ml-auto">attach: ⌘. screenshot · ⌘L logs</span>
        </div>
      </div>
    </div>
  );
}

function MicButton({
  recording,
  onToggle,
}: {
  recording: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      onClick={onToggle}
      className="self-start rounded-md flex items-center justify-center"
      style={{
        width: 24,
        height: 22,
        background: recording ? ACCENT : "transparent",
        color: recording ? BG : ACCENT,
        border: `1px solid ${recording ? ACCENT : EDGE_STRONG}`,
      }}
      aria-label={recording ? "Stop dictation" : "Start dictation"}
      title={recording ? "Stop dictation" : "Start dictation (⌥ hold)"}
    >
      {/* Compact mic glyph in mono */}
      <span style={{ fontSize: 11, lineHeight: 1 }}>{recording ? "●" : "◉"}</span>
    </button>
  );
}

function ModelMenu({
  current,
  onPick,
  onDismiss,
}: {
  current: Model;
  onPick: (m: Model) => void;
  onDismiss: () => void;
}) {
  // Group by family for the menu
  const byFamily = MODELS.reduce<Record<string, Model[]>>((acc, m) => {
    (acc[m.family] = acc[m.family] || []).push(m);
    return acc;
  }, {});
  return (
    <>
      {/* Click-outside scrim */}
      <div
        onClick={onDismiss}
        className="fixed inset-0"
        style={{ zIndex: 10 }}
        aria-hidden
      />
      <div
        className="absolute mt-1 rounded-md"
        style={{
          minWidth: 200,
          background: BG,
          border: `1px solid ${EDGE_STRONG}`,
          boxShadow: "0 4px 14px rgba(0,0,0,0.12)",
          zIndex: 11,
          left: 0,
          top: "100%",
        }}
      >
        {Object.entries(byFamily).map(([family, models]) => (
          <div key={family} className="py-1">
            <div
              className="px-3 py-1 text-[9px] tracking-[0.18em] uppercase"
              style={{ color: INK_SUBTLE }}
            >
              {family}
            </div>
            {models.map((m) => {
              const isCurrent = m.id === current.id;
              return (
                <button
                  key={m.id}
                  onClick={() => onPick(m)}
                  className="w-full text-left px-3 py-1.5 flex items-baseline gap-2"
                  style={{
                    background: isCurrent ? ACCENT_RING : "transparent",
                  }}
                >
                  <span
                    aria-hidden
                    className="inline-block w-[5px] h-[5px] rounded-full"
                    style={{
                      background: isCurrent ? ACCENT : "transparent",
                      border: isCurrent ? "none" : `1px solid ${INK_SUBTLE}`,
                    }}
                  />
                  <span
                    className="text-[11px] flex-1"
                    style={{ color: isCurrent ? ACCENT : INK }}
                  >
                    {m.name}
                  </span>
                  {m.hint && (
                    <span className="text-[10px]" style={{ color: INK_SUBTLE }}>
                      {m.hint}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        ))}
      </div>
    </>
  );
}

function StepRow({ step, first }: { step: Step; first: boolean }) {
  return (
    <div
      className="px-4 py-4"
      style={{ borderTop: first ? "none" : `1px solid ${EDGE}` }}
    >
      <div className="flex items-baseline gap-3">
        <span className="text-[11px] tabular-nums" style={{ color: INK_SUBTLE, width: 18 }}>
          {step.n}
        </span>
        <div className="flex-1">
          <div className="flex items-baseline gap-2">
            <span className="text-[13px] leading-none" style={{ color: INK }}>
              {step.name}
            </span>
            <span className="text-[11px]" style={{ color: ACCENT }}>
              · {step.kind}
            </span>
          </div>
          <div className="mt-2 flex flex-col gap-[2px]">
            {step.bindings.map((b, i) => (
              <BindingLine key={i} binding={b} />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function BindingLine({ binding }: { binding: Binding }) {
  const dirLabel = binding.dir === "in" ? "in " : "out";
  return (
    <div className="flex items-baseline gap-2 text-[11px]" style={{ color: INK_FAINT }}>
      <span className="font-mono tabular-nums" style={{ color: INK_SUBTLE, width: 22 }}>
        {dirLabel}
      </span>
      <span style={{ color: INK_SUBTLE }}>{binding.dir === "in" ? "←" : "→"}</span>
      <Token text={binding.token} />
      <TypeTag text={binding.type} />
      {binding.note ? (
        <span className="text-[11px]" style={{ color: INK_FAINT }}>· {binding.note}</span>
      ) : null}
    </div>
  );
}

// ─── Right: RunInspector ─────────────────────────────────────────────
//
// Two modes:
//   "runs" — input preview, run log, trace (default)
//   "data" — read-only JSON of the workflow definition (Edit toggles here)
//
// The header carries a tab pair so devs can flip without re-finding
// the Edit button.

function RunInspector({
  mode,
  onModeChange,
}: {
  mode: InspectorMode;
  onModeChange: (m: InspectorMode) => void;
}) {
  return (
    <aside className="flex flex-col" style={{ background: BG }}>
      <div
        className="px-5 h-11 flex items-center border-b text-[11px]"
        style={{ borderColor: EDGE, color: INK_FAINT }}
      >
        <ModeTab label="Runs" active={mode === "runs"} onClick={() => onModeChange("runs")} />
        <ModeTab label="Data" active={mode === "data"} onClick={() => onModeChange("data")} />
        {mode === "runs" ? <RunButton small className="ml-auto" /> : (
          <div className="ml-auto flex items-center gap-3">
            <span style={{ color: INK_SUBTLE }}>read-only</span>
            <button className="text-[11px]" style={{ color: INK_SUBTLE }}>copy</button>
          </div>
        )}
      </div>

      {mode === "runs" ? (
        <>
          <InputPreviewBlock />
          <RunsBlock />
          <TraceBlock />
        </>
      ) : (
        <DataInspectorBlock />
      )}
    </aside>
  );
}

function ModeTab({
  label,
  active,
  onClick,
}: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="text-[11px] mr-4 pb-[1px]"
      style={{
        color: active ? INK : INK_FAINT,
        borderBottom: `2px solid ${active ? ACCENT : "transparent"}`,
        paddingBottom: 2,
      }}
    >
      {label}
    </button>
  );
}

// ─── Input picker ────────────────────────────────────────────────────
//
// The Input block IS the picker. Three layers stacked:
//   1. Selected — title, meta, preview tile (varies by source kind)
//   2. Recent — last few inputs, click to swap. The current pick gets
//      a brass dot and ink-primary text; the others are quieter.
//   3. Actions — Library opens a deeper search; Record cuts a fresh
//      audio sample inline; Text drops a plain-text snippet in.
//
// This is the playground surface: cycle inputs without leaving the
// workflow doc. The library sheet still exists for deeper search, but
// you shouldn't NEED it for the next-five-things-I-tried case.

type SourceKind = "capture" | "memo" | "note" | "text" | "recording";

interface InputItem {
  id: string;
  kind: SourceKind;
  title: string;
  meta: string;
}

const SAMPLE_INPUTS: InputItem[] = [
  { id: "in-1", kind: "capture",   title: "Talkie Capture",      meta: "10:36 · window · 1280×525" },
  { id: "in-2", kind: "memo",      title: "Standup notes",       meta: "1m 14s · 247 w" },
  { id: "in-3", kind: "memo",      title: "Daily 2026-05-25",    meta: "3m 02s · 612 w" },
  { id: "in-4", kind: "text",      title: "Pasted snippet",      meta: "24 words" },
  { id: "in-5", kind: "capture",   title: "Talkie Capture",      meta: "09:14 · region · 820×340" },
  { id: "in-6", kind: "note",      title: "Meeting prep",        meta: "182 words" },
];

const RECENT_VISIBLE = 3;

function InputPreviewBlock() {
  const [selectedId, setSelectedId] = React.useState(SAMPLE_INPUTS[0].id);
  const [showAll, setShowAll] = React.useState(false);
  const selected = SAMPLE_INPUTS.find((i) => i.id === selectedId) ?? SAMPLE_INPUTS[0];
  const recents = showAll ? SAMPLE_INPUTS : SAMPLE_INPUTS.slice(0, RECENT_VISIBLE);
  const hiddenCount = SAMPLE_INPUTS.length - RECENT_VISIBLE;

  return (
    <div className="px-5 py-4 border-b" style={{ borderColor: EDGE }}>
      {/* Selected */}
      <div className="flex items-baseline justify-between mb-1.5">
        <span className="text-[11px]" style={{ color: INK }}>Input</span>
      </div>
      <div className="flex items-baseline gap-2 mb-0.5">
        <SourceGlyph kind={selected.kind} />
        <span className="text-[12px]" style={{ color: INK }}>{selected.title}</span>
        <span className="text-[11px] ml-auto" style={{ color: INK_SUBTLE }}>{selected.meta}</span>
      </div>

      <PreviewTile kind={selected.kind} />

      {/* Recent — compact list, top N + more toggle */}
      <div className="mt-3 flex flex-col gap-[2px]">
        {recents.map((item) => (
          <button
            key={item.id}
            onClick={() => setSelectedId(item.id)}
            className="text-left rounded-sm px-2 py-1"
            style={{
              background: item.id === selectedId ? ACCENT_RING : "transparent",
            }}
          >
            <div className="flex items-baseline gap-2">
              <span
                aria-hidden
                className="inline-block w-[5px] h-[5px] rounded-full"
                style={{
                  background: item.id === selectedId ? ACCENT : "transparent",
                  border: item.id === selectedId ? "none" : `1px solid ${INK_SUBTLE}`,
                }}
              />
              <SourceGlyph kind={item.kind} muted={item.id !== selectedId} />
              <span
                className="text-[11px] flex-1 truncate"
                style={{ color: item.id === selectedId ? INK : INK_FAINT }}
              >
                {item.title}
              </span>
              <span className="text-[10px]" style={{ color: INK_SUBTLE }}>
                {item.meta}
              </span>
            </div>
          </button>
        ))}
        {hiddenCount > 0 && (
          <button
            onClick={() => setShowAll((v) => !v)}
            className="text-left px-2 py-1 text-[10px]"
            style={{ color: INK_SUBTLE }}
          >
            {showAll ? "less" : `+${hiddenCount} more`}
          </button>
        )}
      </div>

      {/* Action chips — small, quiet row */}
      <div className="mt-2 flex items-center gap-1.5">
        <InputSourceChip label="library" />
        <InputSourceChip label="record" />
        <InputSourceChip label="text" />
      </div>
    </div>
  );
}

function PreviewTile({ kind }: { kind: SourceKind }) {
  const label =
    kind === "capture"   ? "image preview" :
    kind === "memo"      ? "audio waveform" :
    kind === "note"      ? "text preview" :
    kind === "text"      ? "text preview" :
                           "live recording";
  return (
    <div
      className="mt-3 h-[96px] rounded-md flex items-center justify-center"
      style={{ background: ACCENT_RING, color: INK_SUBTLE, border: `1px solid ${EDGE}` }}
    >
      <span className="text-[11px]">{label}</span>
    </div>
  );
}

function SourceGlyph({ kind, muted = false }: { kind: SourceKind; muted?: boolean }) {
  // Single-char glyph in mono; reads as a type marker without a heavy icon
  const glyph =
    kind === "capture"   ? "▣" :
    kind === "memo"      ? "≋" :
    kind === "note"      ? "¶" :
    kind === "text"      ? "T" :
                           "●";
  return (
    <span
      className="text-[11px]"
      style={{ color: muted ? INK_SUBTLE : ACCENT, width: 12, display: "inline-block" }}
    >
      {glyph}
    </span>
  );
}

function InputSourceChip({ label }: { label: string }) {
  return (
    <button
      className="text-[10px] px-2 py-[3px] rounded-sm"
      style={{
        color: INK_FAINT,
        border: `1px solid ${EDGE}`,
      }}
    >
      + {label}
    </button>
  );
}

function RunsBlock() {
  return (
    <div className="px-5 py-4 border-b" style={{ borderColor: EDGE }}>
      <div className="flex items-baseline justify-between mb-2">
        <span className="text-[11px]" style={{ color: INK }}>Runs</span>
        <span className="text-[11px]" style={{ color: INK_SUBTLE }}>live</span>
      </div>
      <div className="flex flex-col gap-[6px]">
        {RUNS.map((r) => (
          <div
            key={r.n}
            className="grid items-baseline gap-2"
            style={{ gridTemplateColumns: "16px 56px 1fr auto" }}
          >
            <span className="text-[10px] tabular-nums" style={{ color: INK_SUBTLE }}>{r.n}</span>
            <span className="text-[10px] tabular-nums font-mono" style={{ color: INK_FAINT }}>{r.time}</span>
            <span className="text-[11px] truncate" style={{ color: INK }}>{r.label}</span>
            <StatusWord status={r.status} />
          </div>
        ))}
      </div>
    </div>
  );
}

function TraceBlock() {
  return (
    <div className="px-5 py-4 flex-1">
      <div className="flex items-baseline justify-between mb-2">
        <span className="text-[11px]" style={{ color: INK }}>Trace · run 5</span>
        <button className="text-[11px]" style={{ color: INK_SUBTLE }}>expand</button>
      </div>
      <div className="text-[11px] mb-1.5" style={{ color: INK_FAINT }}>
        01 bind · capture inputs · 3 binds · 18 ms
      </div>
      <div className="flex flex-col gap-[3px] text-[11px] font-mono" style={{ color: INK_SUBTLE }}>
        <span>capture.image      PNG · 1280×525</span>
        <span>capture.transcript TXT · 247 w</span>
        <span>capture.audio      m4a · 1m 14s</span>
      </div>
    </div>
  );
}

// ─── Data Inspector ──────────────────────────────────────────────────
//
// Read-only JSON of the workflow definition. Each key is rendered in
// neutral ink, primitives picked up from the scheme (strings in
// brass/amber, numbers in ink, null/bool in faint). No collapsing in
// v0 — the dev wants to read the document; a tree control is more
// chrome than help. Gutter line numbers help when an agent later
// needs to point at "line 24".

function DataInspectorBlock() {
  const json = JSON.stringify(SAMPLE_WORKFLOW_DOC, null, 2);
  const lines = json.split("\n");
  return (
    <div className="flex-1 overflow-auto">
      <div className="px-3 py-3 font-mono text-[11px] leading-[1.55]">
        {lines.map((line, i) => (
          <div key={i} className="flex items-baseline gap-3">
            <span
              className="text-right tabular-nums select-none"
              style={{ color: INK_SUBTLE, width: 28, flexShrink: 0 }}
            >
              {i + 1}
            </span>
            <JsonLine text={line} />
          </div>
        ))}
      </div>
    </div>
  );
}

function JsonLine({ text }: { text: string }) {
  // Cheap, regex-only colorizer. Good enough for the studio mock;
  // a real syntax pass lives in the implementation if we keep this.
  const parts: { text: string; color: string }[] = [];
  // Match: keys ("foo":), strings, numbers, booleans, null, punctuation
  const tokenRe = /("(?:[^"\\]|\\.)*"\s*:)|("(?:[^"\\]|\\.)*")|(\b-?\d+(?:\.\d+)?\b)|(\btrue\b|\bfalse\b|\bnull\b)|([{}\[\],])|(\s+)/g;
  let m: RegExpExecArray | null;
  let lastIndex = 0;
  while ((m = tokenRe.exec(text)) !== null) {
    if (m.index > lastIndex) {
      parts.push({ text: text.slice(lastIndex, m.index), color: INK });
    }
    if (m[1]) parts.push({ text: m[1], color: INK });           // key
    else if (m[2]) parts.push({ text: m[2], color: ACCENT });    // string
    else if (m[3]) parts.push({ text: m[3], color: INK });       // number
    else if (m[4]) parts.push({ text: m[4], color: INK_FAINT }); // bool/null
    else if (m[5]) parts.push({ text: m[5], color: INK_SUBTLE });// punctuation
    else if (m[6]) parts.push({ text: m[6], color: INK });       // whitespace
    lastIndex = tokenRe.lastIndex;
  }
  if (lastIndex < text.length) {
    parts.push({ text: text.slice(lastIndex), color: INK });
  }
  return (
    <pre className="m-0 whitespace-pre" style={{ font: "inherit" }}>
      {parts.map((p, i) => (
        <span key={i} style={{ color: p.color }}>{p.text}</span>
      ))}
    </pre>
  );
}

// Sample document — mirrors the donor workflow's data shape. Real
// app reads from WorkflowDefinition; this is the studio stand-in.
const SAMPLE_WORKFLOW_DOC = {
  id: "WF-02",
  name: "Hey Talkie",
  description:
    "Voice command → resolve intent → execute. Multi-step chain across whisper, Claude, and the tool router.",
  icon: "wand.and.stars",
  maintainer: "talkie",
  isSystem: true,
  isEnabled: true,
  autoRun: false,
  isPinned: false,
  steps: [
    {
      type: "audio",
      outputKey: "audio",
      config: { source: "mic.system", sampleRate: 16000, gainDb: 2, maxSec: 30 },
    },
    {
      type: "transcribe",
      outputKey: "transcript",
      config: { qualityTier: "balanced", primaryModel: "openai_whisper-small", lang: "en" },
    },
    {
      type: "llm",
      outputKey: "intent",
      config: {
        provider: "anthropic",
        modelId: "claude-haiku-4-5",
        temperature: 0.0,
        maxTokens: 512,
        prompt: 'User said "{{transcript}}". Decide: answer | call_tool | escalate.',
      },
    },
    {
      type: "tool",
      outputKey: "toolResult",
      condition: { expression: "{{intent.action}} == 'call_tool'" },
      config: { router: "scout://local", timeoutSec: 8, retry: 1, sandbox: true },
    },
    {
      type: "llm",
      outputKey: "reply",
      config: {
        provider: "anthropic",
        modelId: "claude-haiku-4-5",
        temperature: 0.6,
        maxTokens: 320,
        prompt: "Reply to {{transcript}} using {{intent}} and {{toolResult}}.",
      },
    },
  ],
};

// ─── Atoms ───────────────────────────────────────────────────────────

function Token({ text }: { text: string }) {
  return (
    <span className="font-mono text-[11px]" style={{ color: ACCENT }}>
      {`{${text}}`}
    </span>
  );
}

function TypeTag({ text }: { text: string }) {
  return (
    <span className="font-mono text-[10px] uppercase" style={{ color: INK_SUBTLE }}>
      {text}
    </span>
  );
}

function Btn({
  children,
  className = "",
  onClick,
}: { children: React.ReactNode; className?: string; onClick?: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`px-2.5 py-[5px] text-[11px] rounded-md ${className}`}
      style={{ color: INK_FAINT, border: `1px solid ${EDGE}` }}
    >
      {children}
    </button>
  );
}

function RunButton({
  small,
  className = "",
}: { small?: boolean; className?: string }) {
  return (
    <button
      className={`flex items-center gap-1.5 rounded-md ${small ? "px-2.5 py-[5px]" : "px-3 py-[6px]"} ${className}`}
      style={{
        background: ACCENT,
        color: BG,
      }}
    >
      <span aria-hidden style={{ fontSize: 9 }}>▶</span>
      <span className="text-[11px]">Run</span>
    </button>
  );
}

function StatusWord({ status }: { status: RunStatus }) {
  if (status === "running") {
    return <span className="text-[11px]" style={{ color: ACCENT }}>running</span>;
  }
  if (status === "queued") {
    return <span className="text-[11px]" style={{ color: INK_SUBTLE }}>queued</span>;
  }
  return <span className="text-[11px]" style={{ color: INK_FAINT }}>ok</span>;
}
