"use client";

/**
 * iOS · Codex Deck — lane picker & host signals.
 *
 * ROUND 1 IS SETTLED. T2 · Bottom Sill Rail is the voice-control
 * foundation: a wide inset rail pinned to the lowest reachable band,
 * outside the navigation grid. Its geometry is a constant in this file
 * (RAIL) and every treatment below renders the identical rail, so the
 * only thing under comparison is what sits above it.
 *
 * ROUND 2 QUESTION. Six stable numbered lanes, each bound to one exact
 * Codex Desktop task. How do you scan them, select one, and know —
 * without reading a paragraph — which exact task the next sentence is
 * about to enter, and whether that claim is still true?
 *
 * TRUTH BOUNDARY. The deck is only worth trusting if it never draws a
 * signal the Mac does not send. Every rendered signal in this study
 * carries a source tag: HOST (authoritative, in the current contract),
 * PHONE (derived locally from host interactions), or PROPOSED (would
 * require a host API extension — off by default, and drawn dotted).
 * See SIGNALS below; it is the spine of the whole study.
 *
 * Grounded in:
 *   apps/ios/Talkie iOS/Codex/CodexLane.swift        (phases, delivery, failure)
 *   apps/ios/Talkie iOS/Codex/CodexLaneStore.swift   (60s lock freshness)
 *   apps/ios/Talkie iOS/Codex/CodexLaneBar.swift     (today's strip)
 *   apps/macos/TalkieServer/src/bridge/routes/codex.ts (codes + recovery hints)
 *
 * NOT IN SCOPE. No Swift is written here. See NOTES.md for the handoff.
 */

import { useCallback, useMemo, useState } from "react";

// ═══════════════════════════════════════════════════════════════════
// Fixed geometry — settled in round 1, invariant across treatments.
// ═══════════════════════════════════════════════════════════════════

const PHONE = { w: 375, h: 812 }; // iPhone 13 mini, points
const STATUS_H = 47;
const TITLE_H = 44;

/** T2 · Bottom Sill Rail. These four numbers do not vary. */
const RAIL = { h: 76, inset: 18, padX: 12 };
const RAIL_TOP = PHONE.h - RAIL.inset - RAIL.h; // 718
const RAIL_W = PHONE.w - RAIL.padX * 2; // 351

/** Navigation grid: bottom-anchored above the rail. Not under study. */
const GRID_ROWS = 3;
const GRID_GAP = 9;
const GRID_ROW_H = 91;
const GRID_H = GRID_ROWS * GRID_ROW_H + (GRID_ROWS - 1) * GRID_GAP;
const GRID_BOTTOM = RAIL_TOP - 12;
const GRID_TOP = GRID_BOTTOM - GRID_H;

/** Picker region: everything between the title bar and the grid. */
const PICKER_TOP = STATUS_H + TITLE_H;
const PICKER_H = GRID_TOP - PICKER_TOP;

/** Modelled right-thumb reach to the rail centre. One number, stated once. */
const RAIL_REACH = Math.round(Math.hypot(PHONE.w / 2 - 330, RAIL_TOP + RAIL.h / 2 - PHONE.h));

/** CodexLaneStore.lockFreshness. A confirmation older than this is stale. */
const LOCK_FRESHNESS_S = 60;

// ═══════════════════════════════════════════════════════════════════
// Signal sources — the truth boundary, enumerated.
// ═══════════════════════════════════════════════════════════════════

type Source = "host" | "phone" | "proposed";
type Appearance = "dark" | "light";

const SOURCE_META: Record<Source, { label: string; ink: string; rim: string; note: string }> = {
  host: {
    label: "HOST",
    ink: "#2F7D4F",
    rim: "rgba(47,125,79,0.55)",
    note: "Authoritative. The Mac sent this, in the contract that ships today.",
  },
  phone: {
    label: "PHONE",
    ink: "#3C6E9E",
    rim: "rgba(60,110,158,0.55)",
    note: "Derived on device from host interactions. True about Talkie, not about Codex.",
  },
  proposed: {
    label: "PROPOSED",
    ink: "#B07A1F",
    rim: "rgba(176,122,31,0.6)",
    note: "Would require a host API extension. Never render this as live today.",
  },
};

interface SignalRow {
  source: Source;
  name: string;
  detail: string;
  from: string;
}

const SIGNALS: SignalRow[] = [
  { source: "host", name: "Task catalog", detail: "exact id · title · preview · cwd · updatedAt", from: "GET /codex/tasks" },
  { source: "host", name: "Validation receipt", detail: "exact id · title · cwd, or a typed error", from: "POST /codex/validate" },
  { source: "host", name: "Delivery receipt", detail: "taskId · turnId? · response? · started-turn | queued-turn | steered-active-turn", from: "POST /codex/submit" },
  { source: "host", name: "Typed failure + recovery hint", detail: "code plus the Mac's own sentence about how to fix it", from: "RECOVERY_HINTS in routes/codex.ts" },
  { source: "phone", name: "Bridge connectivity", detail: "connected / disconnected", from: "BridgeManager" },
  { source: "phone", name: "Lane bindings & selection", detail: "six persisted slots; which one is selected", from: "CodexLaneStore.lanes" },
  { source: "phone", name: "Exact-task lock + freshness", detail: `confirmed this session, trusted for ${LOCK_FRESHNESS_S}s, then re-validated on send`, from: "confirmedAt / lockFreshness" },
  { source: "phone", name: "Voice-loop phase", detail: "idle · validating · listening · transcribing · submitting · preparing speech · speaking · failed", from: "CodexLanePhase" },
  { source: "phone", name: "Your own in-flight count", detail: "how many Talkie-originated messages are pending — not the host's queue", from: "queuedMessageCount" },
  { source: "proposed", name: "Per-lane activity light", detail: "idle / active / awaiting-approval for all six lanes at once", from: "needs a status endpoint" },
  { source: "proposed", name: "Queue depth & position", detail: "how many turns are ahead of yours, host-wide", from: "not exposed" },
  { source: "proposed", name: "Progress · ETA · tool · tokens", detail: "granular execution stage inside a running turn", from: "not exposed" },
];

// ═══════════════════════════════════════════════════════════════════
// Model — one scenario produces one deck state, shared by all five.
// ═══════════════════════════════════════════════════════════════════

type Phase =
  | "idle"
  | "validating"
  | "listening"
  | "transcribing"
  | "submitting"
  | "speaking"
  | "failed";

const PHASE_LABEL: Record<Phase, string> = {
  idle: "READY",
  validating: "VALIDATING",
  listening: "LISTENING",
  transcribing: "TRANSCRIBING",
  submitting: "WAITING FOR CODEX",
  speaking: "SPEAKING",
  failed: "FAILED",
};

type Delivery = "started-turn" | "queued-turn" | "steered-active-turn";

const DELIVERY_LABEL: Record<Delivery, string> = {
  "started-turn": "STARTED A NEW TURN",
  "queued-turn": "RAN THE QUEUED TURN",
  "steered-active-turn": "STEERED THE ACTIVE TURN",
};

interface LaneTask {
  n: number;
  id: string;
  title: string;
  project: string;
  rel: string;
}

/**
 * Fixture catalog. Lane 3 carries a deliberately long title; lanes 4 and 5
 * share a title across two projects — the case that decides whether a
 * treatment can be trusted at a glance.
 */
const CATALOG: LaneTask[] = [
  { n: 1, id: "01J8QF…A21", title: "Bridge reconnect backoff", project: "talkie", rel: "12m" },
  { n: 2, id: "01J8QG…7C4", title: "Command deck lane mapper", project: "talkie", rel: "3m" },
  {
    n: 3,
    id: "01J8QH…9F0",
    title: "Codex Desktop adapter — follower IPC ownership checks and rollout tailing",
    project: "talkie-codex-command-deck",
    rel: "now",
  },
  { n: 4, id: "01J8QJ…2B8", title: "Release notes", project: "scout", rel: "2h" },
  { n: 5, id: "01J8QK…5D1", title: "Release notes", project: "openscout", rel: "1h" },
  { n: 6, id: "01J8QM…8E3", title: "Marketing site copy", project: "arach.dev", rel: "3d" },
];

interface Failure {
  code: string;
  message: string;
  /** Verbatim from RECOVERY_HINTS in apps/macos/TalkieServer/src/bridge/routes/codex.ts. */
  hint: string;
}

interface Receipt {
  delivery: Delivery;
  turnId: string;
  chars: number;
}

interface DeckModel {
  bridge: boolean;
  lanes: LaneTask[];
  selected: number | null;
  /** Lane the Mac confirmed it owns. Only this may ever be drawn as locked. */
  confirmed: number | null;
  /** Seconds since that confirmation. Past LOCK_FRESHNESS_S it is stale. */
  confirmAge: number;
  phase: Phase;
  failure: Failure | null;
  receipt: Receipt | null;
  /** Talkie-originated messages still in flight. Phone-local, not host queue depth. */
  pending: number;
}

type ScenarioKey =
  | "unmapped"
  | "mapped"
  | "validating"
  | "stale"
  | "confirmed"
  | "listening"
  | "transcribing"
  | "waiting"
  | "queued"
  | "steered"
  | "approval"
  | "offline"
  | "collision";

interface Scenario {
  key: ScenarioKey;
  label: string;
  note: string;
  build: (lanes: LaneTask[]) => DeckModel;
}

const BASE: Omit<DeckModel, "lanes"> = {
  bridge: true,
  selected: null,
  confirmed: null,
  confirmAge: 0,
  phase: "idle",
  failure: null,
  receipt: null,
  pending: 0,
};

const SCENARIOS: Scenario[] = [
  {
    key: "unmapped",
    label: "No lanes",
    note: "Nothing bound yet. The deck has to say what to do, not just sit empty.",
    build: () => ({ ...BASE, lanes: [] }),
  },
  {
    key: "mapped",
    label: "Mapped, none selected",
    note: "Bindings persist across launches. None of them is confirmed until one is probed.",
    build: (lanes) => ({ ...BASE, lanes }),
  },
  {
    key: "validating",
    label: "Validating",
    note: "Selection fired POST /codex/validate. The lock does not exist yet.",
    build: (lanes) => ({ ...BASE, lanes, selected: 2, phase: "validating" }),
  },
  {
    key: "stale",
    label: "Selected, stale",
    note: `Confirmed ${LOCK_FRESHNESS_S + 34}s ago — past the freshness window. Not an error: the next send re-validates first.`,
    build: (lanes) => ({ ...BASE, lanes, selected: 2, confirmed: null, confirmAge: LOCK_FRESHNESS_S + 34 }),
  },
  {
    key: "confirmed",
    label: "Exact-task confirmed",
    note: "The Mac confirmed this exact task ID. The only state in which the word LOCKED is honest.",
    build: (lanes) => ({ ...BASE, lanes, selected: 2, confirmed: 2, confirmAge: 6 }),
  },
  {
    key: "listening",
    label: "Listening",
    note: "Mic open. The one live phase that earns motion.",
    build: (lanes) => ({ ...BASE, lanes, selected: 2, confirmed: 2, confirmAge: 11, phase: "listening" }),
  },
  {
    key: "transcribing",
    label: "Transcribing",
    note: "On-device. Nothing has reached the Mac yet.",
    build: (lanes) => ({ ...BASE, lanes, selected: 2, confirmed: 2, confirmAge: 14, phase: "transcribing" }),
  },
  {
    key: "waiting",
    label: "Waiting for Codex",
    note: "Submitted. No progress signal exists — the honest report is simply that we are waiting.",
    build: (lanes) => ({ ...BASE, lanes, selected: 2, confirmed: 2, confirmAge: 22, phase: "submitting", pending: 1 }),
  },
  {
    key: "queued",
    label: "Queue accepted",
    note: "Delivery receipt says queued-turn. Queue is the safe default and needs no decision.",
    build: (lanes) => ({
      ...BASE, lanes, selected: 2, confirmed: 2, confirmAge: 4,
      receipt: { delivery: "queued-turn", turnId: "trn_9F2", chars: 1840 },
    }),
  },
  {
    key: "steered",
    label: "Steer accepted",
    note: "Delivery receipt says steered-active-turn. Different outcome, reported verbatim.",
    build: (lanes) => ({
      ...BASE, lanes, selected: 2, confirmed: 2, confirmAge: 4,
      receipt: { delivery: "steered-active-turn", turnId: "trn_9F3", chars: 0 },
    }),
  },
  {
    key: "approval",
    label: "Approval required",
    note: "Talkie never approves a Codex action. It reports the block and repeats the Mac's own fix.",
    build: (lanes) => ({
      ...BASE, lanes, selected: 2, phase: "failed",
      failure: {
        code: "approval-required",
        message: "Codex Desktop is waiting on an approval.",
        hint: "Open this task in Codex Desktop to review the approval request.",
      },
    }),
  },
  {
    key: "offline",
    label: "Host unavailable",
    note: "Bindings survive; confidence does not. Nothing may be drawn as confirmed.",
    build: (lanes) => ({
      ...BASE, lanes, bridge: false, selected: 2, phase: "failed",
      failure: {
        code: "desktop-unavailable",
        message: "Codex Desktop is not reachable.",
        hint: "Codex Desktop is not running. Launch it, then retry.",
      },
    }),
  },
  {
    key: "collision",
    label: "Long title · same title",
    note: "Lane 3 has a 74-character title; lanes 4 and 5 are both “Release notes” in different projects. The deciding case.",
    build: (lanes) => ({ ...BASE, lanes, selected: 5, confirmed: 5, confirmAge: 8 }),
  },
];

const SCENARIO_BY_KEY = Object.fromEntries(SCENARIOS.map((s) => [s.key, s])) as Record<ScenarioKey, Scenario>;

function buildModel(key: ScenarioKey, mappedCount: number): DeckModel {
  const s = SCENARIO_BY_KEY[key];
  const lanes = CATALOG.slice(0, mappedCount);
  const m = s.build(lanes);
  // A scenario that names a lane is meaningless if that lane is not mapped.
  if (m.selected !== null && !lanes.some((l) => l.n === m.selected)) {
    const fallback = lanes.length ? lanes[lanes.length - 1].n : null;
    return { ...m, selected: fallback, confirmed: m.confirmed === null ? null : fallback };
  }
  return m;
}

function laneOf(m: DeckModel, n: number | null): LaneTask | null {
  if (n === null) return null;
  return m.lanes.find((l) => l.n === n) ?? null;
}

/** Lane display state. Ordering matters: this is the honesty ladder. */
type LaneState = "empty" | "mapped" | "selected" | "stale" | "confirmed" | "failed";

function laneStateOf(m: DeckModel, n: number): LaneState {
  if (!m.lanes.some((l) => l.n === n)) return "empty";
  if (m.selected !== n) return "mapped";
  if (m.failure) return "failed";
  if (m.confirmed === n && m.confirmAge < LOCK_FRESHNESS_S) return "confirmed";
  if (m.confirmAge > 0) return "stale";
  return "selected";
}

const LANE_STATE_META: Record<LaneState, { word: string; source: Source | null }> = {
  empty: { word: "unmapped", source: null },
  mapped: { word: "mapped", source: "phone" },
  selected: { word: "selected, not confirmed", source: "phone" },
  stale: { word: "selected, confirmation expired", source: "phone" },
  confirmed: { word: "exact task confirmed", source: "host" },
  failed: { word: "blocked", source: "host" },
};

// ═══════════════════════════════════════════════════════════════════
// Parameters
// ═══════════════════════════════════════════════════════════════════

type ParamValue = string | number | boolean;
type Params = Record<string, ParamValue>;

type ParamDef =
  | { kind: "select"; key: string; label: string; help?: string; options: { value: string; label: string }[] }
  | { kind: "range"; key: string; label: string; help?: string; min: number; max: number; step: number; unit?: string }
  | { kind: "toggle"; key: string; label: string; help?: string };

const str = (p: Params, k: string) => String(p[k]);
const num = (p: Params, k: string) => Number(p[k]);
const bool = (p: Params, k: string) => Boolean(p[k]);

type TreatmentKey = "strip" | "expand" | "twotier" | "glyph" | "sheet";

interface Treatment {
  key: TreatmentKey;
  n: string;
  name: string;
  idea: string;
  failure: string;
  params: ParamDef[];
  defaults: Params;
}

const TREATMENTS: Treatment[] = [
  {
    key: "strip",
    n: "L1",
    name: "Numbered Strip · Central Status",
    idea:
      "Six fixed positions that never move, and exactly one line beneath them that says everything about the selected lane. The strip is a keyboard; the line is the readout.",
    failure:
      "One line cannot carry project, title, phase and a recovery hint. Under stress it truncates, and the part it drops is the part you needed.",
    params: [
      {
        kind: "select", key: "emphasis", label: "Selected emphasis",
        help: "How the selected slot separates itself from the other five.",
        options: [
          { value: "fill", label: "fill" },
          { value: "outline", label: "outline" },
          { value: "underline", label: "underline" },
        ],
      },
      {
        kind: "select", key: "identity", label: "Identity line",
        help: "What the status line leads with when space runs out.",
        options: [
          { value: "projectFirst", label: "project first" },
          { value: "titleFirst", label: "title first" },
          { value: "twoLine", label: "two lines" },
        ],
      },
      {
        kind: "select", key: "freshness", label: "Confirmation freshness",
        help: `A lock is only trusted for ${LOCK_FRESHNESS_S}s. Show it, or stay silent and re-validate on send?`,
        options: [
          { value: "age", label: "age chip" },
          { value: "word", label: "word only" },
          { value: "none", label: "hidden" },
        ],
      },
      {
        kind: "select", key: "failureDisclosure", label: "Failure disclosure",
        help: "Where a typed failure and its Mac-supplied hint go.",
        options: [
          { value: "inline", label: "replaces line" },
          { value: "banner", label: "banner above" },
        ],
      },
      { kind: "toggle", key: "showRecency", label: "Task recency", help: "updatedAt from the catalog, as a relative label." },
    ],
    defaults: { emphasis: "fill", identity: "projectFirst", freshness: "age", failureDisclosure: "banner", showRecency: false },
  },
  {
    key: "expand",
    n: "L2",
    name: "Selected-Lane Expansion",
    idea:
      "Spend pixels only on the lane you are about to talk to. The selected slot grows into a card carrying its own identity; the other five collapse to numbers.",
    failure:
      "If growth reflows its neighbours, the six positions move and the muscle memory that makes a numbered strip worth having is gone.",
    params: [
      { kind: "range", key: "cardH", label: "Expanded height", min: 44, max: 96, step: 4, unit: "pt" },
      { kind: "range", key: "slotW", label: "Collapsed slot", min: 26, max: 44, step: 2, unit: "pt" },
      {
        kind: "select", key: "lines", label: "Identity lines",
        help: "Inside the expanded card.",
        options: [
          { value: "1", label: "1 · title" },
          { value: "2", label: "2 · project + title" },
          { value: "3", label: "3 · + task id" },
        ],
      },
      {
        kind: "toggle", key: "reserve", label: "Reserve row height",
        help: "Keep the row at its expanded height even when nothing is selected, so slots never move vertically.",
      },
      { kind: "toggle", key: "showRecency", label: "Task recency" },
    ],
    defaults: { cardH: 68, slotW: 32, lines: "2", reserve: true, showRecency: true },
  },
  {
    key: "twotier",
    n: "L3",
    name: "Two-Tier Identity",
    idea:
      "Split the two questions. Tier one answers “which lane” in six unchanging positions. Tier two is a fixed-height plate that answers “which exact task, and is that still true” with room to do it properly.",
    failure:
      "The plate is dead weight in the common case where you already know the lane — it costs vertical space every second to pay off in the few seconds that matter.",
    params: [
      { kind: "range", key: "plateH", label: "Readout height", min: 84, max: 142, step: 2, unit: "pt" },
      {
        kind: "select", key: "titleLines", label: "Title lines",
        options: [
          { value: "1", label: "1 · truncate" },
          { value: "2", label: "2 · wrap" },
        ],
      },
      { kind: "toggle", key: "showId", label: "Task ID tail", help: "The exact identity, abbreviated. Host-authoritative." },
      {
        kind: "select", key: "confirmStyle", label: "Confirmation badge",
        options: [
          { value: "wordAge", label: "word + age" },
          { value: "word", label: "word only" },
          { value: "rule", label: "edge rule" },
        ],
      },
      { kind: "toggle", key: "showRecency", label: "Task recency" },
      { kind: "toggle", key: "showPending", label: "Your in-flight count", help: "Phone-local. Never labelled as the host's queue." },
    ],
    defaults: { plateH: 136, titleLines: "2", showId: true, confirmStyle: "rule", showRecency: true, showPending: true },
  },
  {
    key: "glyph",
    n: "L4",
    name: "Per-Lane Status Glyphs",
    idea:
      "State lives where the target lives. Each slot carries its own mark, so there is nothing to read below the strip at all.",
    failure:
      "It implies six live lights. The host sends status for one task at a time, on demand — so five of the six marks can only ever mean “bound”, and a treatment that forgets this is lying in a very legible way.",
    params: [
      {
        kind: "select", key: "vocabulary", label: "Glyph vocabulary",
        options: [
          { value: "outline", label: "outline weight" },
          { value: "shape", label: "shape" },
          { value: "text", label: "text tag" },
        ],
      },
      { kind: "toggle", key: "initials", label: "Project initials in slot", help: "Two characters of the cwd's last component." },
      {
        kind: "select", key: "unmapped", label: "Unmapped slots",
        options: [
          { value: "ghost", label: "ghost outline" },
          { value: "plus", label: "plus target" },
          { value: "hidden", label: "hidden" },
        ],
      },
      {
        kind: "toggle", key: "proposedLights", label: "Proposed: per-lane activity",
        help: "Requires a host status endpoint that does not exist. Drawn dotted and tagged when the global switch allows it.",
      },
    ],
    defaults: { vocabulary: "outline", initials: true, unmapped: "ghost", proposedLights: false },
  },
  {
    key: "sheet",
    n: "L5",
    name: "Current-Lane Plate · Switch Sheet",
    idea:
      "Optimise for the ninety percent case. The lid shows only the lane you are in, at full width and full identity. Switching is a deliberate, readable act in a sheet that has room for recency and the mapper.",
    failure:
      "Alternating between two lanes costs a tap, a sheet, a read and a tap — the cheapest interaction in every other treatment becomes the most expensive one here.",
    params: [
      {
        kind: "select", key: "trigger", label: "Sheet trigger",
        options: [
          { value: "tap", label: "tap the plate" },
          { value: "chevron", label: "chevron only" },
        ],
      },
      { kind: "toggle", key: "quickPrev", label: "Quick-swap arrows", help: "Adjacent-lane stepping without opening the sheet." },
      { kind: "toggle", key: "sheetOpen", label: "Show sheet open", help: "Renders the switch sheet over the deck." },
      { kind: "toggle", key: "showUnmapped", label: "Unmapped rows in sheet", help: "Progressive disclosure into the mapper." },
      { kind: "toggle", key: "showRecency", label: "Task recency" },
    ],
    defaults: { trigger: "tap", quickPrev: true, sheetOpen: false, showUnmapped: true, showRecency: true },
  },
];

// ═══════════════════════════════════════════════════════════════════
// Root
// ═══════════════════════════════════════════════════════════════════

export function CodexDeckLaneSignalsStudy() {
  const [scenario, setScenario] = useState<ScenarioKey>("confirmed");
  const [mapped, setMapped] = useState(6);
  const [proposed, setProposed] = useState(false);
  const [scale, setScale] = useState(0.72);
  const [appearance, setAppearance] = useState<Appearance>("dark");
  const [params, setParams] = useState<Record<TreatmentKey, Params>>(() =>
    Object.fromEntries(TREATMENTS.map((t) => [t.key, { ...t.defaults }])) as Record<TreatmentKey, Params>,
  );
  const [overrides, setOverrides] = useState<Partial<Record<TreatmentKey, ScenarioKey>>>({});

  const setParam = useCallback((k: TreatmentKey, key: string, v: ParamValue) => {
    setParams((prev) => ({ ...prev, [k]: { ...prev[k], [key]: v } }));
  }, []);

  const resetParams = useCallback((k: TreatmentKey) => {
    const t = TREATMENTS.find((x) => x.key === k)!;
    setParams((prev) => ({ ...prev, [k]: { ...t.defaults } }));
    setOverrides((prev) => ({ ...prev, [k]: undefined }));
  }, []);

  const applyScenario = useCallback((s: ScenarioKey) => {
    setScenario(s);
    setOverrides({});
  }, []);

  return (
    <div className="flex flex-col gap-11">
      <MotionStyles />
      <Thesis />
      <DecisionRecord />

      <DeckLineage />

      <Section label="Signal sources" hint="what the Mac actually sends, what the phone infers, and what nobody has yet">
        <SignalLegend />
      </Section>

      <GlobalBar
        scenario={scenario}
        onScenario={applyScenario}
        mapped={mapped}
        onMapped={setMapped}
        proposed={proposed}
        onProposed={setProposed}
        scale={scale}
        onScale={setScale}
        appearance={appearance}
        onAppearance={setAppearance}
      />

      <Section
        label="Five lane-picker treatments"
        hint="identical bottom rail in every one — the only variable is what sits above it"
      >
        <div className="flex flex-wrap gap-7">
          {TREATMENTS.map((t) => (
            <TreatmentCard
              key={t.key}
              treatment={t}
              scenario={overrides[t.key] ?? scenario}
              onScenario={(s) => setOverrides((prev) => ({ ...prev, [t.key]: s }))}
              mapped={mapped}
              proposed={proposed}
              params={params[t.key]}
              onParam={(key, v) => setParam(t.key, key, v)}
              onReset={() => resetParams(t.key)}
              scale={scale}
              appearance={appearance}
            />
          ))}
        </div>
      </Section>

      <Section label="Comparison" hint="scored against the qualities the brief ranked, in that order">
        <ComparisonMatrix />
      </Section>

      <Recommendation />
      <ContractSplit />
      <Vocabulary />
    </div>
  );
}

/**
 * The study's only authored motion: a slow pulse, used exclusively on the
 * rail's live indicator while the mic is open or a submitted turn is
 * outstanding. Mapped and confirmed marks are deliberately static.
 */
function MotionStyles() {
  return (
    <style>{`
      @keyframes cdxLive { 0%,100% { opacity: 1 } 50% { opacity: 0.28 } }
      .cdx-live { animation: cdxLive 1.25s ease-in-out infinite; }
      @media (prefers-reduced-motion: reduce) { .cdx-live { animation: none; opacity: 0.85 } }
      .cdx-focus:focus-visible { outline: 2px solid #FF8800; outline-offset: 2px; }
    `}</style>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Chrome
// ═══════════════════════════════════════════════════════════════════

function Thesis() {
  return (
    <div className="flex flex-col gap-3">
      <p className="max-w-[76ch] font-display italic" style={{ color: "#5A5A5E", fontSize: 14, lineHeight: 1.55 }}>
        A lane is a promise: the next sentence you say goes into <em>this exact Codex task</em> and no other.
        Everything in this round serves that promise. Selection has to be quick and positionally stable,
        identity has to survive a seventy-character title and two projects with the same task name, and the
        deck has to distinguish “bound” from “confirmed” from “confirmed a minute ago” without turning into
        a status console.
      </p>
      <p className="max-w-[76ch] font-display italic" style={{ color: "#5A5A5E", fontSize: 14, lineHeight: 1.55 }}>
        The constraint that shapes every treatment is not layout, it is truth. The Mac answers questions;
        it does not broadcast. There is no live feed of six lanes, no queue depth, no progress. A picker
        that draws six activity lights would be the most legible lie the deck could tell — so each
        treatment is judged first on whether it can be built from{" "}
        <strong style={{ fontStyle: "normal", color: "#232423" }}>signals that exist</strong>.
      </p>
      <p className="max-w-[76ch] font-display italic" style={{ color: "#8A8A8E", fontSize: 12.5, lineHeight: 1.5 }}>
        The voice rail is fixed. {RAIL_W}×{RAIL.h}pt, {RAIL.inset}pt above the home indicator, ~{RAIL_REACH}pt
        from a right thumb&rsquo;s pivot — the natural band. It does not move between treatments, and its
        position does not change with state.
      </p>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// What was borrowed, and from where
//
// The round-2 picker drifted: a flat field with six chips and a card
// floating on it, which is a generic app screen wearing deck colours.
// This section is the audit that corrected it — each row names a Deck
// study, the part taken from it, and where that part now lives.
// ═══════════════════════════════════════════════════════════════════

function DeckLineage() {
  const rows: [string, string, string][] = [
    [
      "IOSDeck.tsx",
      "Chassis → console → keybed → keytop depth ladder; translucent seated caps lit from above; per-key index numerals; the silkscreen legend line; amber used as a lock, never as decoration.",
      "Lane Key material, and the SILKSCREEN across the console's top edge naming module and target.",
    ],
    [
      "DeckKeyBed.tsx",
      "One recessed bed holding every key, rather than groups of chips floating on the face. The Group Seam — a routed groove — separates functions instead of an empty gap.",
      "Lane Bed, and the seam between the six lane keys and the mapper key.",
    ],
    [
      "DeckKeypad.tsx",
      "The faceplate recess: a bounded technical field cut into the chassis, with a lit top chamfer and a dark bottom edge so it reads as depth, not as a border.",
      "Lane Console — the field the whole picker now lives inside.",
    ],
    [
      "IOSDeck.tsx · Pad",
      "The screen-black surface with tape grain, a corner sheen, and a vignette: the deck's way of drawing a display rather than a card.",
      "Task Readout — the identity tier in every treatment.",
    ],
    [
      "ios-deck/page.tsx",
      "The naming discipline itself: every physical part carries one name, used in the studio, in Swift, and in conversation.",
      "The Names table below, extended with the console vocabulary.",
    ],
  ];
  return (
    <Section label="Deck lineage" hint="continuity without imitation — what this study takes from the existing Deck family">
      <div className="rounded-[6px] border border-studio-edge bg-white px-4 py-3">
        <table className="w-full border-collapse text-left">
          <thead>
            <tr className="border-b border-studio-edge">
              <th className="w-[18ch] pb-2 pr-4 font-mono text-[8.5px] font-semibold uppercase tracking-[0.14em]" style={{ color: "#8A8A8E" }}>Source</th>
              <th className="pb-2 pr-4 font-mono text-[8.5px] font-semibold uppercase tracking-[0.14em]" style={{ color: "#8A8A8E" }}>Grammar taken</th>
              <th className="w-[30%] pb-2 font-mono text-[8.5px] font-semibold uppercase tracking-[0.14em]" style={{ color: "#8A8A8E" }}>Where it lives here</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(([src, took, lives]) => (
              <tr key={src} className="border-b border-studio-edge/60 last:border-0 align-top">
                <td className="py-2 pr-4 font-mono text-[9.5px] font-semibold tracking-[0.06em]" style={{ color: "#2F7D4F" }}>{src}</td>
                <td className="py-2 pr-4 font-display text-[12.5px] italic" style={{ color: "#5A5A5E" }}>{took}</td>
                <td className="py-2 font-display text-[12.5px] italic" style={{ color: "#232423" }}>{lives}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="max-w-[80ch] pt-3 font-display text-[12px] italic leading-snug" style={{ color: "#8A6A2E" }}>
          Nothing was copied wholesale. The Deck&rsquo;s trackpad is a pointing surface; this is a channel selector.
          What carries across is the material logic — chassis as ground, one recessed field per module, keys seated
          in a bed, printed legends, and amber reserved for a state that has actually been verified.
        </p>
      </div>
    </Section>
  );
}

function DecisionRecord() {
  const rows = [
    ["T1", "Spacebar Row", "Two-column primary in the first key row", "Rejected — good reach, but the primary still shares a row with keys the thumb hits by accident."],
    ["T2", "Bottom Sill Rail", "Wide inset rail below the grid, in the dead sill", "SELECTED. ~" + RAIL_REACH + "pt reach, no neighbours, one fixed home."],
    ["T3", "Thumb Arc", "Radial primary with satellites on the sweep", "Rejected — best pure geometry, worst everything else. Forks on handedness."],
    ["T4", "Modal Deck", "Verb set swaps by mode around a locked anchor", "Rejected as a layout; its anchor-lock discipline was kept."],
    ["T5", "Hold-Gated Single Key", "Tap queues, sustained hold steers", "Rejected — hides the one decision the product wants legible."],
  ];
  return (
    <details className="rounded-[6px] border border-studio-edge bg-white">
      <summary className="cursor-pointer px-4 py-3 font-mono text-[10px] font-semibold uppercase tracking-[0.16em] text-studio-ink">
        Round 1 · decision record
        <span className="ml-3 font-display text-[11.5px] font-normal italic tracking-normal text-studio-ink-faint">
          settled — T2 won; the five interactive ergonomics phones were removed from this route
        </span>
      </summary>
      <div className="overflow-x-auto border-t border-studio-edge px-4 py-3">
        <table className="w-full min-w-[720px] border-collapse text-left">
          <tbody>
            {rows.map(([id, name, what, verdict]) => (
              <tr key={id} className="border-b border-studio-edge/60 last:border-0">
                <td className="py-2 pr-3 align-top font-mono text-[9px] font-semibold tracking-ch text-studio-ink-faint">{id}</td>
                <td className="py-2 pr-4 align-top font-mono text-[10px] font-semibold uppercase tracking-[0.1em] text-studio-ink">{name}</td>
                <td className="py-2 pr-4 align-top font-display text-[12px] italic text-studio-ink-faint">{what}</td>
                <td
                  className="py-2 align-top font-display text-[12px] italic"
                  style={{ color: id === "T2" ? "#2F7D4F" : "#8A8A8E" }}
                >
                  {verdict}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </details>
  );
}

function SignalLegend() {
  const groups: Source[] = ["host", "phone", "proposed"];
  return (
    <div className="grid gap-4 md:grid-cols-3">
      {groups.map((g) => (
        <div key={g} className="flex flex-col gap-2 rounded-[6px] border border-studio-edge bg-white p-4">
          <div className="flex items-center gap-2">
            <SourceTag source={g} />
            <span className="font-display text-[11.5px] italic leading-snug text-studio-ink-faint">
              {SOURCE_META[g].note}
            </span>
          </div>
          <ul className="flex flex-col gap-2 pt-1">
            {SIGNALS.filter((s) => s.source === g).map((s) => (
              <li key={s.name} className="flex flex-col gap-[3px] border-t border-studio-edge/70 pt-2 first:border-0 first:pt-0">
                <span className="font-mono text-[9.5px] font-semibold uppercase tracking-[0.1em] text-studio-ink">{s.name}</span>
                <span className="font-display text-[12px] italic leading-snug text-studio-ink-faint">{s.detail}</span>
                <span className="font-mono text-[8.5px] tracking-ch" style={{ color: "#A6A6AA" }}>{s.from}</span>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

function SourceTag({ source, dim }: { source: Source; dim?: boolean }) {
  const m = SOURCE_META[source];
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-[2px] px-1.5 py-[2px] font-mono text-[8px] font-semibold tracking-[0.12em]"
      style={{
        color: m.ink,
        border: source === "proposed" ? `1px dashed ${m.rim}` : `1px solid ${m.rim}`,
        opacity: dim ? 0.6 : 1,
      }}
    >
      {m.label}
    </span>
  );
}

function GlobalBar({
  scenario, onScenario, mapped, onMapped, proposed, onProposed, scale, onScale, appearance, onAppearance,
}: {
  scenario: ScenarioKey;
  onScenario: (s: ScenarioKey) => void;
  mapped: number;
  onMapped: (n: number) => void;
  proposed: boolean;
  onProposed: (b: boolean) => void;
  scale: number;
  onScale: (n: number) => void;
  appearance: Appearance;
  onAppearance: (appearance: Appearance) => void;
}) {
  return (
    <div className="sticky top-0 z-30 -mx-2 flex flex-col gap-2.5 rounded-[6px] border border-studio-edge bg-studio-canvas/95 px-4 py-3 backdrop-blur">
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="mr-1 font-mono text-[9px] font-semibold uppercase tracking-ch text-studio-ink-faint">Scenario</span>
        {SCENARIOS.map((s) => (
          <button
            key={s.key}
            onClick={() => onScenario(s.key)}
            aria-pressed={scenario === s.key}
            className={[
              "cdx-focus rounded-[3px] border px-2 py-1 font-mono text-[9px] font-semibold uppercase tracking-[0.09em] transition-colors",
              scenario === s.key
                ? "border-studio-ink bg-studio-ink text-studio-canvas"
                : "border-studio-edge bg-white text-studio-ink-faint hover:border-studio-ink hover:text-studio-ink",
            ].join(" ")}
          >
            {s.label}
          </button>
        ))}
      </div>

      <p className="font-display italic" style={{ color: "#8A8A8E", fontSize: 12.5 }}>
        {SCENARIO_BY_KEY[scenario].note}
      </p>

      <div className="flex flex-wrap items-center gap-5 border-t border-studio-edge pt-2.5">
        <Mini label="Mapped lanes">
          <Seg
            value={String(mapped)}
            onChange={(v) => onMapped(Number(v))}
            options={[
              { value: "2", label: "2" }, { value: "4", label: "4" }, { value: "6", label: "6" },
            ]}
          />
        </Mini>
        <Mini label="Proposed telemetry">
          <Seg
            value={proposed ? "on" : "off"}
            onChange={(v) => onProposed(v === "on")}
            options={[{ value: "off", label: "off" }, { value: "on", label: "on" }]}
          />
          <span className="font-display text-[11.5px] italic" style={{ color: proposed ? "#B07A1F" : "#A6A6AA" }}>
            {proposed
              ? "signals the host cannot send today are drawn dotted and tagged"
              : "only signals in the current contract are drawn"}
          </span>
        </Mini>
        <Mini label="Viewport">
          <Seg
            value={String(scale)}
            onChange={(v) => onScale(Number(v))}
            options={[{ value: "0.62", label: "62%" }, { value: "0.72", label: "72%" }, { value: "1", label: "1:1" }]}
          />
        </Mini>
        <Mini label="Appearance">
          <Seg
            value={appearance}
            onChange={(value) => onAppearance(value as Appearance)}
            options={[{ value: "dark", label: "dark" }, { value: "light", label: "light" }]}
          />
        </Mini>
      </div>
    </div>
  );
}

function Mini({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2">
      <span className="font-mono text-[9px] font-semibold uppercase tracking-ch text-studio-ink-faint">{label}</span>
      {children}
    </div>
  );
}

function Seg({
  value, onChange, options,
}: {
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <div className="flex overflow-hidden rounded-[3px] border border-studio-edge">
      {options.map((o, i) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          aria-pressed={value === o.value}
          className={[
            "cdx-focus px-2 py-[3px] font-mono text-[9px] font-semibold uppercase tracking-[0.08em] transition-colors",
            i > 0 ? "border-l border-studio-edge" : "",
            value === o.value ? "bg-studio-ink text-studio-canvas" : "bg-white text-studio-ink-faint hover:text-studio-ink",
          ].join(" ")}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

function Section({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-4">
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-studio-ink">{label}</span>
        {hint && <span className="font-display italic" style={{ color: "#9A9A9E", fontSize: 11.5 }}>{hint}</span>}
        <div className="ml-1 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
      </div>
      {children}
    </section>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Phone shell
// ═══════════════════════════════════════════════════════════════════

function phoneAppearanceVariables(appearance: Appearance): React.CSSProperties {
  if (appearance === "light") {
    return {
      "--cdx-console-face": "linear-gradient(180deg,#E8E1D6,#D6CCBE)",
      "--cdx-console-shadow": "inset 0 1px 0 rgba(255,255,255,0.82), inset 0 -1px 0 rgba(64,48,32,0.16), inset 0 0 0 1px rgba(64,48,32,0.20), 0 5px 12px rgba(50,37,24,0.13)",
      "--cdx-bed-face": "#050505",
      "--cdx-bed-shadow": "inset 0 1.5px 3px rgba(0,0,0,0.68), inset 0 0 0 1px rgba(255,255,255,0.10)",
      "--cdx-cap-face": "linear-gradient(180deg,rgba(255,255,255,0.14),rgba(255,255,255,0.045))",
      "--cdx-cap-active": "linear-gradient(180deg,rgba(255,136,0,0.32),rgba(255,136,0,0.12))",
      "--cdx-cap-empty": "rgba(0,0,0,0.50)",
      "--cdx-cap-top": "inset 0 1px 0 rgba(255,255,255,0.16)",
      "--cdx-cap-bottom": "inset 0 -1px 0 rgba(0,0,0,0.42)",
      "--cdx-cap-lift": "0 2px 3px rgba(0,0,0,0.42)",
      "--cdx-utility-face": "linear-gradient(180deg,#FFFDF8,#E6DED2)",
      "--cdx-utility-empty": "rgba(70,52,34,0.055)",
      "--cdx-utility-shadow": "0 4px 8px rgba(62,45,28,0.12), inset 0 1px 0 rgba(255,255,255,0.90), inset 0 0 0 1px rgba(74,55,36,0.14)",
      "--cdx-socket-shadow": "inset 0 2px 5px rgba(61,44,28,0.16), inset 0 0 0 1px rgba(74,55,36,0.12)",
      "--cdx-rail-idle": "linear-gradient(180deg,#FFF8EC,#E6DAC8)",
      "--cdx-rail-busy": "linear-gradient(180deg,#F4EFE6,#DDD4C7)",
      "--cdx-rail-shadow": "0 5px 12px rgba(55,39,24,0.16), inset 0 1px 0 rgba(255,255,255,0.88)",
    } as React.CSSProperties;
  }
  return {
    "--cdx-console-face": "linear-gradient(180deg,#191816,#0F0F0E)",
    "--cdx-console-shadow": "inset 0 2px 7px rgba(0,0,0,0.56), inset 0 1px 0 rgba(255,255,255,0.10), inset 0 -1px 0 rgba(0,0,0,0.48), inset 0 0 0 1px rgba(255,255,255,0.12), 0 7px 16px rgba(0,0,0,0.30)",
    "--cdx-bed-face": "#050505",
    "--cdx-bed-shadow": "inset 0 1.5px 3px rgba(0,0,0,0.68), inset 0 0 0 1px rgba(255,255,255,0.10)",
    "--cdx-cap-face": "linear-gradient(180deg,rgba(255,255,255,0.14),rgba(255,255,255,0.045))",
    "--cdx-cap-active": "linear-gradient(180deg,rgba(255,136,0,0.32),rgba(255,136,0,0.12))",
    "--cdx-cap-empty": "rgba(0,0,0,0.50)",
    "--cdx-cap-top": "inset 0 1px 0 rgba(255,255,255,0.16)",
    "--cdx-cap-bottom": "inset 0 -1px 0 rgba(0,0,0,0.42)",
    "--cdx-cap-lift": "0 2px 3px rgba(0,0,0,0.42)",
    "--cdx-utility-face": "linear-gradient(180deg,#242321,#151513)",
    "--cdx-utility-empty": "rgba(0,0,0,0.34)",
    "--cdx-utility-shadow": "0 3px 8px rgba(0,0,0,0.38), inset 0 1px 0 rgba(255,255,255,0.07), inset 0 0 0 1px rgba(255,255,255,0.10)",
    "--cdx-socket-shadow": "inset 0 2px 7px rgba(0,0,0,0.62), inset 0 0 0 1px rgba(255,255,255,0.07)",
    "--cdx-rail-idle": "linear-gradient(180deg,#24201A,#12100D)",
    "--cdx-rail-busy": "linear-gradient(180deg,#242321,#151513)",
    "--cdx-rail-shadow": "0 5px 12px rgba(0,0,0,0.42), inset 0 1px 0 rgba(255,255,255,0.08)",
  } as React.CSSProperties;
}

function Phone({ scale, appearance, children }: { scale: number; appearance: Appearance; children: React.ReactNode }) {
  return (
    <div style={{ width: PHONE.w * scale, height: PHONE.h * scale }} className="relative shrink-0">
      <div
        data-theme={appearance === "light" ? "scope" : "tactical"}
        className="absolute left-0 top-0 select-none overflow-hidden rounded-[34px]"
        style={{
          width: PHONE.w,
          height: PHONE.h,
          transform: `scale(${scale})`,
          transformOrigin: "top left",
          background: "var(--theme-canvas)",
          boxShadow: "0 0 0 1px rgba(0,0,0,0.55), 0 10px 26px -12px rgba(0,0,0,0.6)",
          fontFamily: "var(--theme-font-mono)",
          ...phoneAppearanceVariables(appearance),
        }}
      >
        {children}
      </div>
    </div>
  );
}

function TopBar({ model }: { model: DeckModel }) {
  return (
    <div className="absolute inset-x-0 top-0" style={{ height: PICKER_TOP }}>
      <div className="flex items-center justify-between px-6" style={{ height: STATUS_H }}>
        <span style={{ color: "var(--theme-ink)", fontSize: 13, fontWeight: 600 }}>7:05</span>
        <div className="flex items-center gap-1.5" style={{ color: "var(--theme-ink-dim)" }}>
          <Bars /> <Wifi /> <Batt />
        </div>
      </div>
      <div
        className="flex items-center gap-2 px-5"
        style={{ height: TITLE_H, borderBottom: "0.5px solid var(--theme-edge-faint)" }}
      >
        <span style={{ color: "var(--theme-ink)", fontSize: 11.5, letterSpacing: "0.22em", fontWeight: 600 }}>TALKIE</span>
        <span style={{ color: "var(--theme-ink-subtle)", fontSize: 11 }}>·</span>
        <span style={{ color: "var(--theme-ink)", fontSize: 11.5, letterSpacing: "0.22em", fontWeight: 600 }}>DECK</span>
        <span
          className="ml-auto rounded-[3px] px-2 py-[3px]"
          style={{
            color: model.bridge ? "var(--theme-ink-dim)" : "var(--theme-rec)",
            fontSize: 8.5,
            letterSpacing: "0.16em",
            border: `0.5px solid ${model.bridge ? "var(--theme-edge-dim)" : "rgba(255,69,58,0.6)"}`,
          }}
        >
          {model.bridge ? "BRIDGE" : "NO BRIDGE"}
        </span>
      </div>
    </div>
  );
}

const UTILITIES = [
  { icon: "▤", label: "OUTPUT" }, { icon: "⌗", label: "MAPPER" },
  { icon: "◎", label: "STATUS" }, { icon: "↻", label: "REVALIDATE" },
  { icon: "≡", label: "HISTORY" }, { icon: "▦", label: "SPACES" },
  { icon: "⏵", label: "REPLAY" }, { icon: "♪", label: "NARRATE" },
];

/** Navigation grid. Settled surface — drawn low-emphasis so it reads as context. */
function UtilityGrid() {
  return (
    <div className="absolute inset-x-0" style={{ top: GRID_TOP, height: GRID_H }}>
      {Array.from({ length: GRID_ROWS }).map((_, ri) => (
        <div
          key={ri}
          className="absolute grid"
          style={{
            top: ri * (GRID_ROW_H + GRID_GAP), left: RAIL.padX, right: RAIL.padX,
            height: GRID_ROW_H, gridTemplateColumns: "repeat(4,1fr)", gap: GRID_GAP,
          }}
        >
          {Array.from({ length: 4 }).map((_, ci) => {
            const u = UTILITIES[ri * 4 + ci];
            return (
              <div
                key={ci}
                className="grid place-items-center"
                style={{
                  borderRadius: 12,
                  opacity: u ? 0.66 : 0.3,
                  background: u ? "var(--cdx-utility-face)" : "var(--cdx-utility-empty)",
                  boxShadow: u
                    ? "var(--cdx-utility-shadow)"
                    : "var(--cdx-socket-shadow)",
                }}
              >
                {u && (
                  <span className="flex flex-col items-center gap-1">
                    <span style={{ color: "var(--theme-ink-dim)", fontSize: 14, lineHeight: 1 }}>{u.icon}</span>
                    <span style={{ color: "var(--theme-ink-dim)", fontSize: 7.5, letterSpacing: "0.11em" }}>{u.label}</span>
                  </span>
                )}
                {!u && (
                  <span style={{ color: "var(--theme-ink-subtle)", fontSize: 7, letterSpacing: "0.08em" }}>
                    {String(ri * 4 + ci + 1).padStart(2, "0")}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// The rail — settled, identical in all five treatments.
// ═══════════════════════════════════════════════════════════════════

interface RailFace {
  label: string;
  sub: string;
  tone: "idle" | "live" | "busy" | "blocked" | "off";
  live: boolean;
  disabled: boolean;
}

function railFace(m: DeckModel): RailFace {
  if (!m.bridge) return { label: "HOST UNAVAILABLE", sub: "TALKING IS DISABLED UNTIL THE MAC ANSWERS", tone: "off", live: false, disabled: true };
  if (m.failure) return { label: "BLOCKED", sub: m.failure.code.toUpperCase().replace(/-/g, " "), tone: "blocked", live: false, disabled: true };
  if (m.selected === null) {
    return m.lanes.length === 0
      ? { label: "MAP A TASK TO A LANE", sub: "OPEN THE MAPPER TO START", tone: "off", live: false, disabled: true }
      : { label: "PICK A LANE", sub: "THE RAIL ACTS ON THE SELECTED LANE", tone: "off", live: false, disabled: true };
  }
  switch (m.phase) {
    case "listening":
      return { label: "RELEASE TO SEND", sub: "LISTENING", tone: "live", live: true, disabled: false };
    case "transcribing":
      return { label: "TRANSCRIBING", sub: "ON DEVICE", tone: "busy", live: false, disabled: true };
    case "validating":
      return { label: "CONFIRMING THE TASK", sub: "VALIDATING WITH THE MAC", tone: "busy", live: false, disabled: true };
    case "submitting":
      return { label: "HOLD TO TALK", sub: "CODEX WORKING · YOURS QUEUES NEXT", tone: "idle", live: true, disabled: false };
    case "speaking":
      return { label: "HOLD TO INTERRUPT", sub: "SPEAKING THE RESPONSE", tone: "busy", live: false, disabled: false };
    default:
      break;
  }
  if (m.receipt) {
    return {
      label: "HOLD TO TALK",
      sub: DELIVERY_LABEL[m.receipt.delivery],
      tone: "idle", live: false, disabled: false,
    };
  }
  if (m.confirmed === m.selected && m.confirmAge < LOCK_FRESHNESS_S) {
    return { label: "HOLD TO TALK", sub: `LANE ${String(m.selected).padStart(2, "0")} · READY`, tone: "idle", live: false, disabled: false };
  }
  return { label: "HOLD TO TALK", sub: "CONFIRMS THE TASK ON SEND", tone: "idle", live: false, disabled: false };
}

const RAIL_TONE: Record<RailFace["tone"], { ink: string; bg: string; rim: string }> = {
  // At rest this is a physical control, not an illuminated status panel.
  idle: { ink: "var(--theme-amber)", bg: "var(--cdx-rail-idle)", rim: "var(--theme-edge-dim)" },
  live: { ink: "var(--theme-rec)", bg: "linear-gradient(rgba(255,69,58,0.30),rgba(255,69,58,0.15))", rim: "rgba(255,69,58,0.8)" },
  busy: { ink: "var(--theme-ink-dim)", bg: "var(--cdx-rail-busy)", rim: "var(--theme-edge-dim)" },
  blocked: { ink: "var(--theme-rec)", bg: "linear-gradient(rgba(255,69,58,0.14),rgba(255,69,58,0.06))", rim: "rgba(255,69,58,0.5)" },
  off: { ink: "var(--theme-ink-subtle)", bg: "transparent", rim: "var(--theme-edge-subtle)" },
};

function SillRail({ model }: { model: DeckModel }) {
  const face = railFace(model);
  const tone = RAIL_TONE[face.tone];
  const [messageMode, setMessageMode] = useState<"queue" | "steer">("queue");
  const duringTurn = model.phase === "submitting";
  return (
    <div
      className="absolute flex items-stretch gap-1.5 p-1.5"
      style={{
        left: RAIL.padX,
        top: RAIL_TOP,
        width: RAIL_W,
        height: RAIL.h,
        borderRadius: 18,
        background: tone.bg,
        boxShadow: `var(--cdx-rail-shadow), inset 0 0 0 1px ${tone.rim}`,
      }}
    >
      <button
        type="button"
        disabled={face.disabled}
        aria-label={`${face.label}. ${face.sub}`}
        className="cdx-focus grid min-w-0 flex-1 place-items-center rounded-[10px]"
        style={{
          background: "rgba(255,136,0,0.035)",
          opacity: face.disabled ? 0.55 : 1,
          cursor: face.disabled ? "not-allowed" : "pointer",
        }}
      >
        <span className="flex min-w-0 flex-col items-center gap-[5px] px-2">
          <span className="flex items-center gap-2">
            {face.live && (
              <span
                className="cdx-live"
                style={{ width: 7, height: 7, borderRadius: 4, background: face.tone === "live" ? "var(--theme-rec)" : "var(--theme-amber)" }}
              />
            )}
            <span className="truncate" style={{ color: tone.ink, fontSize: 13, fontWeight: 700, letterSpacing: "0.14em" }}>{face.label}</span>
          </span>
          <span
            className="truncate text-center"
            style={{ color: "var(--theme-ink-subtle)", fontSize: 9, letterSpacing: "0.10em", lineHeight: 1.25, maxWidth: "100%" }}
          >
            {duringTurn ? (messageMode === "queue" ? "RUNS AFTER THIS TURN" : "ADDS TO THE ACTIVE TURN") : face.sub}
          </span>
        </span>
      </button>

      {duringTurn && (
        <div className="flex shrink-0 items-stretch gap-1" aria-label="During-turn delivery mode">
          {(["queue", "steer"] as const).map((mode) => {
            const selected = messageMode === mode;
            return (
              <button
                key={mode}
                type="button"
                aria-pressed={selected}
                onClick={() => setMessageMode(mode)}
                className="cdx-focus flex w-[47px] flex-col items-center justify-center gap-1 rounded-[9px]"
                style={{
                  color: selected ? "var(--theme-ink)" : "var(--theme-ink-subtle)",
                  background: selected ? "rgba(255,136,0,0.18)" : "var(--cdx-utility-face)",
                  boxShadow: selected
                    ? "inset 0 0 0 1px var(--theme-amber)"
                    : "inset 0 0 0 1px var(--theme-edge-faint)",
                }}
              >
                <span style={{ fontSize: 11 }}>{mode === "queue" ? "⇣" : "↗"}</span>
                <span style={{ fontSize: 9, fontWeight: 700, letterSpacing: "0.06em" }}>{mode.toUpperCase()}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Shared picker parts
// ═══════════════════════════════════════════════════════════════════

const LANE_INK: Record<LaneState, string> = {
  empty: "var(--theme-ink-subtle)",
  mapped: "var(--theme-ink-dim)",
  selected: "var(--theme-ink)",
  stale: "var(--theme-ink)",
  confirmed: "var(--theme-amber)",
  failed: "var(--theme-rec)",
};

/** IOSDeck's active-key halo, reused verbatim so a locked lane glows like a
 *  live key on the deck rather than like a coloured chip. */
const ACTIVE_GLOW = "0 0 16px -3px var(--theme-amber-glow)";

// A lane key is a cap SEATED INTO the bed: translucent fill, bright top
// chamfer, dark bottom chamfer, a hair of drop. Lifted from IOSDeck's
// CONSOLE_KEY. It is deliberately NOT the utility tile's opaque
// #161616 → #101010 — that material belongs to the navigation grid, and
// sharing it is exactly what made the lane row read as six stray tiles.
const CAP_TOP = "var(--cdx-cap-top)";
const CAP_BOTTOM = "var(--cdx-cap-bottom)";
const CAP_LIFT = "var(--cdx-cap-lift)";

function laneSkin(state: LaneState, emphasis = "fill"): React.CSSProperties {
  const base: React.CSSProperties = {
    borderRadius: 10,
    transition: "background 160ms ease, box-shadow 160ms ease, transform 160ms ease",
  };
  switch (state) {
    case "empty":
      // No cap fitted. You see the routed socket in the bed, nothing more.
      return {
        ...base,
        background: "var(--cdx-cap-empty)",
        boxShadow: "inset 0 1.5px 3px rgba(0,0,0,0.24), inset 0 0 0 1px var(--theme-edge-subtle)",
      };
    case "mapped":
      return {
        ...base,
        background: "var(--cdx-cap-face)",
        boxShadow: `${CAP_TOP}, ${CAP_BOTTOM}, ${CAP_LIFT}`,
      };
    case "selected":
    case "stale":
      // Dashed edge is the visual form of "selected but not confirmed".
      // CodexLaneBar.swift already draws it this way; nothing here may
      // make an unvalidated lane look like a locked one. The cap is
      // brighter and lifted — pressed — but the rim stays broken.
      return {
        ...base,
        background: "var(--cdx-cap-face)",
        boxShadow: `${CAP_TOP}, ${CAP_BOTTOM}, ${CAP_LIFT}`,
        outline: "1.5px dashed var(--theme-ink-faint)",
        outlineOffset: -1.5,
        transform: "translateY(-0.5px)",
      };
    case "confirmed":
      return {
        ...base,
        background:
          emphasis === "outline"
            ? "var(--cdx-cap-face)"
            : emphasis === "underline"
              ? "var(--cdx-cap-face)"
              : "var(--cdx-cap-active)",
        boxShadow:
          emphasis === "underline"
            ? `inset 0 -3px 0 var(--theme-amber), ${CAP_TOP}, ${CAP_LIFT}`
            : `inset 0 0 0 1px var(--theme-amber), ${ACTIVE_GLOW}, ${CAP_TOP}, ${CAP_LIFT}`,
        transform: "translateY(-0.5px)",
      };
    case "failed":
      return {
        ...base,
        background: "linear-gradient(180deg, rgba(255,69,58,0.26), rgba(255,69,58,0.08))",
        boxShadow: `inset 0 0 0 1px rgba(255,69,58,0.75), ${CAP_TOP}, ${CAP_LIFT}`,
      };
  }
}

function LaneSlot({
  n, state, title, w = 40, h = 34, emphasis, initials, tag, grow, onClick,
}: {
  n: number;
  state: LaneState;
  title: string;
  w?: number | string;
  h?: number;
  emphasis?: string;
  initials?: string;
  tag?: string;
  grow?: boolean;
  onClick?: () => void;
}) {
  const meta = LANE_STATE_META[state];
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={state !== "empty" && state !== "mapped"}
      aria-label={state === "empty" ? `Lane ${n}, unmapped` : `Lane ${n}, ${title}, ${meta.word}`}
      className={`cdx-focus grid place-items-center ${grow ? "min-w-0 flex-1" : "shrink-0"}`}
      style={{ width: grow ? undefined : w, height: h, ...laneSkin(state, emphasis) }}
    >
      <span className="flex flex-col items-center leading-none">
        <span style={{ color: LANE_INK[state], fontSize: 15, fontWeight: 700, letterSpacing: "0.01em" }}>
          {n}
        </span>
        {initials && state !== "empty" && (
          <span style={{ color: "var(--theme-ink-subtle)", fontSize: 6.5, letterSpacing: "0.08em", marginTop: 3 }}>
            {initials}
          </span>
        )}
        {tag && (
          <span style={{ color: LANE_INK[state], fontSize: 6, letterSpacing: "0.1em", marginTop: 2 }}>{tag}</span>
        )}
      </span>
    </button>
  );
}

/** The bed's utility key. Same cap material at lower emphasis, so it is
 *  legibly a key but never competes with the six numbers. */
function BedKey({
  h, glyph, label, text, w = 26, grow = false, expanded,
}: {
  h: number; glyph: string; label: string; text?: string; w?: number; grow?: boolean; expanded?: boolean;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      aria-expanded={expanded}
      className={`cdx-focus grid place-items-center ${grow ? "min-w-0 flex-1" : "shrink-0"}`}
      style={{
        width: grow ? undefined : w,
        height: h,
        borderRadius: 10,
        background: "var(--cdx-cap-face)",
        boxShadow: `inset 0 1px 0 rgba(255,255,255,0.09), ${CAP_BOTTOM}, ${CAP_LIFT}`,
      }}
    >
      {/* Legend first, glyph trailing: a labelled key reads as a label with an
          affordance, not as a glyph that happens to have a caption. */}
      <span className="flex items-center gap-1.5" style={{ color: "var(--theme-ink-faint)", lineHeight: 1 }}>
        {text && <span style={{ fontSize: 8, letterSpacing: "0.14em" }}>{text}</span>}
        <span style={{ fontSize: 13 }}>{glyph}</span>
      </span>
    </button>
  );
}

/** Two characters of the project name — enough to disambiguate at a glance. */
function initialsOf(project: string) {
  return project.replace(/[^a-z0-9]/gi, "").slice(0, 2).toUpperCase();
}

function ConfirmBadge({ model, style = "wordAge" }: { model: DeckModel; style?: string }) {
  const fresh = model.confirmed !== null && model.confirmed === model.selected && model.confirmAge < LOCK_FRESHNESS_S;
  if (model.failure) {
    return <Badge ink="var(--theme-rec)" rim="rgba(255,69,58,0.55)">BLOCKED</Badge>;
  }
  if (model.phase === "validating") {
    return <Badge ink="var(--theme-ink-dim)" rim="var(--theme-edge-dim)">CONFIRMING…</Badge>;
  }
  if (fresh) {
    return (
      <Badge ink="var(--theme-amber)" rim="var(--theme-amber-soft)">
        {style === "word" ? "EXACT TASK" : `EXACT TASK · ${model.confirmAge}S AGO`}
      </Badge>
    );
  }
  if (model.confirmAge > 0) {
    return <Badge ink="var(--theme-ink-faint)" rim="var(--theme-edge-dim)">CONFIRMATION EXPIRED</Badge>;
  }
  return <Badge ink="var(--theme-ink-faint)" rim="var(--theme-edge-dim)">NOT CONFIRMED</Badge>;
}

/** The lock-rim treatment keeps confirmation present without boxing the task title. */
function FreshnessSignal({ model }: { model: DeckModel }) {
  const fresh = model.confirmed !== null && model.confirmed === model.selected && model.confirmAge < LOCK_FRESHNESS_S;
  const validating = model.phase === "validating";
  const label = validating
    ? "CONFIRMING"
    : fresh
      ? `CONFIRMED · ${model.confirmAge}S`
      : model.confirmAge > 0
        ? "CONFIRMATION EXPIRED"
        : "CONFIRMS ON SEND";
  const ink = validating
    ? "var(--theme-ink-dim)"
    : fresh
      ? "var(--theme-amber)"
      : "var(--theme-ink-subtle)";

  return (
    <span
      className="ml-auto inline-flex shrink-0 items-center gap-1.5"
      style={{ color: ink, fontSize: 9, letterSpacing: "0.10em", whiteSpace: "nowrap" }}
    >
      <span
        aria-hidden
        style={{
          width: 4,
          height: 4,
          borderRadius: 1,
          background: fresh ? "var(--theme-amber)" : "var(--theme-edge-dim)",
          boxShadow: fresh ? "0 0 5px var(--theme-amber-soft)" : "none",
        }}
      />
      {label}
    </span>
  );
}

function Badge({ ink, rim, children }: { ink: string; rim: string; children: React.ReactNode }) {
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-[3px] px-1.5 py-[2px]"
      style={{ color: ink, border: `0.5px solid ${rim}`, fontSize: 9, letterSpacing: "0.10em", whiteSpace: "nowrap" }}
    >
      {children}
    </span>
  );
}

/** Failure banner: the Mac's own recovery sentence, never a phone invention. */
function FailureNote({ failure, compact }: { failure: Failure; compact?: boolean }) {
  return (
    <div
      className="flex flex-col gap-[3px] rounded-[6px] px-2.5 py-2"
      style={{ background: "rgba(255,69,58,0.10)", boxShadow: "inset 0 0 0 1px rgba(255,69,58,0.4)" }}
    >
      <span style={{ color: "var(--theme-rec)", fontSize: 8.5, fontWeight: 700, letterSpacing: "0.12em" }}>
        ⚠ {failure.code.toUpperCase()}
      </span>
      {!compact && (
        <span style={{ color: "var(--theme-ink-dim)", fontSize: 9, lineHeight: 1.35 }}>{failure.message}</span>
      )}
      <span style={{ color: "var(--theme-ink-faint)", fontSize: 9, lineHeight: 1.35 }}>{failure.hint}</span>
    </div>
  );
}

function PhaseWord({ model }: { model: DeckModel }) {
  const ink =
    model.phase === "failed" ? "var(--theme-rec)"
    : model.phase === "listening" ? "var(--theme-rec)"
    : model.phase === "idle" ? "var(--theme-ink-faint)"
    : "var(--theme-amber)";
  return (
    <span style={{ color: ink, fontSize: 10, fontWeight: 700, letterSpacing: "0.12em", whiteSpace: "nowrap" }}>
      {PHASE_LABEL[model.phase]}
    </span>
  );
}

function ReceiptLine({ receipt }: { receipt: Receipt }) {
  const good = receipt.delivery !== "steered-active-turn";
  return (
    <span
      className="inline-flex items-center gap-1.5"
      style={{ color: good ? "#5FCD8C" : "var(--theme-amber)", fontSize: 9, letterSpacing: "0.10em" }}
    >
      ✓ {DELIVERY_LABEL[receipt.delivery]}
      <span style={{ color: "var(--theme-ink-subtle)" }}>{receipt.turnId}</span>
    </span>
  );
}

function EmptyPrompt({ line = "MAP A CODEX TASK TO A LANE" }: { line?: string }) {
  return (
    // No frame of its own: the Readout it sits in is already the frame.
    <div className="flex h-full flex-col items-center justify-center gap-1.5">
      <span style={{ color: "var(--theme-ink-faint)", fontSize: 9.5, letterSpacing: "0.14em" }}>{line}</span>
      <span style={{ color: "var(--theme-ink-subtle)", fontSize: 8.5, letterSpacing: "0.1em" }}>
        LANES PERSIST · SIX SLOTS · ONE EXACT TASK EACH
      </span>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// The Lane Console — one bounded technical field, not a row of pills
//
// This is the Codex answer to the Deck's trackpad/technical area. The
// depth ladder is the deck's, unchanged:
//
//   chassis (--theme-canvas)   ground
//   → Lane Console             recessed field, anodised top chamfer   [DeckKeypad faceplate]
//     → Lane Bed               deeper routed pocket                   [DeckKeyBed inset bed]
//       → Lane Key             seated translucent cap, lifted         [IOSDeck CONSOLE_KEY]
//     → Task Readout           the instrument's display               [IOSDeck Pad]
//     → Silkscreen             printed legend: module · target        [IOSDeck Silkscreen]
//
// Every treatment renders inside it. What differs between L1–L5 is how the
// bed and the readout divide the field — not what they are made of.
// ═══════════════════════════════════════════════════════════════════

/** Same gutter as the utility grid and the rail. The console has to line up
 *  with the rest of the chassis or it reads as an overlay. */
const CONSOLE_X = RAIL.padX;
const CONSOLE_TOP = PICKER_TOP + 12;      // 103
/** A ceiling, not a fixed height. The console sizes to what its treatment
 *  actually needs, so the comparison shows each one's true cost in field —
 *  and no treatment can crowd the 48pt of quiet chassis above the grid. */
const CONSOLE_MAX_H = PICKER_H - 60;      // 264
const CONSOLE_PAD = 10;
const KEY_H = 44;                         // a thumb-sized bank key, not a chip
const BED_H = KEY_H + 8;                  // key + the bed's 4pt lip on each side

const CONSOLE_FACE: React.CSSProperties = {
  background: "var(--cdx-console-face)",
  boxShadow: "var(--cdx-console-shadow)",
};

/** Printed legend line. Left names the module, right names what it is
 *  pointed at — the deck's own convention (`KEYBED` / `16 · SAFARI`). */
function Silkscreen({ left, right, ink }: { left: string; right?: string; ink?: string }) {
  return (
    <div className="flex shrink-0 items-center justify-between" style={{ height: 8 }}>
      <span style={{ color: "var(--theme-ink-subtle)", fontSize: 9, fontWeight: 600, letterSpacing: "0.16em" }}>{left}</span>
      {right && (
        <span
          className="min-w-0 truncate pl-3"
          style={{ color: ink ?? "var(--theme-ink-subtle)", fontSize: 9, fontWeight: 600, letterSpacing: "0.16em" }}
        >
          {right}
        </span>
      )}
    </div>
  );
}

/** What the console is currently pointed at. Derived only from state the
 *  phone genuinely holds — binding count, selection, confirmation age. */
function consoleTarget(model: DeckModel): { text: string; ink: string } {
  const lane = laneOf(model, model.selected);
  if (!model.bridge) return { text: "HOST UNAVAILABLE", ink: "var(--theme-rec)" };
  if (model.lanes.length === 0) return { text: "NO BINDINGS", ink: "var(--theme-ink-subtle)" };
  if (!lane) return { text: `${model.lanes.length} OF 6 BOUND`, ink: "var(--theme-ink-subtle)" };
  const fresh = model.confirmed === lane.n && model.confirmAge < LOCK_FRESHNESS_S;
  return {
    text: `LANE ${String(lane.n).padStart(2, "0")} · ${lane.project.slice(0, 12).toUpperCase()}`,
    ink: fresh ? "var(--theme-amber)" : "var(--theme-ink-subtle)",
  };
}

function LaneConsole({ model, children }: { model: DeckModel; children: React.ReactNode }) {
  const target = consoleTarget(model);
  return (
    <div
      className="absolute flex flex-col"
      style={{
        left: CONSOLE_X,
        right: CONSOLE_X,
        top: CONSOLE_TOP,
        maxHeight: CONSOLE_MAX_H,
        borderRadius: 24,
        padding: CONSOLE_PAD,
        gap: 8,
        ...CONSOLE_FACE,
      }}
    >
      <Silkscreen left="LANE CONSOLE" right={target.text} ink={target.ink} />
      {children}
    </div>
  );
}

/** The routed pocket the lane keys seat into. One bed, not six chips. */
function LaneBed({ h, grow, children }: { h?: number; grow?: boolean; children: React.ReactNode }) {
  return (
    <div
      className={`flex items-stretch ${grow ? "flex-1" : "shrink-0"}`}
      style={{
        height: grow ? undefined : h,
        borderRadius: 14,
        padding: 4,
        gap: 4,
        background: "var(--cdx-bed-face)",
        boxShadow: "var(--cdx-bed-shadow)",
      }}
    >
      {children}
    </div>
  );
}

/** DeckKeyBed's group seam: a routed groove divides functional groups, so
 *  the mapper key is visibly not a seventh lane. Cheaper than a gap and
 *  reads as machined rather than forgotten. */
function Seam() {
  return (
    <span
      aria-hidden
      className="shrink-0 self-stretch"
      style={{
        width: 3,
        margin: "1px 1px",
        borderRadius: 2,
        background: "rgba(0,0,0,0.7)",
        boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.05)",
      }}
    />
  );
}

interface ReadoutProps {
  children: React.ReactNode;
  /** Amber rim + halo. Reserved for a fresh, host-confirmed exact task. */
  locked?: boolean;
  h?: number;
  grow?: boolean;
  onClick?: () => void;
  ariaLabel?: string;
  ariaExpanded?: boolean;
}

/** The instrument's display. IOSDeck's Pad, at picker scale: recessed glass
 *  with tape grain, a corner sheen and an edge vignette. Identity lives on
 *  a readout, never on a card floating over the chassis. */
function Readout({ children, locked, h, grow, onClick, ariaLabel, ariaExpanded }: ReadoutProps) {
  const style = {
    height: grow ? undefined : h,
    minHeight: grow ? h : undefined,
    borderRadius: 14,
    background: "var(--theme-screen-bg)",
    boxShadow: locked
      ? `inset 0 0 0 1px var(--theme-amber), inset 0 2px 9px rgba(0,0,0,0.65), ${ACTIVE_GLOW}`
      : "inset 0 2px 9px rgba(0,0,0,0.65), inset 0 1px 0 rgba(255,255,255,0.05), inset 0 0 0 1px var(--theme-edge-faint)",
    transition: "box-shadow 160ms ease",
    "--theme-ink": "#F6F0E7",
    "--theme-ink-dim": "#D7CFC4",
    "--theme-ink-faint": "#AAA197",
    "--theme-ink-subtle": "#766F68",
    "--theme-amber": "#F2A13B",
    "--theme-amber-soft": "rgba(242,161,59,0.42)",
    "--theme-rec": "#FF6B5F",
  } as React.CSSProperties;
  const inner = (
    <>
      <span
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-[0.055]"
        style={{
          backgroundImage:
            "repeating-linear-gradient(135deg, transparent 0 13px, var(--theme-screen-trace) 13px 14px)",
        }}
      />
      <span
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{ background: "linear-gradient(150deg, rgba(255,255,255,0.07), transparent 36%)" }}
      />
      <span
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{ background: "radial-gradient(120% 78% at 50% 42%, transparent 52%, rgba(0,0,0,0.45))" }}
      />
      <div className="relative flex h-full min-h-0 flex-col px-3 py-2.5">{children}</div>
    </>
  );
  const cls = `relative overflow-hidden ${grow ? "flex-1" : "shrink-0"}`;
  if (onClick || ariaLabel) {
    return (
      <button
        type="button"
        onClick={onClick}
        aria-label={ariaLabel}
        aria-expanded={ariaExpanded}
        className={`cdx-focus ${cls} text-left`}
        style={style}
      >
        {inner}
      </button>
    );
  }
  return (
    <div className={cls} style={style}>
      {inner}
    </div>
  );
}

/** The console's bottom line: delivery receipt, failure, or a printed note.
 *  Sits under a routed hairline so the field has a real bottom edge. */
function ConsoleFooter({ children }: { children: React.ReactNode }) {
  return (
    <div className="mt-auto flex shrink-0 flex-col gap-1.5">
      <span aria-hidden style={{ height: 1, background: "var(--theme-edge-subtle)" }} />
      <div className="flex min-h-[11px] items-center gap-2">{children}</div>
    </div>
  );
}

/** A printed note on the field — silkscreen register, never a live signal. */
function ConsoleNote({ children, ink }: { children: React.ReactNode; ink?: string }) {
  return (
    <span
      style={{ color: ink ?? "var(--theme-ink-subtle)", fontSize: 9, letterSpacing: "0.12em", lineHeight: 1.4 }}
    >
      {children}
    </span>
  );
}

interface PickerProps {
  model: DeckModel;
  params: Params;
  proposed: boolean;
  select: (n: number) => void;
}

// ═══════════════════════════════════════════════════════════════════
// L1 · Numbered Strip · Central Status
// ═══════════════════════════════════════════════════════════════════

function LaneKeyRow({
  model, select, keyH = KEY_H, emphasis, initials, tagOf,
}: {
  model: DeckModel;
  select: (n: number) => void;
  keyH?: number;
  emphasis?: string;
  initials?: boolean;
  tagOf?: (state: LaneState) => string | undefined;
}) {
  return (
    <>
      {[1, 2, 3, 4, 5, 6].map((n) => {
        const l = laneOf(model, n);
        const state = laneStateOf(model, n);
        return (
          <LaneSlot
            key={n}
            n={n}
            state={state}
            title={l ? `${l.project} — ${l.title}` : ""}
            emphasis={emphasis}
            grow
            h={keyH}
            initials={initials && l ? initialsOf(l.project) : undefined}
            tag={tagOf?.(state)}
            onClick={() => l && select(n)}
          />
        );
      })}
      <Seam />
      <BedKey h={keyH} glyph="⌗" label="Map Codex tasks to lanes" />
    </>
  );
}

function StripPicker({ model, params, select }: PickerProps) {
  const lane = laneOf(model, model.selected);
  const identity = str(params, "identity");
  const banner = str(params, "failureDisclosure") === "banner";
  const locked = lane !== null && model.confirmed === lane.n && model.confirmAge < LOCK_FRESHNESS_S;

  return (
    <LaneConsole model={model}>
      {model.failure && banner && <FailureNote failure={model.failure} compact />}

      <LaneBed h={BED_H}>
        <LaneKeyRow model={model} select={select} emphasis={str(params, "emphasis")} />
      </LaneBed>

      <Readout grow h={54} locked={locked}>
        {model.lanes.length === 0 ? (
          <EmptyPrompt />
        ) : model.failure && !banner ? (
          <FailureNote failure={model.failure} compact />
        ) : lane ? (
          <div className="flex flex-col gap-1.5">
            <div className="flex items-center gap-2">
              <PhaseWord model={model} />
              <span style={{ color: "var(--theme-ink-subtle)", fontSize: 8 }}>·</span>
              <span
                className="min-w-0 flex-1 truncate"
                style={{ color: "var(--theme-ink-dim)", fontSize: 9.5, letterSpacing: "0.02em" }}
              >
                {identity === "titleFirst"
                  ? `${lane.title} — ${lane.project}`
                  : identity === "twoLine"
                    ? lane.project
                    : `${lane.project} — ${lane.title}`}
              </span>
              {str(params, "freshness") !== "none" && (
                <ConfirmBadge model={model} style={str(params, "freshness") === "age" ? "wordAge" : "word"} />
              )}
            </div>
            {identity === "twoLine" && (
              <span className="truncate" style={{ color: "var(--theme-ink-faint)", fontSize: 9.5 }}>{lane.title}</span>
            )}
            {bool(params, "showRecency") && (
              <ConsoleNote>UPDATED {lane.rel.toUpperCase()}</ConsoleNote>
            )}
          </div>
        ) : (
          <ConsoleNote ink="var(--theme-ink-faint)">PICK A LANE.</ConsoleNote>
        )}

        <div className="mt-auto">
          <ConsoleNote>ONE LINE · WHATEVER DOES NOT FIT IS LOST</ConsoleNote>
        </div>
      </Readout>

      <ConsoleFooter>
        {model.receipt ? <ReceiptLine receipt={model.receipt} /> : <ConsoleNote>NO DELIVERY THIS SESSION</ConsoleNote>}
      </ConsoleFooter>
    </LaneConsole>
  );
}

// ═══════════════════════════════════════════════════════════════════
// L2 · Selected-Lane Expansion
// ═══════════════════════════════════════════════════════════════════

function ExpandPicker({ model, params, select }: PickerProps) {
  const cardH = num(params, "cardH");
  const slotW = num(params, "slotW");
  const lines = Number(str(params, "lines"));
  const rowH = bool(params, "reserve") ? cardH : model.selected === null ? KEY_H : cardH;
  const lane = laneOf(model, model.selected);

  return (
    <LaneConsole model={model}>
      {model.lanes.length === 0 ? (
        <Readout grow h={72}>
          <EmptyPrompt />
        </Readout>
      ) : (
        // L2 has no second tier: the bed IS the identity surface, so the
        // selected key grows a readout face inside the same pocket.
        <LaneBed h={rowH + 8}>
          {[1, 2, 3, 4, 5, 6].map((n) => {
            const l = laneOf(model, n);
            const state = laneStateOf(model, n);
            const isSel = model.selected === n;
            if (!isSel || !l) {
              return (
                <LaneSlot
                  key={n}
                  n={n}
                  state={state}
                  title={l ? `${l.project} — ${l.title}` : ""}
                  w={slotW}
                  h={rowH}
                  onClick={() => l && select(n)}
                />
              );
            }
            return (
              <button
                key={n}
                type="button"
                aria-pressed
                aria-label={`Lane ${n}, ${l.project} — ${l.title}, ${LANE_STATE_META[state].word}`}
                className="cdx-focus relative flex min-w-0 flex-1 flex-col justify-center gap-[3px] overflow-hidden px-2.5 text-left"
                style={{ ...laneSkin(state), height: rowH }}
              >
                <span
                  aria-hidden
                  className="pointer-events-none absolute inset-0"
                  style={{ background: "linear-gradient(150deg, rgba(255,255,255,0.06), transparent 40%)" }}
                />
                {/* No badge in here: one lane key is far too narrow to hold
                    "CONFIRMATION EXPIRED" without clipping it, and a clipped
                    truth claim is worse than none. It rides the footer. */}
                <div className="relative flex min-w-0 items-center gap-1.5">
                  <span style={{ color: LANE_INK[state], fontSize: 12, fontWeight: 700 }}>{n}</span>
                  <PhaseWord model={model} />
                </div>
                {lines >= 2 && (
                  <span className="relative truncate" style={{ color: "var(--theme-ink-faint)", fontSize: 8.5, letterSpacing: "0.08em" }}>
                    {l.project.toUpperCase()}
                    {bool(params, "showRecency") && ` · ${l.rel.toUpperCase()}`}
                  </span>
                )}
                <span className="relative truncate" style={{ color: "var(--theme-ink)", fontSize: 10 }}>{l.title}</span>
                {lines >= 3 && (
                  <span className="relative truncate" style={{ color: "var(--theme-ink-subtle)", fontSize: 7.5 }}>{l.id}</span>
                )}
              </button>
            );
          })}
          <Seam />
          <BedKey h={rowH} glyph="⌗" label="Map Codex tasks to lanes" />
        </LaneBed>
      )}

      {model.failure && <FailureNote failure={model.failure} compact />}
      {!model.failure && model.selected === null && model.lanes.length > 0 && (
        <ConsoleNote ink="var(--theme-ink-faint)">PICK A LANE TO SEE ITS TASK.</ConsoleNote>
      )}

      <ConsoleFooter>
        {lane && <ConfirmBadge model={model} style="word" />}
        <span className="min-w-0 flex-1 truncate">
          {model.receipt && lane ? (
            <ReceiptLine receipt={model.receipt} />
          ) : (
            <ConsoleNote>IDENTITY LIVES IN THE KEY · NO SECOND TIER</ConsoleNote>
          )}
        </span>
      </ConsoleFooter>
    </LaneConsole>
  );
}

// ═══════════════════════════════════════════════════════════════════
// L3 · Two-Tier Identity
// ═══════════════════════════════════════════════════════════════════

function TwoTierPicker({ model, params, select }: PickerProps) {
  const plateH = num(params, "plateH");
  const lane = laneOf(model, model.selected);
  const titleLines = Number(str(params, "titleLines"));
  const confirmStyle = str(params, "confirmStyle");
  const fresh = model.confirmed !== null
    && model.confirmed === model.selected
    && model.confirmAge < LOCK_FRESHNESS_S;

  return (
    // The most resolved of the five: bed and readout are the console's two
    // tiers, in the console's own materials, sharing one bounded field.
    <LaneConsole model={model}>
      <LaneBed h={BED_H}>
        <LaneKeyRow model={model} select={select} />
      </LaneBed>

      {/* Tier two is the instrument's display, not a card floating on the chassis.
          confirmStyle "rule" drives the readout's own amber lock rim. */}
      <Readout
        h={plateH}
        locked={confirmStyle === "rule" && fresh}
        ariaLabel={lane ? `${lane.project} — ${lane.title}` : "No Codex lane selected"}
      >
        {model.failure ? (
          <div className="flex h-full items-center">
            <FailureNote failure={model.failure} compact />
          </div>
        ) : model.lanes.length === 0 ? (
          <div className="flex h-full flex-col justify-center gap-1">
            <span style={{ color: "var(--theme-ink-faint)", fontSize: 9.5, letterSpacing: "0.12em" }}>NO TASK BOUND</span>
            <span style={{ color: "var(--theme-ink-subtle)", fontSize: 8.5, lineHeight: 1.4 }}>
              Open the mapper and bind a recent Codex task to one of the six slots.
            </span>
          </div>
        ) : !lane ? (
          <div className="flex h-full flex-col justify-center gap-1">
            <span style={{ color: "var(--theme-ink-faint)", fontSize: 9.5, letterSpacing: "0.12em" }}>NO LANE SELECTED</span>
            <span style={{ color: "var(--theme-ink-subtle)", fontSize: 8.5 }}>
              {model.lanes.length} of 6 slots bound. Pick one — the rail acts on it.
            </span>
          </div>
        ) : (
          <div className="flex h-full flex-col gap-1.5">
            <div className="flex items-center gap-1.5">
              <span style={{ color: "var(--theme-amber)", fontSize: 10, fontWeight: 700, letterSpacing: "0.12em" }}>
                LANE {String(lane.n).padStart(2, "0")}
              </span>
              <span className="min-w-0 truncate" style={{ color: "var(--theme-ink-faint)", fontSize: 10, letterSpacing: "0.10em" }}>
                {lane.project.toUpperCase()}
              </span>
              {bool(params, "showRecency") && (
                <span className="shrink-0" style={{ color: "var(--theme-ink-subtle)", fontSize: 9 }}>· {lane.rel}</span>
              )}
              {confirmStyle === "rule" ? (
                <FreshnessSignal model={model} />
              ) : (
                <span className="ml-auto shrink-0">
                  <ConfirmBadge model={model} style={confirmStyle} />
                </span>
              )}
            </div>

            <span
              style={{
                color: "var(--theme-ink)",
                fontSize: 15,
                fontWeight: 600,
                lineHeight: 1.3,
                display: "-webkit-box",
                WebkitBoxOrient: "vertical",
                WebkitLineClamp: titleLines,
                overflow: "hidden",
              }}
            >
              {lane.title}
            </span>

            <div className="mt-auto flex items-center gap-2">
              <PhaseWord model={model} />
              {bool(params, "showId") && (
                <span className="truncate" style={{ color: "var(--theme-ink-subtle)", fontSize: 9, letterSpacing: "0.04em" }}>
                  {lane.id}
                </span>
              )}
              {bool(params, "showPending") && model.pending > 0 && (
                <span className="ml-auto shrink-0" style={{ color: "#5E90C4", fontSize: 9, letterSpacing: "0.10em" }}>
                  {model.pending} OF YOURS IN FLIGHT
                </span>
              )}
            </div>
          </div>
        )}
      </Readout>

      <ConsoleFooter>
        {model.receipt ? (
          <ReceiptLine receipt={model.receipt} />
        ) : (
          <ConsoleNote>{lane ? "FIXED BANK · # OPENS THE MAPPER" : "NO DELIVERY THIS SESSION"}</ConsoleNote>
        )}
      </ConsoleFooter>
    </LaneConsole>
  );
}

// ═══════════════════════════════════════════════════════════════════
// L4 · Per-Lane Status Glyphs
// ═══════════════════════════════════════════════════════════════════

const GLYPH_SHAPE: Record<LaneState, string> = {
  empty: "·",
  mapped: "○",
  selected: "◌",
  stale: "◌",
  confirmed: "●",
  failed: "⊘",
};

const GLYPH_TEXT: Record<LaneState, string> = {
  empty: "",
  mapped: "BOUND",
  selected: "SEL",
  stale: "STALE",
  confirmed: "EXACT",
  failed: "BLOCK",
};

function GlyphPicker({ model, params, proposed, select }: PickerProps) {
  const vocabulary = str(params, "vocabulary");
  const unmappedStyle = str(params, "unmapped");
  const lights = proposed && bool(params, "proposedLights");
  const lane = laneOf(model, model.selected);
  const keyH = 62;  // taller cap: the glyph and the initials both live on it

  return (
    <LaneConsole model={model}>
      {model.lanes.length === 0 && unmappedStyle === "hidden" ? (
        <Readout grow h={72}>
          <EmptyPrompt />
        </Readout>
      ) : (
        <LaneBed h={keyH + 8}>
          {[1, 2, 3, 4, 5, 6].map((n) => {
            const l = laneOf(model, n);
            const state = laneStateOf(model, n);
            if (state === "empty" && unmappedStyle === "hidden") return null;
            return (
              <div key={n} className="relative min-w-0 flex-1">
                <LaneSlot
                  n={n}
                  state={state}
                  title={l ? `${l.project} — ${l.title}` : ""}
                  w="100%"
                  h={keyH}
                  initials={bool(params, "initials") && l ? initialsOf(l.project) : undefined}
                  tag={
                    vocabulary === "text" ? GLYPH_TEXT[state]
                    : vocabulary === "shape" ? GLYPH_SHAPE[state]
                    : undefined
                  }
                  onClick={() => l && select(n)}
                />
                {state === "empty" && unmappedStyle === "plus" && (
                  <span
                    className="pointer-events-none absolute inset-0 grid place-items-center"
                    style={{ color: "var(--theme-ink-subtle)", fontSize: 12 }}
                  >
                    +
                  </span>
                )}
                {lights && state !== "empty" && (
                  <span
                    className="pointer-events-none absolute right-[3px] top-[3px] rounded-[2px] px-[3px]"
                    style={{
                      border: "1px dashed rgba(176,122,31,0.85)",
                      background: "#0A0A0A",
                      color: "#D69B33",
                      fontSize: 5.5,
                      letterSpacing: "0.06em",
                    }}
                  >
                    PROP
                  </span>
                )}
              </div>
            );
          })}
          <Seam />
          <BedKey h={keyH} glyph="⌗" label="Map Codex tasks to lanes" />
        </LaneBed>
      )}

      {/* L4 spends its field on the keys, so the readout stays a single line. */}
      <Readout grow h={44}>
        {model.failure ? (
          <FailureNote failure={model.failure} compact />
        ) : lane ? (
          <div className="flex h-full items-center gap-2">
            <PhaseWord model={model} />
            <span className="min-w-0 flex-1 truncate" style={{ color: "var(--theme-ink-faint)", fontSize: 10 }}>
              {lane.title}
            </span>
            {model.receipt && <ReceiptLine receipt={model.receipt} />}
          </div>
        ) : (
          <ConsoleNote ink="var(--theme-ink-faint)">PICK A LANE TO SEE ITS TASK.</ConsoleNote>
        )}
      </Readout>

      {/* The caption is the whole point of L4: it says out loud what the
          five unselected keys are, and are not, allowed to mean. */}
      <ConsoleFooter>
        <ConsoleNote ink={lights ? "#D69B33" : undefined}>
          {lights
            ? "PROPOSED · NO HOST ENDPOINT SUPPLIES PER-LANE ACTIVITY"
            : "UNSELECTED KEYS MEAN “BOUND” — NOTHING MORE"}
        </ConsoleNote>
      </ConsoleFooter>
    </LaneConsole>
  );
}

// ═══════════════════════════════════════════════════════════════════
// L5 · Current-Lane Plate · Switch Sheet
// ═══════════════════════════════════════════════════════════════════

function SheetPicker({ model, params, select }: PickerProps) {
  const lane = laneOf(model, model.selected);
  const open = bool(params, "sheetOpen");

  const fresh = lane !== null && model.confirmed === lane.n && model.confirmAge < LOCK_FRESHNESS_S;

  return (
    <>
      {/* L5 inverts the console: the readout takes the field, and the bed
          shrinks to a transport strip. Same materials, different division. */}
      <LaneConsole model={model}>
        {model.lanes.length === 0 ? (
          <Readout grow h={72}>
            <EmptyPrompt line="NO LANES · OPEN THE MAPPER" />
          </Readout>
        ) : (
          <Readout
            grow
            h={100}
            locked={fresh}
            ariaExpanded={open}
            ariaLabel={lane ? `Lane ${lane.n}, ${lane.project} — ${lane.title}. Open lane switcher` : "Open lane switcher"}
          >
            {lane ? (
              <div className="flex h-full flex-col gap-1">
                <div className="flex items-center gap-1.5">
                  <span style={{ color: "var(--theme-amber)", fontSize: 8.5, fontWeight: 700, letterSpacing: "0.14em" }}>
                    LANE {String(lane.n).padStart(2, "0")}
                  </span>
                  <span className="min-w-0 truncate" style={{ color: "var(--theme-ink-faint)", fontSize: 8.5, letterSpacing: "0.1em" }}>
                    {lane.project.toUpperCase()}
                  </span>
                  <span className="ml-auto shrink-0"><ConfirmBadge model={model} style="word" /></span>
                  <span className="shrink-0" style={{ color: "var(--theme-ink-subtle)", fontSize: 11 }}>⌄</span>
                </div>
                <span
                  style={{
                    color: "var(--theme-ink)",
                    fontSize: 13,
                    lineHeight: 1.3,
                    display: "-webkit-box",
                    WebkitBoxOrient: "vertical",
                    WebkitLineClamp: 2,
                    overflow: "hidden",
                  }}
                >
                  {lane.title}
                </span>
                <div className="mt-auto flex items-center gap-2">
                  <PhaseWord model={model} />
                  {bool(params, "showRecency") && (
                    <span style={{ color: "var(--theme-ink-subtle)", fontSize: 7.5 }}>{lane.rel}</span>
                  )}
                </div>
              </div>
            ) : (
              <div className="flex h-full flex-col justify-center">
                <span style={{ color: "var(--theme-ink-faint)", fontSize: 10, letterSpacing: "0.1em" }}>
                  PICK A LANE — {model.lanes.length} BOUND
                </span>
              </div>
            )}
          </Readout>
        )}

        {model.failure && <FailureNote failure={model.failure} compact />}

        {model.lanes.length > 0 && (
          <LaneBed h={BED_H}>
            {bool(params, "quickPrev") && <BedKey h={KEY_H} glyph="‹" label="Previous lane" w={44} />}
            <BedKey h={KEY_H} glyph="⌄" text="SWITCH LANE" label="Open lane switcher" grow expanded={open} />
            {bool(params, "quickPrev") && <BedKey h={KEY_H} glyph="›" label="Next lane" w={44} />}
            <Seam />
            <BedKey h={KEY_H} glyph="⌗" label="Map Codex tasks to lanes" />
          </LaneBed>
        )}

        <ConsoleFooter>
          {model.receipt && lane ? (
            <ReceiptLine receipt={model.receipt} />
          ) : (
            <ConsoleNote>ONE LANE VISIBLE · THE OTHER FIVE LIVE IN THE SHEET</ConsoleNote>
          )}
        </ConsoleFooter>
      </LaneConsole>

      {open && (
        <div className="absolute inset-0" style={{ background: "rgba(0,0,0,0.55)" }}>
          <div
            className="absolute inset-x-0 bottom-0 flex flex-col gap-1.5 px-4 pb-6 pt-3"
            style={{
              background: "var(--theme-paper)",
              borderTopLeftRadius: 18,
              borderTopRightRadius: 18,
              boxShadow: "inset 0 1px 0 var(--theme-edge-faint)",
            }}
          >
            <span style={{ color: "var(--theme-ink-faint)", fontSize: 8.5, letterSpacing: "0.16em" }}>SWITCH LANE</span>
            {[1, 2, 3, 4, 5, 6].map((n) => {
              const l = laneOf(model, n);
              const state = laneStateOf(model, n);
              if (!l && !bool(params, "showUnmapped")) return null;
              return (
                <button
                  key={n}
                  type="button"
                  onClick={() => l && select(n)}
                  aria-pressed={model.selected === n}
                  aria-label={l ? `Lane ${n}, ${l.project} — ${l.title}, ${LANE_STATE_META[state].word}` : `Lane ${n}, unmapped. Bind a task`}
                  className="cdx-focus flex items-center gap-2.5 px-2 py-2 text-left"
                  style={{
                    borderRadius: 8,
                    background: model.selected === n ? "rgba(255,136,0,0.10)" : "transparent",
                    boxShadow: model.selected === n ? "inset 0 0 0 1px var(--theme-amber-soft)" : "inset 0 0 0 1px var(--theme-edge-subtle)",
                  }}
                >
                  <span style={{ color: l ? LANE_INK[state] : "var(--theme-ink-subtle)", fontSize: 12, fontWeight: 700, width: 12 }}>{n}</span>
                  {l ? (
                    <span className="flex min-w-0 flex-1 flex-col">
                      <span className="truncate" style={{ color: "var(--theme-ink)", fontSize: 10 }}>{l.title}</span>
                      <span style={{ color: "var(--theme-ink-subtle)", fontSize: 8, letterSpacing: "0.08em" }}>
                        {l.project.toUpperCase()}
                        {bool(params, "showRecency") && ` · ${l.rel}`}
                      </span>
                    </span>
                  ) : (
                    <span className="flex-1" style={{ color: "var(--theme-ink-subtle)", fontSize: 9.5, letterSpacing: "0.1em" }}>
                      UNMAPPED — BIND A TASK
                    </span>
                  )}
                  {state === "confirmed" && (
                    <span style={{ color: "var(--theme-amber)", fontSize: 7.5, letterSpacing: "0.1em" }}>EXACT</span>
                  )}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </>
  );
}

const PICKERS: Record<TreatmentKey, (p: PickerProps) => React.ReactElement> = {
  strip: StripPicker,
  expand: ExpandPicker,
  twotier: TwoTierPicker,
  glyph: GlyphPicker,
  sheet: SheetPicker,
};

// ═══════════════════════════════════════════════════════════════════
// Treatment card
// ═══════════════════════════════════════════════════════════════════

function TreatmentCard({
  treatment, scenario, onScenario, mapped, proposed, params, onParam, onReset, scale, appearance,
}: {
  treatment: Treatment;
  scenario: ScenarioKey;
  onScenario: (s: ScenarioKey) => void;
  mapped: number;
  proposed: boolean;
  params: Params;
  onParam: (key: string, v: ParamValue) => void;
  onReset: () => void;
  scale: number;
  appearance: Appearance;
}) {
  const base = useMemo(() => buildModel(scenario, mapped), [scenario, mapped]);
  const [localSelect, setLocalSelect] = useState<number | null>(null);

  // Selecting a lane inside a phone is a real interaction: it moves the
  // deck to "selected, not confirmed", which is the whole point.
  const model: DeckModel =
    localSelect !== null && localSelect !== base.selected
      ? { ...base, selected: localSelect, confirmed: null, confirmAge: 0, phase: "idle", receipt: null }
      : base;

  const Picker = PICKERS[treatment.key];

  return (
    <div className="flex flex-col gap-3" style={{ width: PHONE.w * scale }}>
      <div className="flex flex-col gap-1.5">
        <div className="flex items-baseline gap-2">
          <span className="font-mono text-[9px] font-semibold tracking-ch text-studio-ink-faint">{treatment.n}</span>
          <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.11em] text-studio-ink">{treatment.name}</span>
        </div>
        <p className="font-display italic" style={{ color: "#6A6A6E", fontSize: 12, lineHeight: 1.45 }}>
          <strong style={{ fontStyle: "normal", color: "#232423", fontSize: 9, letterSpacing: "0.1em" }}>IDEA </strong>
          {treatment.idea}
        </p>
        <p className="font-display italic" style={{ color: "#9A6A5E", fontSize: 12, lineHeight: 1.45 }}>
          <strong style={{ fontStyle: "normal", color: "#B23A2F", fontSize: 9, letterSpacing: "0.1em" }}>FAILS WHEN </strong>
          {treatment.failure}
        </p>
      </div>

      <Phone scale={scale} appearance={appearance}>
        <TopBar model={model} />
        <Picker model={model} params={params} proposed={proposed} select={setLocalSelect} />
        <UtilityGrid />
        <SillRail model={model} />
      </Phone>

      <div className="flex flex-wrap items-center gap-1">
        <span className="mr-1 font-mono text-[8px] font-semibold uppercase tracking-ch text-studio-ink-faint">This phone</span>
        {(["mapped", "confirmed", "listening", "waiting", "approval", "collision"] as ScenarioKey[]).map((s) => (
          <button
            key={s}
            onClick={() => onScenario(s)}
            aria-pressed={scenario === s}
            className={[
              "cdx-focus rounded-[3px] border px-1.5 py-[2px] font-mono text-[8px] uppercase tracking-[0.08em]",
              scenario === s
                ? "border-studio-ink bg-studio-ink text-studio-canvas"
                : "border-studio-edge bg-white text-studio-ink-faint hover:text-studio-ink",
            ].join(" ")}
          >
            {SCENARIO_BY_KEY[s].label}
          </button>
        ))}
      </div>

      <ParamPanel defs={treatment.params} params={params} onParam={onParam} onReset={onReset} />
    </div>
  );
}

function ParamPanel({
  defs, params, onParam, onReset,
}: {
  defs: ParamDef[];
  params: Params;
  onParam: (key: string, v: ParamValue) => void;
  onReset: () => void;
}) {
  return (
    <div className="flex flex-col gap-2.5 rounded-[6px] border border-studio-edge bg-white p-3">
      <div className="flex items-center justify-between">
        <span className="font-mono text-[8.5px] font-semibold uppercase tracking-ch text-studio-ink-faint">Parameters</span>
        <button
          onClick={onReset}
          className="cdx-focus font-mono text-[8.5px] uppercase tracking-ch text-studio-ink-faint underline decoration-dotted hover:text-studio-ink"
        >
          reset
        </button>
      </div>
      {defs.map((d) => (
        <div key={d.key} className="flex flex-col gap-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-mono text-[8.5px] uppercase tracking-[0.08em] text-studio-ink">{d.label}</span>
            {d.kind === "select" && (
              <Seg value={String(params[d.key])} onChange={(v) => onParam(d.key, v)} options={d.options} />
            )}
            {d.kind === "toggle" && (
              <Seg
                value={params[d.key] ? "on" : "off"}
                onChange={(v) => onParam(d.key, v === "on")}
                options={[{ value: "off", label: "off" }, { value: "on", label: "on" }]}
              />
            )}
            {d.kind === "range" && (
              <span className="flex items-center gap-2">
                <input
                  type="range"
                  min={d.min}
                  max={d.max}
                  step={d.step}
                  value={Number(params[d.key])}
                  onChange={(e) => onParam(d.key, Number(e.target.value))}
                  aria-label={d.label}
                  className="cdx-focus h-[3px] w-24 cursor-pointer appearance-none rounded bg-studio-edge accent-studio-ink"
                />
                <span className="font-mono text-[8.5px] text-studio-ink-faint">
                  {Number(params[d.key])}{d.unit ?? ""}
                </span>
              </span>
            )}
          </div>
          {d.help && (
            <span className="font-display italic" style={{ color: "#A0A0A4", fontSize: 11, lineHeight: 1.4 }}>{d.help}</span>
          )}
        </div>
      ))}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Comparison
// ═══════════════════════════════════════════════════════════════════

interface Score {
  key: TreatmentKey;
  switchSpeed: number;
  confidence: number;
  truth: number;
  longTitle: number;
  quiet: number;
  note: string;
}

const SCORES: Score[] = [
  {
    key: "strip", switchSpeed: 3, confidence: 2, truth: 3, longTitle: 1, quiet: 3,
    note: "Fastest to scan and quietest at rest. Collapses on the collision case: one line cannot hold project, a 74-character title and a freshness badge, and the truncation eats the title.",
  },
  {
    key: "expand", switchSpeed: 2, confidence: 3, truth: 3, longTitle: 2, quiet: 2,
    note: "Identity lands where your eye already is. Costs a fixed reserved row to stop the other five from moving — and with the row reserved, the layout is L3 with less room.",
  },
  {
    key: "twotier", switchSpeed: 3, confidence: 3, truth: 3, longTitle: 3, quiet: 2,
    note: "The only treatment that survives every required scenario without a parameter change. Positions never move, the plate has room for project, a two-line title, the exact ID and the freshness word.",
  },
  {
    key: "glyph", switchSpeed: 3, confidence: 2, truth: 1, longTitle: 1, quiet: 1,
    note: "Reads beautifully and reports almost nothing true. Five of six marks can only mean “bound”; with proposed lights on it invents a feed the host does not have.",
  },
  {
    key: "sheet", switchSpeed: 1, confidence: 3, truth: 3, longTitle: 3, quiet: 3,
    note: "Best single-lane experience and the best mapper on-ramp. Punishes alternation, which is exactly what a six-lane deck is for.",
  },
];

const CRITERIA: { key: keyof Omit<Score, "key" | "note">; label: string }[] = [
  { key: "switchSpeed", label: "Lane-switch speed" },
  { key: "confidence", label: "Exact-task confidence" },
  { key: "truth", label: "Truthful reporting" },
  { key: "longTitle", label: "Long-title resilience" },
  { key: "quiet", label: "Low visual noise" },
];

function Dots({ n }: { n: number }) {
  return (
    <span className="font-mono text-[11px]" style={{ color: n >= 3 ? "#2F7D4F" : n === 2 ? "#B07A1F" : "#B23A2F", letterSpacing: "0.12em" }}>
      {"●".repeat(n)}
      <span style={{ color: "#D8D8D6" }}>{"●".repeat(3 - n)}</span>
    </span>
  );
}

function ComparisonMatrix() {
  return (
    <div className="overflow-x-auto rounded-[6px] border border-studio-edge bg-white">
      <table className="w-full min-w-[880px] border-collapse text-left">
        <thead>
          <tr className="border-b border-studio-edge">
            <th className="px-4 py-2.5 font-mono text-[8.5px] font-semibold uppercase tracking-ch text-studio-ink-faint">Treatment</th>
            {CRITERIA.map((c) => (
              <th key={c.key} className="px-3 py-2.5 font-mono text-[8.5px] font-semibold uppercase tracking-ch text-studio-ink-faint">
                {c.label}
              </th>
            ))}
            <th className="px-4 py-2.5 font-mono text-[8.5px] font-semibold uppercase tracking-ch text-studio-ink-faint">Reading</th>
          </tr>
        </thead>
        <tbody>
          {SCORES.map((s) => {
            const t = TREATMENTS.find((x) => x.key === s.key)!;
            const win = s.key === "twotier";
            return (
              <tr key={s.key} className="border-b border-studio-edge/60 last:border-0" style={{ background: win ? "rgba(47,125,79,0.05)" : undefined }}>
                <td className="px-4 py-3 align-top">
                  <div className="font-mono text-[9px] tracking-ch text-studio-ink-faint">{t.n}</div>
                  <div className="font-mono text-[9.5px] font-semibold uppercase leading-tight tracking-[0.08em] text-studio-ink">{t.name}</div>
                </td>
                {CRITERIA.map((c) => (
                  <td key={c.key} className="px-3 py-3 align-top"><Dots n={s[c.key]} /></td>
                ))}
                <td className="max-w-[30ch] px-4 py-3 align-top font-display text-[12px] italic leading-snug" style={{ color: "#6A6A6E" }}>
                  {s.note}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Recommendation
// ═══════════════════════════════════════════════════════════════════

function Recommendation() {
  return (
    <div className="flex flex-col gap-4 rounded-[6px] border p-5" style={{ borderColor: "rgba(47,125,79,0.3)", background: "rgba(47,125,79,0.045)" }}>
      <div className="flex flex-wrap items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-ch" style={{ color: "#2F7D4F" }}>Recommendation</span>
        <span className="font-mono text-[12px] font-semibold uppercase tracking-[0.12em] text-studio-ink">L3 · Two-Tier Identity</span>
        <span className="font-display text-[12.5px] italic" style={{ color: "#6A6A6E" }}>
          six fixed slots over one fixed-height task plate, on the settled T2 rail
        </span>
      </div>

      <div className="grid gap-5 md:grid-cols-2">
        <div className="flex flex-col gap-3">
          <Para title="Why it wins">
            It is the only treatment that clears every required scenario at its default parameters. The six
            positions never move, so switching stays a single blind tap. The plate is tall enough to carry
            project, a two-line title, the exact task ID and a freshness word simultaneously — which is what
            the collision case demands, and what L1 and L4 cannot do at any setting.
          </Para>
          <Para title="What it borrows">
            L2&rsquo;s idea that the selected lane deserves its own pixels, without L2&rsquo;s reflow. L5&rsquo;s sheet is kept,
            demoted to the mapper on-ramp and the &ldquo;more than six&rdquo; overflow rather than the primary switch. L4&rsquo;s
            restraint is kept as a rule, not a layout: an unselected slot may say &ldquo;bound&rdquo; and nothing else.
          </Para>
          <Para title="The freshness question">
            A lock is trusted for {LOCK_FRESHNESS_S}s and then quietly expires. Showing the age turns that into
            information the user can act on, and the rail already says the honest thing when it lapses — it
            confirms on send rather than blocking. Recommend showing the age; recommend never blocking on staleness.
          </Para>
        </div>
        <div className="flex flex-col gap-3">
          <Para title="Ship now, on the current contract">
            The whole of L3 is buildable today. Catalog gives project, title and recency; validate gives the
            authoritative id/title/cwd that the plate renders; submit gives the delivery word; failures arrive
            with the Mac&rsquo;s own recovery sentence. Nothing in the recommended layout waits on the host.
          </Para>
          <Para title="Needs a host extension">
            Only one thing in this study is worth asking the Mac for: a cheap multi-task status read, so a lane can
            show activity before it is selected. Everything else on the proposed list — queue depth, progress, ETA,
            tool names — is either unavailable upstream or would encourage the deck to narrate what it cannot see.
          </Para>
          <Para title="What stays out">
            No approval affordance, ever. Talkie reports that Codex is waiting on one and repeats the fix. The
            deck does not grow an approve button, and no treatment here proposes one.
          </Para>
        </div>
      </div>
    </div>
  );
}

function Para({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="font-mono text-[8.5px] font-semibold uppercase tracking-ch text-studio-ink">{title}</span>
      <p className="max-w-[62ch] font-display italic" style={{ color: "#5A5A5E", fontSize: 12.5, lineHeight: 1.5 }}>{children}</p>
    </div>
  );
}

function ContractSplit() {
  const now = [
    "Project name and task title on the plate, from the catalog and re-folded from every validation.",
    "Exact task ID tail — the identity the whole lane concept rests on.",
    "Confirmed / expired / not-confirmed, with the age of the confirmation.",
    "Voice-loop phase, verbatim from CodexLanePhase.",
    "Delivery receipt word: started, queued, or steered.",
    "Typed failure code plus the Mac's recovery hint, rendered as given.",
    "Your own in-flight count — labelled as yours, never as the host's queue.",
    "Task recency from updatedAt.",
  ];
  const later = [
    "Per-lane activity light for all six slots (idle / active / awaiting-approval).",
    "Queue depth and your position in it.",
    "Progress, ETA, current tool, token usage, execution stage.",
  ];
  return (
    <Section label="Signal boundary" hint="what the recommendation can render today, and the one thing worth asking the Mac for">
      <div className="grid gap-4 md:grid-cols-2">
        <div className="flex flex-col gap-2 rounded-[6px] border border-studio-edge bg-white p-4">
          <div className="flex items-center gap-2">
            <SourceTag source="host" />
            <SourceTag source="phone" />
            <span className="font-mono text-[9px] font-semibold uppercase tracking-ch text-studio-ink">Implementable now</span>
          </div>
          <ul className="flex flex-col gap-1.5 pt-1">
            {now.map((x) => (
              <li key={x} className="font-display text-[12.5px] italic leading-snug" style={{ color: "#5A5A5E" }}>· {x}</li>
            ))}
          </ul>
        </div>
        <div className="flex flex-col gap-2 rounded-[6px] border border-dashed p-4" style={{ borderColor: "rgba(176,122,31,0.5)", background: "rgba(176,122,31,0.04)" }}>
          <div className="flex items-center gap-2">
            <SourceTag source="proposed" />
            <span className="font-mono text-[9px] font-semibold uppercase tracking-ch text-studio-ink">Requires a host API extension</span>
          </div>
          <ul className="flex flex-col gap-1.5 pt-1">
            {later.map((x) => (
              <li key={x} className="font-display text-[12.5px] italic leading-snug" style={{ color: "#5A5A5E" }}>· {x}</li>
            ))}
          </ul>
          <p className="pt-1 font-display text-[12px] italic leading-snug" style={{ color: "#8A6A2E" }}>
            The only one recommended for consideration is the first: a batched status read over known task IDs,
            polled rather than streamed. Without it, L4 cannot be built honestly — which is the finding, not a blocker.
          </p>
        </div>
      </div>
    </Section>
  );
}

function Vocabulary() {
  const rows: [string, string][] = [
    ["LANE", "one of six stable numbered slots, each bound to exactly one Codex task ID"],
    ["BINDING", "the persisted lane → task assignment. Survives launches. Says nothing about ownership."],
    ["CONFIRMATION", "the Mac's answer that it can resume this exact task right now. The only basis for the word EXACT."],
    ["FRESHNESS", `how long a confirmation is trusted — ${LOCK_FRESHNESS_S}s, then it lapses and the next send re-validates`],
    ["LANE CONSOLE", "the bounded, recessed technical field the whole picker lives in. The Codex counterpart to the Deck's trackpad area — one module, not a row of loose controls."],
    ["LANE BED", "the deeper routed pocket inside the console that the lane keys are seated in. Named for the Deck's Key Bed."],
    ["LANE KEY", "one seated bank key — a numbered channel selector. Its material carries the state; its position never moves."],
    ["GROUP SEAM", "the routed groove separating the six lane keys from the mapper key. A divider, not an empty gap."],
    ["TASK READOUT", "the instrument's display: the tier that answers which exact task, and whether that is still true. In L3 it is fixed-height; in L5 it takes the whole field."],
    ["SILKSCREEN", "the printed legend across the console's top edge — module name on the left, current target on the right"],
    ["CONSOLE FOOTER", "the hairline strip that closes the console's bottom edge. Carries the last delivery receipt, or the printed sentence that stands in for one."],
    ["RAIL", `the settled T2 voice control: ${RAIL_W}×${RAIL.h}pt, ${RAIL.inset}pt above the home indicator, never moves`],
    ["DELIVERY", "which route the utterance took — started / queued / steered. Named exactly as CodexTurnDelivery names it."],
    ["HINT", "the Mac's own recovery sentence, travelling with a typed failure code. Repeated, never rewritten."],
  ];
  return (
    <Section label="Names" hint="one vocabulary for studio · Swift · chat">
      <div className="rounded-[6px] border border-studio-edge bg-white px-4 py-3">
        <table className="w-full border-collapse text-left">
          <tbody>
            {rows.map(([k, v]) => (
              <tr key={k} className="border-b border-studio-edge/60 last:border-0">
                <td className="w-[16ch] py-2 pr-4 align-top font-mono text-[9.5px] font-semibold tracking-[0.1em]" style={{ color: "#2F7D4F" }}>{k}</td>
                <td className="py-2 font-display text-[12.5px] italic" style={{ color: "#5A5A5E" }}>{v}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Section>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Status-bar glyphs
// ═══════════════════════════════════════════════════════════════════

function Bars() {
  return (
    <svg width="17" height="11" viewBox="0 0 17 11" fill="none" aria-hidden>
      {[0, 1, 2, 3].map((i) => (
        <rect key={i} x={i * 4.4} y={8 - i * 2.4} width="3" height={3 + i * 2.4} rx="0.8" fill="currentColor" opacity={i === 3 ? 0.35 : 1} />
      ))}
    </svg>
  );
}

function Wifi() {
  return (
    <svg width="15" height="11" viewBox="0 0 15 11" fill="none" aria-hidden>
      <path d="M1 4.2A9 9 0 0114 4.2" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
      <path d="M3.6 6.7a5.4 5.4 0 017.8 0" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
      <circle cx="7.5" cy="9.3" r="1.1" fill="currentColor" />
    </svg>
  );
}

function Batt() {
  return (
    <svg width="24" height="11" viewBox="0 0 24 11" fill="none" aria-hidden>
      <rect x="0.5" y="0.5" width="20" height="10" rx="2.6" stroke="currentColor" strokeWidth="1" opacity="0.5" />
      <rect x="2" y="2" width="13" height="7" rx="1.6" fill="currentColor" />
      <path d="M22 4v3a1.8 1.8 0 000-3z" fill="currentColor" opacity="0.5" />
    </svg>
  );
}
