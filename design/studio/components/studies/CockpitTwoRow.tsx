"use client";

/**
 * Home · Cockpit Two-Row — the converged cockpit.
 *
 * This is a CONVERGENCE, not another fan-out. The material language is SETTLED
 * (see /cockpit-grid + /cockpit-compact) and re-used verbatim: the amber-CRT
 * Terminal Message Line (phosphor mono + scanlines + dither + static block
 * cursor), the Roll's contribution cells with an amber Streak Run + Today
 * Marker, the v2 instrument vocabulary (12-segment Meter today-vs-7-day-avg +
 * pace label, Life-in-Dots). Nothing is redesigned here — parts are re-seated.
 *
 * What the verdict picked out of the /cockpit-compact board:
 *
 *   · the BEZEL ON metal wrap is the frame — the Console is that wrap around
 *     the whole instrument (the hardware charm the user loved).
 *   · the TWO-ROW BASELINE layout is good — BUT its header is dropped entirely:
 *     no "TALKIE" repeat, no clock (iOS already shows a clock top-right), no
 *     status word. The Message Line goes straight on top.
 *   · "instead of the clock, something else useful" → a small right-docked
 *     Docked Readout ON the Message Line (HUD-strip vocabulary: STRK n or the
 *     day's take count), shown here with + without.
 *   · the big section is a user-controlled TOGGLE between two pages:
 *       THE ROLL   — the 18×7 contribution calendar, as-is.
 *       GAUGES     — instrument content that reads gauge-like (NOT a Take Log
 *                    replay — the list is dead, ENGINE is killed): TAKES today
 *                    (count + Meter vs 7-day avg + pace) · TIME today (m:ss +
 *                    Meter) · STRK (Life-in-Dots + count).
 *     The Toggle is a tiny hardware two-position Bay Selector on the section's
 *     label row. The studio is STATIC — both toggle states are drawn side by
 *     side with the affordance shown in each position.
 *   · the Message Line as a system — the "Strip System" board seats the bare
 *     36pt strip in ghosted non-Home contexts (Library · Ask AI · Settings),
 *     one message area travelling the app.
 *
 * Heights are declared once (as explicit constants) and used BOTH to render and
 * to annotate, so the pt labels can never drift from the pixels. The Console
 * comes in AT the target — under the old 231pt Two-Row Baseline — by dropping
 * the header. Nothing animates.
 */

import { useMemo } from "react";

// ── Shipped tactical palette — frozen (HomeTacticalPalette / CockpitGrid) ──
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

// Amber phosphor — the Terminal's lit ink (shared vocabulary with /cockpit-grid).
const PHOSPHOR = "#FFB24A";
const PHOSPHOR_DIM = "rgba(255,178,74,0.5)";
const PHOSPHOR_GLOW =
  "0 0 1px rgba(255,205,130,0.9), 0 0 5px rgba(255,140,0,0.55)";

// Terminal dark glass — the shared strip material.
const TERM_GLASS: React.CSSProperties = {
  background:
    "radial-gradient(130% 200% at 50% 42%, rgba(255,140,0,0.12), transparent 60%), linear-gradient(180deg, #0b0704, #050301)",
  border: "1px solid rgba(255,136,0,0.16)",
  boxShadow:
    "inset 0 0 10px rgba(255,140,0,0.10), inset 0 1px 4px rgba(0,0,0,0.8)",
};

// The instrument's dark-glass screen — the surface the metal Bezel wraps.
const SCREEN_GLASS: React.CSSProperties = {
  background: `radial-gradient(circle at 50% 40%, rgba(255,136,0,0.20), transparent 48%), linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02) 45%, rgba(0,0,0,0.24)), ${P.screen}`,
  border: `0.8px solid ${P.accentEdge}`,
  boxShadow:
    "inset 0 0.5px 0 rgba(255,255,255,0.14), inset 0 -18px 28px -28px rgba(0,0,0,0.85)",
};

// The raised metal Bezel — the frame the verdict kept (BEZEL ON).
const BEZEL_METAL: React.CSSProperties = {
  background: `linear-gradient(180deg, ${P.matteEdge}, ${P.matte} 52%, #262626)`,
  border: "0.8px solid rgba(0,0,0,0.5)",
  boxShadow:
    "inset 0 1px 0 rgba(255,255,255,0.18), 0 10px 24px -14px rgba(0,0,0,0.55)",
};

// A recessed inset panel — the Bay's own well (Roll block / gauge lanes).
const INSET_WELL: React.CSSProperties = {
  background: "rgba(255,255,255,0.035)",
  border: "1px solid rgba(255,255,255,0.08)",
};

// ── Frozen geometry — declared once, used to render AND to annotate ─────────
const CONTENT_W = 366; // px — true iPhone content width
const BEZEL_PAD = 7; // px — the metal Bezel's padding (the frame)
const SCREEN_PAD = 10; // px — the dark-glass screen's inner padding
const STRIP_PAD_X = 10; // px — Message Line inner horizontal padding
const STACK_GAP = 8; // px — gap between the Message Line and the Bay

const MSG_H = 32; // px — the Message Line strip (no header above it)
const MSG_FONT = 15; // px — phosphor cap height ≈ the 32pt line
const MSG_CHAR = MSG_FONT * 0.62; // px — monospace advance (SSR-safe fit)

// The Roll — the 18×7 contribution calendar, as-is (from /cockpit-grid).
const WEEKS = 18;
const DAYS = 7;
const CELL = 12; // px — one contribution cell (unchanged cell language)
const CGAP = 3; // px — gap between cells (unchanged)
const CELLS = WEEKS * DAYS; // 126
const TODAY_INDEX = 17 * DAYS + 2; // 121 — week 17, day 2 (a mid-week "today")
const ROLL_GRID_H = DAYS * CELL + (DAYS - 1) * CGAP; // 102 — drives the Bay height

// The Bay — the toggled big section. Both pages (Roll · Gauges) fill the SAME
// well, so the toggle swaps content with no layout shift.
const BAY_PAD = 10;
const BAY_LABEL_H = 14; // px — the label row (Toggle + readout)
const BAY_LABEL_GAP = 8;
const BAY_CONTENT_H = ROLL_GRID_H; // 102 — the Roll grid is the driver
const BAY_H = BAY_PAD * 2 + BAY_LABEL_H + BAY_LABEL_GAP + BAY_CONTENT_H; // 144

// The whole Console — Message Line over the Bay, inside the metal Bezel.
const SCREEN_H = SCREEN_PAD * 2 + MSG_H + STACK_GAP + BAY_H; // 204
const CONSOLE_H = BEZEL_PAD * 2 + SCREEN_H + 2; // 220 (+ Bezel/screen borders)
const SCREEN_CONTENT_W = CONTENT_W - BEZEL_PAD * 2 - SCREEN_PAD * 2; // 332

// GAUGES — three gauge lanes fitting the SAME content well (sums to 102).
const G_TAKES_H = 28;
const G_TIME_H = 28;
const G_STRK_H = 38;
const G_GAP = 4; // 28 + 28 + 38 + 2·4 = 102 = BAY_CONTENT_H

// Life-in-Dots — the v2 6×2 module, last 12 days.
const DOT_DAYS = 12;
const DOT = 7; // px
const DOT_GAP = 4;

// The Docked Readout lane on the Message Line (replaces the dropped clock).
const DOCK_W = 96;

// The Strip System — the bare Message Line at its 36pt form, no Bezel.
const STRIP_H = 36;

// Fit the terminal line deterministically (SSR-safe, no DOM measure).
function overflowsIn(text: string, contentW: number): boolean {
  return (text.length + 2) * MSG_CHAR > contentW;
}
const clamp01 = (n: number) => Math.max(0, Math.min(1, n));

// ─────────────────────────────────────────────────────────────────────────
//  Data model — two scenarios (NOMINAL + FIRST-RUN / standby), per page
// ─────────────────────────────────────────────────────────────────────────

interface ConsoleModel {
  /** the Message Line — ONE derived fact, single terminal line (static) */
  message: string;
  /** 126 day intensities (0 none · 1–3), oldest→newest — the Roll + streak */
  calendar: number[];
  /** GAUGES · # takes each of the last 7 days (oldest→today) — TAKES gauge */
  takesByDay: number[];
  /** GAUGES · total capture seconds each of the last 7 days — TIME gauge */
  secByDay: number[];
  /** first-run / empty library — the elevated standby (Ghost Cells + DAY 1) */
  standby?: boolean;
}

/** Deterministic hash → [0,1). SSR-safe (IEEE-754 identical server + client). */
function hash01(n: number): number {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

/** Build a 126-cell Roll with an exact trailing streak run (from /cockpit-grid). */
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
    if (r < density) cal[i] = r < density * 0.33 ? 3 : r < density * 0.66 ? 2 : 1;
  }
  if (!endsToday) cal[TODAY_INDEX] = 0;
  const runEnd = endsToday ? TODAY_INDEX : TODAY_INDEX - 1;
  for (let k = 0; k < runLength; k++) {
    const idx = runEnd - k;
    if (idx < 0) break;
    cal[idx] = 1 + Math.floor(hash01(idx + seed * 1000 + 7) * 3);
  }
  const beforeRun = runEnd - runLength;
  if (beforeRun >= 0) cal[beforeRun] = 0; // clean boundary → exact streak length
  return cal;
}

/** Trailing consecutive capture-day run ending on today (or yesterday). */
function streakRun(calendar: number[]): number[] {
  let end = -1;
  if (calendar[TODAY_INDEX] > 0) end = TODAY_INDEX;
  else if (TODAY_INDEX - 1 >= 0 && calendar[TODAY_INDEX - 1] > 0) end = TODAY_INDEX - 1;
  if (end < 0) return [];
  const run: number[] = [];
  for (let i = end; i >= 0 && calendar[i] > 0; i--) run.push(i);
  return run;
}

const mean = (a: number[]) => (a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0);

function fmtDur(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.round(sec % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

const NOMINAL: ConsoleModel = {
  message: "LAST TAKE 2H AGO",
  calendar: buildRoll({ seed: 3, density: 0.5, runLength: 5, endsToday: true }),
  takesByDay: [2, 0, 3, 1, 2, 4, 3], // today = 3, 7-day avg ≈ 2.1
  secByDay: [180, 0, 260, 90, 150, 420, 252], // today = 4:12, avg ≈ 3:13
};

const FIRST_RUN: ConsoleModel = {
  message: "STANDING BY — ROLL TAPE TO BEGIN",
  calendar: buildRoll({ seed: 1, density: 0, runLength: 0, endsToday: false, empty: true }),
  takesByDay: [0, 0, 0, 0, 0, 0, 0],
  secByDay: [0, 0, 0, 0, 0, 0, 0],
  standby: true,
};

// Meter full-bar scales — a full 12-seg bar = a strong day.
const SCALE_TAKES = 4; // 4 takes fills the bar
const SCALE_TIME = 360; // 6:00 of capture fills the bar

// ─────────────────────────────────────────────────────────────────────────
//  Terminal overlays — shared low-fi CRT grain (settled, static)
// ─────────────────────────────────────────────────────────────────────────

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

/** Amber phosphor mono line + static block cursor (fits) / right fade (over). */
function Phosphor({
  text,
  contentW,
  padRight = 0,
}: {
  text: string;
  contentW: number;
  padRight?: number;
}) {
  const upper = text.toUpperCase();
  const overflow = overflowsIn(upper, contentW);
  const fade = "linear-gradient(90deg, #000 78%, transparent)";
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "center",
        padding: `0 ${STRIP_PAD_X}px`,
        paddingRight: padRight ? padRight + STRIP_PAD_X : STRIP_PAD_X,
        WebkitMaskImage: overflow ? fade : undefined,
        maskImage: overflow ? fade : undefined,
      }}
    >
      <span
        style={{
          whiteSpace: "nowrap",
          fontFamily: MONO,
          fontSize: MSG_FONT,
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
              width: MSG_CHAR * 0.9,
              height: MSG_FONT * 0.95,
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
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Docked Readout — the useful right-docked slot that replaces the clock
// ─────────────────────────────────────────────────────────────────────────

type DockKind = "none" | "strk" | "takes";

/** A small HUD-strip readout docked on the right of the Message Line. */
function DockedReadout({ kind, model }: { kind: Exclude<DockKind, "none">; model: ConsoleModel }) {
  const streak = useMemo(() => streakRun(model.calendar).length, [model.calendar]);
  const takesToday = model.takesByDay[model.takesByDay.length - 1] ?? 0;

  let label: string;
  let value: string;
  let hot: boolean;
  if (kind === "strk") {
    label = "STRK";
    value = model.standby ? "DAY 1" : String(streak);
    hot = model.standby || streak > 0;
  } else {
    label = "TAKES";
    value = model.standby ? "0" : String(takesToday);
    hot = !model.standby && takesToday > 0;
  }
  return (
    <div
      style={{
        position: "absolute",
        top: 0,
        bottom: 0,
        right: 0,
        width: DOCK_W,
        zIndex: 1,
        display: "flex",
        alignItems: "center",
        justifyContent: "flex-end",
        gap: 6,
        paddingRight: STRIP_PAD_X,
        // a hairline divider + a whisper of glass so the slot reads as its own lane
        borderLeft: "1px solid rgba(255,136,0,0.16)",
        background: "linear-gradient(90deg, transparent, rgba(255,140,0,0.05))",
      }}
    >
      <span
        style={{
          fontFamily: MONO,
          fontSize: 8,
          fontWeight: 600,
          letterSpacing: "0.14em",
          color: PHOSPHOR_DIM,
        }}
      >
        {label}
      </span>
      <span
        style={{
          fontFamily: MONO,
          fontSize: 13,
          fontWeight: 700,
          fontVariantNumeric: "tabular-nums",
          letterSpacing: "0.04em",
          color: hot ? P.accent : PHOSPHOR_DIM,
          textShadow: hot ? "0 0 5px rgba(255,136,0,0.5)" : "none",
        }}
      >
        {value}
      </span>
    </div>
  );
}

/** The Message Line — settled Terminal strip, with an optional Docked Readout. */
function MessageLine({
  model,
  height = MSG_H,
  width = "100%",
  contentW,
  dock = "none",
}: {
  model: ConsoleModel;
  height?: number;
  width?: number | string;
  /** text content width used for the fit decision (excludes the dock) */
  contentW: number;
  dock?: DockKind;
}) {
  const docked = dock !== "none";
  return (
    <div
      style={{
        ...TERM_GLASS,
        position: "relative",
        width,
        height,
        boxSizing: "border-box",
        borderRadius: 7,
        overflow: "hidden",
      }}
    >
      <Phosphor
        text={model.message}
        contentW={docked ? contentW - DOCK_W : contentW}
        padRight={docked ? DOCK_W : 0}
      />
      {docked && <DockedReadout kind={dock} model={model} />}
      <Dither />
      <Scanlines />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  The Roll — the promoted, full-width 18×7 contribution calendar (as-is)
// ─────────────────────────────────────────────────────────────────────────

function activeInk(intensity: number): string {
  if (intensity >= 3) return "rgba(255,255,255,0.85)";
  if (intensity === 2) return "rgba(255,255,255,0.55)";
  return "rgba(255,255,255,0.30)";
}

function RollCell({
  intensity,
  today,
  inRun,
  ghost,
}: {
  intensity: number;
  today: boolean;
  inRun: boolean;
  /** standby — draw an outlined Ghost Cell, today as the amber Seed */
  ghost: boolean;
}) {
  let background = "rgba(255,255,255,0.05)";
  let boxShadow = "none";
  let border = "0";
  if (ghost && today) {
    // the amber Today Seed — the "you are here" the streak grows from.
    background = "transparent";
    border = `1.5px solid ${P.accent}`;
    boxShadow = "0 0 6px rgba(255,136,0,0.7)";
  } else if (ghost) {
    background = "transparent";
    border = "1px solid rgba(255,255,255,0.11)"; // Ghost Cell
  } else if (today && intensity > 0) {
    background = P.accent;
    boxShadow = "0 0 5px rgba(255,136,0,0.85)";
  } else if (today) {
    background = "transparent";
    border = `1px solid ${P.accent}`;
  } else if (inRun) {
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

/** THE ROLL page — the 18×7 grid, streak run lit amber, Today Marker. */
function RollBay({ model }: { model: ConsoleModel }) {
  const run = useMemo(() => streakRun(model.calendar), [model.calendar]);
  const runSet = useMemo(() => new Set(run), [run]);
  const ghost = !!model.standby;
  return (
    <div
      aria-hidden
      style={{
        height: BAY_CONTENT_H,
        display: "grid",
        gridTemplateColumns: `repeat(${WEEKS}, ${CELL}px)`,
        gridTemplateRows: `repeat(${DAYS}, ${CELL}px)`,
        gridAutoFlow: "column", // fill week-by-week
        gap: CGAP,
        justifyContent: "center", // center the roll across the well
        alignContent: "center",
      }}
    >
      {model.calendar.map((intensity, i) => (
        <RollCell
          key={i}
          intensity={intensity}
          today={i === TODAY_INDEX}
          inRun={runSet.has(i)}
          ghost={ghost}
        />
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  GAUGES — instrument content that reads gauge-like (NOT a Take Log replay)
// ─────────────────────────────────────────────────────────────────────────

/** The slim 12-segment Meter: fill = today, brighter amber tick = 7-day avg. */
function SegMeter({
  todayLevel,
  avgLevel,
  standby,
  height = 6,
}: {
  todayLevel: number;
  avgLevel: number;
  standby: boolean;
  height?: number;
}) {
  const filled = standby ? 0 : Math.round(clamp01(todayLevel) * 12);
  const avgIndex = standby ? 0 : Math.round(clamp01(avgLevel) * 12); // 1..12 marks the avg
  return (
    <div style={{ display: "flex", gap: 2, height, alignItems: "stretch", width: "100%" }}>
      {Array.from({ length: 12 }, (_, i) => {
        const lit = i < filled;
        const isAvg = !standby && avgIndex > 0 && i === avgIndex - 1;
        let background = "rgba(255,255,255,0.12)";
        let border = "0";
        let boxShadow = "none";
        if (standby) {
          background = "transparent";
          border = "1px solid rgba(255,255,255,0.10)";
        } else if (lit) {
          background = P.accent;
          if (i === filled - 1) boxShadow = "0 0 3px rgba(255,136,0,0.55)";
        }
        if (isAvg) {
          if (!lit) background = "rgba(255,136,0,0.5)";
          boxShadow = "0 0 4px rgba(255,136,0,0.7)";
        }
        return (
          <span
            key={i}
            style={{ flex: 1, borderRadius: 1.5, background, border, boxShadow, boxSizing: "border-box" }}
          />
        );
      })}
    </div>
  );
}

function paceOf(todayLevel: number, avgLevel: number, standby: boolean): { text: string; hot: boolean } {
  if (standby) return { text: "—", hot: false };
  const d = todayLevel - avgLevel;
  if (d > 0.02) return { text: "▲ ABOVE AVG", hot: true };
  if (d < -0.02) return { text: "▼ BELOW AVG", hot: false };
  return { text: "= AT AVG", hot: false };
}

/** One meter gauge lane — CAPTION · big readout · Meter · pace. */
function MeterLane({
  caption,
  readout,
  todayLevel,
  avgLevel,
  standby,
  height,
}: {
  caption: string;
  readout: string;
  todayLevel: number;
  avgLevel: number;
  standby: boolean;
  height: number;
}) {
  const pace = paceOf(todayLevel, avgLevel, standby);
  return (
    <div
      style={{
        ...INSET_WELL,
        height,
        boxSizing: "border-box",
        borderRadius: 6,
        display: "flex",
        alignItems: "center",
        gap: 9,
        padding: "0 9px",
      }}
    >
      <span
        style={{
          width: 42,
          flex: "0 0 auto",
          fontFamily: MONO,
          fontSize: 8,
          fontWeight: 600,
          letterSpacing: "0.1em",
          color: PHOSPHOR_DIM,
        }}
      >
        {caption}
      </span>
      <span
        style={{
          width: 44,
          flex: "0 0 auto",
          fontFamily: MONO,
          fontSize: 15,
          fontWeight: 700,
          fontVariantNumeric: "tabular-nums",
          letterSpacing: "0.02em",
          color: standby ? PHOSPHOR_DIM : PHOSPHOR,
          textShadow: standby ? "none" : PHOSPHOR_GLOW,
        }}
      >
        {readout}
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <SegMeter todayLevel={todayLevel} avgLevel={avgLevel} standby={standby} />
      </div>
      <span
        style={{
          width: 72,
          flex: "0 0 auto",
          textAlign: "right",
          fontFamily: MONO,
          fontSize: 8,
          fontWeight: 600,
          letterSpacing: "0.06em",
          color: pace.hot ? P.accent : PHOSPHOR_DIM,
        }}
      >
        {pace.text}
      </span>
    </div>
  );
}

/** The STRK gauge — Life-in-Dots (last 12 days, 6×2) + count. */
function StrkLane({ model, height }: { model: ConsoleModel; height: number }) {
  const run = useMemo(() => streakRun(model.calendar), [model.calendar]);
  const streak = run.length;
  const standby = !!model.standby;
  const from = TODAY_INDEX - (DOT_DAYS - 1);
  const idxs = Array.from({ length: DOT_DAYS }, (_, i) => from + i);
  return (
    <div
      style={{
        ...INSET_WELL,
        height,
        boxSizing: "border-box",
        borderRadius: 6,
        display: "flex",
        alignItems: "center",
        gap: 9,
        padding: "0 9px",
      }}
    >
      <span
        style={{
          width: 42,
          flex: "0 0 auto",
          fontFamily: MONO,
          fontSize: 8,
          fontWeight: 600,
          letterSpacing: "0.1em",
          color: PHOSPHOR_DIM,
        }}
      >
        STRK
      </span>
      <div style={{ width: 66, flex: "0 0 auto", display: "flex", alignItems: "baseline", gap: 5 }}>
        <span
          style={{
            fontFamily: MONO,
            fontSize: 17,
            fontWeight: 700,
            fontVariantNumeric: "tabular-nums",
            color: standby || streak > 0 ? P.accent : PHOSPHOR_DIM,
            textShadow: !standby && streak > 0 ? "0 0 5px rgba(255,136,0,0.5)" : "none",
          }}
        >
          {standby ? "0" : streak}
        </span>
        <span style={{ fontFamily: MONO, fontSize: 7, fontWeight: 600, letterSpacing: "0.08em", color: PHOSPHOR_DIM }}>
          {standby ? "DAY 1" : "DAY RUN"}
        </span>
      </div>
      {/* Life-in-Dots — the v2 6×2 module, docked right */}
      <div style={{ marginLeft: "auto", flex: "0 0 auto" }}>
        <div
          aria-hidden
          style={{
            display: "grid",
            gridTemplateColumns: `repeat(6, ${DOT}px)`,
            gap: DOT_GAP,
            justifyContent: "end",
          }}
        >
          {idxs.map((idx) => {
            const today = idx === TODAY_INDEX;
            const filled = model.calendar[idx] > 0;
            let background = "transparent";
            let border = "1px solid rgba(255,255,255,0.16)";
            let boxShadow = "none";
            if (standby && today) {
              border = `1.5px solid ${P.accent}`; // amber Today Seed
              boxShadow = "0 0 5px rgba(255,136,0,0.7)";
            } else if (standby) {
              border = "1px solid rgba(255,255,255,0.11)"; // Ghost Cell
            } else if (today) {
              background = P.accent;
              border = "0";
              boxShadow = "0 0 5px rgba(255,136,0,0.8)";
            } else if (filled) {
              background = "rgba(255,255,255,0.9)";
              border = "0";
            }
            return (
              <span
                key={idx}
                style={{ width: DOT, height: DOT, borderRadius: DOT, background, border, boxShadow, boxSizing: "border-box" }}
              />
            );
          })}
        </div>
      </div>
    </div>
  );
}

/** GAUGES page — TAKES · TIME · STRK, three gauge lanes filling the well. */
function GaugesBay({ model }: { model: ConsoleModel }) {
  const standby = !!model.standby;
  const takesToday = model.takesByDay[model.takesByDay.length - 1] ?? 0;
  const takesAvg = mean(model.takesByDay);
  const secToday = model.secByDay[model.secByDay.length - 1] ?? 0;
  const secAvg = mean(model.secByDay);
  return (
    <div style={{ height: BAY_CONTENT_H, display: "flex", flexDirection: "column", gap: G_GAP }}>
      <MeterLane
        caption="TAKES"
        readout={standby ? "0" : String(takesToday)}
        todayLevel={clamp01(takesToday / SCALE_TAKES)}
        avgLevel={clamp01(takesAvg / SCALE_TAKES)}
        standby={standby}
        height={G_TAKES_H}
      />
      <MeterLane
        caption="TIME"
        readout={standby ? "0:00" : fmtDur(secToday)}
        todayLevel={clamp01(secToday / SCALE_TIME)}
        avgLevel={clamp01(secAvg / SCALE_TIME)}
        standby={standby}
        height={G_TIME_H}
      />
      <StrkLane model={model} height={G_STRK_H} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Toggle — the hardware two-position Bay Selector on the label row
// ─────────────────────────────────────────────────────────────────────────

type Page = "roll" | "gauges";

/** A tiny recessed two-position selector; the active bay is lit amber. Static
 *  in the studio — rendered in each position side by side. */
function Toggle({ page }: { page: Page }) {
  const segs: [Page, string][] = [
    ["roll", "ROLL"],
    ["gauges", "GAUGES"],
  ];
  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "stretch",
        height: BAY_LABEL_H,
        borderRadius: 4,
        padding: 1,
        gap: 1,
        background: "linear-gradient(180deg, #050301, #0b0704)",
        border: "1px solid rgba(255,136,0,0.22)",
        boxShadow: "inset 0 1px 3px rgba(0,0,0,0.8)",
      }}
    >
      {segs.map(([key, label]) => {
        const on = key === page;
        return (
          <span
            key={key}
            style={{
              display: "flex",
              alignItems: "center",
              padding: "0 7px",
              borderRadius: 3,
              fontFamily: MONO,
              fontSize: 8,
              fontWeight: 700,
              letterSpacing: "0.12em",
              color: on ? PHOSPHOR : PHOSPHOR_DIM,
              textShadow: on ? PHOSPHOR_GLOW : "none",
              background: on ? "rgba(255,136,0,0.16)" : "transparent",
              boxShadow: on ? "inset 0 0 0 0.5px rgba(255,136,0,0.4)" : "none",
            }}
          >
            {label}
          </span>
        );
      })}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  The Bay — label row (Toggle + readout) over the toggled page
// ─────────────────────────────────────────────────────────────────────────

function Bay({ page, model }: { page: Page; model: ConsoleModel }) {
  const streak = useMemo(() => streakRun(model.calendar).length, [model.calendar]);
  const readout =
    page === "roll"
      ? model.standby
        ? "DAY 1"
        : `STRK ${streak}`
      : model.standby
        ? "DAY 1 · STANDBY"
        : "TODAY · 7-DAY AVG";
  const readoutHot = page === "roll" && (model.standby || streak > 0);
  return (
    <div
      style={{
        ...INSET_WELL,
        height: BAY_H,
        boxSizing: "border-box",
        borderRadius: 8,
        padding: BAY_PAD,
        display: "flex",
        flexDirection: "column",
        gap: BAY_LABEL_GAP,
      }}
    >
      {/* label row — the Toggle on the left, a contextual readout on the right */}
      <div style={{ height: BAY_LABEL_H, display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <Toggle page={page} />
        <span
          style={{
            fontFamily: MONO,
            fontSize: 8,
            fontWeight: 600,
            letterSpacing: "0.1em",
            color: readoutHot ? P.accent : P.screenInkFaint,
          }}
        >
          {readout}
        </span>
      </div>
      {page === "roll" ? <RollBay model={model} /> : <GaugesBay model={model} />}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  The Console — the metal Bezel around the Message Line + the Bay
// ─────────────────────────────────────────────────────────────────────────

function Console({ page, model, dock = "strk" }: { page: Page; model: ConsoleModel; dock?: DockKind }) {
  return (
    <div
      style={{
        ...BEZEL_METAL,
        width: CONTENT_W,
        boxSizing: "border-box",
        borderRadius: 14,
        padding: BEZEL_PAD,
      }}
    >
      <div
        style={{
          ...SCREEN_GLASS,
          boxSizing: "border-box",
          borderRadius: 12,
          padding: SCREEN_PAD,
          overflow: "hidden",
          display: "flex",
          flexDirection: "column",
          gap: STACK_GAP,
        }}
      >
        {/* Message Line — straight on top, no header row */}
        <MessageLine model={model} contentW={SCREEN_CONTENT_W} dock={dock} />
        <Bay page={page} model={model} />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Harness chrome
// ─────────────────────────────────────────────────────────────────────────

function SectionHeading({ label, hint }: { label: string; hint: string }) {
  return (
    <div className="flex items-baseline gap-3">
      <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em] text-stone-600">{label}</span>
      <span className="italic text-stone-400" style={{ fontSize: 12 }}>
        {hint}
      </span>
      <div className="ml-1 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
    </div>
  );
}

function StateLabel({ children }: { children: React.ReactNode }) {
  return (
    <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.16em] text-stone-400">{children}</span>
  );
}

function HeightChip({ h, muted = false }: { h: number; muted?: boolean }) {
  return (
    <span
      className="rounded-full px-2 py-0.5 font-mono text-[11px] font-semibold tabular-nums"
      style={
        muted
          ? { color: "#78716c", border: "1px solid rgba(120,113,108,0.32)", background: "rgba(120,113,108,0.05)" }
          : { color: "#B45309", border: "1px solid rgba(180,83,9,0.32)", background: "rgba(255,136,0,0.06)" }
      }
    >
      {h}pt
    </span>
  );
}

// ── Board 1 · The Console — both toggle pages, exact height ─────────────────
function ConsoleBoard() {
  const pages: [Page, string][] = [
    ["roll", "THE ROLL"],
    ["gauges", "GAUGES"],
  ];
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="The Console"
        hint="the BEZEL ON metal wrap around the Message Line (no header) + the toggled big section · both toggle pages side by side, the Toggle shown in each position · header dropped → the console comes in under the 231pt baseline"
      />
      <div className="flex items-baseline gap-2 px-0.5">
        <span className="font-mono text-[13px] font-semibold uppercase tracking-[0.12em] text-stone-800">
          CONSOLE
        </span>
        <HeightChip h={CONSOLE_H} />
        <span className="font-mono text-[11px] tabular-nums text-stone-400">vs 231pt baseline · −{231 - CONSOLE_H}pt</span>
      </div>
      <div className="flex flex-wrap gap-x-12 gap-y-6">
        {pages.map(([page, name]) => (
          <div key={page} className="flex flex-col gap-2">
            <div className="flex items-baseline gap-2 px-0.5">
              <StateLabel>Toggle → {name}</StateLabel>
              <HeightChip h={CONSOLE_H} />
            </div>
            <Console page={page} model={NOMINAL} dock="strk" />
          </div>
        ))}
      </div>
      <p className="max-w-[760px] text-[12px] italic leading-relaxed text-stone-500">
        Both pages seat in the SAME well at {BAY_H}pt, so the Toggle swaps content with no layout shift — the console
        height is fixed at {CONSOLE_H}pt whichever page is up. GAUGES reads as instruments (count + Meter + pace · m:ss +
        Meter · Life-in-Dots), never a Take Log replay.
      </p>
    </div>
  );
}

// ── Board 2 · Docked Readout option — the strip with + without the slot ─────
function DockedReadoutBoard() {
  const opts: [DockKind, string][] = [
    ["none", "no readout — bare Message Line"],
    ["strk", "docked · STRK n"],
    ["takes", "docked · take count"],
  ];
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Docked Readout · option"
        hint="'instead of the clock, something else useful' — a small right-docked readout ON the Message Line (HUD-strip vocabulary). Toggleable in the study; shown with + without."
      />
      <div className="flex flex-col gap-4" style={{ maxWidth: SCREEN_CONTENT_W + 40 }}>
        {opts.map(([kind, label]) => (
          <div key={kind} className="flex flex-col gap-1.5">
            <StateLabel>{label}</StateLabel>
            <div style={{ width: SCREEN_CONTENT_W }}>
              <MessageLine model={NOMINAL} height={MSG_H} contentW={SCREEN_CONTENT_W} dock={kind} />
            </div>
          </div>
        ))}
      </div>
      <p className="max-w-[720px] text-[12px] italic leading-relaxed text-stone-500">
        The slot is one lane wide ({DOCK_W}pt), hairline-divided with a whisper of glass so it reads as its own gauge.
        It carries STRK n or the day&apos;s take count — the useful fact the dropped clock used to displace.
      </p>
    </div>
  );
}

// ── Board 3 · Scenarios — NOMINAL + FIRST-RUN × both pages ──────────────────
function ScenarioBoard() {
  const scenarios: [ConsoleModel, string, string][] = [
    [NOMINAL, "NOMINAL", "active day · healthy streak — the freshest fact on the line, gauges above average, the Roll's amber run of 5 ends on today"],
    [FIRST_RUN, "FIRST-RUN · standby", "empty library — the Standby Voice leads the line, gauges read Ghost segments + DAY 1, the Roll sketches Ghost Cells around the amber Today Seed"],
  ];
  const pages: [Page, string][] = [
    ["roll", "THE ROLL"],
    ["gauges", "GAUGES"],
  ];
  return (
    <div className="flex flex-col gap-6">
      <SectionHeading
        label="Scenarios"
        hint="NOMINAL and FIRST-RUN (elevated standby — Ghost Cells · Standby Voice · DAY 1), for both toggle pages"
      />
      {scenarios.map(([model, name, intent]) => (
        <div key={name} className="flex flex-col gap-3">
          <div className="flex items-baseline gap-2 px-0.5">
            <span className="font-mono text-[12px] font-semibold uppercase tracking-[0.14em] text-stone-700">{name}</span>
          </div>
          <div className="flex flex-wrap gap-x-12 gap-y-6">
            {pages.map(([page, pname]) => (
              <div key={page} className="flex flex-col gap-2">
                <StateLabel>Toggle → {pname}</StateLabel>
                <Console page={page} model={model} dock="strk" />
              </div>
            ))}
          </div>
          <p className="max-w-[760px] text-[11px] leading-snug text-stone-400">{intent}</p>
          {model.standby && (
            <p className="max-w-[760px] text-[10px] leading-snug text-stone-400">
              <span className="font-mono uppercase tracking-[0.1em]" style={{ color: "#B45309" }}>
                standby ·{" "}
              </span>
              tapping the strip opens the recorder, not the Library — first-run has nothing to browse yet.
            </p>
          )}
        </div>
      ))}
    </div>
  );
}

// ── Board 4 · Strip System — the bare 36pt strip travelling non-Home contexts ─
const GHOST_INK = "rgba(15,12,8,0.09)";
const GHOST_LINE = "rgba(15,12,8,0.14)";

function GhostBar({ w, h = 8, r = 3 }: { w: number | string; h?: number; r?: number }) {
  return <span style={{ display: "block", width: w, height: h, borderRadius: r, background: GHOST_INK }} />;
}

/** A bare Message Line strip (36pt, no Bezel) — the travelling message area. */
function StripBare({ message, width }: { message: string; width: number }) {
  const model: ConsoleModel = { message, calendar: [], takesByDay: [], secByDay: [] };
  return <MessageLine model={model} height={STRIP_H} width={width} contentW={width - STRIP_PAD_X * 2} dock="none" />;
}

function GhostContext({
  title,
  message,
  children,
}: {
  title: string;
  message: string;
  children: React.ReactNode;
}) {
  const W = 320;
  const stripW = W - 28;
  return (
    <div className="flex flex-col gap-2" style={{ width: W }}>
      <StateLabel>{title}</StateLabel>
      <div
        style={{
          width: W,
          borderRadius: 20,
          padding: 14,
          background: P.canvas,
          border: "1px solid rgba(15,12,8,0.10)",
          boxShadow: "0 12px 30px -20px rgba(0,0,0,0.4)",
          display: "flex",
          flexDirection: "column",
          gap: 12,
        }}
      >
        {/* ghost context header — the surface's own chrome, ghosted */}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <span style={{ fontFamily: MONO, fontSize: 11, fontWeight: 700, letterSpacing: "0.2em", color: "rgba(15,12,8,0.34)" }}>
            {title}
          </span>
          <span style={{ width: 26, height: 26, borderRadius: 13, background: GHOST_INK }} />
        </div>
        {/* the ONE lit element — the travelling Message Line strip */}
        <StripBare message={message} width={stripW} />
        {children}
      </div>
    </div>
  );
}

function StripSystemBoard() {
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Strip System"
        hint="the Message Line as a system — the bare 36pt strip (no Bezel) seated in ghosted non-Home contexts, each with plausible real copy. One message area travelling the app."
      />
      <div className="flex flex-wrap gap-x-8 gap-y-8">
        <GhostContext title="LIBRARY" message="3 TAKES TODAY">
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {[0, 1, 2].map((i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 10, borderTop: `1px solid ${GHOST_LINE}`, paddingTop: 8 }}>
                <span style={{ width: 28, height: 28, borderRadius: 6, background: GHOST_INK }} />
                <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 5 }}>
                  <GhostBar w={"70%"} h={8} />
                  <GhostBar w={"40%"} h={6} />
                </div>
                <GhostBar w={28} h={7} r={2} />
              </div>
            ))}
          </div>
        </GhostContext>

        <GhostContext title="ASK AI" message="ASK ANYTHING — HOLD TO TALK">
          <div style={{ display: "flex", flexDirection: "column", gap: 10, paddingTop: 4 }}>
            <GhostBar w={"52%"} h={9} />
            <GhostBar w={"78%"} h={9} />
            <GhostBar w={"34%"} h={9} />
            <div style={{ marginTop: 6, height: 40, borderRadius: 20, border: `1px solid ${GHOST_LINE}`, background: "rgba(15,12,8,0.02)", display: "flex", alignItems: "center", gap: 10, padding: "0 14px" }}>
              <span style={{ width: 15, height: 15, borderRadius: 4, background: GHOST_INK }} />
              <GhostBar w={130} h={9} />
              <span style={{ marginLeft: "auto", width: 26, height: 26, borderRadius: 13, background: GHOST_INK }} />
            </div>
          </div>
        </GhostContext>

        <GhostContext title="SETTINGS" message="PARAKEET READY">
          <div style={{ display: "flex", flexDirection: "column", gap: 8, paddingTop: 4 }}>
            {[0, 1, 2, 3].map((i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 10, borderTop: `1px solid ${GHOST_LINE}`, paddingTop: 8 }}>
                <span style={{ width: 18, height: 18, borderRadius: 4, background: GHOST_INK }} />
                <GhostBar w={"46%"} h={8} />
                <span style={{ marginLeft: "auto", width: 30, height: 16, borderRadius: 8, background: GHOST_INK }} />
              </div>
            ))}
          </div>
        </GhostContext>
      </div>
      <p className="max-w-[760px] text-[12px] italic leading-relaxed text-stone-500">
        Same strip material, same phosphor voice — one derived fact per surface. The copy is contextual (Library&apos;s
        day count · Ask AI&apos;s hold-to-talk prompt · Settings&apos; model-ready status), but the instrument is one
        system carried across the app.
      </p>
    </div>
  );
}

// ── Board 5 · Context board — the Console in a ghosted Home column ──────────
// Ghost Home chrome geometry — the SAME constants as /cockpit-compact so the
// Recents-above-the-fold math is comparable (8.2 / 8.1 / 7.8 there).
const COL_H = 740;
const BOTTOM_CHROME = 92;
const FOLD_Y = COL_H - BOTTOM_CHROME; // 648
const STATUSBAR_H = 20;
const HEADER_H = 44;
const BLOCK_GAP = 10;
const ACTIONS_H = 78;
const COMMAND_H = 62;
const RECENTS_EYEBROW_H = 28;
const RECENT_ROW_H = 38;

function recentsStartFor(consoleH: number): number {
  return (
    STATUSBAR_H +
    HEADER_H +
    BLOCK_GAP +
    consoleH +
    BLOCK_GAP +
    ACTIONS_H +
    BLOCK_GAP +
    COMMAND_H +
    BLOCK_GAP +
    RECENTS_EYEBROW_H
  );
}

// The reference points the verdict asked to compare against.
const BASELINE_H = 231; // the old Two-Row Baseline (with header)
const COMPACT_INSTRUMENT = [
  ["Instrument · bezel-off 64pt", 8.2],
  ["Instrument · glass 66pt", 8.1],
  ["Instrument · bezel-on 80pt", 7.8],
] as const;

function ghostRowsFor(consoleH: number): number {
  return Math.max(0, FOLD_Y - recentsStartFor(consoleH)) / RECENT_ROW_H;
}

function GhostStatusBar() {
  return (
    <div style={{ height: STATUSBAR_H, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 14px" }}>
      <GhostBar w={34} h={9} />
      <GhostBar w={44} h={9} />
    </div>
  );
}
function GhostHeader() {
  return (
    <div style={{ height: HEADER_H, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 16px" }}>
      <span style={{ width: 30, height: 30, borderRadius: 15, background: GHOST_INK }} />
      <span style={{ fontFamily: MONO, fontSize: 12, fontWeight: 700, letterSpacing: "0.22em", color: "rgba(15,12,8,0.28)" }}>
        TALKIE
      </span>
      <span style={{ width: 30, height: 30, borderRadius: 15, background: GHOST_INK }} />
    </div>
  );
}
function GhostActions() {
  return (
    <div style={{ height: ACTIONS_H, display: "flex", flexDirection: "column", gap: 8 }}>
      <GhostBar w={44} h={8} />
      <div style={{ flex: 1, display: "grid", gridTemplateColumns: "repeat(4, 1fr)", borderRadius: 12, overflow: "hidden", border: `1px solid ${GHOST_LINE}`, background: "rgba(15,12,8,0.02)" }}>
        {[0, 1, 2, 3].map((i) => (
          <div key={i} style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 6, borderRight: i < 3 ? `1px solid ${GHOST_LINE}` : "0" }}>
            <span style={{ width: 15, height: 15, borderRadius: 4, background: GHOST_INK }} />
            <GhostBar w={30} h={6} />
          </div>
        ))}
      </div>
    </div>
  );
}
function GhostCommand() {
  return (
    <div style={{ height: COMMAND_H, display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ height: 44, borderRadius: 22, border: `1px solid ${GHOST_LINE}`, background: "rgba(15,12,8,0.02)", display: "flex", alignItems: "center", gap: 10, padding: "0 14px" }}>
        <span style={{ width: 15, height: 15, borderRadius: 4, background: GHOST_INK }} />
        <GhostBar w={150} h={9} />
        <span style={{ marginLeft: "auto", width: 26, height: 26, borderRadius: 13, background: GHOST_INK }} />
      </div>
      <GhostBar w={190} h={6} />
    </div>
  );
}
function GhostRecentsEyebrow() {
  return (
    <div style={{ height: RECENTS_EYEBROW_H, display: "flex", alignItems: "center", gap: 8 }}>
      <span style={{ fontFamily: MONO, fontSize: 10, fontWeight: 600, letterSpacing: "0.24em", color: "rgba(15,12,8,0.34)" }}>
        RECENT
      </span>
      <GhostBar w={36} h={7} />
      <span style={{ marginLeft: "auto" }} />
      <GhostBar w={24} h={7} />
    </div>
  );
}
function GhostRecentRow() {
  return (
    <div style={{ height: RECENT_ROW_H, display: "flex", alignItems: "center", gap: 10, borderTop: `1px solid ${GHOST_LINE}`, padding: "0 4px" }}>
      <span style={{ width: 14, height: 14, borderRadius: 3, background: GHOST_INK }} />
      <GhostBar w={"58%"} h={9} />
      <GhostBar w={30} h={7} r={2} />
    </div>
  );
}

function ContextColumn({ page }: { page: Page }) {
  const rowsFloat = ghostRowsFor(CONSOLE_H);
  const start = recentsStartFor(CONSOLE_H);
  const rowsAvail = Math.max(0, FOLD_Y - start);
  const drawRows = Math.max(0, Math.ceil(rowsAvail / RECENT_ROW_H) + 2);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <div className="flex items-baseline gap-2 px-0.5">
        <span className="font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-700">
          {page === "roll" ? "THE ROLL" : "GAUGES"}
        </span>
        <HeightChip h={CONSOLE_H} />
      </div>
      <div
        style={{
          position: "relative",
          width: CONTENT_W + 24,
          height: COL_H,
          overflow: "hidden",
          borderRadius: 24,
          padding: 12,
          background: P.canvas,
          border: "1px solid rgba(15,12,8,0.10)",
          boxShadow: "0 12px 30px -20px rgba(0,0,0,0.4)",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column" }}>
          <GhostStatusBar />
          <GhostHeader />
          <div style={{ height: BLOCK_GAP }} />
          {/* the one lit element — the Console */}
          <div style={{ display: "flex", justifyContent: "center" }}>
            <Console page={page} model={NOMINAL} dock="strk" />
          </div>
          <div style={{ height: BLOCK_GAP }} />
          <GhostActions />
          <div style={{ height: BLOCK_GAP }} />
          <GhostCommand />
          <div style={{ height: BLOCK_GAP }} />
          <GhostRecentsEyebrow />
          {Array.from({ length: drawRows }, (_, i) => (
            <GhostRecentRow key={i} />
          ))}
        </div>

        {/* Fold Line — the visible-screen cut; Recents below it are lost */}
        <div aria-hidden style={{ position: "absolute", left: 0, right: 0, top: FOLD_Y + 12, height: 0, borderTop: "1.5px dashed rgba(220,38,38,0.7)" }} />
        <div aria-hidden style={{ position: "absolute", left: 0, right: 0, top: FOLD_Y + 12, bottom: 0, background: "linear-gradient(180deg, rgba(233,230,223,0), rgba(233,230,223,0.72) 40%)", pointerEvents: "none" }} />
        <span style={{ position: "absolute", right: 14, top: FOLD_Y + 12 - 16, fontFamily: MONO, fontSize: 8, fontWeight: 700, letterSpacing: "0.12em", color: "rgba(220,38,38,0.85)" }}>
          FOLD
        </span>
      </div>

      <div className="rounded-md px-3 py-2" style={{ width: CONTENT_W + 24, background: "#FFFFFF", border: "0.5px solid #DEDEDD" }}>
        <div className="font-mono text-[11px] font-semibold uppercase tracking-[0.1em]" style={{ color: "#B45309" }}>
          RECENTS VISIBLE: {rowsFloat.toFixed(1)} rows
          <span className="text-stone-400">
            {"  ·  "}old baseline 231pt: {ghostRowsFor(BASELINE_H).toFixed(1)} rows
          </span>
        </div>
        <p className="mt-1 text-[11px] leading-snug text-stone-500">
          The Console is {CONSOLE_H}pt — dropping the header recovers {(rowsFloat - ghostRowsFor(BASELINE_H)).toFixed(1)}{" "}
          of a Recents row over the old {BASELINE_H}pt baseline. It stays the rich two-row option: it costs more than the
          compact strips ({COMPACT_INSTRUMENT.map(([, n]) => n.toFixed(1)).join(" / ")} rows for the Instrument family),
          the price of carrying both the Message Line and a full toggled bay.
        </p>
      </div>
    </div>
  );
}

function ContextBoard() {
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Context board · Home real estate"
        hint="the Console seated in a ghosted Home column (~366×740) — the only lit element. Watch the Recents count above the FOLD, against the compact 8.2 / 8.1 / 7.8 and the old baseline's 3.8."
      />
      <div className="flex flex-wrap gap-x-10 gap-y-12">
        <ContextColumn page="roll" />
        <ContextColumn page="gauges" />
      </div>
    </div>
  );
}

// ── Data-source legend — every readout backed by a verified iOS publisher ───
const SOURCES: [string, string][] = [
  [
    "Message Line",
    "One derived fact — the freshest signal (last take · roll-tape nudge · STANDING BY on an empty library) — on a single amber-CRT Terminal line. Fit by monospace advance; long strings fade at the right edge. Static.",
  ],
  [
    "Docked Readout",
    "STRK n or the day's take count. Streak = trailing consecutive capture days (createdAt across VoiceMemo + KeyboardDictationStore + CaptureStore); take count = HomeFeed.todayStats.takeCount.",
  ],
  [
    "GAUGES · TAKES",
    "HomeFeed.todayStats.takeCount for today, meter fill = today vs the trailing 7-day average (same publisher, per-day). Pace label ▲/▼/= from the delta. Honest — no list replay.",
  ],
  [
    "GAUGES · TIME",
    "Σ VoiceMemo.duration (+ dictation seconds) captured today → m:ss; meter fill = today's total vs the trailing 7-day average total. The TIME instrument, not a transcript.",
  ],
  [
    "GAUGES · STRK",
    "Life-in-Dots — the last 12 days as dots (filled = captured, amber = today, outlined = empty) + STRK n, all derived from createdAt across the stores. Same streak the Roll paints.",
  ],
  [
    "THE ROLL",
    "createdAt across VoiceMemo + KeyboardDictationStore + CaptureStore, last ~18 weeks. Cell intensity = captures that day; Streak Run + STRK n from the same days; Today Marker = the newest cell.",
  ],
];

function SourceLegend() {
  return (
    <div
      className="grid"
      style={{ gridTemplateColumns: "150px 1fr", rowGap: 8, columnGap: 18, padding: "16px 20px", background: "#FFFFFF", border: "0.5px solid #DEDEDD", borderRadius: 8 }}
    >
      {SOURCES.map(([name, def]) => (
        <div key={name} className="contents">
          <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-stone-700">{name}</span>
          <span style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>{def}</span>
        </div>
      ))}
    </div>
  );
}

export function CockpitTwoRowStudio() {
  return (
    <div className="flex flex-col gap-12">
      <ConsoleBoard />
      <DockedReadoutBoard />
      <ScenarioBoard />
      <StripSystemBoard />
      <ContextBoard />
      <div className="flex flex-col gap-5">
        <SectionHeading label="Data sources" hint="every readout is backed by a verified iOS publisher — no placeholders" />
        <SourceLegend />
      </div>
    </div>
  );
}
