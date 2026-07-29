"use client";

/**
 * iOS · Codex Deck — Round 3: the Bridge Bar and the Turn Pane.
 *
 * WHAT ROUNDS 1–2 SETTLED, AND STAYS SETTLED HERE:
 *   · T2 · Bottom Sill Rail. 351 × 76pt, 18pt above the home indicator.
 *     The voice control lives outside the grid, in the lowest reachable
 *     band, and never moves. It is a constant in this file (RAIL).
 *   · The instrument depth ladder: chassis → recessed bed → seated key,
 *     and a black-glass readout that is the only screen on the face.
 *     Modelled purely in box-shadow, borrowed from IOSDeck / DeckKeyBed.
 *
 * WHAT THIS ROUND CHANGES:
 *   The upper half now has two jobs it did not have before — jump between
 *   the Codex deck and the regular Command deck, and move between three
 *   paired hosts — and the deck now has real host turn content to show:
 *   the transcript you submitted, a running status, the host's own public
 *   progress updates, and the response. Rounds 1–2 had none of that; the
 *   contract did not exist yet. It does now (see SIGNALS).
 *
 * TWO CORRECTIONS THIS ROUND MAKES:
 *
 *   1. "Three active hosts" cannot be drawn as three live hosts.
 *      BridgeManager.activatePairedMac() disconnects the current bridge
 *      before connecting the next one — exactly one host is ever connected.
 *      The other two are paired and reachable-in-principle, with a
 *      last-selected time and nothing more. A bar with three lit hosts would
 *      be this deck's most legible lie, so the switch is three-wide and one
 *      tap deep, and the state drawn on it is one LIVE and two STANDBY.
 *
 *   2. HOST SWITCHING IS NOT PRODUCTION-READY, AND THIS STUDY SAYS SO.
 *      Verified in CodexLaneStore.swift: lane mappings and the active lane
 *      persist under flat, host-agnostic keys —
 *
 *          static let lanes      = "codex.lanes.v1"
 *          static let activeLane = "codex.lanes.active.v1"
 *
 *      loadPersistedLanes() runs once, in init, and nothing reloads it when
 *      the active Mac changes. A CodexLane binds one EXACT Codex Desktop
 *      task id (CodexLane.swift is explicit that the id is the identity), so
 *      a lane mapped on MINI survives a switch to ARCHIE holding a task id
 *      that does not exist on ARCHIE — and the deck would happily submit to
 *      it. The lane bed is therefore host-local BY REQUIREMENT and only
 *      host-local BY CONTRACT once the store is keyed per paired host.
 *
 *      So the host switch is drawn here as a PROPOSED interaction: the
 *      control is designed, the geometry is settled, and its production
 *      readiness is blocked on a data-contract change stated in full under
 *      "Production blocker" below. The `lane scope` parameter shows both
 *      worlds — today's global keying (which goes stale, visibly) and the
 *      required host-keyed contract (which does not).
 *
 * Grounded in, and not ahead of:
 *   apps/macos/TalkieServer/src/bridge/routes/codex.ts   (turn jobs, updates)
 *   apps/ios/Talkie iOS/Bridge/BridgeClient.swift        (CodexTurnJob shape)
 *   apps/ios/Talkie iOS/Bridge/BridgeManager.swift       (pairedMacs, activate)
 *   apps/ios/Talkie iOS/Codex/CodexLaneActivity.swift    (instruction, updates)
 *   apps/ios/Talkie iOS/Codex/CodexLaneStore.swift       (per-lane live turns,
 *                                                         host-agnostic keys)
 *   apps/ios/Talkie iOS/Codex/CodexLane.swift            (exact task id = identity)
 *
 * NOT IN SCOPE. No Swift is written here.
 */

import { useCallback, useMemo, useState } from "react";

// ═══════════════════════════════════════════════════════════════════
// The frozen spine — every number here is a constant, not a layout result
//
// SPATIAL THESIS. Three bands never move in any state: the Bridge Bar at
// the top, the Lane Bed under it, and the Rail at the bottom. Everything
// the host says lands in the single pane between the Lane Bed and the
// Rail, and that pane is the only element allowed to change height. It
// grows downward, borrowing rows from the utility grid, because during a
// turn the grid is context and the turn is the subject. A thumb that has
// learned where HOST 2 and LANE 3 are keeps that memory through idle,
// working, streaming, failure and host switch alike.
// ═══════════════════════════════════════════════════════════════════

const PHONE = { w: 375, h: 812 }; // iPhone 13 mini, points
const GUTTER = 12;
const CONTENT_W = PHONE.w - GUTTER * 2; // 351

const STATUS_H = 47;
const MAST_H = 40;

/** T2 · Bottom Sill Rail. Settled in round 1. These do not vary. */
const RAIL = { h: 76, inset: 18 };
const RAIL_TOP = PHONE.h - RAIL.inset - RAIL.h; // 718

/** Band 1 — the Bridge Bar. Top is frozen; only its height is a dial. */
const BRIDGE_TOP = STATUS_H + MAST_H; // 87
const BRIDGE_PAD = 4;

/** Band 2 — the Lane Bed. */
const LANE_KEY_H = 40;
const LANE_BED_H = LANE_KEY_H + 8;

/** Band 4 — the utility grid, bottom-anchored above the rail. */
const GRID_GAP = 9;
const GRID_ROW_H = 91;
const GRID_BOTTOM = RAIL_TOP - 12; // 706

const BAND_GAP = 8;
const PANE_GAP = 12;

/** Modelled right-thumb pivot reach, stated once so the top-band cost is explicit. */
const reach = (y: number) => Math.round(Math.hypot(PHONE.w / 2 - 330, y - PHONE.h));
const RAIL_REACH = reach(RAIL_TOP + RAIL.h / 2);
const BRIDGE_REACH = reach(BRIDGE_TOP + 20);

/**
 * Vertical solve. Bridge height and borrowed grid rows are the only two
 * inputs; everything else falls out. Nothing above the pane moves when
 * the pane grows, which is the whole point.
 */
function solve(bridgeKeyH: number, borrowedRows: number) {
  const bridgeH = bridgeKeyH + BRIDGE_PAD * 2;
  const bedTop = BRIDGE_TOP + bridgeH + BAND_GAP;
  const paneTop = bedTop + LANE_BED_H + BAND_GAP;
  const gridRows = Math.max(0, 3 - borrowedRows);
  const gridH = gridRows === 0 ? 0 : gridRows * GRID_ROW_H + (gridRows - 1) * GRID_GAP;
  const gridTop = GRID_BOTTOM - gridH;
  const paneH = (gridRows === 0 ? GRID_BOTTOM : gridTop - PANE_GAP) - paneTop;
  return { bridgeH, bedTop, paneTop, paneH, gridTop, gridH, gridRows };
}

const REST = solve(36, 0);

// ═══════════════════════════════════════════════════════════════════
// Truth boundary — enumerated, because the deck is only worth trusting
// if it never draws a signal the Mac does not send.
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
    note: "Derived on device. True about Talkie — not necessarily about Codex.",
  },
  proposed: {
    label: "PROPOSED",
    ink: "#B07A1F",
    rim: "rgba(176,122,31,0.6)",
    note: "Would require a host API extension. Off by default, drawn dashed.",
  },
};

interface SignalRow {
  source: Source;
  name: string;
  detail: string;
  from: string;
  /** New since round 2 — the reason this round can show turn content at all. */
  fresh?: boolean;
  /** Ships-blocking. Host switching cannot go to production without this. */
  blocker?: boolean;
}

const SIGNALS: SignalRow[] = [
  { source: "host", name: "Turn job status", detail: "queued · running · completed · failed", from: "GET /codex/turns/:id", fresh: true },
  { source: "host", name: "Public progress updates", detail: "ordered { kind: commentary | tool, text } — best-effort, may be empty", from: "job.updates", fresh: true },
  { source: "host", name: "Final response", detail: "the whole answer, once — arrives complete at completion", from: "job.response", fresh: true },
  { source: "host", name: "Delivery outcome", detail: "started-turn · queued-turn · steered-active-turn, plus turnId", from: "job.delivery" },
  { source: "host", name: "Typed failure + recovery hint", detail: "code plus the Mac's own sentence about how to fix it", from: "job.code · RECOVERY_HINTS" },
  { source: "host", name: "Task catalog", detail: "exact id · title · cwd · updatedAt", from: "GET /codex/tasks" },
  { source: "phone", name: "Submitted transcript", detail: "the exact sentence this device sent — held locally, never echoed back", from: "CodexLaneActivity.instruction", fresh: true },
  { source: "phone", name: "Per-lane live turn", detail: "which lanes have a turn THIS PHONE started and is still polling", from: "liveActivityByLane", fresh: true },
  { source: "phone", name: "Paired hosts & active host", detail: "the list, which one is active, and when each was last selected", from: "BridgeManager.pairedMacs", fresh: true },
  { source: "phone", name: "Bridge connectivity", detail: "connected / disconnected — for the active host only", from: "BridgeManager.status" },
  { source: "phone", name: "Lane bindings & selection", detail: "six persisted slots; which one is selected — persisted GLOBALLY, not per host", from: "CodexLaneStore.lanes" },
  { source: "proposed", name: "Host-scoped lane mappings", detail: "which host a lane's task id belongs to — today nothing records this, so a switch leaves stale ids in place", from: "keys are codex.lanes.v1 · codex.lanes.active.v1", blocker: true },
  { source: "proposed", name: "Standby host liveness", detail: "is host 2 actually up right now, without switching to it", from: "needs a per-host health poll" },
  { source: "proposed", name: "Token-streamed response", detail: "the answer arriving progressively rather than whole", from: "job.response is atomic" },
  { source: "proposed", name: "Turns started elsewhere", detail: "a lane busy because someone typed into Codex Desktop directly", from: "not exposed" },
  { source: "proposed", name: "Queue depth · position · ETA · tokens", detail: "anything quantitative about progress inside a turn", from: "not exposed" },
];

// ═══════════════════════════════════════════════════════════════════
// Model
// ═══════════════════════════════════════════════════════════════════

/** Exactly one host is connected. The other two are paired, not live. */
type HostState = "live" | "standby" | "connecting" | "unreachable";

interface Host {
  n: number;
  name: string;
  fqdn: string;
  /** Seconds since this host was last the active one. PHONE-derived. */
  lastSelected: number;
  state: HostState;
}

const HOSTS: Host[] = [
  { n: 1, name: "MINI", fqdn: "arachs-mac-mini.local", lastSelected: 0, state: "live" },
  { n: 2, name: "ARCHIE", fqdn: "archie.local", lastSelected: 840, state: "standby" },
  { n: 3, name: "STUDIO", fqdn: "studio.local", lastSelected: 191_000, state: "standby" },
];

type DeckMode = "codex" | "command";

interface Lane {
  n: number;
  title: string;
  project: string;
}

/**
 * Lane sets are HOST-LOCAL. A lane binds one exact Codex Desktop task id, and
 * task ids live on one Mac — so three paired hosts mean three different lane
 * beds, not one bed viewed through three connections. This is the fact the
 * production store does not yet encode.
 */
const LANES_BY_HOST: Record<number, Lane[]> = {
  1: [
    { n: 1, title: "Bridge reconnect backoff", project: "talkie" },
    { n: 2, title: "Command deck lane mapper", project: "talkie" },
    { n: 3, title: "Codex Desktop adapter — follower IPC ownership checks and rollout tailing", project: "talkie-codex-command-deck" },
    { n: 4, title: "Release notes", project: "scout" },
    { n: 5, title: "Release notes", project: "openscout" },
    { n: 6, title: "Marketing site copy", project: "arach.dev" },
  ],
  2: [
    { n: 1, title: "Parakeet long-session drift", project: "talkie-engine" },
    { n: 2, title: "Sync conflict resolver", project: "talkie" },
    { n: 4, title: "Notarization pipeline", project: "talkie" },
  ],
  3: [
    { n: 1, title: "Studio token export", project: "talkie" },
    { n: 3, title: "Deck material grammar", project: "talkie" },
  ],
};

const LANES = LANES_BY_HOST[1];

type UpdateKind = "commentary" | "tool";

interface ProgressUpdate {
  id: string;
  kind: UpdateKind;
  text: string;
}

/** Mirrors CodexTurnJobStatus, plus the pre-job moment the phone owns alone. */
type TurnStatus = "sending" | "queued" | "running" | "completed" | "failed";
type DeliveryMode = "queue" | "steer";

interface Turn {
  lane: number;
  /** PHONE. The exact sentence this device submitted. */
  transcript: string;
  status: TurnStatus;
  mode: DeliveryMode;
  updates: ProgressUpdate[];
  response: string | null;
  delivery: "started-turn" | "queued-turn" | "steered-active-turn" | null;
  turnId: string | null;
  failure: { code: string; hint: string } | null;
  /** Seconds since submit. PHONE clock, honest — not an ETA. */
  elapsed: number;
}

interface DeckModel {
  mode: DeckMode;
  hosts: Host[];
  activeHost: number;
  bridge: boolean;
  lanes: Lane[];
  /**
   * Which host the loaded lane set was actually mapped against. Under today's
   * global keying this stays pinned to whichever Mac last ran the mapper, so
   * it can disagree with activeHost — and that disagreement is the bug.
   */
  laneHost: number;
  selected: number;
  /** Turns THIS PHONE started and is still polling, keyed by lane. */
  turns: Turn[];
  /** True while activatePairedMac() has torn down one bridge and not yet built the next. */
  switching: boolean;
}

/** Lane bindings are trustworthy only when they were mapped on the connected host. */
function laneScopeStale(m: DeckModel): boolean {
  return m.laneHost !== m.activeHost;
}

const TRANSCRIPT =
  "Check whether the follower ever holds IPC ownership after the rollout tail closes early, and fix it if so.";

const UPDATES: ProgressUpdate[] = [
  { id: "u1", kind: "tool", text: "read apps/macos/TalkieServer/src/bridge/adapter/follower.ts" },
  { id: "u2", kind: "commentary", text: "The follower keeps IPC ownership when the rollout tail closes before the turn resolves." },
  { id: "u3", kind: "tool", text: "apply_patch follower.ts" },
  { id: "u4", kind: "commentary", text: "Re-running the adapter suite to confirm ownership is released on the early-close path." },
];

const RESPONSE =
  "Confirmed and fixed. The follower released IPC ownership only on the normal completion path, so an early rollout-tail close left the channel owned and the next turn inherited a dead adapter. releaseOwnership() now runs in a defer block and the tail close is idempotent. Adapter suite passes, including the new early-close case.";

const BASE_TURN: Omit<Turn, "status"> = {
  lane: 3,
  transcript: TRANSCRIPT,
  mode: "queue",
  updates: [],
  response: null,
  delivery: null,
  turnId: null,
  failure: null,
  elapsed: 0,
};

const BASE: Omit<DeckModel, "turns"> = {
  mode: "codex",
  hosts: HOSTS,
  activeHost: 1,
  bridge: true,
  lanes: LANES,
  laneHost: 1,
  selected: 3,
  switching: false,
};

type ScenarioKey =
  | "idle"
  | "sending"
  | "queued"
  | "working"
  | "progress"
  | "responded"
  | "failed"
  | "elsewhere"
  | "switching"
  | "stale"
  | "switched"
  | "offline";

interface Scenario {
  key: ScenarioKey;
  label: string;
  note: string;
  build: () => DeckModel;
}

const SCENARIOS: Scenario[] = [
  {
    key: "idle",
    label: "Idle",
    note: "Connected host, a lane selected, nothing in flight. The pane says what it is pointed at and nothing else.",
    build: () => ({ ...BASE, turns: [] }),
  },
  {
    key: "sending",
    label: "Sending",
    note: "The phone has the transcript; the host has not answered with a job id yet. Everything on screen is PHONE truth.",
    build: () => ({ ...BASE, turns: [{ ...BASE_TURN, status: "sending", elapsed: 1 }] }),
  },
  {
    key: "queued",
    label: "Queued",
    note: "Job accepted, status queued. The host has it and has not started it. There is no queue position to show, so none is shown.",
    build: () => ({ ...BASE, turns: [{ ...BASE_TURN, status: "queued", turnId: "trn_9F2", elapsed: 4 }] }),
  },
  {
    key: "working",
    label: "Working · no updates yet",
    note: "status=running and updates is empty. The honest report is that it started and has said nothing. This is the shimmer state — the only place motion is earned.",
    build: () => ({ ...BASE, turns: [{ ...BASE_TURN, status: "running", turnId: "trn_9F2", elapsed: 19 }] }),
  },
  {
    key: "progress",
    label: "Streaming updates",
    note: "status=running with four public updates. They arrive by poll, in order, and are best-effort — the snapshot can fail without the turn failing.",
    build: () => ({ ...BASE, turns: [{ ...BASE_TURN, status: "running", turnId: "trn_9F2", updates: UPDATES, elapsed: 74 }] }),
  },
  {
    key: "responded",
    label: "Response landed",
    note: "status=completed. The response arrives whole, in one poll — it does not stream in. The pane must not pretend otherwise.",
    build: () => ({
      ...BASE,
      turns: [{ ...BASE_TURN, status: "completed", turnId: "trn_9F2", updates: UPDATES, response: RESPONSE, delivery: "started-turn", elapsed: 118 }],
    }),
  },
  {
    key: "failed",
    label: "Blocked on approval",
    note: "Talkie never approves a Codex action. It reports the typed code and repeats the Mac's own recovery sentence.",
    build: () => ({
      ...BASE,
      turns: [{
        ...BASE_TURN,
        status: "failed",
        turnId: "trn_9F2",
        updates: UPDATES.slice(0, 2),
        elapsed: 46,
        failure: { code: "approval-required", hint: "Open this task in Codex Desktop to review the approval request." },
      }],
    }),
  },
  {
    key: "elsewhere",
    label: "Turn running, viewing another lane",
    note: "A turn is live on lane 3 while lane 5 is selected. Switching lanes mid-turn is allowed and costs nothing — the poll is per-lane and keeps running.",
    build: () => ({
      ...BASE,
      selected: 5,
      turns: [{ ...BASE_TURN, status: "running", turnId: "trn_9F2", updates: UPDATES.slice(0, 3), elapsed: 61 }],
    }),
  },
  {
    key: "switching",
    label: "Switching host",
    note: "activatePairedMac() disconnected MINI and is connecting ARCHIE. The lane bed belongs to the old host and is honestly dark until the new catalog answers.",
    build: () => ({ ...BASE, activeHost: 2, bridge: false, switching: true, turns: [] }),
  },
  {
    key: "stale",
    label: "Stale mapping (today)",
    note: "PRODUCTION BUG, drawn as it is. ARCHIE is connected but the lane bed still holds MINI's mappings, because codex.lanes.v1 has no host in the key. Every task id in this bed belongs to another Mac. The deck must refuse to submit.",
    build: () => ({ ...BASE, activeHost: 2, laneHost: 1, lanes: LANES_BY_HOST[1], bridge: true, turns: [] }),
  },
  {
    key: "switched",
    label: "Host-keyed reload (required)",
    note: "The contract this study asks for. Switching to ARCHIE loaded ARCHIE's own three lanes atomically; MINI's six are untouched and waiting. Lane 3 is genuinely unbound here — that is a real answer, not a gap.",
    build: () => ({ ...BASE, activeHost: 2, laneHost: 2, lanes: LANES_BY_HOST[2], selected: 2, bridge: true, turns: [] }),
  },
  {
    key: "offline",
    label: "Host unavailable",
    note: "Bindings survive a dead bridge; confidence does not. Nothing may be drawn as live.",
    build: () => ({ ...BASE, bridge: false, turns: [] }),
  },
];

const SCENARIO_BY_KEY = Object.fromEntries(SCENARIOS.map((s) => [s.key, s])) as Record<ScenarioKey, Scenario>;

function turnFor(m: DeckModel, lane: number): Turn | null {
  return m.turns.find((t) => t.lane === lane) ?? null;
}
function laneFor(m: DeckModel, n: number): Lane | null {
  return m.lanes.find((l) => l.n === n) ?? null;
}
function hostFor(m: DeckModel): Host | null {
  return m.hosts.find((h) => h.n === m.activeHost) ?? null;
}

/** Effective host state — derived, never asserted. */
function hostStateOf(m: DeckModel, h: Host, probeAll: boolean): HostState {
  if (h.n === m.activeHost) {
    if (m.switching) return "connecting";
    return m.bridge ? "live" : "unreachable";
  }
  return probeAll ? h.state : "standby";
}

function ago(s: number): string {
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.round(s / 60)}m`;
  if (s < 86_400) return `${Math.round(s / 3600)}h`;
  return `${Math.round(s / 86_400)}d`;
}

// ═══════════════════════════════════════════════════════════════════
// Parameters
// ═══════════════════════════════════════════════════════════════════

type ParamValue = string | number | boolean;
type Params = Record<string, ParamValue>;

type ParamDef =
  | { key: string; label: string; kind: "opt"; options: { value: ParamValue; label: string }[]; note?: string }
  | { key: string; label: string; kind: "bool"; note?: string };

const str = (p: Params, k: string) => String(p[k]);
const num = (p: Params, k: string) => Number(p[k]);
const bool = (p: Params, k: string) => Boolean(p[k]);

/** Shared across all three treatments — the dials the brief actually asks about. */
const COMMON_PARAMS: ParamDef[] = [
  {
    key: "laneScope", label: "lane scope", kind: "opt",
    options: [{ value: "global", label: "global · today" }, { value: "hostKeyed", label: "host-keyed · required" }],
    note: "Today CodexLaneStore persists lanes under codex.lanes.v1 with no host in the key, so switching hosts carries stale task ids forward. Switch a host in these frames and watch the bed.",
  },
  {
    key: "keyH", label: "bridge target height", kind: "opt",
    options: [{ value: 32, label: "32 · tightest" }, { value: 36, label: "36 · default" }, { value: 44, label: "44 · HIG" }],
    note: "The top band's real cost. 44 is the Apple minimum and eats 8pt from the pane.",
  },
  {
    key: "grow", label: "pane growth in flight", kind: "opt",
    options: [{ value: 0, label: "fixed" }, { value: 1, label: "+1 grid row" }, { value: 2, label: "+2 grid rows" }],
    note: "The only element allowed to change height, and it only grows downward.",
  },
  {
    key: "transcript", label: "submitted transcript", kind: "opt",
    options: [{ value: 1, label: "1 line" }, { value: 2, label: "2 lines" }, { value: 0, label: "full" }],
    note: "PHONE truth. What you said is the one thing the deck always knows.",
  },
  {
    key: "updates", label: "progress updates", kind: "opt",
    options: [{ value: "latest", label: "latest only" }, { value: "last3", label: "last 3" }, { value: "all", label: "all · scroll" }],
  },
  { key: "kindMarks", label: "mark tool vs commentary", kind: "bool", note: "job.updates carries kind. Showing it separates what Codex did from what it said." },
  {
    key: "hostLine", label: "host identity", kind: "opt",
    options: [{ value: "name", label: "name" }, { value: "seen", label: "name + last seen" }, { value: "num", label: "number + name" }],
  },
  { key: "reachStepper", label: "in-reach host stepper", kind: "bool", note: "Duplicates prev/next host beside the rail. Maps to activateAdjacentPairedMac(offset:)." },
  { key: "probeAll", label: "PROPOSED · probe standby hosts", kind: "bool", note: "Draws liveness for hosts we are not connected to. Needs a host API that does not exist." },
];

const COMMON_DEFAULTS: Params = {
  laneScope: "global", keyH: 36, grow: 1, transcript: 1, updates: "last3",
  kindMarks: true, hostLine: "seen", reachStepper: false, probeAll: false,
};

type TreatmentKey = "unified" | "altitude" | "hostfirst";

interface Treatment {
  key: TreatmentKey;
  name: string;
  bar: string;
  pane: string;
  thesis: string;
  cost: string;
  params: ParamDef[];
  defaults: Params;
}

const TREATMENTS: Treatment[] = [
  {
    key: "unified",
    name: "T1 · Unified Bar · Transcript Stack",
    bar: "One bed, two seated groups: deck mode, group seam, three hosts. Five fixed targets in one band.",
    pane: "One scrolling column in strict chronology — you said, then status, then each update, then the response.",
    thesis:
      "Both switches are the same kind of act — “change what the next sentence lands in” — so they belong in one bed, divided by a routed seam rather than by distance. The pane mirrors that literalism: time runs down the glass, exactly once.",
    cost: "Five targets across 343pt means the narrowest key is 58pt wide, and the column reflows every time an update arrives.",
    params: [
      { key: "seam", label: "group divider", kind: "opt", options: [{ value: "seam", label: "routed seam" }, { value: "gap", label: "gap" }], note: "The deck's own convention is a machined groove, not absence." },
      { key: "anchor", label: "column anchor", kind: "opt", options: [{ value: "bottom", label: "newest at bottom" }, { value: "top", label: "newest at top" }] },
    ],
    defaults: { ...COMMON_DEFAULTS, seam: "seam", anchor: "bottom" },
  },
  {
    key: "altitude",
    name: "T2 · Masthead Mode · Host Bed",
    bar: "Deck mode becomes a two-position tab inside the masthead. The whole bed below belongs to three hosts, ~111pt each.",
    pane: "A pinned header carries the transcript and status; the glass below is a live channel that updates scroll through and the response replaces.",
    thesis:
      "Mode and host are different altitudes. Which deck you are on is an app-level fact and belongs in the masthead, where app-level facts already live; which host you are pointed at is an instrument setting and deserves the whole bed. Separating them buys the largest, most legible host targets on offer.",
    cost: "Mode moves into the least reachable band on the phone and gets the smallest targets in the study.",
    params: [
      { key: "mastStyle", label: "masthead mode", kind: "opt", options: [{ value: "tabs", label: "two tabs" }, { value: "rocker", label: "rocker" }], note: "A rocker is smaller still; a tab pair says where you are." },
      { key: "hostSub", label: "host key sub-line", kind: "bool", note: "111pt of width is enough to say more than a name." },
    ],
    defaults: { ...COMMON_DEFAULTS, mastStyle: "tabs", hostSub: true },
  },
  {
    key: "hostfirst",
    name: "T3 · Host Bed · Mode Key · Two-Register Pane",
    bar: "One bed of four: a single mode key naming the deck you would go to, then three hosts at ~95pt.",
    pane: "Two registers that never reflow. Upper is fixed — transcript and status. Lower switches between the newest update and the response.",
    thesis:
      "Maximum spatial stability, bought by giving up scrollback. Nothing in the pane ever changes height or position; only the text inside two fixed registers is replaced. History is real, so it goes where history already lives — the turn history sheet — instead of pushing the layout around.",
    cost: "A mode key that names its destination hides where you currently are, and the pane forgets everything but the newest line.",
    params: [
      { key: "modeKey", label: "mode key reads", kind: "opt", options: [{ value: "dest", label: "destination · → CMD" }, { value: "here", label: "current · CODEX" }] },
      { key: "lower", label: "lower register when running", kind: "opt", options: [{ value: "latest", label: "newest update" }, { value: "count", label: "newest + count" }] },
    ],
    defaults: { ...COMMON_DEFAULTS, updates: "latest", modeKey: "dest", lower: "count" },
  },
];

// ═══════════════════════════════════════════════════════════════════
// Study
// ═══════════════════════════════════════════════════════════════════

export function CodexDeckBridgeBarStudy() {
  const [scenario, setScenario] = useState<ScenarioKey>("progress");
  const [scale, setScale] = useState(0.72);
  const [appearance, setAppearance] = useState<Appearance>("dark");
  const [params, setParams] = useState<Record<TreatmentKey, Params>>(
    () => Object.fromEntries(TREATMENTS.map((t) => [t.key, { ...t.defaults }])) as Record<TreatmentKey, Params>,
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

  return (
    <div className="flex flex-col gap-11">
      <MotionStyles />
      <Thesis />
      <ProductionBlocker />
      <SpineDiagram />

      <Section label="Signal sources" hint="what the Mac sends today, what the phone infers, and what nobody has yet">
        <SignalLegend />
      </Section>

      <GlobalBar
        scenario={scenario}
        onScenario={(s) => { setScenario(s); setOverrides({}); }}
        scale={scale}
        onScale={setScale}
        appearance={appearance}
        onAppearance={setAppearance}
      />

      <Section
        label="Three structural treatments"
        hint="identical rail, identical frozen spine — the variables are how the top band divides and how the pane organises a turn"
      >
        <div className="flex flex-wrap gap-7">
          {TREATMENTS.map((t) => (
            <TreatmentCard
              key={t.key}
              treatment={t}
              scenario={overrides[t.key] ?? scenario}
              onScenario={(s) => setOverrides((prev) => ({ ...prev, [t.key]: s }))}
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
 * The study's only authored motion. A shimmer on the status line while a
 * turn is running and has said nothing, and a slow pulse on the rail's
 * live dot. Everything else is static on purpose.
 */
function MotionStyles() {
  return (
    <style>{`
      @keyframes cdbLive { 0%,100% { opacity: 1 } 50% { opacity: 0.28 } }
      @keyframes cdbShimmer { 0% { background-position: -140% 0 } 100% { background-position: 240% 0 } }
      .cdb-live { animation: cdbLive 1.25s ease-in-out infinite; }
      .cdb-shimmer {
        background-image: linear-gradient(100deg, transparent 34%, rgba(242,161,59,0.55) 50%, transparent 66%);
        background-size: 220% 100%;
        background-repeat: no-repeat;
        -webkit-background-clip: text;
        background-clip: text;
        animation: cdbShimmer 2.1s linear infinite;
      }
      @media (prefers-reduced-motion: reduce) {
        .cdb-live { animation: none; opacity: 0.85 }
        .cdb-shimmer { animation: none; background-image: none; }
      }
      .cdb-focus:focus-visible { outline: 2px solid #FF8800; outline-offset: 2px; }
    `}</style>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Chrome
// ═══════════════════════════════════════════════════════════════════

function Thesis() {
  return (
    <div className="flex flex-col gap-3">
      <p className="max-w-[78ch] font-display italic" style={{ color: "#5A5A5E", fontSize: 14, lineHeight: 1.55 }}>
        <strong style={{ fontStyle: "normal", color: "#232423" }}>Spatial thesis — one frozen spine, one growing pane.</strong>{" "}
        Three bands never move, in any state: the Bridge Bar at the top, the Lane Bed under it, and the
        settled Rail at the bottom. Their y-positions are constants in this file, not results of layout.
        Everything the host says — the transcript you submitted, the working state, the public progress
        updates, the response — lands in the single pane between the Lane Bed and the Rail, and that pane
        is the only element permitted to change height. It grows <em>downward</em>, borrowing rows from the
        utility grid, because during a turn the grid is context and the turn is the subject. A thumb that
        has learned where <em>host 2</em> and <em>lane 3</em> are keeps that memory through idle, working,
        streaming, failure and host switch alike.
      </p>
      <p className="max-w-[78ch] font-display italic" style={{ color: "#5A5A5E", fontSize: 14, lineHeight: 1.55 }}>
        The correction this round makes is about the word <em>active</em>.{" "}
        <code style={{ fontStyle: "normal", fontSize: 12.5 }}>BridgeManager.activatePairedMac()</code>{" "}
        disconnects the current bridge before it connects the next one, so exactly one host is ever
        connected. Three paired hosts, one live, two standby with a last-selected time and nothing more.
        The switch is still three-wide and one tap deep — but a bar with three lit hosts would be the most
        legible lie this deck could tell, so it does not draw one. Probing the other two is a real, cheap,
        useful host extension, and it is here as a{" "}
        <strong style={{ fontStyle: "normal", color: "#232423" }}>PROPOSED</strong> dial, dashed and off.
      </p>
      <p className="max-w-[78ch] font-display italic" style={{ color: "#5A5A5E", fontSize: 14, lineHeight: 1.55 }}>
        And the lane bed is <em>host-local</em>, which the deck must show even though the store does not
        yet enforce it. A lane binds one exact Codex Desktop task id; task ids live on one Mac; so three
        paired hosts mean three different beds, not one bed seen through three connections. MINI has six
        lanes here, ARCHIE three, STUDIO two — and lane 3 being empty on ARCHIE is a true answer, not a
        gap. Today&rsquo;s store keys lanes globally, so a switch carries the wrong bed forward; the
        control is therefore drawn as{" "}
        <strong style={{ fontStyle: "normal", color: "#232423" }}>PROPOSED</strong>, and the requirements
        to un-propose it are stated below.
      </p>
      <p className="max-w-[78ch] font-display italic" style={{ color: "#8A8A8E", fontSize: 12.5, lineHeight: 1.5 }}>
        Ergonomic honesty: the rail centre sits ~{RAIL_REACH}pt from a right thumb&rsquo;s pivot — the natural
        band. The Bridge Bar sits ~{BRIDGE_REACH}pt away, which is a stretch, and no amount of styling changes
        that. It is placed there deliberately: mode and host are switches you throw <em>between</em> bursts of
        work, not during one, and the band that is bad for the thumb is the band that is best for
        never-moving reference. The cost is paid back with a parameterised in-reach stepper beside the rail,
        mapping to the real{" "}
        <code style={{ fontStyle: "normal", fontSize: 12.5 }}>activateAdjacentPairedMac(offset:)</code>.
      </p>
    </div>
  );
}

/**
 * The one thing in this study that is not a design question. Stated at the
 * top, before the treatments, because no arrangement of keys fixes it.
 */
function ProductionBlocker() {
  const req: [string, string][] = [
    ["Key lane mappings by paired host", "codex.lanes.v1 → codex.lanes.v2.<pairedMacID>. A binding is only meaningful next to the Mac whose task id it holds."],
    ["Key the active lane by paired host", "codex.lanes.active.v1 → the same per-host namespace. Selection is per bed, and there is one bed per host."],
    ["Reload atomically on host change", "activatePairedMac() must swap bindings and connection in one step. There must be no window in which activeHost and the loaded lane set disagree."],
    ["Invalidate in-flight lane activity", "liveActivityByLane polls jobs on the Mac we just left. Detach or drop it on switch; do not carry job ids across hosts."],
    ["Fail closed on any mismatch", "If a loaded lane set cannot be attributed to the connected host, refuse to submit and say why. Silence here means speaking into the wrong conversation."],
    ["Revalidate task ids after reload", "refreshCatalog() already exists. Run it on switch and mark lanes whose task id is gone rather than leaving them looking bound."],
  ];
  return (
    <Section label="Production blocker" hint="host switching is designed here, and is not shippable yet">
      <div className="flex flex-col gap-3 rounded-[8px] bg-white px-5 py-4" style={{ border: "0.5px solid rgba(176,60,52,0.4)", boxShadow: "inset 3px 0 0 rgba(176,60,52,0.55)" }}>
        <div className="flex flex-wrap items-baseline gap-2.5">
          <span className="rounded-[2px] px-1.5 py-[2px] font-mono text-[8px] font-bold uppercase tracking-[0.16em]" style={{ color: "#B03C34", border: "0.5px solid rgba(176,60,52,0.5)" }}>
            BLOCKED
          </span>
          <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.1em] text-stone-700">
            Lane state is global, not host-scoped
          </span>
        </div>
        <p style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.55, margin: 0 }}>
          PR review turned this up and the source confirms it.{" "}
          <code style={{ fontSize: 12 }}>CodexLaneStore</code> persists lane mappings under{" "}
          <code style={{ fontSize: 12 }}>&quot;codex.lanes.v1&quot;</code> and the active lane under{" "}
          <code style={{ fontSize: 12 }}>&quot;codex.lanes.active.v1&quot;</code> — flat keys with no paired-host
          component. <code style={{ fontSize: 12 }}>loadPersistedLanes()</code> runs once in{" "}
          <code style={{ fontSize: 12 }}>init</code>, and nothing reloads it when the active Mac changes.
          A <code style={{ fontSize: 12 }}>CodexLane</code> binds one <em>exact</em> Codex Desktop task id
          — the file says so in its own header — so switching hosts leaves the bed pointing at ids that
          belong to the Mac you just left, and the deck will submit to them.
        </p>
        <p style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.55, margin: 0 }}>
          <strong style={{ color: "#232423" }}>What this means for the study.</strong> The host switch is
          drawn as a <strong style={{ color: "#232423" }}>PROPOSED</strong> interaction: the geometry is
          settled and the control is worth building, but it must not ship until the contract below is met.
          Nothing in these frames should be read as a claim that switching is currently safe. The host
          group wears a dashed rim for exactly as long as{" "}
          <code style={{ fontSize: 12 }}>lane scope</code> is set to <em>global</em>, and the{" "}
          <em>Stale mapping (today)</em> state shows what a switch actually produces right now — a red
          bed, a disabled rail, and the deck refusing to speak. Set{" "}
          <code style={{ fontSize: 12 }}>lane scope</code> to <em>host-keyed</em> and switch a host in any
          frame to see the behaviour the contract buys: MINI&rsquo;s six lanes, ARCHIE&rsquo;s three,
          STUDIO&rsquo;s two, each loaded atomically with its own bridge.
        </p>
        <div className="grid" style={{ gridTemplateColumns: "236px 1fr", rowGap: 7, columnGap: 16 }}>
          {req.map(([name, detail]) => (
            <div key={name} className="contents">
              <span className="font-mono text-[9.5px] font-semibold tracking-[0.03em] text-stone-700">{name}</span>
              <span style={{ fontSize: 11.5, color: "#4A4A4A", lineHeight: 1.42 }}>{detail}</span>
            </div>
          ))}
        </div>
        <p style={{ fontSize: 11.5, color: "#6A6A6E", lineHeight: 1.45, margin: 0 }}>
          Owner: whoever lands the <code style={{ fontSize: 11.5 }}>CodexLaneStore</code> change. This
          study is Studio-only and writes no Swift — the requirements above are stated for that work, not
          performed by it.
        </p>
      </div>
    </Section>
  );
}

const BANDS: { name: string; detail: string; frozen: boolean }[] = [
  { name: "Status", detail: `${STATUS_H}pt`, frozen: true },
  { name: "Masthead", detail: `${MAST_H}pt · T2 puts deck mode here`, frozen: true },
  { name: "Bridge Bar", detail: `top ${BRIDGE_TOP} · height ${REST.bridgeH} (dial: 40 / 44 / 52)`, frozen: true },
  { name: "Lane Bed", detail: `top ${REST.bedTop} · height ${LANE_BED_H} · six ${LANE_KEY_H}pt keys`, frozen: true },
  { name: "Turn Pane", detail: `top ${REST.paneTop} · height ${REST.paneH} at rest, ${solve(36, 2).paneH} at full growth`, frozen: false },
  { name: "Utility Grid", detail: "bottom-anchored · lends rows to the pane", frozen: false },
  { name: "Rail", detail: `top ${RAIL_TOP} · ${CONTENT_W}×${RAIL.h} · settled in round 1`, frozen: true },
];

function SpineDiagram() {
  return (
    <Section label="The frozen spine" hint="what is a constant, and what is allowed to move">
      <div className="grid" style={{ gridTemplateColumns: "auto 132px 1fr", rowGap: 7, columnGap: 16, padding: "14px 18px", background: "#FFFFFF", border: "0.5px solid #DEDEDD", borderRadius: 8 }}>
        {BANDS.map((b) => (
          <div key={b.name} className="contents">
            <span
              className="self-center rounded-[3px] px-1.5 py-[2px] font-mono text-[8px] font-bold uppercase tracking-[0.14em]"
              style={{
                color: b.frozen ? "#2F7D4F" : "#B07A1F",
                border: `0.5px solid ${b.frozen ? "rgba(47,125,79,0.5)" : "rgba(176,122,31,0.55)"}`,
              }}
            >
              {b.frozen ? "FROZEN" : "MOVES"}
            </span>
            <span className="self-center font-mono text-[10px] font-semibold uppercase tracking-[0.13em] text-stone-700">{b.name}</span>
            <span className="self-center" style={{ fontSize: 12, color: "#3A3A3A" }}>{b.detail}</span>
          </div>
        ))}
      </div>
    </Section>
  );
}

function SignalLegend() {
  const groups: Source[] = ["host", "phone", "proposed"];
  return (
    <div className="flex flex-col gap-3">
      {groups.map((g) => {
        const meta = SOURCE_META[g];
        const rows = SIGNALS.filter((s) => s.source === g);
        return (
          <div key={g} className="rounded-[8px] border-[0.5px] border-studio-edge bg-white">
            <div className="flex items-baseline gap-3 border-b-[0.5px] border-studio-edge px-4 py-2">
              <SourceTag source={g} />
              <span style={{ fontSize: 12, color: "#3A3A3A" }}>{meta.note}</span>
            </div>
            <div className="grid" style={{ gridTemplateColumns: "190px 1fr 210px", rowGap: 5, columnGap: 14, padding: "10px 16px" }}>
              {rows.map((s) => (
                <div key={s.name} className="contents">
                  <span className="flex items-baseline gap-1.5 font-mono text-[10px] font-semibold tracking-[0.04em] text-stone-700">
                    {s.name}
                    {s.fresh && (
                      <span className="rounded-[2px] px-1 text-[7.5px] font-bold tracking-[0.1em]" style={{ color: "#2F7D4F", border: "0.5px solid rgba(47,125,79,0.4)" }}>
                        NEW
                      </span>
                    )}
                    {s.blocker && (
                      <span className="rounded-[2px] px-1 text-[7.5px] font-bold tracking-[0.1em]" style={{ color: "#B03C34", border: "0.5px solid rgba(176,60,52,0.45)" }}>
                        BLOCKER
                      </span>
                    )}
                  </span>
                  <span style={{ fontSize: 11.5, color: "#4A4A4A", lineHeight: 1.4 }}>{s.detail}</span>
                  <span className="font-mono" style={{ fontSize: 10, color: "#9A9A9A" }}>{s.from}</span>
                </div>
              ))}
            </div>
          </div>
        );
      })}
      <p className="max-w-[78ch]" style={{ fontSize: 12, color: "#6A6A6E", lineHeight: 1.5 }}>
        The five <strong>NEW</strong> rows are why this round can show a turn at all — rounds 1–2 had no
        contract for progress, so they correctly refused to draw one. Two limits survive and shape every
        treatment below: <em>updates are best-effort</em> (the activity snapshot can fail without the turn
        failing, so an empty update list means &ldquo;nothing said&rdquo;, never &ldquo;nothing happening&rdquo;),
        and <em>the response is atomic</em> — it arrives whole in one poll. No treatment types it out
        character by character, because that would be a picture of a thing the host does not do.
      </p>
    </div>
  );
}

function SourceTag({ source, dim }: { source: Source; dim?: boolean }) {
  const m = SOURCE_META[source];
  return (
    <span
      className="rounded-[2px] px-1 py-[1px] font-mono text-[7.5px] font-bold uppercase tracking-[0.14em]"
      style={{ color: m.ink, border: `0.5px ${source === "proposed" ? "dashed" : "solid"} ${m.rim}`, opacity: dim ? 0.7 : 1 }}
    >
      {m.label}
    </span>
  );
}

function GlobalBar({
  scenario, onScenario, scale, onScale, appearance, onAppearance,
}: {
  scenario: ScenarioKey; onScenario: (s: ScenarioKey) => void;
  scale: number; onScale: (n: number) => void;
  appearance: Appearance; onAppearance: (a: Appearance) => void;
}) {
  const s = SCENARIO_BY_KEY[scenario];
  return (
    <div className="sticky top-0 z-20 flex flex-col gap-2.5 rounded-[8px] border-[0.5px] border-studio-edge bg-white/95 px-4 py-3 backdrop-blur">
      <div className="flex flex-wrap items-center gap-x-6 gap-y-2.5">
        <Mini label="state">
          <div className="flex flex-wrap gap-1">
            {SCENARIOS.map((x) => (
              <Seg key={x.key} on={x.key === scenario} onClick={() => onScenario(x.key)}>{x.label}</Seg>
            ))}
          </div>
        </Mini>
        <Mini label="appearance">
          <div className="flex gap-1">
            {(["dark", "light"] as const).map((a) => (
              <Seg key={a} on={a === appearance} onClick={() => onAppearance(a)}>{a}</Seg>
            ))}
          </div>
        </Mini>
        <Mini label="scale">
          <div className="flex gap-1">
            {[0.62, 0.72, 0.86, 1].map((v) => (
              <Seg key={v} on={Math.abs(v - scale) < 0.001} onClick={() => onScale(v)}>{v === 1 ? "1:1" : `${v}×`}</Seg>
            ))}
          </div>
        </Mini>
      </div>
      <p className="max-w-[92ch]" style={{ fontSize: 11.5, color: "#6A6A6E", lineHeight: 1.45 }}>{s.note}</p>
    </div>
  );
}

function Mini({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2">
      <span className="font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">{label}</span>
      {children}
    </div>
  );
}

function Seg({ on, onClick, children }: { on: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={on}
      className="cdb-focus rounded-[4px] px-2 py-[3px] font-mono text-[9.5px] font-semibold uppercase tracking-[0.1em] transition-colors"
      style={{
        color: on ? "#FFFFFF" : "#5A5A5E",
        background: on ? "#232423" : "#F2F1EE",
        border: `0.5px solid ${on ? "#232423" : "#DEDEDD"}`,
      }}
    >
      {children}
    </button>
  );
}

function Section({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-3">
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.3em] text-stone-500">· {label}</span>
        {hint && <span className="italic text-stone-400" style={{ fontSize: 12 }}>{hint}</span>}
        <div className="ml-3 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
      </div>
      {children}
    </section>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Phone shell — the material ladder, carried unchanged from IOSDeck
// ═══════════════════════════════════════════════════════════════════

function appearanceVars(a: Appearance): React.CSSProperties {
  if (a === "light") {
    return {
      "--cdb-bed-face": "#0A0A09",
      "--cdb-bed-shadow": "inset 0 1.5px 3px rgba(0,0,0,0.62), inset 0 0 0 1px rgba(90,70,46,0.28)",
      "--cdb-cap": "linear-gradient(180deg,#FFFDF8,#E9E1D4)",
      "--cdb-cap-on": "linear-gradient(180deg,#FFF3DC,#F0DDB6)",
      "--cdb-cap-ink": "#2A2620",
      "--cdb-cap-ink-off": "#7C7263",
      "--cdb-cap-shadow": "0 2px 3px rgba(0,0,0,0.36), inset 0 1px 0 rgba(255,255,255,0.9), inset 0 -1px 0 rgba(70,52,34,0.22)",
      "--cdb-socket": "rgba(0,0,0,0.42)",
      "--cdb-socket-shadow": "inset 0 2px 5px rgba(0,0,0,0.5), inset 0 0 0 1px rgba(255,255,255,0.06)",
      "--cdb-utility-face": "linear-gradient(180deg,#FFFDF8,#E6DED2)",
      "--cdb-utility-shadow": "0 3px 7px rgba(62,45,28,0.11), inset 0 1px 0 rgba(255,255,255,0.9), inset 0 0 0 1px rgba(74,55,36,0.13)",
      "--cdb-rail": "linear-gradient(180deg,#FFF8EC,#E6DAC8)",
      "--cdb-rail-shadow": "0 5px 12px rgba(55,39,24,0.16), inset 0 1px 0 rgba(255,255,255,0.88)",
    } as React.CSSProperties;
  }
  return {
    "--cdb-bed-face": "#050505",
    "--cdb-bed-shadow": "inset 0 1.5px 3px rgba(0,0,0,0.68), inset 0 0 0 1px rgba(255,255,255,0.10)",
    "--cdb-cap": "linear-gradient(180deg,rgba(255,255,255,0.15),rgba(255,255,255,0.05))",
    "--cdb-cap-on": "linear-gradient(180deg,rgba(255,150,40,0.34),rgba(255,140,20,0.13))",
    "--cdb-cap-ink": "#F4EEE4",
    "--cdb-cap-ink-off": "#8C857C",
    "--cdb-cap-shadow": "0 2px 3px rgba(0,0,0,0.44), inset 0 1px 0 rgba(255,255,255,0.16), inset 0 -1px 0 rgba(0,0,0,0.42)",
    "--cdb-socket": "rgba(0,0,0,0.5)",
    "--cdb-socket-shadow": "inset 0 2px 5px rgba(0,0,0,0.6), inset 0 0 0 1px rgba(255,255,255,0.05)",
    "--cdb-utility-face": "linear-gradient(180deg,#242321,#151513)",
    "--cdb-utility-shadow": "0 3px 8px rgba(0,0,0,0.38), inset 0 1px 0 rgba(255,255,255,0.07), inset 0 0 0 1px rgba(255,255,255,0.10)",
    "--cdb-rail": "linear-gradient(180deg,#24201A,#12100D)",
    "--cdb-rail-shadow": "0 5px 12px rgba(0,0,0,0.42), inset 0 1px 0 rgba(255,255,255,0.08)",
  } as React.CSSProperties;
}

function Phone({ scale, appearance, children }: { scale: number; appearance: Appearance; children: React.ReactNode }) {
  return (
    <div style={{ width: PHONE.w * scale, height: PHONE.h * scale }} className="relative shrink-0">
      <div
        data-theme={appearance === "light" ? "scope" : "tactical"}
        className="absolute left-0 top-0 select-none overflow-hidden rounded-[34px]"
        style={{
          width: PHONE.w, height: PHONE.h,
          transform: `scale(${scale})`, transformOrigin: "top left",
          background: "var(--theme-canvas)",
          boxShadow: "0 0 0 1px rgba(0,0,0,0.55), 0 10px 26px -12px rgba(0,0,0,0.6)",
          fontFamily: "var(--theme-font-mono)",
          ...appearanceVars(appearance),
        }}
      >
        {children}
      </div>
    </div>
  );
}

/** Printed legend, in the deck's silkscreen register. Never a live signal. */
function Silk({ children, ink, size = 8.5 }: { children: React.ReactNode; ink?: string; size?: number }) {
  return (
    <span style={{ color: ink ?? "var(--theme-ink-subtle)", fontSize: size, fontWeight: 600, letterSpacing: "0.16em", lineHeight: 1.3 }}>
      {children}
    </span>
  );
}

/** DeckKeyBed's routed groove. A divider that reads machined, not forgotten. */
function Seam() {
  return (
    <span
      aria-hidden
      className="shrink-0 self-stretch"
      style={{ width: 3, margin: "2px 2px", borderRadius: 2, background: "rgba(0,0,0,0.72)", boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.05)" }}
    />
  );
}

/** The one recessed pocket shape, shared by the Bridge Bar and the Lane Bed. */
function Bed({ h, children, style }: { h: number; children: React.ReactNode; style?: React.CSSProperties }) {
  return (
    <div
      className="flex items-stretch"
      style={{
        height: h, borderRadius: 13, padding: BRIDGE_PAD, gap: 4,
        background: "var(--cdb-bed-face)", boxShadow: "var(--cdb-bed-shadow)",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

/** One seated key. Material carries state; position never moves. */
function Key({
  on, dim, dashed, onClick, ariaLabel, ariaPressed, w, grow, children,
}: {
  on?: boolean; dim?: boolean; dashed?: boolean;
  onClick?: () => void; ariaLabel?: string; ariaPressed?: boolean;
  w?: number; grow?: boolean; children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={ariaLabel}
      aria-pressed={ariaPressed}
      className={`cdb-focus relative grid place-items-center overflow-hidden ${grow ? "flex-1" : "shrink-0"}`}
      style={{
        width: w, borderRadius: 9,
        background: on ? "var(--cdb-cap-on)" : dim ? "var(--cdb-socket)" : "var(--cdb-cap)",
        boxShadow: dim ? "var(--cdb-socket-shadow)" : "var(--cdb-cap-shadow)",
        outline: dashed ? "1px dashed var(--theme-amber-soft)" : undefined,
        outlineOffset: -2,
        color: on ? "var(--theme-amber)" : dim ? "var(--cdb-cap-ink-off)" : "var(--cdb-cap-ink)",
        transition: "background 140ms ease, box-shadow 140ms ease",
      }}
    >
      {children}
    </button>
  );
}

/** Black glass. The one screen on the face — reserved so it never reads as a key. */
function Glass({ h, grow, children }: { h?: number; grow?: boolean; children: React.ReactNode }) {
  return (
    <div
      className={`relative overflow-hidden ${grow ? "flex-1" : "shrink-0"}`}
      style={{
        height: grow ? undefined : h,
        borderRadius: 14,
        background: "var(--theme-screen-bg)",
        boxShadow: "inset 0 2px 9px rgba(0,0,0,0.65), inset 0 1px 0 rgba(255,255,255,0.05), inset 0 0 0 1px var(--theme-edge-faint)",
        "--theme-ink": "#F6F0E7",
        "--theme-ink-dim": "#D7CFC4",
        "--theme-ink-faint": "#A8A099",
        "--theme-ink-subtle": "#736C65",
        "--theme-amber": "#F2A13B",
        "--theme-amber-soft": "rgba(242,161,59,0.42)",
        "--theme-rec": "#FF6B5F",
      } as React.CSSProperties}
    >
      <span aria-hidden className="pointer-events-none absolute inset-0 opacity-[0.055]" style={{ backgroundImage: "repeating-linear-gradient(135deg, transparent 0 13px, var(--theme-screen-trace) 13px 14px)" }} />
      <span aria-hidden className="pointer-events-none absolute inset-0" style={{ background: "linear-gradient(150deg, rgba(255,255,255,0.07), transparent 36%)" }} />
      <span aria-hidden className="pointer-events-none absolute inset-0" style={{ background: "radial-gradient(120% 78% at 50% 42%, transparent 54%, rgba(0,0,0,0.42))" }} />
      <div className="relative flex h-full min-h-0 flex-col">{children}</div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Band 0 — status + masthead
// ═══════════════════════════════════════════════════════════════════

function Masthead({ model, mastMode, onMode, style }: {
  model: DeckModel;
  /** T2 only: the mode switch lives up here. */
  mastMode?: "tabs" | "rocker";
  onMode?: (m: DeckMode) => void;
  style?: React.CSSProperties;
}) {
  return (
    <div className="absolute inset-x-0 top-0" style={{ height: BRIDGE_TOP, ...style }}>
      <div className="flex items-center justify-between px-6" style={{ height: STATUS_H }}>
        <span style={{ color: "var(--theme-ink)", fontSize: 13, fontWeight: 600 }}>7:05</span>
        <div className="flex items-center gap-1.5" style={{ color: "var(--theme-ink-dim)" }}><Bars /><Wifi /><Batt /></div>
      </div>
      <div className="flex items-center gap-2 px-4" style={{ height: MAST_H, borderBottom: "0.5px solid var(--theme-edge-faint)" }}>
        <span style={{ color: "var(--theme-ink)", fontSize: 11, letterSpacing: "0.22em", fontWeight: 600 }}>TALKIE</span>
        {mastMode ? (
          <div className="ml-auto flex items-center" style={{ gap: mastMode === "tabs" ? 0 : 2 }}>
            {mastMode === "tabs" ? (
              <div className="flex overflow-hidden rounded-[6px]" style={{ boxShadow: "inset 0 0 0 0.5px var(--theme-edge-dim)" }}>
                {(["codex", "command"] as const).map((m) => (
                  <button
                    key={m}
                    type="button"
                    aria-pressed={model.mode === m}
                    onClick={() => onMode?.(m)}
                    className="cdb-focus px-2.5"
                    style={{
                      height: 24,
                      fontSize: 8.5, fontWeight: 700, letterSpacing: "0.14em",
                      color: model.mode === m ? "var(--theme-amber)" : "var(--theme-ink-subtle)",
                      background: model.mode === m ? "var(--theme-amber-faint)" : "transparent",
                      boxShadow: model.mode === m ? "inset 0 0 0 0.5px var(--theme-amber-soft)" : undefined,
                    }}
                  >
                    {m === "codex" ? "CODEX" : "CMD"}
                  </button>
                ))}
              </div>
            ) : (
              <button
                type="button"
                onClick={() => onMode?.(model.mode === "codex" ? "command" : "codex")}
                className="cdb-focus flex items-center gap-1.5 rounded-[6px] px-2"
                style={{ height: 24, background: "var(--cdb-cap)", boxShadow: "var(--cdb-cap-shadow)" }}
              >
                <span style={{ fontSize: 8.5, fontWeight: 700, letterSpacing: "0.12em", color: "var(--theme-amber)" }}>
                  {model.mode === "codex" ? "CODEX" : "CMD"}
                </span>
                <span aria-hidden style={{ fontSize: 9, color: "var(--cdb-cap-ink-off)" }}>⇄</span>
              </button>
            )}
          </div>
        ) : (
          <>
            <span style={{ color: "var(--theme-ink-subtle)", fontSize: 11 }}>·</span>
            <span style={{ color: "var(--theme-ink)", fontSize: 11, letterSpacing: "0.22em", fontWeight: 600 }}>DECK</span>
          </>
        )}
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Band 1 — the Bridge Bar
//
// Two switches, one band, frozen top edge. What differs between the
// three treatments is only how the band is divided.
// ═══════════════════════════════════════════════════════════════════

const HOST_TONE: Record<HostState, { ink: string; word: string; dot: string | null }> = {
  live: { ink: "var(--theme-amber)", word: "LIVE", dot: "var(--theme-amber)" },
  connecting: { ink: "var(--theme-ink-dim)", word: "CONNECTING", dot: "var(--theme-ink-dim)" },
  standby: { ink: "var(--cdb-cap-ink-off)", word: "STANDBY", dot: null },
  unreachable: { ink: "var(--theme-rec)", word: "NO ANSWER", dot: "var(--theme-rec)" },
};

function HostKey({
  host, state, active, hostLine, probed, sub, onClick, keyH, w, grow,
}: {
  host: Host; state: HostState; active: boolean; hostLine: string;
  probed: boolean; sub?: boolean; onClick: () => void; keyH: number; w?: number; grow?: boolean;
}) {
  const tone = HOST_TONE[state];
  const secondary =
    hostLine === "seen"
      ? active ? tone.word : `${ago(host.lastSelected)} AGO`
      : null;
  return (
    <Key
      on={active}
      dashed={probed && !active}
      onClick={onClick}
      ariaPressed={active}
      ariaLabel={`Host ${host.n}, ${host.name}. ${active ? tone.word : `Standby, last selected ${ago(host.lastSelected)} ago`}`}
      w={w}
      grow={grow}
    >
      <span className="flex w-full min-w-0 flex-col items-center justify-center px-1" style={{ gap: keyH >= 44 ? 3 : 1.5 }}>
        <span className="flex min-w-0 items-center gap-1">
          {active && tone.dot && (
            <span className={state === "connecting" ? "cdb-live" : ""} style={{ width: 4, height: 4, borderRadius: 3, background: tone.dot, flexShrink: 0 }} />
          )}
          <span className="truncate" style={{ fontSize: keyH >= 44 ? 10 : 9.5, fontWeight: 700, letterSpacing: "0.09em" }}>
            {hostLine === "num" ? `${host.n} ${host.name}` : host.name}
          </span>
        </span>
        {(secondary || sub) && (
          <span className="truncate" style={{ fontSize: 7, letterSpacing: "0.1em", color: "var(--cdb-cap-ink-off)", maxWidth: "100%" }}>
            {sub && !active ? host.fqdn.replace(".local", "") : secondary}
          </span>
        )}
      </span>
    </Key>
  );
}

function ModeKey({ mode, value, onClick, w, label }: { mode: DeckMode; value: DeckMode; onClick: () => void; w?: number; label: string }) {
  return (
    <Key on={mode === value} onClick={onClick} ariaPressed={mode === value} ariaLabel={`${label} deck`} w={w} grow={w === undefined}>
      <span className="truncate px-1" style={{ fontSize: 9, fontWeight: 700, letterSpacing: "0.12em" }}>{label}</span>
    </Key>
  );
}

/**
 * The host group wears a dashed PROPOSED rim for as long as lane state is
 * globally keyed. It is not decoration: with codex.lanes.v1 host-agnostic,
 * throwing this switch is what produces a bed full of another Mac's task ids.
 * Set `lane scope` to host-keyed and the rim goes solid — that is the whole
 * remaining distance between this control and production.
 */
function HostGroup({ proposed, children }: { proposed: boolean; children: React.ReactNode }) {
  return (
    <div
      className="relative flex min-w-0 flex-1 items-stretch gap-1"
      style={
        proposed
          ? { outline: "1px dashed rgba(224,168,74,0.55)", outlineOffset: 2, borderRadius: 11 }
          : undefined
      }
    >
      {children}
    </div>
  );
}

interface BarProps {
  model: DeckModel;
  params: Params;
  keyH: number;
  onHost: (n: number) => void;
  onMode: (m: DeckMode) => void;
}

/** T1 — one bed, two groups, a routed seam between them. */
function UnifiedBar({ model, params, keyH, onHost, onMode }: BarProps) {
  const probe = bool(params, "probeAll");
  const seam = str(params, "seam") === "seam";
  return (
    <Bed h={keyH + BRIDGE_PAD * 2}>
      <ModeKey mode={model.mode} value="codex" onClick={() => onMode("codex")} w={58} label="CODEX" />
      <ModeKey mode={model.mode} value="command" onClick={() => onMode("command")} w={58} label="CMD" />
      {seam ? <Seam /> : <span aria-hidden className="shrink-0" style={{ width: 8 }} />}
      <HostGroup proposed={str(params, "laneScope") === "global"}>
        {model.hosts.map((h) => (
          <HostKey
            key={h.n}
            host={h}
            state={hostStateOf(model, h, probe)}
            active={h.n === model.activeHost}
            hostLine={str(params, "hostLine")}
            probed={probe}
            onClick={() => onHost(h.n)}
            keyH={keyH}
            grow
          />
        ))}
      </HostGroup>
    </Bed>
  );
}

/** T2 — mode has moved to the masthead; the bed is all host. */
function HostBed({ model, params, keyH, onHost }: BarProps) {
  const probe = bool(params, "probeAll");
  return (
    <Bed h={keyH + BRIDGE_PAD * 2}>
      <HostGroup proposed={str(params, "laneScope") === "global"}>
        {model.hosts.map((h) => (
          <HostKey
            key={h.n}
            host={h}
            state={hostStateOf(model, h, probe)}
            active={h.n === model.activeHost}
            hostLine={str(params, "hostLine")}
            probed={probe}
            sub={bool(params, "hostSub")}
            onClick={() => onHost(h.n)}
            keyH={keyH}
            grow
          />
        ))}
      </HostGroup>
    </Bed>
  );
}

/** T3 — one mode key, three hosts, four targets total. */
function HostFirstBar({ model, params, keyH, onHost, onMode }: BarProps) {
  const probe = bool(params, "probeAll");
  const dest = str(params, "modeKey") === "dest";
  const other: DeckMode = model.mode === "codex" ? "command" : "codex";
  const label = dest
    ? `→ ${other === "codex" ? "CODEX" : "CMD"}`
    : model.mode === "codex" ? "CODEX" : "CMD";
  return (
    <Bed h={keyH + BRIDGE_PAD * 2}>
      <Key on={!dest} onClick={() => onMode(other)} w={58} ariaLabel={`Switch to the ${other} deck`}>
        <span className="truncate px-1" style={{ fontSize: 9, fontWeight: 700, letterSpacing: "0.1em" }}>{label}</span>
      </Key>
      <Seam />
      <HostGroup proposed={str(params, "laneScope") === "global"}>
        {model.hosts.map((h) => (
          <HostKey
            key={h.n}
            host={h}
            state={hostStateOf(model, h, probe)}
            active={h.n === model.activeHost}
            hostLine={str(params, "hostLine")}
            probed={probe}
            onClick={() => onHost(h.n)}
            keyH={keyH}
            grow
          />
        ))}
      </HostGroup>
    </Bed>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Band 2 — the Lane Bed
//
// Six positions, always six, always the same width. No "selected"
// label and no confirmation badge: selection is carried by the cap's
// material, and the pane below already names the lane in words.
// ═══════════════════════════════════════════════════════════════════

function LaneBed({ model, onSelect }: { model: DeckModel; onSelect: (n: number) => void }) {
  const stale = laneScopeStale(model);
  return (
    <Bed
      h={LANE_BED_H}
      style={stale ? { boxShadow: "var(--cdb-bed-shadow), inset 0 0 0 1px rgba(255,107,95,0.55)" } : undefined}
    >
      {Array.from({ length: 6 }, (_, i) => i + 1).map((n) => {
        const lane = laneFor(model, n);
        const live = turnFor(model, n);
        const running = live !== null && live.status !== "completed" && live.status !== "failed";
        const selected = model.selected === n && !model.switching && !stale;
        return (
          <Key
            key={n}
            on={selected}
            dim={!lane || model.switching || stale}
            onClick={() => onSelect(n)}
            ariaPressed={selected}
            ariaLabel={
              stale
                ? `Lane ${n}, mapped on a different host — not safe to use`
                : lane
                  ? `Lane ${n}, ${lane.title}${running ? ", turn running" : ""}`
                  : `Lane ${n}, unbound`
            }
            grow
          >
            <span className="flex flex-col items-center" style={{ gap: 2 }}>
              <span style={{ fontSize: 12.5, fontWeight: 700, letterSpacing: "0.02em", lineHeight: 1 }}>
                {String(n).padStart(2, "0")}
              </span>
              {/* A live turn is PHONE truth: this device started it and is still
                  polling. It is never a claim about the task being busy. */}
              <span
                aria-hidden
                className={running ? "cdb-live" : ""}
                style={{
                  width: running ? 12 : 4,
                  height: 2.5,
                  borderRadius: 2,
                  background: stale
                    ? "var(--theme-rec)"
                    : running
                      ? "var(--theme-amber)"
                      : lane && !model.switching
                        ? "currentColor"
                        : "transparent",
                  opacity: running ? 1 : 0.35,
                }}
              />
            </span>
          </Key>
        );
      })}
    </Bed>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Band 3 — the Turn Pane
//
// The only element allowed to change height. Four kinds of content, in
// a fixed order of trust: what YOU said (phone), what the host's status
// is (host), what the host has said publicly (host, best-effort), and
// the answer (host, atomic).
// ═══════════════════════════════════════════════════════════════════

const STATUS_WORD: Record<TurnStatus, string> = {
  sending: "SENDING",
  queued: "QUEUED ON THE HOST",
  running: "WORKING",
  completed: "DONE",
  failed: "BLOCKED",
};

function statusInk(s: TurnStatus): string {
  if (s === "failed") return "var(--theme-rec)";
  if (s === "completed") return "var(--theme-ink)";
  return "var(--theme-amber)";
}

/** The header line every pane shares: which lane, and what state it is in. */
function PaneHead({ model, turn, deliveryMode, onDeliveryMode }: {
  model: DeckModel;
  turn: Turn | null;
  deliveryMode: DeliveryMode;
  onDeliveryMode: (mode: DeliveryMode) => void;
}) {
  const lane = laneFor(model, model.selected);
  const stale = laneScopeStale(model);
  const running = turn !== null && (turn.status === "running" || turn.status === "queued" || turn.status === "sending");
  const shimmer = turn?.status === "running" && turn.updates.length === 0;
  return (
    <div className="flex shrink-0 items-baseline gap-2 px-3 pt-2.5">
      <Silk ink={stale ? "var(--theme-rec)" : "var(--theme-ink-faint)"}>
        {model.switching || stale ? "NO LANE" : `LANE ${String(model.selected).padStart(2, "0")}`}
      </Silk>
      <span className="min-w-0 flex-1 truncate" style={{ color: "var(--theme-ink-faint)", fontSize: 9, letterSpacing: "0.08em" }}>
        {stale ? "MAPPING OUT OF SCOPE" : lane ? lane.project.toUpperCase() : "—"}
      </span>
      {turn && (
        <span className="flex shrink-0 items-center gap-1.5">
          {running && <span className="cdb-live" style={{ width: 5, height: 5, borderRadius: 3, background: statusInk(turn.status) }} />}
          <span
            className={shimmer ? "cdb-shimmer" : ""}
            style={{ color: statusInk(turn.status), fontSize: 8.5, fontWeight: 700, letterSpacing: "0.14em" }}
          >
            {STATUS_WORD[turn.status]}
          </span>
          {/* Elapsed is a phone clock, not an estimate. There is no ETA to give. */}
          <span style={{ color: "var(--theme-ink-subtle)", fontSize: 8.5, letterSpacing: "0.08em" }}>{ago(turn.elapsed)}</span>
        </span>
      )}
      {!model.switching && !stale && lane && (
        <button
          type="button"
          aria-label={`Lane ${model.selected} delivery mode: ${deliveryMode}. Tap to switch to ${deliveryMode === "steer" ? "queue" : "steer"}.`}
          onClick={() => onDeliveryMode(deliveryMode === "steer" ? "queue" : "steer")}
          className="cdb-focus shrink-0 rounded-[5px] px-1.5 py-1"
          style={{
            color: "var(--theme-amber)",
            background: "var(--theme-amber-faint)",
            boxShadow: "inset 0 0 0 1px var(--theme-amber-soft)",
            fontSize: 7.5,
            fontWeight: 700,
            letterSpacing: "0.1em",
          }}
        >
          {deliveryMode === "steer" ? "↗ STEER" : "⇣ QUEUE"}
        </button>
      )}
    </div>
  );
}

/** What you said. The one thing the deck always knows, drawn as a quotation. */
function TranscriptLine({ text, lines }: { text: string; lines: number }) {
  return (
    <div className="flex shrink-0 gap-2 px-3 pt-2">
      <span aria-hidden style={{ width: 2, borderRadius: 2, background: "var(--theme-amber-soft)", flexShrink: 0 }} />
      <p
        className={lines > 0 ? "overflow-hidden" : ""}
        style={{
          margin: 0, color: "var(--theme-ink-dim)", fontSize: 10, lineHeight: 1.42, letterSpacing: "0.01em",
          display: lines > 0 ? "-webkit-box" : undefined,
          WebkitLineClamp: lines > 0 ? lines : undefined,
          WebkitBoxOrient: lines > 0 ? "vertical" : undefined,
        }}
      >
        {text}
      </p>
    </div>
  );
}

const KIND_MARK: Record<UpdateKind, { glyph: string; ink: string; label: string }> = {
  tool: { glyph: "▸", ink: "var(--theme-ink-subtle)", label: "TOOL" },
  commentary: { glyph: "·", ink: "var(--theme-amber)", label: "SAID" },
};

function UpdateLine({ u, marks, dim }: { u: ProgressUpdate; marks: boolean; dim?: boolean }) {
  const m = KIND_MARK[u.kind];
  return (
    <div className="flex gap-1.5" style={{ opacity: dim ? 0.55 : 1 }}>
      {marks && (
        <span className="shrink-0" style={{ color: m.ink, fontSize: 9, lineHeight: 1.45, width: 8 }}>{m.glyph}</span>
      )}
      <span
        className="min-w-0 flex-1 truncate"
        style={{
          color: u.kind === "tool" ? "var(--theme-ink-faint)" : "var(--theme-ink-dim)",
          fontSize: 9.5, lineHeight: 1.45, letterSpacing: "0.01em",
        }}
      >
        {u.text}
      </span>
    </div>
  );
}

function visibleUpdates(turn: Turn, mode: string): ProgressUpdate[] {
  if (mode === "latest") return turn.updates.slice(-1);
  if (mode === "last3") return turn.updates.slice(-3);
  return turn.updates;
}

/** Empty updates means "the host has said nothing", never "nothing is happening". */
function NoUpdatesYet() {
  return (
    <Silk ink="var(--theme-ink-subtle)" size={8.5}>NO PUBLIC UPDATES YET</Silk>
  );
}

function ResponseBlock({ text, clamp }: { text: string; clamp?: number }) {
  return (
    <p
      className={clamp ? "overflow-hidden" : ""}
      style={{
        margin: 0, color: "var(--theme-ink)", fontSize: 10, lineHeight: 1.48,
        display: clamp ? "-webkit-box" : undefined,
        WebkitLineClamp: clamp,
        WebkitBoxOrient: clamp ? "vertical" : undefined,
      }}
    >
      {text}
    </p>
  );
}

function FailureBlock({ turn }: { turn: Turn }) {
  if (!turn.failure) return null;
  return (
    <div className="flex flex-col gap-1">
      <Silk ink="var(--theme-rec)">{turn.failure.code.toUpperCase().replace(/-/g, " ")}</Silk>
      <span style={{ color: "var(--theme-ink-dim)", fontSize: 9.5, lineHeight: 1.45 }}>{turn.failure.hint}</span>
    </div>
  );
}

/** The pane's bottom edge. Delivery outcome, or a printed sentence in its place. */
function PaneFoot({ model, turn }: { model: DeckModel; turn: Turn | null }) {
  let text: React.ReactNode;
  let ink = "var(--theme-ink-subtle)";
  if (laneScopeStale(model)) {
    text = "LANE STATE IS NOT KEYED BY HOST · CODEX.LANES.V1";
    ink = "var(--theme-rec)";
  } else if (!model.bridge && model.switching) text = "CATALOG ARRIVES WHEN THE NEW HOST ANSWERS";
  else if (!model.bridge) text = "HOST UNAVAILABLE · NOTHING HERE IS LIVE";
  else if (turn?.delivery) {
    text = turn.delivery === "started-turn" ? "STARTED A NEW TURN" : turn.delivery === "queued-turn" ? "RAN THE QUEUED TURN" : "STEERED THE ACTIVE TURN";
    ink = "var(--theme-ink-faint)";
  } else if (turn?.turnId) text = `TURN ${turn.turnId.toUpperCase()} · PROGRESS IS BEST-EFFORT`;
  else if (turn) text = "NO TURN ID YET";
  else text = "HOLD THE RAIL TO SPEAK INTO THIS LANE";
  return (
    <div className="mt-auto flex shrink-0 flex-col gap-1.5 px-3 pb-2.5 pt-2">
      <span aria-hidden style={{ height: 1, background: "rgba(255,255,255,0.07)" }} />
      <Silk ink={ink} size={8}>{text}</Silk>
    </div>
  );
}

/** Nothing in flight. The pane says what it is pointed at, and stops. */
function IdleBody({ model }: { model: DeckModel }) {
  const lane = laneFor(model, model.selected);
  /**
   * The stale-mapping report. This is the one place the deck accuses its own
   * state, and it has to: every task id in the bed belongs to another Mac, and
   * a lane's whole promise is that you know exactly which conversation your
   * next sentence enters.
   */
  if (laneScopeStale(model)) {
    const mapped = model.hosts.find((h) => h.n === model.laneHost);
    return (
      <div className="flex flex-1 flex-col justify-center gap-1.5 px-3">
        <Silk ink="var(--theme-rec)">LANES BELONG TO {mapped?.name ?? "ANOTHER HOST"}</Silk>
        <span style={{ color: "var(--theme-ink-dim)", fontSize: 9.5, lineHeight: 1.45 }}>
          These six slots were mapped on {mapped?.name ?? "another Mac"} and hold that Mac&rsquo;s exact task
          ids. {hostFor(model)?.name} has its own tasks and does not know these. Nothing here is safe to
          speak into.
        </span>
        <Silk ink="var(--theme-ink-subtle)" size={8}>REMAP ON {hostFor(model)?.name} TO USE THIS DECK</Silk>
      </div>
    );
  }
  if (model.switching) {
    return (
      <div className="flex flex-1 flex-col justify-center gap-1.5 px-3">
        <Silk ink="var(--theme-ink-dim)">CONNECTING TO {hostFor(model)?.name}</Silk>
        <span style={{ color: "var(--theme-ink-subtle)", fontSize: 9.5, lineHeight: 1.45 }}>
          The previous bridge is closed. Lanes belong to a host, so this bed is dark until the new catalog answers.
        </span>
      </div>
    );
  }
  if (!lane) return <div className="flex flex-1 items-center px-3"><Silk>MAP A CODEX TASK TO THIS LANE</Silk></div>;
  return (
    <div className="flex flex-1 flex-col justify-center gap-1.5 px-3">
      <p style={{ margin: 0, color: "var(--theme-ink)", fontSize: 11.5, lineHeight: 1.35, fontWeight: 600 }}>{lane.title}</p>
      <Silk>{model.bridge ? "READY" : "HOST UNAVAILABLE"}</Silk>
    </div>
  );
}

interface PaneProps {
  model: DeckModel;
  turn: Turn | null;
  deliveryMode: DeliveryMode;
  onDeliveryMode: (mode: DeliveryMode) => void;
  params: Params;
  h: number;
}

/** A · Transcript Stack — one column, strict chronology. */
function StackPane({ model, turn, deliveryMode, onDeliveryMode, params, h }: PaneProps) {
  const marks = bool(params, "kindMarks");
  const rows = turn ? visibleUpdates(turn, str(params, "updates")) : [];
  const bottom = str(params, "anchor") === "bottom";
  const body = (
    <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-hidden px-3 pt-2">
      {turn && turn.updates.length === 0 && turn.status === "running" && <NoUpdatesYet />}
      {rows.length > 0 && (
        <div className="flex min-h-0 flex-col gap-[3px]">
          {(bottom ? rows : [...rows].reverse()).map((u, i) => (
            <UpdateLine key={u.id} u={u} marks={marks} dim={bottom ? i < rows.length - 1 : i > 0} />
          ))}
        </div>
      )}
      {turn?.failure && <FailureBlock turn={turn} />}
      {turn?.response && (
        <div className="flex min-h-0 flex-col gap-1">
          <Silk ink="var(--theme-amber)">RESPONSE</Silk>
          <ResponseBlock text={turn.response} clamp={Math.max(2, Math.floor((h - 150) / 15))} />
        </div>
      )}
    </div>
  );
  return (
    <Glass h={h}>
      <PaneHead model={model} turn={turn} deliveryMode={deliveryMode} onDeliveryMode={onDeliveryMode} />
      {turn ? <TranscriptLine text={turn.transcript} lines={num(params, "transcript")} /> : null}
      {turn ? body : <IdleBody model={model} />}
      <PaneFoot model={model} turn={turn} />
    </Glass>
  );
}

/** B · Pinned Header + Live Channel — the header never moves or reflows. */
function ChannelPane({ model, turn, deliveryMode, onDeliveryMode, params, h }: PaneProps) {
  const marks = bool(params, "kindMarks");
  const rows = turn ? visibleUpdates(turn, str(params, "updates")) : [];
  return (
    <Glass h={h}>
      <PaneHead model={model} turn={turn} deliveryMode={deliveryMode} onDeliveryMode={onDeliveryMode} />
      {turn && <TranscriptLine text={turn.transcript} lines={num(params, "transcript")} />}
      {turn && <span aria-hidden className="mx-3 mt-2 shrink-0" style={{ height: 1, background: "rgba(255,255,255,0.08)" }} />}
      {turn ? (
        <div className="flex min-h-0 flex-1 flex-col gap-1.5 overflow-hidden px-3 pt-2">
          {turn.response ? (
            <>
              <Silk ink="var(--theme-amber)">RESPONSE · ARRIVED WHOLE</Silk>
              <ResponseBlock text={turn.response} clamp={Math.max(2, Math.floor((h - 138) / 15))} />
            </>
          ) : turn.failure ? (
            <FailureBlock turn={turn} />
          ) : rows.length > 0 ? (
            <>
              <Silk ink="var(--theme-ink-subtle)">
                CHANNEL · {turn.updates.length} UPDATE{turn.updates.length === 1 ? "" : "S"}
              </Silk>
              <div className="flex min-h-0 flex-col gap-[3px]">
                {rows.map((u, i) => <UpdateLine key={u.id} u={u} marks={marks} dim={i < rows.length - 1} />)}
              </div>
            </>
          ) : (
            <NoUpdatesYet />
          )}
        </div>
      ) : (
        <IdleBody model={model} />
      )}
      <PaneFoot model={model} turn={turn} />
    </Glass>
  );
}

/** C · Two Registers — nothing reflows; only the text inside is replaced. */
function RegisterPane({ model, turn, deliveryMode, onDeliveryMode, params, h }: PaneProps) {
  const marks = bool(params, "kindMarks");
  const upperH = 74;
  const latest = turn && turn.updates.length > 0 ? turn.updates[turn.updates.length - 1] : null;
  const withCount = str(params, "lower") === "count";
  return (
    <Glass h={h}>
      <div className="flex shrink-0 flex-col overflow-hidden" style={{ height: upperH }}>
        <PaneHead model={model} turn={turn} deliveryMode={deliveryMode} onDeliveryMode={onDeliveryMode} />
        {turn && <TranscriptLine text={turn.transcript} lines={num(params, "transcript")} />}
      </div>
      <span aria-hidden className="mx-3 shrink-0" style={{ height: 1, background: "rgba(255,255,255,0.08)" }} />
      <div className="flex min-h-0 flex-1 flex-col gap-1 overflow-hidden px-3 pt-2">
        {!turn ? (
          <IdleBody model={model} />
        ) : turn.response ? (
          <>
            <Silk ink="var(--theme-amber)">RESPONSE</Silk>
            <ResponseBlock text={turn.response} clamp={Math.max(2, Math.floor((h - upperH - 62) / 15))} />
          </>
        ) : turn.failure ? (
          <FailureBlock turn={turn} />
        ) : latest ? (
          <>
            <Silk ink="var(--theme-ink-subtle)">
              LATEST{withCount && ` · ${turn.updates.length} OF ${turn.updates.length}`}
              {marks && ` · ${KIND_MARK[latest.kind].label}`}
            </Silk>
            <span style={{ color: "var(--theme-ink-dim)", fontSize: 10, lineHeight: 1.45 }}>{latest.text}</span>
          </>
        ) : (
          <NoUpdatesYet />
        )}
      </div>
      <PaneFoot model={model} turn={turn} />
    </Glass>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Band 4 — utility grid (context) and Band 5 — the settled rail
// ═══════════════════════════════════════════════════════════════════

const UTILITIES = [
  { icon: "▤", label: "OUTPUT" }, { icon: "⌗", label: "MAPPER" },
  { icon: "◎", label: "STATUS" }, { icon: "↻", label: "REVALIDATE" },
  { icon: "≡", label: "HISTORY" }, { icon: "▦", label: "SPACES" },
  { icon: "⏵", label: "REPLAY" }, { icon: "♪", label: "NARRATE" },
];

function UtilityGrid({ top, rows }: { top: number; rows: number }) {
  if (rows <= 0) return null;
  return (
    <div className="absolute" style={{ left: GUTTER, right: GUTTER, top }}>
      {Array.from({ length: rows }).map((_, ri) => (
        <div
          key={ri}
          className="absolute grid"
          style={{
            top: ri * (GRID_ROW_H + GRID_GAP), left: 0, right: 0,
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
                  borderRadius: 12, opacity: u ? 0.62 : 0.3,
                  background: u ? "var(--cdb-utility-face)" : "var(--cdb-socket)",
                  boxShadow: u ? "var(--cdb-utility-shadow)" : "var(--cdb-socket-shadow)",
                }}
              >
                {u ? (
                  <span className="flex flex-col items-center gap-1">
                    <span style={{ color: "var(--theme-ink-dim)", fontSize: 14, lineHeight: 1 }}>{u.icon}</span>
                    <span style={{ color: "var(--theme-ink-dim)", fontSize: 7.5, letterSpacing: "0.11em" }}>{u.label}</span>
                  </span>
                ) : (
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

interface RailFace { label: string; sub: string; live: boolean; disabled: boolean; alarm: boolean }

function railFace(m: DeckModel, turn: Turn | null, deliveryMode: DeliveryMode): RailFace {
  // A stale bed disables the rail outright. Speaking into a lane whose task id
  // belongs to another Mac is the failure this whole round exists to prevent.
  if (laneScopeStale(m)) {
    const mapped = m.hosts.find((h) => h.n === m.laneHost);
    return { label: "REMAP BEFORE TALKING", sub: `LANES BELONG TO ${mapped?.name ?? "ANOTHER HOST"}`, live: false, disabled: true, alarm: true };
  }
  if (m.switching) return { label: "SWITCHING HOST", sub: `CONNECTING TO ${hostFor(m)?.name ?? ""}`, live: true, disabled: true, alarm: false };
  if (!m.bridge) return { label: "HOST UNAVAILABLE", sub: "TALKING IS DISABLED UNTIL THE MAC ANSWERS", live: false, disabled: true, alarm: true };
  if (!laneFor(m, m.selected)) return { label: "MAP A TASK TO THIS LANE", sub: "OPEN THE MAPPER TO START", live: false, disabled: true, alarm: false };
  if (turn?.status === "failed") return { label: "HOLD TO TALK", sub: "THE LAST TURN IS BLOCKED", live: false, disabled: false, alarm: true };
  if (turn && (turn.status === "running" || turn.status === "queued")) {
    return { label: "HOLD TO TALK", sub: deliveryMode === "queue" ? "RUNS AFTER THIS TURN" : "ADDS TO THE ACTIVE TURN", live: true, disabled: false, alarm: false };
  }
  if (turn?.status === "sending") return { label: "SENDING", sub: "HANDING THE TURN TO THE MAC", live: true, disabled: true, alarm: false };
  return { label: "HOLD TO TALK", sub: `LANE ${String(m.selected).padStart(2, "0")} · ${deliveryMode.toUpperCase()} MODE`, live: false, disabled: false, alarm: false };
}

function SillRail({ model, turn, deliveryMode, stepper, onHostStep }: {
  model: DeckModel; turn: Turn | null; deliveryMode: DeliveryMode; stepper: boolean; onHostStep: (offset: number) => void;
}) {
  const face = railFace(model, turn, deliveryMode);
  const duringTurn = turn !== null && (turn.status === "running" || turn.status === "queued");
  return (
    <div
      className="absolute flex items-stretch gap-1.5 p-1.5"
      style={{
        left: GUTTER, top: RAIL_TOP, width: CONTENT_W, height: RAIL.h, borderRadius: 18,
        background: face.alarm ? "linear-gradient(rgba(255,69,58,0.14),rgba(255,69,58,0.05))" : "var(--cdb-rail)",
        boxShadow: `var(--cdb-rail-shadow), inset 0 0 0 1px ${face.alarm ? "rgba(255,69,58,0.5)" : "var(--theme-edge-dim)"}`,
      }}
    >
      {stepper && (
        <button
          type="button"
          onClick={() => onHostStep(-1)}
          aria-label="Previous host"
          className="cdb-focus grid w-[38px] shrink-0 place-items-center rounded-[10px]"
          style={{ background: "var(--cdb-cap)", boxShadow: "var(--cdb-cap-shadow)", color: "var(--cdb-cap-ink-off)" }}
        >
          <span className="flex flex-col items-center gap-0.5">
            <span style={{ fontSize: 12, lineHeight: 1 }}>‹</span>
            <span style={{ fontSize: 6.5, letterSpacing: "0.1em" }}>HOST</span>
          </span>
        </button>
      )}

      <button
        type="button"
        disabled={face.disabled}
        aria-label={`${face.label}. ${face.sub}`}
        className="cdb-focus grid min-w-0 flex-1 place-items-center rounded-[10px]"
        style={{ background: "rgba(255,136,0,0.035)", opacity: face.disabled ? 0.55 : 1, cursor: face.disabled ? "not-allowed" : "pointer" }}
      >
        <span className="flex min-w-0 flex-col items-center gap-[5px] px-2">
          <span className="flex items-center gap-2">
            {face.live && <span className="cdb-live" style={{ width: 7, height: 7, borderRadius: 4, background: "var(--theme-amber)" }} />}
            <span className="truncate" style={{ color: face.alarm ? "var(--theme-rec)" : "var(--theme-amber)", fontSize: 13, fontWeight: 700, letterSpacing: "0.14em" }}>
              {face.label}
            </span>
          </span>
          <span className="truncate text-center" style={{ color: "var(--theme-ink-subtle)", fontSize: 9, letterSpacing: "0.1em", lineHeight: 1.25, maxWidth: "100%" }}>
            {face.sub}
          </span>
        </span>
      </button>

      {stepper && !duringTurn && (
        <button
          type="button"
          onClick={() => onHostStep(1)}
          aria-label="Next host"
          className="cdb-focus grid w-[38px] shrink-0 place-items-center rounded-[10px]"
          style={{ background: "var(--cdb-cap)", boxShadow: "var(--cdb-cap-shadow)", color: "var(--cdb-cap-ink-off)" }}
        >
          <span className="flex flex-col items-center gap-0.5">
            <span style={{ fontSize: 12, lineHeight: 1 }}>›</span>
            <span style={{ fontSize: 6.5, letterSpacing: "0.1em" }}>HOST</span>
          </span>
        </button>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Deck assembly
// ═══════════════════════════════════════════════════════════════════

function Deck({ treatment, model, params, onModel }: {
  treatment: TreatmentKey; model: DeckModel; params: Params;
  onModel: (m: DeckModel) => void;
}) {
  const [deliveryMode, setDeliveryMode] = useState<DeliveryMode>("steer");
  const keyH = num(params, "keyH");
  const turn = turnFor(model, model.selected);
  const anyRunning = model.turns.some((t) => t.status !== "completed" && t.status !== "failed");
  const borrow = anyRunning || turn !== null ? num(params, "grow") : 0;
  const g = solve(keyH, borrow);

  /**
   * Tapping a host key lands in the SETTLED post-switch state so the
   * consequence is visible; the connecting transient has its own scenario.
   *
   * Under `hostKeyed` the new host's lane set is loaded atomically with the
   * bridge — bindings and connection change in one step, so they can never
   * disagree. Under `global` (production today) the lane set simply does not
   * change, which is the entire defect: the bed keeps pointing at task ids
   * that belong to the Mac we just left.
   */
  const onHost = (n: number) => {
    if (n === model.activeHost) return;
    if (str(params, "laneScope") === "hostKeyed") {
      const next = LANES_BY_HOST[n] ?? [];
      onModel({
        ...model,
        activeHost: n, laneHost: n, bridge: true, switching: false,
        lanes: next,
        selected: next.some((l) => l.n === model.selected) ? model.selected : (next[0]?.n ?? model.selected),
        turns: [],
      });
      return;
    }
    onModel({ ...model, activeHost: n, bridge: true, switching: false, turns: [] });
  };
  const onMode = (m: DeckMode) => onModel({ ...model, mode: m });
  const onSelect = (n: number) => onModel({ ...model, selected: n });
  const onStep = (o: number) => {
    const next = ((model.activeHost - 1 + o + model.hosts.length) % model.hosts.length) + 1;
    onHost(next);
  };

  const bar =
    treatment === "unified" ? <UnifiedBar model={model} params={params} keyH={keyH} onHost={onHost} onMode={onMode} />
    : treatment === "altitude" ? <HostBed model={model} params={params} keyH={keyH} onHost={onHost} onMode={onMode} />
    : <HostFirstBar model={model} params={params} keyH={keyH} onHost={onHost} onMode={onMode} />;

  const paneProps: PaneProps = {
    model,
    turn,
    deliveryMode,
    onDeliveryMode: setDeliveryMode,
    params,
    h: g.paneH,
  };
  const pane =
    treatment === "unified" ? <StackPane {...paneProps} />
    : treatment === "altitude" ? <ChannelPane {...paneProps} />
    : <RegisterPane {...paneProps} />;

  return (
    <>
      <Masthead
        model={model}
        mastMode={treatment === "altitude" ? (str(params, "mastStyle") as "tabs" | "rocker") : undefined}
        onMode={onMode}
      />
      <div className="absolute" style={{ left: GUTTER, right: GUTTER, top: BRIDGE_TOP }}>{bar}</div>
      <div className="absolute" style={{ left: GUTTER, right: GUTTER, top: g.bedTop }}>
        <LaneBed model={model} onSelect={onSelect} />
      </div>
      <div className="absolute" style={{ left: GUTTER, right: GUTTER, top: g.paneTop }}>{pane}</div>
      <UtilityGrid top={g.gridTop} rows={g.gridRows} />
      <SillRail
        model={model}
        turn={turn}
        deliveryMode={deliveryMode}
        stepper={bool(params, "reachStepper")}
        onHostStep={onStep}
      />
    </>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Treatment card
// ═══════════════════════════════════════════════════════════════════

function TreatmentCard({
  treatment, scenario, onScenario, params, onParam, onReset, scale, appearance,
}: {
  treatment: Treatment; scenario: ScenarioKey; onScenario: (s: ScenarioKey) => void;
  params: Params; onParam: (k: string, v: ParamValue) => void; onReset: () => void;
  scale: number; appearance: Appearance;
}) {
  const built = useMemo(() => SCENARIO_BY_KEY[scenario].build(), [scenario]);
  const [model, setModel] = useState<DeckModel>(built);
  const [seen, setSeen] = useState(scenario);
  if (seen !== scenario) { setSeen(scenario); setModel(built); }

  const g = solve(num(params, "keyH"), model.turns.length > 0 ? num(params, "grow") : 0);

  return (
    <div className="flex flex-col gap-3" style={{ width: PHONE.w * scale }}>
      <div className="flex flex-col gap-1.5">
        <span className="font-mono text-[10px] font-bold uppercase tracking-[0.14em] text-stone-700">{treatment.name}</span>
        <span style={{ fontSize: 11.5, color: "#4A4A4A", lineHeight: 1.42 }}><strong>Bar.</strong> {treatment.bar}</span>
        <span style={{ fontSize: 11.5, color: "#4A4A4A", lineHeight: 1.42 }}><strong>Pane.</strong> {treatment.pane}</span>
      </div>

      <Phone scale={scale} appearance={appearance}>
        <Deck treatment={treatment.key} model={model} params={params} onModel={setModel} />
      </Phone>

      <p className="italic" style={{ fontSize: 11.5, color: "#5A5A5E", lineHeight: 1.45 }}>{treatment.thesis}</p>
      <p style={{ fontSize: 11, color: "#8A6A2A", lineHeight: 1.45 }}><strong>Cost.</strong> {treatment.cost}</p>

      <div className="flex flex-wrap items-center gap-1">
        <span className="mr-1 font-mono text-[8px] font-semibold uppercase tracking-[0.2em] text-stone-400">state</span>
        {SCENARIOS.map((s) => (
          <Seg key={s.key} on={s.key === scenario} onClick={() => onScenario(s.key)}>{s.label}</Seg>
        ))}
      </div>

      <div className="rounded-[6px] border-[0.5px] border-studio-edge bg-white px-3 py-2.5">
        <div className="mb-2 flex items-baseline justify-between">
          <span className="font-mono text-[8px] font-semibold uppercase tracking-[0.2em] text-stone-400">variations</span>
          <button type="button" onClick={onReset} className="cdb-focus font-mono text-[8.5px] uppercase tracking-[0.12em] text-stone-400 hover:text-stone-700">
            reset
          </button>
        </div>
        <div className="flex flex-col gap-2">
          {[...COMMON_PARAMS, ...treatment.params].map((d) => (
            <div key={d.key} className="flex flex-col gap-1">
              <div className="flex flex-wrap items-center gap-1.5">
                <span className="w-[150px] shrink-0 font-mono text-[9px] tracking-[0.04em] text-stone-500">{d.label}</span>
                {d.kind === "bool" ? (
                  <Seg on={bool(params, d.key)} onClick={() => onParam(d.key, !bool(params, d.key))}>
                    {bool(params, d.key) ? "on" : "off"}
                  </Seg>
                ) : (
                  d.options.map((o) => (
                    <Seg key={String(o.value)} on={params[d.key] === o.value} onClick={() => onParam(d.key, o.value)}>{o.label}</Seg>
                  ))
                )}
              </div>
              {d.note && <span className="pl-[156px] text-[10px] leading-snug text-stone-400">{d.note}</span>}
            </div>
          ))}
        </div>
        <div className="mt-2.5 border-t-[0.5px] border-studio-edge pt-2 font-mono text-[9px] leading-relaxed text-stone-400">
          bridge {g.bridgeH} · bed top {g.bedTop} · pane {g.paneTop}→{g.paneTop + g.paneH} ({g.paneH}pt) · grid {g.gridRows} row{g.gridRows === 1 ? "" : "s"} · rail {RAIL_TOP} <span className="text-stone-300">— top of bar and bed never move</span>
          <div className={laneScopeStale(model) ? "text-[#B03C34]" : ""}>
            host {model.hosts.find((h) => h.n === model.activeHost)?.name} · lanes mapped on{" "}
            {model.hosts.find((h) => h.n === model.laneHost)?.name} · {model.lanes.length} bound
            {laneScopeStale(model) && " · STALE — REFUSING TO SUBMIT"}
          </div>
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Comparison + recommendation
// ═══════════════════════════════════════════════════════════════════

interface Score {
  key: TreatmentKey;
  switchSpeed: number;
  stability: number;
  legibility: number;
  turnDensity: number;
  truth: number;
  reach: number;
  note: string;
}

const SCORES: Score[] = [
  {
    key: "unified", switchSpeed: 3, stability: 3, legibility: 2, turnDensity: 3, truth: 3, reach: 2,
    note: "Both switches in one band, both one tap deep, and the pane shows the most turn history of the three. Pays for it in the narrowest keys (58pt) and a column that reflows on every poll.",
  },
  {
    key: "altitude", switchSpeed: 3, stability: 3, legibility: 3, turnDensity: 2, truth: 3, reach: 1,
    note: "The largest, clearest host targets in the study — 111pt each, room for a name and a state word. The mode tabs are 24pt tall in the worst band on the phone, which is the trade.",
  },
  {
    key: "hostfirst", switchSpeed: 2, stability: 3, legibility: 3, turnDensity: 1, truth: 3, reach: 2,
    note: "Zero reflow anywhere, and only four targets to learn. Loses scrollback entirely and hides which deck you are currently on behind a destination label.",
  },
];

const CRITERIA: { key: keyof Omit<Score, "key" | "note">; label: string; why: string }[] = [
  { key: "switchSpeed", label: "switch speed", why: "how many taps and how much aim to change deck or host" },
  { key: "stability", label: "spatial stability", why: "does anything move between idle, working, streaming, failed" },
  { key: "legibility", label: "target legibility", why: "can you read and hit it without looking twice" },
  { key: "turnDensity", label: "turn context", why: "how much truthful host/turn detail fits without clutter" },
  { key: "truth", label: "truthfulness", why: "nothing drawn that the contract cannot supply" },
  { key: "reach", label: "thumb reach", why: "cost of the top band, net of the in-reach stepper" },
];

function Dots({ n }: { n: number }) {
  return (
    <span className="flex gap-[3px]">
      {[1, 2, 3].map((i) => (
        <span key={i} style={{ width: 6, height: 6, borderRadius: 4, background: i <= n ? "#232423" : "#E0E0DE" }} />
      ))}
    </span>
  );
}

function ComparisonMatrix() {
  return (
    <div className="overflow-x-auto rounded-[8px] border-[0.5px] border-studio-edge bg-white">
      <table className="w-full border-collapse" style={{ fontSize: 12 }}>
        <thead>
          <tr>
            <th className="border-b-[0.5px] border-studio-edge px-4 py-2.5 text-left font-mono text-[9px] font-semibold uppercase tracking-[0.16em] text-stone-500">criterion</th>
            {TREATMENTS.map((t) => (
              <th key={t.key} className="border-b-[0.5px] border-studio-edge px-4 py-2.5 text-left font-mono text-[9px] font-semibold uppercase tracking-[0.14em] text-stone-700">
                {t.name.split(" · ")[0]}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {CRITERIA.map((c) => (
            <tr key={c.key}>
              <td className="border-b-[0.5px] border-studio-edge-faint px-4 py-2 align-top">
                <span className="font-mono text-[10px] font-semibold tracking-[0.04em] text-stone-700">{c.label}</span>
                <div className="text-[10.5px] leading-snug text-stone-400">{c.why}</div>
              </td>
              {SCORES.map((s) => (
                <td key={s.key} className="border-b-[0.5px] border-studio-edge-faint px-4 py-2 align-top">
                  <Dots n={s[c.key]} />
                </td>
              ))}
            </tr>
          ))}
          <tr>
            <td className="px-4 py-2.5 align-top font-mono text-[10px] font-semibold text-stone-700">read</td>
            {SCORES.map((s) => (
              <td key={s.key} className="px-4 py-2.5 align-top" style={{ fontSize: 11, color: "#4A4A4A", lineHeight: 1.42 }}>{s.note}</td>
            ))}
          </tr>
        </tbody>
      </table>
    </div>
  );
}

function Recommendation() {
  return (
    <Section label="Recommendation" hint="one to build, with two grafts">
      <div className="flex flex-col gap-3 rounded-[8px] border-[0.5px] border-studio-edge bg-white px-5 py-4">
        <p style={{ fontSize: 13.5, color: "#232423", lineHeight: 1.5 }}>
          Build <strong>T1 · Unified Bar · Transcript Stack</strong>, at{" "}
          <code style={{ fontSize: 12 }}>keyH 44</code>, <code style={{ fontSize: 12 }}>grow +1</code>,{" "}
          <code style={{ fontSize: 12 }}>transcript 1 line</code>, <code style={{ fontSize: 12 }}>updates last 3</code>,{" "}
          <code style={{ fontSize: 12 }}>kind marks on</code>, <code style={{ fontSize: 12 }}>host identity name + last seen</code>,{" "}
          <code style={{ fontSize: 12 }}>in-reach stepper on</code>.
        </p>
        <Para title="Why T1">
          It is the only treatment where both primary tasks are one tap deep from the same band, which is
          what the brief actually ranks first. At 44pt targets the bar costs 52pt of the 328pt upper
          region — 16% — for the two switches the deck is now organised around, and it never moves. The
          seam does the work a gap would do worse: two groups read as two functions without spending
          horizontal space that the host names need.
        </Para>
        <Para title="Why not T2">
          T2 wins on pure host legibility and its altitude argument is correct in the abstract — mode
          <em>is</em> an app-level fact. But it puts a primary, frequently-thrown switch into 24pt masthead
          tabs in the least reachable band on the phone, and then still needs the bed. Two bands for two
          switches costs more than one band with a seam, and buys width the host names do not need.
        </Para>
        <Para title="Why not T3">
          T3&rsquo;s zero-reflow pane is genuinely the calmest thing here and its four-target bar is the
          easiest to learn. It loses on turn context, which the brief ranks: a single latest-update
          register cannot answer &ldquo;what has it actually been doing for ninety seconds&rdquo;. And a mode
          key labelled with its destination is a small, permanent tax on knowing where you are.
        </Para>
        <Para title="Graft from T3">
          Take the fixed upper register. In T1 the transcript is already clamped to one line, so pin it
          and the status word at a fixed height and let only the update list and the response scroll
          beneath. That removes T1&rsquo;s single real defect — the header shifting as the column grows —
          without giving up scrollback.
        </Para>
        <Para title="Graft from T2">
          Take the host key sub-line. At the widths T1 leaves, the active host can still carry a state
          word and the standby hosts a last-seen age. That is the whole honest host story in one line and
          it is worth the pixels.
        </Para>
        <Para title="Sequencing — build the bar, ship the mode switch, hold the host switch">
          T1&rsquo;s geometry can land now, and so can the deck-mode half of it. The three host keys should
          be built and left behind whatever flag the team prefers until{" "}
          <code style={{ fontSize: 12 }}>CodexLaneStore</code> is keyed by paired host and reloads
          atomically on switch. Shipping the host switch against today&rsquo;s global keys would turn a
          one-tap control into a way to send voice instructions into a task on the wrong machine — the
          precise failure the lane primitive exists to make impossible. The <em>Stale mapping (today)</em>
          {" "}state above is what that looks like, and the red bed and dead rail in it are the minimum the
          deck owes the user if the switch ever ships ahead of the fix.
        </Para>
        <Para title="What the brief asked for that is not here, and why">
          A response that streams in. <code style={{ fontSize: 12 }}>job.response</code> is atomic — it
          appears whole on the poll that reports <code style={{ fontSize: 12 }}>completed</code>. What
          genuinely streams is <code style={{ fontSize: 12 }}>job.updates</code>, and every treatment
          streams those. Animating the response into existence would be a picture of a capability the
          host does not have, so none of the three does it. If progressive response text is wanted, it is
          a host change, not a deck change.
        </Para>
      </div>
    </Section>
  );
}

function Para({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <p style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.55, margin: 0 }}>
      <strong style={{ color: "#232423" }}>{title}.</strong> {children}
    </p>
  );
}

function ContractSplit() {
  const groups: { title: string; source: Source; rows: string[] }[] = [
    {
      title: "Buildable today, exactly as drawn", source: "host",
      rows: [
        "Deck-mode switch, one tap. (The host switch is NOT in this column.)",
        "Per-lane live-turn marks for turns this phone started.",
        "Submitted transcript, status word, elapsed clock.",
        "Ordered public updates with commentary/tool marks.",
        "Response, whole, with the delivery outcome under it.",
        "Typed failure code plus the Mac's own recovery sentence.",
      ],
    },
    {
      title: "Drawn honestly as absent", source: "phone",
      rows: [
        "Standby hosts show a last-selected age, never liveness.",
        "An empty update list reads NO PUBLIC UPDATES YET, never idle.",
        "Elapsed is a phone clock; no ETA, no percentage, no queue position.",
        "Lanes busy from Codex Desktop itself are invisible — the phone cannot know.",
        "Switching hosts darkens the lane bed until the new catalog answers.",
        "A bed mapped on another Mac reads NO LANE and disables the rail outright.",
      ],
    },
    {
      title: "Blocked until the store changes", source: "proposed",
      rows: [
        "HOST SWITCHING ITSELF — lanes and active lane must be keyed by paired host.",
        "Atomic reload of the lane set on activatePairedMac(), with no disagreeing window.",
        "Invalidation of liveActivityByLane polls belonging to the previous host.",
        "A cheap per-host health poll, so standby hosts can show liveness.",
        "A batched task-status read, so lanes can show activity started elsewhere.",
        "Progressive response text, if the response should ever appear to stream.",
        "Queue depth or position, if 'runs after this turn' should ever be a number.",
      ],
    },
  ];
  return (
    <Section label="Contract split" hint="what ships, what is honestly absent, what needs the Mac to change">
      <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))" }}>
        {groups.map((g) => (
          <div key={g.title} className="rounded-[8px] border-[0.5px] border-studio-edge bg-white px-4 py-3">
            <div className="mb-2 flex items-baseline gap-2">
              <SourceTag source={g.source} />
              <span className="font-mono text-[10px] font-semibold tracking-[0.04em] text-stone-700">{g.title}</span>
            </div>
            <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
              {g.rows.map((r) => (
                <li key={r} className="flex gap-2" style={{ fontSize: 11.5, color: "#4A4A4A", lineHeight: 1.42 }}>
                  <span aria-hidden style={{ color: "#C8C8C4" }}>·</span>
                  <span>{r}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </Section>
  );
}

function Vocabulary() {
  const rows: [string, string][] = [
    ["Bridge Bar", "Band 1. The one recessed bed carrying the deck-mode switch and the host switch. Top edge frozen at y=87; only its height is a dial."],
    ["Mode Key", "A seated key selecting which deck the phone is showing — Codex or Command. Two of them in T1, a masthead tab pair in T2, one destination key in T3."],
    ["Host Key", "A seated key selecting which paired Mac the deck is pointed at. Exactly one can be lit, because exactly one bridge can be connected."],
    ["Standby", "A paired host that is not connected. It carries a last-selected age and nothing else. Not 'offline', not 'idle' — unknown, and drawn as unknown."],
    ["Lane Bed", "Band 2. Six fixed lane keys in one routed pocket. Stays live and tappable while a turn runs; switching away costs nothing."],
    ["Lane Scope", "The host a lane set belongs to. Lanes are host-local by nature — a lane holds one exact task id, and task ids live on one Mac. Today's store keys them globally, which is the production blocker."],
    ["Stale Mapping", "A loaded lane set whose scope is not the connected host. Drawn with a red bed rim, reported in the pane, and it disables the rail. Never silently tolerated."],
    ["Live Mark", "The short amber bar under a lane number: this phone started a turn here and is still polling it. Never a claim that the task is busy."],
    ["Turn Pane", "Band 3. The single black-glass display, and the only element in the deck permitted to change height."],
    ["Transcript", "The exact sentence this device submitted, quoted against an amber rule. Phone-held, never echoed back from the host."],
    ["Update", "One entry from job.updates — commentary (what Codex said) or tool (what Codex did). Ordered, best-effort, and absent is a legitimate answer."],
    ["Shimmer", "The status word's sweep while a turn is running and has published nothing. The one place motion is earned, because there is genuinely nothing else to report."],
    ["Response", "The final answer. Arrives whole, in the poll that reports completed. Never typed out."],
    ["Pane Foot", "The hairline strip closing the pane: the delivery outcome, or the printed sentence that stands in for one."],
    ["Borrowed Row", "A utility-grid row the pane takes while a turn is in flight. Growth is always downward and always in whole rows."],
    ["Rail", "Band 5. The settled T2 voice control. Never moves, in any treatment or state."],
    ["Host Stepper", "The optional 38pt prev/next keys flanking the rail — the in-reach answer to a top-band host switch. Maps to activateAdjacentPairedMac(offset:)."],
  ];
  return (
    <Section label="Names" hint="one vocabulary for studio · Swift · chat">
      <div className="grid" style={{ gridTemplateColumns: "150px 1fr", rowGap: 8, columnGap: 18, padding: "16px 20px", background: "#FFFFFF", border: "0.5px solid #DEDEDD", borderRadius: 8 }}>
        {rows.map(([name, def]) => (
          <div key={name} className="contents">
            <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-stone-700">{name}</span>
            <span style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>{def}</span>
          </div>
        ))}
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
        <rect key={i} x={i * 4.4} y={8 - i * 2.4} width="3" height={3 + i * 2.4} rx="0.8" fill="currentColor" opacity={i === 3 ? 0.4 : 1} />
      ))}
    </svg>
  );
}

function Wifi() {
  return (
    <svg width="15" height="11" viewBox="0 0 15 11" fill="none" aria-hidden>
      <path d="M1 4.2a9.6 9.6 0 0 1 13 0" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
      <path d="M3.4 6.6a6.2 6.2 0 0 1 8.2 0" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
      <circle cx="7.5" cy="9.2" r="1.2" fill="currentColor" />
    </svg>
  );
}

function Batt() {
  return (
    <svg width="24" height="11" viewBox="0 0 24 11" fill="none" aria-hidden>
      <rect x="0.5" y="0.5" width="20" height="10" rx="3" stroke="currentColor" strokeOpacity="0.5" />
      <rect x="2" y="2" width="14" height="7" rx="1.8" fill="currentColor" />
      <path d="M22 4v3a2 2 0 0 0 0-3z" fill="currentColor" fillOpacity="0.5" />
    </svg>
  );
}
