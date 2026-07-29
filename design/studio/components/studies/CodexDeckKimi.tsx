"use client";

/**
 * iOS · Codex Deck — Alternate K: "One display, one scale, one keyboard."
 *
 * This study answers the operator's de-buttonization review of the Bridge
 * Bar round (design/reviews/2026-07-28-codex-deck-bridge-bar-review.md):
 * "The typography is fine. The problem is that everything is a button."
 * The correction is not typographic — it is categorical. Interaction
 * semantics are carried by five material registers that never overlap:
 *
 *   1. CHROME TEXT     ambient identity and host telemetry. Never
 *                      pressable except the two deliberate switches.
 *   2. ENGRAVED SEGMENT flat lit text in a hairline groove = a selection,
 *                      not an action.
 *   3. RECESSED SCALE  one machined channel with six divisions = lane
 *                      position and selection.
 *   4. BLACK GLASS     the readout. Nothing on it is ever pressable.
 *   5. SEATED CAP      the only thing that presses. All caps live in ONE
 *                      4×4 bed at the bottom.
 *
 * The model, the twelve scenarios, the pane content, and the disabled-reason
 * ladder are PORTED VERBATIM from CodexDeckBridgeBar.tsx — this study changes
 * the composition, not the product truth. CSS vars are --kcd-* and classes
 * kcd-* so nothing collides with the incumbent's --cdb-* / cdb-*.
 *
 * NOT IN SCOPE. No Swift is written here.
 */

import { useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";

// ═══════════════════════════════════════════════════════════════════
// The frozen spine — every number here is a constant, not a layout result
//
// SPATIAL THESIS. Four bands never move in any state: the chrome line at
// the top, the lane scale under it, the black glass in the middle, and
// the keybed at the bottom. The glass is the visual subject; the top is
// quiet on purpose; the bed is the only keyboard. A thumb that has learned
// where LANE 3 and TALK are keeps that memory through idle, working,
// streaming, failure and host switch alike.
// ═══════════════════════════════════════════════════════════════════

const PHONE = { w: 375, h: 812 }; // iPhone 13 mini, points
const GUTTER = 12;
const CONTENT_W = PHONE.w - GUTTER * 2; // 351

const STATUS_H = 47;
const CHROME_H = 46; // band 1 bottom = 93

const SCALE_TOP = 103;
const SCALE_H = 34;

const GLASS_TOP = 147;

const BED_BOTTOM = 792; // 20pt above the screen edge
const BED_H = 323;
const BED_TOP = BED_BOTTOM - BED_H; // 469
const GLASS_H = BED_TOP - 12 - GLASS_TOP; // 310 — the glass is the subject

// ═══════════════════════════════════════════════════════════════════
// Model — ported verbatim from CodexDeckBridgeBar.tsx
// ═══════════════════════════════════════════════════════════════════

type Appearance = "dark" | "light";

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
function hostStateOf(m: DeckModel, h: Host): HostState {
  if (h.n === m.activeHost) {
    if (m.switching) return "connecting";
    return m.bridge ? "live" : "unreachable";
  }
  return "standby";
}

function ago(s: number): string {
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.round(s / 60)}m`;
  if (s < 86_400) return `${Math.round(s / 3600)}h`;
  return `${Math.round(s / 86_400)}d`;
}

// ═══════════════════════════════════════════════════════════════════
// Study control types
// ═══════════════════════════════════════════════════════════════════

type LaneScope = "global" | "hostKeyed";
type UpdatesMode = "latest" | "last3" | "all";

// ═══════════════════════════════════════════════════════════════════
// Material recipes — ported from the incumbent, renamed --cdb-* → --kcd-*
// ═══════════════════════════════════════════════════════════════════

function appearanceVars(a: Appearance): React.CSSProperties {
  if (a === "light") {
    return {
      "--kcd-bed-face": "#0A0A09",
      "--kcd-bed-shadow": "inset 0 1.5px 3px rgba(0,0,0,0.62), inset 0 0 0 1px rgba(90,70,46,0.28)",
      "--kcd-cap": "linear-gradient(180deg,#FFFDF8,#E9E1D4)",
      "--kcd-cap-on": "linear-gradient(180deg,#FFF3DC,#F0DDB6)",
      "--kcd-cap-ink": "#2A2620",
      "--kcd-cap-ink-off": "#7C7263",
      "--kcd-cap-shadow": "0 2px 3px rgba(0,0,0,0.36), inset 0 1px 0 rgba(255,255,255,0.9), inset 0 -1px 0 rgba(70,52,34,0.22)",
      "--kcd-socket": "rgba(0,0,0,0.42)",
      "--kcd-socket-shadow": "inset 0 2px 5px rgba(0,0,0,0.5), inset 0 0 0 1px rgba(255,255,255,0.06)",
      "--kcd-scale-ink": "#A39989",
    } as React.CSSProperties;
  }
  return {
    "--kcd-bed-face": "#050505",
    "--kcd-bed-shadow": "inset 0 1.5px 3px rgba(0,0,0,0.68), inset 0 0 0 1px rgba(255,255,255,0.10)",
    "--kcd-cap": "linear-gradient(180deg,rgba(255,255,255,0.15),rgba(255,255,255,0.05))",
    "--kcd-cap-on": "linear-gradient(180deg,rgba(255,150,40,0.34),rgba(255,140,20,0.13))",
    "--kcd-cap-ink": "#F4EEE4",
    "--kcd-cap-ink-off": "#8C857C",
    "--kcd-cap-shadow": "0 2px 3px rgba(0,0,0,0.44), inset 0 1px 0 rgba(255,255,255,0.16), inset 0 -1px 0 rgba(0,0,0,0.42)",
    "--kcd-socket": "rgba(0,0,0,0.5)",
    "--kcd-socket-shadow": "inset 0 2px 5px rgba(0,0,0,0.6), inset 0 0 0 1px rgba(255,255,255,0.05)",
    "--kcd-scale-ink": "#707070",
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

// ═══════════════════════════════════════════════════════════════════
// Band 0 — status bar
// ═══════════════════════════════════════════════════════════════════

function StatusBar() {
  return (
    <div className="absolute inset-x-0 top-0 flex items-center justify-between px-6" style={{ height: STATUS_H }}>
      <span style={{ color: "var(--theme-ink)", fontSize: 13, fontWeight: 600 }}>7:05</span>
      <div className="flex items-center gap-1.5" style={{ color: "var(--theme-ink-dim)" }}><Bars /><Wifi /><Batt /></div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Band 1 — the chrome line
//
// Chassis level. Left: wordmark + the deck segment (a selection, engraved
// in a hairline groove — no cap gradient, no raised shadow). Right: the
// host line, one transparent button carrying a lamp and a chevron. Between
// the two groups: air. The mostly-empty middle is what makes this read as
// a header instead of a console.
// ═══════════════════════════════════════════════════════════════════

const HOST_LAMP: Record<HostState, { dot: string | null; pulse: boolean; word: string }> = {
  live: { dot: "var(--theme-amber)", pulse: false, word: "live" },
  connecting: { dot: "var(--theme-ink-dim)", pulse: true, word: "connecting" },
  standby: { dot: null, pulse: false, word: "standby" },
  unreachable: { dot: "var(--theme-rec)", pulse: false, word: "unreachable" },
};

function ChromeLine({ model, onMode, onHost }: {
  model: DeckModel;
  onMode: (m: DeckMode) => void;
  onHost: () => void;
}) {
  const host = hostFor(model);
  const state: HostState = host ? hostStateOf(model, host) : "unreachable";
  const lamp = HOST_LAMP[state];
  const next = model.hosts[model.activeHost % model.hosts.length];
  return (
    <div
      className="absolute inset-x-0 flex items-center justify-between px-4"
      style={{ top: STATUS_H, height: CHROME_H, borderBottom: "0.5px solid var(--theme-edge-faint)" }}
    >
      <div className="flex items-center gap-2">
        <span style={{ color: "var(--theme-ink)", fontSize: 11, fontWeight: 600, letterSpacing: "0.22em" }}>TALKIE</span>
        <span aria-hidden style={{ color: "var(--theme-ink-subtle)", fontSize: 11 }}>·</span>
        {/* The deck segment — engraved, not seated. A selection, not an action. */}
        <div
          className="flex items-stretch overflow-hidden"
          style={{ height: 26, borderRadius: 7, boxShadow: "inset 0 0 0 0.5px var(--theme-edge-dim)" }}
        >
          {(["codex", "command"] as const).map((m) => {
            const on = model.mode === m;
            return (
              <button
                key={m}
                type="button"
                aria-pressed={on}
                onClick={() => onMode(m)}
                className="kcd-focus px-2.5"
                style={{
                  fontSize: 9, fontWeight: 700, letterSpacing: "0.14em",
                  color: on ? "var(--theme-amber)" : "var(--theme-ink-subtle)",
                  background: on ? "var(--theme-amber-faint)" : "transparent",
                  boxShadow: on ? "inset 0 0 0 0.5px var(--theme-amber-soft)" : undefined,
                }}
              >
                {m === "codex" ? "CODEX" : "CMD"}
              </button>
            );
          })}
        </div>
      </div>

      {/* The host line — one name, one lamp, one chevron. Exactly one host is
          ever connected, so exactly one is ever shown. */}
      <button
        type="button"
        onClick={onHost}
        aria-label={`Active host ${host?.name ?? "unknown"}, ${lamp.word}. Switch to next host ${next?.name ?? ""}.`}
        className="kcd-focus flex items-center gap-1.5 rounded-[4px] px-1 py-1"
        style={{ background: "transparent" }}
      >
        {lamp.dot && (
          <span
            aria-hidden
            className={lamp.pulse ? "kcd-live" : ""}
            style={{ width: 6, height: 6, borderRadius: 4, background: lamp.dot, flexShrink: 0 }}
          />
        )}
        <span style={{ color: "var(--theme-ink)", fontSize: 10, fontWeight: 700, letterSpacing: "0.09em" }}>
          {host?.name ?? "—"}
        </span>
        <span aria-hidden style={{ color: "var(--theme-ink-subtle)", fontSize: 9 }}>⌄</span>
      </button>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Band 2 — the lane scale
//
// ONE machined channel with six divisions — a tuner scale, never six keys.
// No per-division background, no per-division shadow. Selection is a lit
// number plus a detent bar; a turn in flight is a tick lamp that shows
// even when its lane is not selected. Each division is a real button so
// keyboard focus works, but visually there is only one groove.
// ═══════════════════════════════════════════════════════════════════

function LaneScale({ model, onSelect }: { model: DeckModel; onSelect: (n: number) => void }) {
  const stale = laneScopeStale(model);
  return (
    <div
      className="absolute flex items-stretch"
      style={{
        left: GUTTER, width: CONTENT_W, top: SCALE_TOP, height: SCALE_H,
        borderRadius: 10,
        background: "var(--kcd-bed-face)",
        boxShadow: stale
          ? "var(--kcd-bed-shadow), inset 0 0 0 1px rgba(255,107,95,0.55)"
          : "var(--kcd-bed-shadow)",
        opacity: stale ? 0.75 : model.switching ? 0.6 : 1,
        transition: "opacity 160ms ease, box-shadow 160ms ease",
      }}
    >
      {Array.from({ length: 6 }, (_, i) => i + 1).map((n, i) => {
        const lane = laneFor(model, n);
        const live = turnFor(model, n);
        const running = live !== null && live.status !== "completed" && live.status !== "failed";
        const selected = model.selected === n && !model.switching && !stale;
        return (
          <div key={n} className="flex min-w-0 flex-1 items-stretch">
            {i > 0 && (
              <span
                aria-hidden
                className="shrink-0 self-stretch"
                style={{ width: 1, margin: "8px 0", background: "rgba(255,255,255,0.08)" }}
              />
            )}
            <button
              type="button"
              onClick={() => onSelect(n)}
              aria-pressed={selected}
              aria-label={
                stale
                  ? `Lane ${n}, mapped on a different host — not safe to use`
                  : lane
                    ? `Lane ${n}, ${lane.title}${running ? ", turn running" : ""}`
                    : `Lane ${n}, unbound`
              }
              className="kcd-division relative flex min-w-0 flex-1 flex-col items-center justify-center"
              style={{ gap: 3, background: "transparent" }}
            >
              {selected && (
                <span
                  aria-hidden
                  className="absolute left-1/2 top-0 -translate-x-1/2"
                  style={{ width: 26, height: 2.5, borderRadius: 2, background: "var(--theme-amber)" }}
                />
              )}
              {/* A live turn is PHONE truth: this device started it and is still
                  polling. Visible even when this lane is not selected. */}
              <span style={{ height: 3.5, display: "block" }}>
                {running && (
                  <span
                    aria-hidden
                    className="kcd-live"
                    style={{ display: "block", width: 3.5, height: 3.5, borderRadius: 2, background: "var(--theme-amber)" }}
                  />
                )}
              </span>
              <span
                style={{
                  fontSize: 8, fontWeight: 600, letterSpacing: "0.12em", lineHeight: 1,
                  color: selected ? "var(--theme-amber)" : "var(--kcd-scale-ink)",
                  opacity: !lane ? 0.45 : 1,
                }}
              >
                {String(n).padStart(2, "0")}
              </span>
            </button>
          </div>
        );
      })}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Band 3 — the glass. The readout. NOTHING on it is ever pressable.
// ═══════════════════════════════════════════════════════════════════

/** Black glass. The one screen on the face — reserved so it never reads as a key. */
function Glass({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="absolute overflow-hidden"
      style={{
        left: GUTTER, width: CONTENT_W, top: GLASS_TOP, height: GLASS_H,
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

/**
 * The head line every glass shares: which lane, what state, and the printed
 * delivery mode. STEER/QUEUE is a lane ATTRIBUTE printed in silk — not a
 * button, not a pill, no background, no border. The bed sets it.
 */
function PaneHead({ model, turn, deliveryMode }: {
  model: DeckModel;
  turn: Turn | null;
  deliveryMode: DeliveryMode;
}) {
  const lane = laneFor(model, model.selected);
  const stale = laneScopeStale(model);
  const running = turn !== null && (turn.status === "running" || turn.status === "queued" || turn.status === "sending");
  const shimmer = turn?.status === "running" && turn.updates.length === 0;
  return (
    <div className="flex shrink-0 items-baseline gap-2 px-3 pt-2.5">
      <Silk ink={stale || model.switching ? "var(--theme-rec)" : "var(--theme-ink-faint)"}>
        {model.switching || stale ? "NO LANE" : `LANE ${String(model.selected).padStart(2, "0")}`}
      </Silk>
      <span className="min-w-0 flex-1 truncate" style={{ color: "var(--theme-ink-faint)", fontSize: 9, letterSpacing: "0.08em" }}>
        {stale ? "MAPPING OUT OF SCOPE" : lane ? lane.project.toUpperCase() : "—"}
      </span>
      {turn && (
        <span className="flex shrink-0 items-center gap-1.5">
          {running && <span className="kcd-live" style={{ width: 5, height: 5, borderRadius: 3, background: statusInk(turn.status) }} />}
          <span
            className={shimmer ? "kcd-shimmer" : ""}
            style={{ color: statusInk(turn.status), fontSize: 8.5, fontWeight: 700, letterSpacing: "0.14em" }}
          >
            {STATUS_WORD[turn.status]}
          </span>
          {/* Elapsed is a phone clock, not an estimate. There is no ETA to give. */}
          <span style={{ color: "var(--theme-ink-subtle)", fontSize: 8.5, letterSpacing: "0.08em" }}>{ago(turn.elapsed)}</span>
        </span>
      )}
      {!model.switching && !stale && lane && (
        <Silk ink="var(--theme-ink-faint)" size={8.5}>{deliveryMode.toUpperCase()}</Silk>
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

function UpdateLine({ u, dim }: { u: ProgressUpdate; dim?: boolean }) {
  const m = KIND_MARK[u.kind];
  return (
    <div className="flex gap-1.5" style={{ opacity: dim ? 0.55 : 1 }}>
      <span className="shrink-0" style={{ color: m.ink, fontSize: 9, lineHeight: 1.45, width: 8 }}>{m.glyph}</span>
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

function visibleUpdates(turn: Turn, mode: UpdatesMode): ProgressUpdate[] {
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

/** The glass's bottom edge. Delivery outcome, or a printed sentence in its place. */
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
  else text = "HOLD TALK TO SPEAK INTO THIS LANE";
  return (
    <div className="mt-auto flex shrink-0 flex-col gap-1.5 px-3 pb-2.5 pt-2">
      <span aria-hidden style={{ height: 1, background: "rgba(255,255,255,0.07)" }} />
      <Silk ink={ink} size={8}>{text}</Silk>
    </div>
  );
}

/** Nothing in flight. The glass says what it is pointed at, and stops. */
function IdleBody({ model }: { model: DeckModel }) {
  const lane = laneFor(model, model.selected);
  /**
   * The stale-mapping report. This is the one place the deck accuses its own
   * state, and it has to: every task id on the scale belongs to another Mac,
   * and a lane's whole promise is that you know exactly which conversation
   * your next sentence enters.
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
          The previous bridge is closed. Lanes belong to a host, so this scale is dark until the new catalog answers.
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

/** The glass, assembled. Head → transcript → live channel → response/failure → foot. */
function TurnGlass({ model, turn, deliveryMode, transcriptLines, updatesMode }: {
  model: DeckModel;
  turn: Turn | null;
  deliveryMode: DeliveryMode;
  transcriptLines: number;
  updatesMode: UpdatesMode;
}) {
  const rows = turn ? visibleUpdates(turn, updatesMode) : [];
  return (
    <Glass>
      <PaneHead model={model} turn={turn} deliveryMode={deliveryMode} />
      {turn && <TranscriptLine text={turn.transcript} lines={transcriptLines} />}
      {turn && <span aria-hidden className="mx-3 mt-2 shrink-0" style={{ height: 1, background: "rgba(255,255,255,0.08)" }} />}
      {turn ? (
        <div className="flex min-h-0 flex-1 flex-col gap-1.5 overflow-hidden px-3 pt-2">
          {turn.response ? (
            <>
              <Silk ink="var(--theme-amber)">RESPONSE · ARRIVED WHOLE</Silk>
              <ResponseBlock text={turn.response} clamp={Math.max(2, Math.floor((GLASS_H - 138) / 15))} />
            </>
          ) : turn.failure ? (
            <FailureBlock turn={turn} />
          ) : rows.length > 0 ? (
            <>
              <Silk ink="var(--theme-ink-subtle)">
                CHANNEL · {turn.updates.length} UPDATE{turn.updates.length === 1 ? "" : "S"}
              </Silk>
              <div className="flex min-h-0 flex-col gap-[3px]">
                {rows.map((u, i) => <UpdateLine key={u.id} u={u} dim={i < rows.length - 1} />)}
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

// ═══════════════════════════════════════════════════════════════════
// Band 4 — the keybed. The ONLY caps on the face.
//
// Sixteen slots in one recessed bed. Utility keys are real buttons — the
// incumbent's fake-div tiles were a defect this study does not repeat.
// Slots 11, 12, 13 and 16 are empty sockets: they read as empty mounts,
// not disabled buttons. Talk spans 14+15, framed by air.
// ═══════════════════════════════════════════════════════════════════

interface TalkFace { label: string; sub: string; live: boolean; disabled: boolean; alarm: boolean }

/**
 * The disabled-reason ladder, ported verbatim from the incumbent's
 * railFace() — the best piece of state reasoning in that file, retargeted
 * from the deleted rail to the Talk key at slots 14+15.
 */
function talkFace(m: DeckModel, turn: Turn | null, deliveryMode: DeliveryMode): TalkFace {
  // A stale bed disables talk outright. Speaking into a lane whose task id
  // belongs to another Mac is the failure this whole design exists to prevent.
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

/** One seated utility cap. Real button, real press, same material as its neighbours. */
function UtilityKey({ icon, label }: { icon: string; label: string }) {
  return (
    <button
      type="button"
      aria-label={label.toLowerCase()}
      className="kcd-focus kcd-cap-press flex flex-col items-center justify-center gap-1.5"
      style={{
        borderRadius: 10,
        background: "var(--kcd-cap)",
        boxShadow: "var(--kcd-cap-shadow)",
        color: "var(--kcd-cap-ink)",
        transition: "background 140ms ease, box-shadow 140ms ease",
      }}
    >
      <span aria-hidden style={{ fontSize: 13, lineHeight: 1 }}>{icon}</span>
      <span style={{ fontSize: 7.5, fontWeight: 600, letterSpacing: "0.11em" }}>{label}</span>
    </button>
  );
}

/**
 * Slot 09 — the persistent lane-level Steer/Queue control. The glass head
 * prints the attribute; this key is where it is set. Steer is the hotter
 * mode, so it wears amber; queue wears cap ink.
 */
function ModeKey({ mode, lane, onToggle }: { mode: DeliveryMode; lane: number; onToggle: () => void }) {
  return (
    <button
      type="button"
      aria-pressed={mode === "steer"}
      aria-label={`Lane ${lane} delivery mode: ${mode}. Tap to switch to ${mode === "steer" ? "queue" : "steer"}.`}
      onClick={onToggle}
      className="kcd-focus kcd-cap-press flex flex-col items-center justify-center gap-1"
      style={{
        borderRadius: 10,
        background: "var(--kcd-cap)",
        boxShadow: "var(--kcd-cap-shadow)",
        transition: "background 140ms ease, box-shadow 140ms ease",
      }}
    >
      <span style={{ fontSize: 7, fontWeight: 600, letterSpacing: "0.16em", color: "var(--kcd-cap-ink-off)" }}>DELIVER</span>
      <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: "0.12em", color: mode === "steer" ? "var(--theme-amber)" : "var(--kcd-cap-ink)" }}>
        {mode.toUpperCase()}
      </span>
    </button>
  );
}

/** An empty mount. Recessed, engraved with its slot number, plain div. */
function Socket({ n }: { n: number }) {
  return (
    <div
      className="grid place-items-center"
      style={{ borderRadius: 10, background: "var(--kcd-socket)", boxShadow: "var(--kcd-socket-shadow)" }}
    >
      <span style={{ fontSize: 7, fontWeight: 600, letterSpacing: "0.12em", color: "var(--kcd-cap-ink-off)", opacity: 0.35 }}>
        {String(n).padStart(2, "0")}
      </span>
    </div>
  );
}

/**
 * Slots 14+15 — the deck's one deliberate primary. Amber-washed at rest
 * whenever it is enabled; socket-dimmed with a real `disabled` attribute
 * when it is not. Alarm state gets rec ink and a thin rec rim, never a
 * red fill flood.
 */
function TalkKey({ face }: { face: TalkFace }) {
  const enabled = !face.disabled;
  return (
    <button
      type="button"
      disabled={face.disabled}
      aria-label={`${face.label}. ${face.sub}`}
      className="kcd-focus kcd-cap-press flex flex-col items-center justify-center gap-[5px]"
      style={{
        gridColumn: "2 / 4",
        borderRadius: 10,
        background: enabled ? "var(--kcd-cap-on)" : "var(--kcd-socket)",
        boxShadow: `${enabled ? "var(--kcd-cap-shadow)" : "var(--kcd-socket-shadow)"}${face.alarm ? ", inset 0 0 0 1px rgba(255,107,95,0.45)" : ""}`,
        cursor: face.disabled ? "not-allowed" : "pointer",
        transition: "background 140ms ease, box-shadow 140ms ease",
      }}
    >
      <span className="flex items-center gap-2">
        {face.live && <span className="kcd-live" style={{ width: 7, height: 7, borderRadius: 4, background: "var(--theme-amber)" }} />}
        <span
          style={{
            fontSize: 12, fontWeight: 700, letterSpacing: "0.14em",
            color: face.alarm
              ? enabled ? "var(--theme-amber)" : "var(--theme-rec)"
              : enabled ? "var(--theme-amber)" : "var(--kcd-cap-ink-off)",
          }}
        >
          {face.label}
        </span>
      </span>
      <span
        style={{
          fontSize: 7.5, letterSpacing: "0.1em", lineHeight: 1.25,
          color: face.alarm ? "var(--theme-rec)" : "var(--kcd-cap-ink-off)",
          opacity: face.disabled && !face.alarm ? 0.8 : 1,
        }}
      >
        {face.sub}
      </span>
    </button>
  );
}

function KeyBed({ model, turn, deliveryMode, onToggleMode }: {
  model: DeckModel;
  turn: Turn | null;
  deliveryMode: DeliveryMode;
  onToggleMode: () => void;
}) {
  const face = talkFace(model, turn, deliveryMode);
  return (
    <div
      className="absolute grid"
      style={{
        left: GUTTER, width: CONTENT_W, top: BED_TOP, height: BED_H,
        borderRadius: 16, padding: 8, gap: 9,
        background: "var(--kcd-bed-face)",
        boxShadow: "var(--kcd-bed-shadow)",
        gridTemplateColumns: "repeat(4,1fr)",
        gridTemplateRows: "repeat(4,1fr)",
      }}
    >
      {/* Row 1 — audio is deliberately quiet: same cap, same ink as its neighbours. */}
      <UtilityKey icon="∿" label="AUDIO" />
      <UtilityKey icon="⌗" label="MAPPER" />
      <UtilityKey icon="≡" label="HISTORY" />
      <UtilityKey icon="▤" label="OUTPUT" />
      {/* Row 2 */}
      <UtilityKey icon="◎" label="STATUS" />
      <UtilityKey icon="▦" label="SPACES" />
      <UtilityKey icon="⏵" label="REPLAY" />
      <UtilityKey icon="♪" label="NARRATE" />
      {/* Row 3 */}
      <ModeKey mode={deliveryMode} lane={model.selected} onToggle={onToggleMode} />
      <UtilityKey icon="↻" label="REVALIDATE" />
      <Socket n={11} />
      <Socket n={12} />
      {/* Row 4 — Talk at 14+15, framed by empty sockets. The air is mandatory. */}
      <Socket n={13} />
      <TalkKey face={face} />
      <Socket n={16} />
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Deck assembly
// ═══════════════════════════════════════════════════════════════════

function Deck({ model, laneScope, transcriptLines, updatesMode, deliveryModes, onModel, onDeliveryMode }: {
  model: DeckModel;
  laneScope: LaneScope;
  transcriptLines: number;
  updatesMode: UpdatesMode;
  deliveryModes: Record<number, DeliveryMode>;
  onModel: (m: DeckModel) => void;
  onDeliveryMode: (lane: number, mode: DeliveryMode) => void;
}) {
  const turn = turnFor(model, model.selected);
  const deliveryMode = deliveryModes[model.selected] ?? "steer";

  /**
   * Tapping the host line cycles to the next paired host and lands in the
   * SETTLED post-switch state so the consequence is visible; the connecting
   * transient has its own scenario. Ported from the incumbent's onHost:
   *
   * Under `hostKeyed` the new host's lane set is loaded atomically with the
   * bridge — bindings and connection change in one step, so they can never
   * disagree. Under `global` (production today) the lane set simply does not
   * change, which is the entire defect: the scale keeps pointing at task ids
   * that belong to the Mac we just left.
   */
  const onHost = () => {
    const n = ((model.activeHost - 1 + 1 + model.hosts.length) % model.hosts.length) + 1;
    if (n === model.activeHost) return;
    if (laneScope === "hostKeyed") {
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
  const onToggleMode = () => onDeliveryMode(model.selected, deliveryMode === "steer" ? "queue" : "steer");

  return (
    <>
      <StatusBar />
      <ChromeLine model={model} onMode={onMode} onHost={onHost} />
      <LaneScale model={model} onSelect={onSelect} />
      <TurnGlass
        model={model}
        turn={turn}
        deliveryMode={deliveryMode}
        transcriptLines={transcriptLines}
        updatesMode={updatesMode}
      />
      <KeyBed model={model} turn={turn} deliveryMode={deliveryMode} onToggleMode={onToggleMode} />
    </>
  );
}

// ═══════════════════════════════════════════════════════════════════
// Study
// ═══════════════════════════════════════════════════════════════════

export function CodexDeckKimiStudy() {
  const search = useSearchParams();
  const paramA = search.get("a");
  const paramS = search.get("s") as ScenarioKey | null;

  const [appearance, setAppearance] = useState<Appearance>(paramA === "light" ? "light" : "dark");
  const [scenario, setScenario] = useState<ScenarioKey>(
    paramS && paramS in SCENARIO_BY_KEY ? paramS : "progress",
  );
  const [scale, setScale] = useState(0.78);
  const [laneScope, setLaneScope] = useState<LaneScope>("global");
  const [transcriptLines, setTranscriptLines] = useState(1);
  const [updatesMode, setUpdatesMode] = useState<UpdatesMode>("last3");

  const built = useMemo(() => SCENARIO_BY_KEY[scenario].build(), [scenario]);
  const [model, setModel] = useState<DeckModel>(built);
  const [seen, setSeen] = useState(scenario);
  if (seen !== scenario) { setSeen(scenario); setModel(built); }

  const [deliveryModes, setDeliveryModes] = useState<Record<number, DeliveryMode>>({});
  const onDeliveryMode = (lane: number, mode: DeliveryMode) =>
    setDeliveryModes((prev) => ({ ...prev, [lane]: mode }));

  return (
    <div className="flex flex-col gap-5">
      <KcdStyles />

      {/* Lab controls — quiet studio text, deliberately not instrument-styled. */}
      <div className="kcd-lab flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-x-1 gap-y-1">
          <span className="mr-2 font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">state</span>
          {SCENARIOS.map((s) => (
            <LabSeg key={s.key} on={s.key === scenario} onClick={() => setScenario(s.key)}>{s.label}</LabSeg>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-x-6 gap-y-2">
          <div className="flex items-center gap-1">
            <span className="mr-1.5 font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">appearance</span>
            {(["dark", "light"] as const).map((a) => (
              <LabSeg key={a} on={a === appearance} onClick={() => setAppearance(a)}>{a}</LabSeg>
            ))}
          </div>
          <div className="flex items-center gap-2">
            <span className="font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">scale</span>
            <input
              type="range"
              min={0.6}
              max={1}
              step={0.01}
              value={scale}
              onChange={(e) => setScale(Number(e.target.value))}
              aria-label="Phone scale"
              style={{ width: 110, accentColor: "#B5823A" }}
            />
            <span className="font-mono text-[9px] text-stone-500">{scale.toFixed(2)}×</span>
          </div>
          <div className="flex items-center gap-1">
            <span className="mr-1.5 font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">lane scope</span>
            <LabSeg on={laneScope === "global"} onClick={() => setLaneScope("global")}>global · today</LabSeg>
            <LabSeg on={laneScope === "hostKeyed"} onClick={() => setLaneScope("hostKeyed")}>host-keyed · required</LabSeg>
          </div>
          <div className="flex items-center gap-1">
            <span className="mr-1.5 font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">transcript</span>
            {([1, 2, 0] as const).map((v) => (
              <LabSeg key={v} on={transcriptLines === v} onClick={() => setTranscriptLines(v)}>
                {v === 0 ? "full" : `${v} line${v === 1 ? "" : "s"}`}
              </LabSeg>
            ))}
          </div>
          <div className="flex items-center gap-1">
            <span className="mr-1.5 font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">updates</span>
            {(["latest", "last3", "all"] as const).map((v) => (
              <LabSeg key={v} on={updatesMode === v} onClick={() => setUpdatesMode(v)}>
                {v === "last3" ? "last 3" : v}
              </LabSeg>
            ))}
          </div>
        </div>
      </div>

      <div className="flex flex-wrap items-start gap-8">
        <Phone scale={scale} appearance={appearance}>
          <Deck
            model={model}
            laneScope={laneScope}
            transcriptLines={transcriptLines}
            updatesMode={updatesMode}
            deliveryModes={deliveryModes}
            onModel={setModel}
            onDeliveryMode={onDeliveryMode}
          />
        </Phone>

        <aside className="flex max-w-[360px] flex-col gap-4 pt-1">
          <p style={{ fontSize: 13, color: "#3A3A3A", lineHeight: 1.55, margin: 0 }}>
            <strong style={{ color: "#232423" }}>One display, one scale, one keyboard.</strong> Everything the
            host says lands on the single black glass, and nothing on that glass is pressable. The recessed
            scale above it only ever answers <em>where am I</em>; the 4×4 bed at the bottom is the only region
            made of keys. The top of the face is quiet on purpose — the air between the wordmark and the host
            line is what makes it read as a header instead of a console.
          </p>
          <div className="flex flex-col gap-1.5">
            <span className="font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">material grammar</span>
            <span className="font-mono" style={{ fontSize: 10.5, color: "#4A4A4A", lineHeight: 1.7 }}>
              chrome text = ambient · segment = selection · scale = lane position · glass = readout · cap = action
            </span>
          </div>
          <div className="flex flex-col gap-1.5">
            <span className="font-mono text-[8.5px] font-semibold uppercase tracking-[0.2em] text-stone-400">
              state · {SCENARIO_BY_KEY[scenario].label}
            </span>
            <p style={{ fontSize: 12, color: "#4A4A4A", lineHeight: 1.5, margin: 0 }}>{SCENARIO_BY_KEY[scenario].note}</p>
          </div>
          <div className="flex flex-col gap-2" style={{ borderTop: "0.5px solid #DEDEDD", paddingTop: 12 }}>
            <p style={{ fontSize: 11.5, color: "#6A6A6E", lineHeight: 1.5, margin: 0 }}>
              <strong style={{ color: "#3A3A3A" }}>One host, ever.</strong> activatePairedMac() tears one bridge
              down before building the next, so the chrome line shows one name with one lamp — never a row of
              lit hosts.
            </p>
            <p style={{ fontSize: 11.5, color: "#6A6A6E", lineHeight: 1.5, margin: 0 }}>
              <strong style={{ color: "#3A3A3A" }}>Stale is a real state, not an edge case.</strong> Lane
              bindings are globally keyed today (codex.lanes.v1 has no host in the key), so a host switch can
              strand another Mac&rsquo;s task ids on the scale. When that happens the deck refuses to talk.
            </p>
          </div>
        </aside>
      </div>
    </div>
  );
}

/** Quiet text segment for the lab controls. Active = underlined with an amber dot. */
function LabSeg({ on, onClick, children }: { on: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={on}
      className="flex items-center gap-1 rounded-[3px] px-1.5 py-[3px] font-mono text-[9.5px] font-semibold uppercase tracking-[0.1em]"
      style={{
        color: on ? "#232423" : "#8A8A8E",
        textDecoration: on ? "underline" : "none",
        textUnderlineOffset: 3,
        textDecorationColor: "#B5823A",
      }}
    >
      <span
        aria-hidden
        style={{ width: 4, height: 4, borderRadius: 3, background: on ? "#B5823A" : "transparent", flexShrink: 0 }}
      />
      {children}
    </button>
  );
}

/**
 * The study's only authored motion. A shimmer on the status line while a
 * turn is running and has said nothing, and a slow pulse on live lamps.
 * Everything else is static on purpose.
 */
function KcdStyles() {
  return (
    <style>{`
      @keyframes kcdLive { 0%,100% { opacity: 1 } 50% { opacity: 0.28 } }
      @keyframes kcdShimmer { 0% { background-position: -140% 0 } 100% { background-position: 240% 0 } }
      .kcd-live { animation: kcdLive 1.25s ease-in-out infinite; }
      .kcd-shimmer {
        background-image: linear-gradient(100deg, transparent 34%, rgba(242,161,59,0.55) 50%, transparent 66%);
        background-size: 220% 100%;
        background-repeat: no-repeat;
        -webkit-background-clip: text;
        background-clip: text;
        animation: kcdShimmer 2.1s linear infinite;
      }
      @media (prefers-reduced-motion: reduce) {
        .kcd-live { animation: none; opacity: 0.85 }
        .kcd-shimmer { animation: none; background-image: none; }
      }
      .kcd-focus:focus-visible { outline: 2px solid var(--theme-amber); outline-offset: 1px; }
      .kcd-division:focus-visible { outline: 1.5px solid var(--theme-amber); outline-offset: -4px; }
      .kcd-cap-press:active { transform: translateY(1px); }
      .kcd-lab button:focus-visible, .kcd-lab input:focus-visible { outline: 1.5px solid #B5823A; outline-offset: 1px; }
    `}</style>
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
