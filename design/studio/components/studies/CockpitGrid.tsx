"use client";

/**
 * Home · Cockpit Grid — the cockpit, converged.
 *
 * Same chassis / dark-screen material vocabulary as /home-cockpit and
 * /led-messenger, recomposed as THREE full-width stacked rows inside one
 * instrument glass — no more 2-column grid:
 *
 *   ┌───────────────────────────────────────────┐
 *   │  MESSAGE LINE   (amber CRT terminal)        │  ← one derived fact
 *   ├───────────────────────────────────────────┤
 *   │  TAKE LOG       (3 tape-log rows)           │  ← recent captures
 *   ├───────────────────────────────────────────┤
 *   │  THE ROLL       (full-width contribution)   │  ← the streak roll
 *   └───────────────────────────────────────────┘
 *
 * This is a convergence pass — the treatment exploration is closed:
 *
 *   · MESSAGE LINE is the amber-CRT TERMINAL, and only the terminal: phosphor
 *     mono text, thin dark scanlines, a faint Bayer-ish dither, soft glow, a
 *     static block cursor when the line fits (a right-edge phosphor fade when it
 *     overflows). It takes ONE derived fact and fits it on a single line by
 *     pitch/advance — nothing scrolls, blinks, or animates. The shared LED
 *     MATRIX board still lives in ./ledBoard (used by /led-messenger); it is
 *     kept ONLY as a demoted, settled-decision reference row at the bottom.
 *
 *   · TAKE LOG replays the most recent captures as a tape-log readout — up to
 *     three mono phosphor rows on the dark glass, most recent first, each row a
 *     short title (truncating) · age · duration. Empty library ⇒ NO TAKES ON
 *     TAPE. Static.
 *
 *   · THE ROLL is the promoted Almanac — a full-width GitHub-contribution
 *     calendar. Now that it spans the whole width it widens to ~18 weeks at the
 *     same praised cell/marker language; the current streak run lights amber and
 *     ends on today's marker, with the STRK n readout.
 *
 * The harness varies DATA SCENARIOS only (layout + treatment frozen): a scenario
 * picker, a board of all five states, and the demoted Matrix-vs-Terminal
 * reference. Nothing animates.
 */

import { useMemo, useState } from "react";

import {
  DotMatrix,
  PITCH_PX,
  computeLine,
  type Material,
} from "./ledBoard";

// ── Shipped tactical palette (HomeTacticalPalette, HomeNextView.swift:365) ──
const P = {
  accent: "#FF8800",
  accentEdge: "rgba(255,136,0,0.34)",
  matte: "#303030",
  matteEdge: "#454545",
  screen: "#050505",
  screenInk: "#F3F1EA",
  screenInkFaint: "#A6A29A",
  canvas: "#E9E6DF",
} as const;

const MONO = "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace";

// Amber phosphor — the terminal's lit ink, shared by the Message Line + Take Log.
const PHOSPHOR = "#FFB24A";
const PHOSPHOR_GLOW =
  "0 0 1px rgba(255,205,130,0.9), 0 0 5px rgba(255,140,0,0.55)";

// Terminal dark glass — the shared material behind the Message Line + Take Log.
const TERM_GLASS: React.CSSProperties = {
  background:
    "radial-gradient(130% 200% at 50% 42%, rgba(255,140,0,0.12), transparent 60%), linear-gradient(180deg, #0b0704, #050301)",
  border: "1px solid rgba(255,136,0,0.16)",
  boxShadow:
    "inset 0 0 10px rgba(255,140,0,0.10), inset 0 1px 4px rgba(0,0,0,0.8)",
};

// ── Message Line — the slim single-line readout strip ─────────────────────
// One glyph row tall, full-width across the screen. TERMINAL is the treatment.
const LINE_W = 280; // px — text/dot content width inside the full-width strip
const LINE_H = 20; // px — one glyph row tall at fine pitch (7 rows), frozen
const STRIP_PAD_Y = 6; // px — vertical padding inside the strip
const STRIP_H = LINE_H + STRIP_PAD_Y * 2; // 32 — frozen strip outer height
const LINE_BASE_PITCH = PITCH_PX.fine; // 2 — base dot size (MATRIX reference only)
const LINE_MAT: Material = {
  pitch: "fine",
  shape: "round",
  bloom: true,
  ghost: true,
};

// TERMINAL treatment metrics — a monospace advance estimate lets us decide,
// deterministically (SSR-safe, no DOM measurement), whether the line fits (show
// the block cursor) or overflows (fade the right edge).
const TERM_FONT = 14; // px — cap height ≈ one glyph row
const TERM_CHAR = TERM_FONT * 0.62; // px — monospace glyph advance
function terminalOverflows(text: string): boolean {
  return (text.length + 2) * TERM_CHAR > LINE_W; // +2 leaves room for the cursor
}

type Treatment = "matrix" | "terminal";

// The Roll geometry — a full-width contribution grid, column-major (each column
// is a week, top→bottom = Sun→Sat). At the same praised cell size the full-width
// row honestly fits 18 weeks; today is fixed near the right edge so the last week
// reads as partial, the same across every scenario — layout is frozen, only the
// day intensities change.
const WEEKS = 18;
const DAYS = 7;
const CELL = 12; // px — one contribution cell (unchanged cell language)
const CGAP = 3; // px — gap between cells (unchanged)
const CELLS = WEEKS * DAYS; // 126
const TODAY_INDEX = 17 * DAYS + 2; // 121 — week 17, day 2 (a mid-week "today")

// ─────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────

type ScenarioKey =
  | "nominal"
  | "quiet"
  | "first-run"
  | "downloading"
  | "milestone";

/** One tape-log entry — a recent capture replayed on the Take Log. */
interface Take {
  /** short title (truncates honestly on overflow) */
  title: string;
  /** relative age — "20M" · "2H" · "1D" */
  age: string;
  /** duration — "0:42" */
  dur: string;
}

interface GridModel {
  /** header center readout */
  status: string;
  /** header right readout — wall clock */
  clock: string;
  /** the Message Line — ONE derived fact, rendered on a single line (static) */
  message: string;
  /** the Take Log — up to 3 recent captures, most recent first ([] = zero-state) */
  takes: Take[];
  /** 126 day intensities (0 = none · 1–3 brightness), oldest→newest. */
  calendar: number[];
}

interface Scenario {
  key: ScenarioKey;
  label: string;
  intent: string;
  model: GridModel;
}

/**
 * The trailing consecutive capture-day run ending on today (or on yesterday,
 * when today has no capture yet — the streak is still alive). Returns the cell
 * indices in the run; its length is the streak count. Derived from the same
 * day data the Roll paints — nothing about the streak is stored separately.
 */
function streakRun(calendar: number[], today: number): number[] {
  let end = -1;
  if (calendar[today] > 0) end = today;
  else if (today - 1 >= 0 && calendar[today - 1] > 0) end = today - 1;
  if (end < 0) return [];
  const run: number[] = [];
  for (let i = end; i >= 0 && calendar[i] > 0; i--) run.push(i);
  return run;
}

/** Deterministic hash → [0,1). SSR-safe (IEEE-754 identical server + client). */
function hash01(n: number): number {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

/**
 * Build a 126-cell Roll deterministically: scatter past days at `density`, then
 * carve an exact trailing run of `runLength` ending on today (or yesterday when
 * `endsToday` is false), clearing the cell just before the run so `streakRun`
 * reads the length exactly. `empty` returns a bare grid (first run).
 */
function buildRoll({
  seed,
  density,
  runLength,
  endsToday,
  empty = false,
}: {
  seed: number;
  density: number;
  runLength: number;
  endsToday: boolean;
  empty?: boolean;
}): number[] {
  const cal = new Array<number>(CELLS).fill(0);
  if (empty) return cal;
  for (let i = 0; i <= TODAY_INDEX; i++) {
    const r = hash01(i + seed * 1000);
    if (r < density) {
      cal[i] = r < density * 0.33 ? 3 : r < density * 0.66 ? 2 : 1;
    }
  }
  if (!endsToday) cal[TODAY_INDEX] = 0;
  const runEnd = endsToday ? TODAY_INDEX : TODAY_INDEX - 1;
  for (let k = 0; k < runLength; k++) {
    const idx = runEnd - k;
    if (idx < 0) break;
    cal[idx] = 1 + Math.floor(hash01(idx + seed * 1000 + 7) * 3); // 1..3, always lit
  }
  const beforeRun = runEnd - runLength;
  if (beforeRun >= 0) cal[beforeRun] = 0; // clean boundary → exact streak length
  return cal;
}

const SCENARIOS: Scenario[] = [
  {
    key: "nominal",
    label: "Nominal",
    intent:
      "Active day, healthy streak. The line reports the freshest fact; the Take Log replays today's three captures; the Roll's amber run of 5 ends on today's lit marker.",
    model: {
      status: "READY",
      clock: "20:04",
      message: "LAST TAKE 2H AGO",
      takes: [
        { title: "Standup blockers for the sprint review", age: "2H", dur: "0:42" },
        { title: "Grocery run", age: "5H", dur: "0:18" },
        { title: "Podcast cold-open idea", age: "1D", dur: "2:07" },
      ],
      calendar: buildRoll({ seed: 3, density: 0.5, runLength: 5, endsToday: true }),
    },
  },
  {
    key: "quiet",
    label: "Quiet",
    intent:
      "No takes today, but the streak is alive through yesterday. The line nudges ROLL TAPE; the Take Log's newest row is a day old; the amber run of 5 ends one cell short of today's unlit ring marker.",
    model: {
      status: "READY",
      clock: "18:47",
      message: "ROLL TAPE TODAY",
      takes: [
        { title: "Client recap + next steps", age: "1D", dur: "1:12" },
        { title: "Reading list", age: "2D", dur: "0:24" },
        { title: "Hallway voice note", age: "2D", dur: "0:51" },
      ],
      calendar: buildRoll({ seed: 8, density: 0.42, runLength: 5, endsToday: false }),
    },
  },
  {
    key: "first-run",
    label: "First run",
    intent:
      "Empty library. The line leads with the longest scenario string — STANDING BY — so the terminal overflows to a right-edge phosphor fade. The Take Log shows its zero-state; the Roll is bare, today just an unlit ring marker.",
    model: {
      status: "STANDBY",
      clock: "06:12",
      message: "STANDING BY — ROLL TAPE TO BEGIN",
      takes: [],
      calendar: buildRoll({ seed: 1, density: 0, runLength: 0, endsToday: false, empty: true }),
    },
  },
  {
    key: "downloading",
    label: "Downloading",
    intent:
      "Model still pulling down — the line carries the job (PARAKEET DOWNLOADING) instead of a take fact and the header reads PREP. A light early history: two takes on the log, a short 3-day run on the Roll. (Repurposed — the retired ENGINE tile used to own the download meter; the download fact now lives on the Message Line.)",
    model: {
      status: "PREP",
      clock: "09:31",
      message: "PARAKEET DOWNLOADING",
      takes: [
        { title: "First memo", age: "20M", dur: "0:48" },
        { title: "Mic test", age: "2H", dur: "0:12" },
      ],
      calendar: buildRoll({ seed: 5, density: 0.3, runLength: 3, endsToday: true }),
    },
  },
  {
    key: "milestone",
    label: "Streak milestone",
    intent:
      "A long unbroken run — 14 days lit amber across the Roll, ending on today. The line calls out the take count; the Take Log replays the day's longest sessions.",
    model: {
      status: "READY",
      clock: "21:15",
      message: "TAKE #128 ON TAPE",
      takes: [
        { title: "Chapter 12 draft — revised open", age: "1H", dur: "6:30" },
        { title: "Interview pull quotes", age: "3H", dur: "4:15" },
        { title: "Melody hum", age: "6H", dur: "0:33" },
      ],
      calendar: buildRoll({ seed: 12, density: 0.62, runLength: 14, endsToday: true }),
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────
//  Terminal overlays — shared low-fi CRT grain (scanlines + dither)
// ─────────────────────────────────────────────────────────────────────────

/** Faint Bayer-ish checkerboard, screen-blended over the phosphor. Static. */
function Dither() {
  return (
    <div
      aria-hidden
      style={{
        position: "absolute",
        inset: 0,
        pointerEvents: "none",
        opacity: 0.5,
        mixBlendMode: "screen",
        backgroundImage:
          "conic-gradient(rgba(255,180,90,0.07) 0 25%, transparent 0 50%, rgba(255,180,90,0.07) 0 75%, transparent 0)",
        backgroundSize: "3px 3px",
      }}
    />
  );
}

/** Thin dark raster lines over the whole strip. Static, no roll. */
function Scanlines() {
  return (
    <div
      aria-hidden
      style={{
        position: "absolute",
        inset: 0,
        pointerEvents: "none",
        backgroundImage:
          "repeating-linear-gradient(0deg, rgba(0,0,0,0.30) 0px, rgba(0,0,0,0.30) 1px, transparent 1px, transparent 3px)",
      }}
    />
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Message Line — TERMINAL (the treatment) · MATRIX kept for reference only
// ─────────────────────────────────────────────────────────────────────────

/** MATRIX — the shared LED dot-matrix board (kept only for the settled-decision reference). */
function MatrixLine({ text, style }: { text: string; style?: React.CSSProperties }) {
  const board = useMemo(
    () => computeLine(text, LINE_BASE_PITCH, LINE_W, LINE_H),
    [text]
  );
  return (
    <div
      style={{
        ...style,
        height: STRIP_H,
        boxSizing: "border-box",
        borderRadius: 6,
        padding: `${STRIP_PAD_Y}px 8px`,
        overflow: "hidden",
        background: "#080604",
        border: "1px solid rgba(255,136,0,0.16)",
        boxShadow: "inset 0 1px 4px rgba(0,0,0,0.7)",
      }}
    >
      <DotMatrix board={board} mat={LINE_MAT} height={LINE_H} />
    </div>
  );
}

/**
 * TERMINAL — an old-school CRT readout: amber phosphor mono text with a soft
 * glow, thin dark scanlines, a faint dither, and a static block cursor when the
 * line fits (a right-edge phosphor fade when it overflows). Strictly
 * non-animating — no flicker, no blink, no scroll.
 */
function TerminalLine({ text, style }: { text: string; style?: React.CSSProperties }) {
  const upper = text.toUpperCase();
  const overflow = terminalOverflows(upper);
  const fade = "linear-gradient(90deg, #000 74%, transparent)";
  return (
    <div
      style={{
        ...style,
        ...TERM_GLASS,
        position: "relative",
        height: STRIP_H,
        boxSizing: "border-box",
        borderRadius: 6,
        overflow: "hidden",
      }}
    >
      {/* PHOSPHOR — amber mono text, glowing, with a static block cursor */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          alignItems: "center",
          padding: "0 9px",
          WebkitMaskImage: overflow ? fade : undefined,
          maskImage: overflow ? fade : undefined,
        }}
      >
        <span
          style={{
            whiteSpace: "nowrap",
            fontFamily: MONO,
            fontSize: TERM_FONT,
            fontWeight: 500,
            letterSpacing: "0.06em",
            lineHeight: 1,
            color: PHOSPHOR,
            textShadow: PHOSPHOR_GLOW,
          }}
        >
          {upper}
          {!overflow && (
            <span
              aria-hidden
              style={{
                display: "inline-block",
                width: TERM_CHAR * 0.9,
                height: TERM_FONT * 0.95,
                marginLeft: 3,
                verticalAlign: "-0.14em",
                background: PHOSPHOR,
                borderRadius: 1,
                boxShadow: "0 0 6px rgba(255,150,0,0.8)",
              }}
            />
          )}
        </span>
      </div>
      <Dither />
      <Scanlines />
    </div>
  );
}

function MessageLine({
  text,
  treatment,
  style,
}: {
  text: string;
  treatment: Treatment;
  style?: React.CSSProperties;
}) {
  return treatment === "terminal" ? (
    <TerminalLine text={text} style={style} />
  ) : (
    <MatrixLine text={text} style={style} />
  );
}

/** A compact caption reporting how the terminal fit the current line. */
function LineFitNote({ text }: { text: string }) {
  const bits = [
    "TERMINAL",
    `${text.length} CH`,
    terminalOverflows(text) ? "RIGHT-EDGE FADE" : "BLOCK CURSOR",
  ];
  return (
    <p className="px-1 font-mono text-[10px] uppercase tracking-[0.12em] text-stone-400">
      {bits.join(" · ")}
    </p>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Take Log — the most recent captures replayed as a tape-log readout
// ─────────────────────────────────────────────────────────────────────────

function TakeRow({ take, last }: { take: Take; last: boolean }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "baseline",
        gap: 10,
        padding: "5px 0",
        borderBottom: last ? "0" : "1px solid rgba(255,136,0,0.09)",
        fontFamily: MONO,
      }}
    >
      {/* title — flexes and truncates honestly */}
      <span
        style={{
          flex: 1,
          minWidth: 0,
          overflow: "hidden",
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
          fontSize: 12.5,
          letterSpacing: "0.01em",
          color: PHOSPHOR,
          textShadow: PHOSPHOR_GLOW,
        }}
      >
        {take.title}
      </span>
      {/* age — dimmer phosphor, fixed lane */}
      <span
        style={{
          fontSize: 11,
          fontVariantNumeric: "tabular-nums",
          letterSpacing: "0.08em",
          color: "rgba(255,178,74,0.55)",
        }}
      >
        {take.age}
      </span>
      {/* duration — lit phosphor, tabular, fixed lane */}
      <span
        style={{
          minWidth: 32,
          textAlign: "right",
          fontSize: 11.5,
          fontVariantNumeric: "tabular-nums",
          letterSpacing: "0.04em",
          color: PHOSPHOR,
          textShadow: PHOSPHOR_GLOW,
        }}
      >
        {take.dur}
      </span>
    </div>
  );
}

function TakeLog({ takes, style }: { takes: Take[]; style?: React.CSSProperties }) {
  const empty = takes.length === 0;
  return (
    <div
      style={{
        ...style,
        ...TERM_GLASS,
        position: "relative",
        boxSizing: "border-box",
        borderRadius: 6,
        overflow: "hidden",
        padding: "8px 11px",
      }}
    >
      {/* header — TAKE LOG · n ON TAPE */}
      <div
        style={{
          display: "flex",
          alignItems: "baseline",
          justifyContent: "space-between",
          marginBottom: empty ? 0 : 4,
          fontFamily: MONO,
          fontSize: 8,
          fontWeight: 600,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          color: "rgba(255,178,74,0.6)",
          position: "relative",
          zIndex: 1,
        }}
      >
        <span>TAKE LOG</span>
        <span>{empty ? "—" : `${takes.length} ON TAPE`}</span>
      </div>

      <div style={{ position: "relative", zIndex: 1 }}>
        {empty ? (
          <div
            style={{
              padding: "12px 0",
              textAlign: "center",
              fontFamily: MONO,
              fontSize: 12,
              letterSpacing: "0.14em",
              color: "rgba(255,178,74,0.34)",
            }}
          >
            NO TAKES ON TAPE
          </div>
        ) : (
          takes.map((t, i) => (
            <TakeRow key={i} take={t} last={i === takes.length - 1} />
          ))
        )}
      </div>

      <Dither />
      <Scanlines />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  The Roll — the promoted, full-width contribution calendar
// ─────────────────────────────────────────────────────────────────────────

/** Neutral (non-streak) brightness step for an active day. */
function activeInk(intensity: number): string {
  if (intensity >= 3) return "rgba(255,255,255,0.85)";
  if (intensity === 2) return "rgba(255,255,255,0.55)";
  return "rgba(255,255,255,0.30)";
}

function RollCell({
  intensity,
  today,
  inRun,
  future,
}: {
  intensity: number;
  today: boolean;
  inRun: boolean;
  future: boolean;
}) {
  let background = "rgba(255,255,255,0.05)"; // empty past day
  let boxShadow = "none";
  let border = "0";

  if (future) {
    background = "rgba(255,255,255,0.03)";
  } else if (today && intensity > 0) {
    // today, captured — the marker treatment (amber + glow).
    background = P.accent;
    boxShadow = "0 0 5px rgba(255,136,0,0.85)";
  } else if (today) {
    // today, no capture yet — an unlit amber ring marker.
    background = "transparent";
    border = `1px solid ${P.accent}`;
  } else if (inRun) {
    // part of the current streak run — amber, brightness by intensity.
    background = `rgba(255,136,0,${(0.7 + intensity * 0.1).toFixed(2)})`;
    boxShadow = "0 0 3px rgba(255,136,0,0.4)";
  } else if (intensity > 0) {
    background = activeInk(intensity);
  }

  return (
    <span
      style={{
        width: CELL,
        height: CELL,
        borderRadius: 2,
        background,
        boxShadow,
        border,
        boxSizing: "border-box",
      }}
    />
  );
}

function Roll({
  calendar,
  style,
}: {
  calendar: number[];
  style?: React.CSSProperties;
}) {
  const run = streakRun(calendar, TODAY_INDEX);
  const runSet = useMemo(() => new Set(run), [run]);
  const streak = run.length;
  return (
    <div
      style={{
        ...style,
        display: "flex",
        flexDirection: "column",
        gap: 8,
        padding: 9,
        borderRadius: 8,
        background: "rgba(255,255,255,0.035)",
        border: "1px solid rgba(255,255,255,0.08)",
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "baseline",
          fontFamily: MONO,
          fontSize: 7,
          fontWeight: 600,
          letterSpacing: "0.06em",
          textTransform: "uppercase",
          color: P.screenInkFaint,
        }}
      >
        <span>THE ROLL</span>
        <span style={{ color: streak > 0 ? P.accent : P.screenInkFaint }}>
          STRK {streak}
        </span>
      </div>
      <div
        aria-hidden
        style={{
          display: "grid",
          gridTemplateColumns: `repeat(${WEEKS}, ${CELL}px)`,
          gridTemplateRows: `repeat(${DAYS}, ${CELL}px)`,
          gridAutoFlow: "column", // fill column-by-column = week-by-week
          gap: CGAP,
          justifyContent: "center", // center the roll across the full-width row
        }}
      >
        {calendar.map((intensity, i) => (
          <RollCell
            key={i}
            intensity={intensity}
            today={i === TODAY_INDEX}
            inRun={runSet.has(i)}
            future={i > TODAY_INDEX}
          />
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  The Screen — three full-width rows: Message Line · Take Log · the Roll
// ─────────────────────────────────────────────────────────────────────────

function Screen({ model }: { model: GridModel }) {
  return (
    <div
      style={{
        borderRadius: 14,
        padding: "10px 12px",
        overflow: "hidden",
        background: `radial-gradient(circle at 50% 40%, rgba(255,136,0,0.20), transparent 48%), linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02) 45%, rgba(0,0,0,0.24)), ${P.screen}`,
        border: `0.8px solid ${P.accentEdge}`,
        boxShadow:
          "inset 0 0.5px 0 rgba(255,255,255,0.14), inset 0 -18px 28px -28px rgba(0,0,0,0.85)",
      }}
    >
      {/* header: TALKIE · status · clock */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: 8,
          fontFamily: MONO,
          fontSize: 8,
          fontWeight: 600,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          color: P.screenInkFaint,
        }}
      >
        <span>TALKIE</span>
        <span style={{ color: P.accent }}>{model.status}</span>
        <span style={{ fontVariantNumeric: "tabular-nums" }}>{model.clock}</span>
      </div>

      {/* three stacked full-width rows */}
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        <MessageLine text={model.message} treatment="terminal" />
        <TakeLog takes={model.takes} />
        <Roll calendar={model.calendar} />
      </div>
    </div>
  );
}

/**
 * CockpitGrid — the full instrument on Home: `· COCKPIT GRID` eyebrow over the
 * raised metal chassis, screen inside. Rendered at true iPhone content width.
 */
function CockpitGrid({ model }: { model: GridModel }) {
  return (
    <div style={{ width: 366, background: P.canvas, padding: "10px 12px 14px", borderRadius: 20 }}>
      <div
        style={{
          fontFamily: MONO,
          fontSize: 9,
          fontWeight: 600,
          letterSpacing: "0.18em",
          textTransform: "uppercase",
          color: "#6f6a62",
          paddingLeft: 4,
          marginBottom: 8,
        }}
      >
        · Cockpit Grid
      </div>
      {/* raised metal chassis — bezelChassis(padding:10, corner:14, metal) */}
      <div
        style={{
          borderRadius: 14,
          padding: 10,
          background: `linear-gradient(180deg, ${P.matteEdge}, ${P.matte} 52%, #262626)`,
          border: "0.8px solid rgba(0,0,0,0.5)",
          boxShadow:
            "inset 0 1px 0 rgba(255,255,255,0.18), 0 10px 24px -14px rgba(0,0,0,0.55)",
        }}
      >
        <Screen model={model} />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Harness
// ─────────────────────────────────────────────────────────────────────────

function Segmented({
  options,
  value,
  onChange,
}: {
  options: { value: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="inline-flex rounded-lg border border-stone-200 bg-white p-1">
      {options.map((o) => {
        const on = o.value === value;
        return (
          <button
            key={o.value}
            onClick={() => onChange(o.value)}
            className={`rounded-md px-3 py-1.5 font-mono text-[11px] uppercase tracking-[0.12em] transition ${
              on ? "bg-stone-900 text-white" : "text-stone-500 hover:text-stone-800"
            }`}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

function SectionHeading({ label, hint }: { label: string; hint: string }) {
  return (
    <div className="flex items-baseline gap-3">
      <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em] text-stone-600">
        {label}
      </span>
      <span className="italic text-stone-400" style={{ fontSize: 12 }}>
        {hint}
      </span>
      <div className="ml-1 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
    </div>
  );
}

/** Data-source legend — proves nothing on the composition is a placeholder. */
const SOURCES: [string, string][] = [
  [
    "Message Line",
    "One derived fact — the freshest signal (last take · roll-tape nudge · download job · milestone count · STANDING BY on an empty library) — rendered on a single terminal line. Fit by advance; the longest strings fade at the right edge. Static.",
  ],
  [
    "Take Log",
    "HomeFeed.recentItems / VoiceMemo (title, createdAt, duration) + KeyboardDictationStore — the most recent captures, newest first. Each row: title (truncates) · age · duration. Empty library ⇒ NO TAKES ON TAPE.",
  ],
  [
    "the Roll",
    "createdAt across VoiceMemo + KeyboardDictationStore + CaptureStore, last ~18 weeks. Cell intensity = captures that day. Streak Run + STRK n derived from the same days; Today Marker = the newest cell.",
  ],
];

function SourceLegend() {
  return (
    <div
      className="grid"
      style={{
        gridTemplateColumns: "130px 1fr",
        rowGap: 8,
        columnGap: 18,
        padding: "16px 20px",
        background: "#FFFFFF",
        border: "0.5px solid #DEDEDD",
        borderRadius: 8,
      }}
    >
      {SOURCES.map(([name, def]) => (
        <div key={name} className="contents">
          <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-stone-700">
            {name}
          </span>
          <span style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>{def}</span>
        </div>
      ))}
    </div>
  );
}

function Picker() {
  const [key, setKey] = useState<ScenarioKey>("nominal");
  const active = SCENARIOS.find((s) => s.key === key) ?? SCENARIOS[0];
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Scenario picker"
        hint="pick a data scenario — the composition (Message Line · Take Log · the Roll) and its terminal treatment are frozen; only content + state change"
      />
      <div className="flex flex-col gap-1.5">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.18em] text-stone-500">
          Scenario
        </span>
        <Segmented
          options={SCENARIOS.map((s) => ({ value: s.key, label: s.label }))}
          value={key}
          onChange={(v) => setKey(v as ScenarioKey)}
        />
      </div>
      <p className="max-w-[680px] text-[12.5px] italic leading-relaxed text-stone-500">
        <span className="font-mono not-italic uppercase tracking-[0.14em] text-stone-700">
          {active.label}
        </span>
        {" — "}
        {active.intent}
      </p>
      <div className="flex flex-col items-start gap-2">
        <CockpitGrid model={active.model} />
        <LineFitNote text={active.model.message} />
      </div>
    </div>
  );
}

function Board() {
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="All scenarios"
        hint="the five data states side by side — one frozen composition, five contents, in the terminal treatment"
      />
      <div className="flex flex-wrap gap-7">
        {SCENARIOS.map((s) => (
          <div key={s.key} className="flex flex-col gap-2">
            <div className="flex items-baseline gap-2 px-1">
              <span className="font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-700">
                {s.label}
              </span>
            </div>
            <CockpitGrid model={s.model} />
            <p className="max-w-[366px] px-1 text-[11px] leading-snug text-stone-400">
              {s.intent}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

/**
 * A single demoted reference row — the SAME message in both materials, labeled
 * as a settled decision. The exploration is over: TERMINAL is the treatment;
 * MATRIX (the shared LED board) is kept in ./ledBoard because /led-messenger
 * uses it, not because this composition is still choosing.
 */
function SettledReference() {
  const message = "LAST TAKE 2H AGO";
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Message line · settled"
        hint="decision closed — Terminal is the composition's voice; Matrix stays in ledBoard for /led-messenger"
      />
      <div className="flex flex-wrap items-end gap-x-10 gap-y-4">
        <div className="flex flex-col gap-1.5">
          <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-stone-400">
            Matrix — LED dot-matrix · retired here
          </span>
          <MessageLine text={message} treatment="matrix" style={{ width: 280 }} />
        </div>
        <div className="flex flex-col gap-1.5">
          <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-stone-700">
            Terminal — amber CRT · in use
          </span>
          <MessageLine text={message} treatment="terminal" style={{ width: 280 }} />
        </div>
      </div>
    </div>
  );
}

export function CockpitGridStudio() {
  return (
    <div className="flex flex-col gap-12">
      <Picker />
      <Board />
      <SettledReference />
      <div className="flex flex-col gap-5">
        <SectionHeading
          label="Data sources"
          hint="every readout is backed by a verified iOS publisher — no placeholders"
        />
        <SourceLegend />
      </div>
    </div>
  );
}
