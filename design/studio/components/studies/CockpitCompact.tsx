"use client";

/**
 * Home · Cockpit Compact — how small can the cockpit get and keep its soul?
 *
 * The material language is SETTLED (see /cockpit-grid): amber-CRT Terminal
 * Message Line (phosphor mono + scanlines + dither + static block cursor),
 * Take Log tape rows, "the Roll" contribution cells with an amber streak run +
 * STRK readout. Palette + glyphs are frozen — this study does NOT redesign
 * them. The ONE variable here is VERTICAL FOOTPRINT.
 *
 * The shipped Swift build collapsed the Take Log + Roll into one alternating
 * slot at Roll height (~226pt with its chassis). Live feedback: still reserves
 * too much space at the top of Home. So this board fans out compact cockpit
 * forms and — the point of the study — seats each one in a ghosted Home column
 * so the Home-real-estate trade-off (how many Recents rows survive above the
 * fold) is VISIBLE per variant.
 *
 *   STRIP           — the Message Line alone IS the cockpit. ~36pt.
 *   LINE+MICRO-ROLL — Message Line over a one-row 18-day activity band. 70pt.
 *   TICKER FUSION   — one strip; message / freshest take / STRK alternate as
 *                     static pages (shown side-by-side). ~38pt/page.
 *   HUD STRIP       — invention: message + a right-docked live STRK gauge on the
 *                     SAME strip (simultaneous, not alternating). ~38pt.
 *   INSTRUMENT      — recovers the v2 cockpit's hardware charm at compact scale:
 *                     the settled Message Line + a right-docked Life-in-Dots
 *                     module + a slim 12-segment meter, seated back in a THIN
 *                     metal bezel. Judged as two sub-treatments side by side —
 *                     BEZEL ON (80pt) vs BEZEL OFF / glass only (64pt).
 *   TWO-ROW BASELINE— the shipped incumbent (message line + Roll-height slot in
 *                     the metal chassis), for reference. ~231pt.
 *
 * Most compact forms drop the raised metal Chassis — the strip's own dark glass
 * is the instrument. The INSTRUMENT variant is the deliberate exception: it
 * brings a slimmed bezel back to test whether the hardware charm is worth a few
 * Recents rows. Nothing animates (ticker alternation is drawn as side-by-side
 * page states). The shared LED board (ledBoard.tsx) is imported only for the
 * "why Terminal at strip height" reference row.
 *
 * The FIRST-RUN / standby state is designed, not dimmed: the strip leads with
 * the standby voice, the activity grids sketch themselves as GHOST CELLS with a
 * single amber Today Seed ("you are here"), and a caption notes the standby
 * strip routes its tap to the recorder rather than the Library.
 */

import { useMemo } from "react";

import { DotMatrix, PITCH_PX, computeLine, type Material } from "./ledBoard";

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

// ── Frozen geometry ───────────────────────────────────────────────────────
const CONTENT_W = 366; // px — true iPhone content width; heights annotated here
const STRIP_PAD_X = 10; // px — strip inner horizontal padding

// Compact strip heights (the study's whole point) — declared once, used to
// render AND to annotate, so the labels can never drift from the pixels.
const STRIP_H = 36; // STRIP · TICKER page · HUD baseline strip
const HUD_H = 38;
const TICKER_H = 38;
const MICRO_GAP = 6;
const MICRO_BAND_H = 28;
const MICRO_H = STRIP_H + MICRO_GAP + MICRO_BAND_H; // 70

// Terminal fit — a monospace advance estimate (SSR-safe, no DOM measure) picks
// block-cursor (fits) vs. right-edge phosphor fade (overflows). Same rule as
// the settled Message Line, retuned to the compact strip's larger cap height.
const TERM_FONT = 15; // px — cap height ≈ the 36–38pt strip
const TERM_CHAR = TERM_FONT * 0.62; // px — monospace advance
function overflowsIn(text: string, contentW: number): boolean {
  return (text.length + 2) * TERM_CHAR > contentW;
}

// ── Roll cells — one row of the last 18 days (the Micro-Roll) ──────────────
const MICRO_DAYS = 18;
const MICRO_TODAY = MICRO_DAYS - 1;
const MCELL = 12; // px — one Roll cell (unchanged cell language)
const MGAP = 3; // px — gap between cells (unchanged)
const GAUGE_CELL = 8; // px — the HUD/ticker mini-run cell
const GAUGE_GAP = 2;

// ── INSTRUMENT geometry — the hardware-charm variant (bezel + dots + meter) ──
// Explicit heights so the pt annotation is exact by construction (same trick as
// the Two-Row Baseline). BEZEL ON wraps the glass in a thin metal bezel; BEZEL
// OFF is the same glass alone.
const INST = {
  bezelPad: 7, // px — the slimmed metal bezel's padding (BEZEL ON only)
  glassPadX: 9,
  glassPadY: 8,
  rowGap: 10, // px — gap between the left (message+meter) column and the dots
  msgH: 26, // px — the Message Line strip inside the instrument
  colGap: 6, // px — gap between message strip and meter inside the left column
  meterLabelH: 9,
  meterGap: 3,
  meterBarH: 4,
  dotsW: 76, // px — the right-docked Life-in-Dots module
} as const;
const INST_METER_H = INST.meterLabelH + INST.meterGap + INST.meterBarH; // 16
const INST_CONTENT_H = INST.msgH + INST.colGap + INST_METER_H; // 48
const INST_GLASS_H = INST.glassPadY * 2 + INST_CONTENT_H; // 64 — BEZEL OFF height
const INST_BEZEL_H = INST.bezelPad * 2 + INST_GLASS_H + 2; // 80 — BEZEL ON (+borders)
const INST_DOTS_DAYS = 12; // Life-in-Dots — the last 12 days (6×2)
const INST_DOT = 6; // px — one Life dot
const INST_DOT_GAP = 4; // px — gap between Life dots

// ─────────────────────────────────────────────────────────────────────────
//  Data model — two scenarios per variant (NOMINAL + FIRST-RUN / standby)
// ─────────────────────────────────────────────────────────────────────────

type ScenarioKey = "nominal" | "first-run";

interface Take {
  title: string;
  age: string;
  dur: string;
}

interface CompactModel {
  /** the Message Line — ONE derived fact, single terminal line (static) */
  message: string;
  /** the freshest Take Log row (null = empty library) — used by the Ticker */
  take: Take | null;
  /** 18 day intensities (0 none · 1–3), oldest→newest — the Micro-Roll */
  micro: number[];
  /** first-run / empty library — drives the designed standby zero-state
   *  (standby voice + Ghost Cells + amber Today Seed instead of dimmed nominal) */
  standby?: boolean;
}

interface Scenario {
  key: ScenarioKey;
  label: string;
  model: CompactModel;
}

/** Deterministic hash → [0,1). SSR-safe. */
function hash01(n: number): number {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

/** Build the 18-day Micro-Roll with an exact trailing streak run. */
function buildMicro({
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
  const cal = new Array<number>(MICRO_DAYS).fill(0);
  if (empty) return cal;
  for (let i = 0; i <= MICRO_TODAY; i++) {
    const r = hash01(i + seed * 1000);
    if (r < density) cal[i] = r < density * 0.33 ? 3 : r < density * 0.66 ? 2 : 1;
  }
  if (!endsToday) cal[MICRO_TODAY] = 0;
  const end = endsToday ? MICRO_TODAY : MICRO_TODAY - 1;
  for (let k = 0; k < runLength; k++) {
    const idx = end - k;
    if (idx < 0) break;
    cal[idx] = 1 + Math.floor(hash01(idx + seed * 1000 + 7) * 3);
  }
  const before = end - runLength;
  if (before >= 0) cal[before] = 0; // clean boundary → exact streak length
  return cal;
}

/** Trailing consecutive capture-day run ending on today (or yesterday). */
function streakRun(cal: number[]): number[] {
  let end = -1;
  if (cal[MICRO_TODAY] > 0) end = MICRO_TODAY;
  else if (MICRO_TODAY - 1 >= 0 && cal[MICRO_TODAY - 1] > 0) end = MICRO_TODAY - 1;
  if (end < 0) return [];
  const run: number[] = [];
  for (let i = end; i >= 0 && cal[i] > 0; i--) run.push(i);
  return run;
}

const SCENARIOS: Scenario[] = [
  {
    key: "nominal",
    label: "Nominal",
    model: {
      message: "LAST TAKE 2H AGO",
      take: { title: "Standup blockers for the review", age: "2H", dur: "0:42" },
      micro: buildMicro({ seed: 3, density: 0.5, runLength: 5, endsToday: true }),
    },
  },
  {
    key: "first-run",
    label: "First run · standby",
    model: {
      message: "STANDING BY — ROLL TAPE TO BEGIN",
      take: null,
      micro: buildMicro({ seed: 1, density: 0, runLength: 0, endsToday: false, empty: true }),
      standby: true,
    },
  },
];

const NOMINAL = SCENARIOS[0].model;
const FIRST_RUN = SCENARIOS[1].model;

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

/** The dark-glass strip shell + CRT overlays. The strip IS the instrument. */
function Strip({
  height,
  children,
  style,
  width = CONTENT_W,
}: {
  height: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
  /** default = full iPhone content width; the INSTRUMENT narrows it to a lane */
  width?: number | string;
}) {
  return (
    <div
      style={{
        ...TERM_GLASS,
        ...style,
        position: "relative",
        width,
        height,
        boxSizing: "border-box",
        borderRadius: 7,
        overflow: "hidden",
      }}
    >
      {children}
      <Dither />
      <Scanlines />
    </div>
  );
}

/** Amber phosphor mono line + static block cursor (fits) / right fade (over). */
function Phosphor({
  text,
  contentW,
  padRight = 0,
}: {
  text: string;
  /** width the text may occupy — drives the fit decision */
  contentW: number;
  /** reserve space on the right (e.g. for the HUD gauge) */
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
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Roll cell language — reused at Micro-Roll + gauge scale
// ─────────────────────────────────────────────────────────────────────────

function activeInk(intensity: number): string {
  if (intensity >= 3) return "rgba(255,255,255,0.85)";
  if (intensity === 2) return "rgba(255,255,255,0.55)";
  return "rgba(255,255,255,0.30)";
}

function Cell({
  intensity,
  today,
  inRun,
  size,
  ghost = false,
}: {
  intensity: number;
  today: boolean;
  inRun: boolean;
  size: number;
  /** standby / first-run — draw an outlined Ghost Cell, with today as the Seed */
  ghost?: boolean;
}) {
  let background = "rgba(255,255,255,0.05)";
  let boxShadow = "none";
  let border = "0";
  if (ghost && today) {
    // the amber Today Seed — the "you are here" that the streak grows from.
    // Honestly empty (nothing captured yet) so it stays a ring, but brighter
    // than nominal's marker and softly lit so it reads as an invitation.
    background = "transparent";
    border = `1.5px solid ${P.accent}`;
    boxShadow = "0 0 6px rgba(255,136,0,0.7)";
  } else if (ghost) {
    // a Ghost Cell — a faint outline sketching the grid that will fill in.
    background = "transparent";
    border = "1px solid rgba(255,255,255,0.11)";
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
        width: size,
        height: size,
        borderRadius: 2,
        background,
        boxShadow,
        border,
        boxSizing: "border-box",
        flex: "0 0 auto",
      }}
    />
  );
}

/** A horizontal run of day cells (Micro-Roll, or the last-7 gauge slice). */
function RunRow({
  micro,
  from,
  to,
  runSet,
  size,
  gap,
  ghost = false,
}: {
  micro: number[];
  from: number;
  to: number;
  runSet: Set<number>;
  size: number;
  gap: number;
  /** standby — render the row as Ghost Cells with the amber Today Seed */
  ghost?: boolean;
}) {
  const cells: React.ReactNode[] = [];
  for (let i = from; i <= to; i++) {
    cells.push(
      <Cell
        key={i}
        intensity={micro[i]}
        today={i === MICRO_TODAY}
        inRun={runSet.has(i)}
        size={size}
        ghost={ghost}
      />
    );
  }
  return <div style={{ display: "flex", gap, alignItems: "center" }}>{cells}</div>;
}

// ─────────────────────────────────────────────────────────────────────────
//  VARIANT 1 — STRIP · the Message Line alone IS the cockpit
// ─────────────────────────────────────────────────────────────────────────

function StripVariant({ model }: { model: CompactModel }) {
  return (
    <Strip height={STRIP_H}>
      <Phosphor text={model.message} contentW={CONTENT_W - STRIP_PAD_X * 2} />
    </Strip>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  VARIANT 2 — LINE + MICRO-ROLL · strip over a one-row 18-day band
// ─────────────────────────────────────────────────────────────────────────

function MicroRollBand({ model }: { model: CompactModel }) {
  const run = useMemo(() => streakRun(model.micro), [model.micro]);
  const runSet = useMemo(() => new Set(run), [run]);
  const streak = run.length;
  return (
    <Strip height={MICRO_BAND_H} style={{ borderRadius: 6 }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          zIndex: 1,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 10,
          padding: `0 ${STRIP_PAD_X}px`,
        }}
      >
        <span
          style={{
            fontFamily: MONO,
            fontSize: 7,
            fontWeight: 600,
            letterSpacing: "0.1em",
            color: PHOSPHOR_DIM,
            flex: "0 0 auto",
          }}
        >
          18D
        </span>
        <RunRow micro={model.micro} from={0} to={MICRO_TODAY} runSet={runSet} size={MCELL} gap={MGAP} ghost={model.standby} />
        <span
          style={{
            fontFamily: MONO,
            fontSize: 8,
            fontWeight: 700,
            letterSpacing: "0.08em",
            color: streak > 0 ? P.accent : model.standby ? P.accent : PHOSPHOR_DIM,
            flex: "0 0 auto",
          }}
        >
          {model.standby ? "DAY 1" : `STRK ${streak}`}
        </span>
      </div>
    </Strip>
  );
}

function MicroRollVariant({ model }: { model: CompactModel }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: MICRO_GAP }}>
      <Strip height={STRIP_H}>
        <Phosphor text={model.message} contentW={CONTENT_W - STRIP_PAD_X * 2} />
      </Strip>
      <MicroRollBand model={model} />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  VARIANT 3 — TICKER FUSION · one strip, three static alternating pages
// ─────────────────────────────────────────────────────────────────────────

/** Page 2 — the freshest Take Log row as a single terminal line. Empty library
 *  ⇒ the invitation, not a husk: a lit phosphor prompt with a block cursor. */
function TakePage({ take }: { take: Take | null }) {
  if (!take) {
    return (
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: `0 ${STRIP_PAD_X}px`,
          fontFamily: MONO,
        }}
      >
        <span
          style={{
            fontSize: 13,
            letterSpacing: "0.08em",
            color: PHOSPHOR,
            textShadow: PHOSPHOR_GLOW,
          }}
        >
          ROLL TAPE TO BEGIN
        </span>
        <span
          aria-hidden
          style={{
            display: "inline-block",
            width: TERM_CHAR * 0.9,
            height: TERM_FONT * 0.95,
            background: PHOSPHOR,
            borderRadius: 1,
            boxShadow: "0 0 6px rgba(255,150,0,0.8)",
          }}
        />
        <span
          style={{
            marginLeft: "auto",
            fontSize: 8,
            fontWeight: 600,
            letterSpacing: "0.1em",
            color: PHOSPHOR_DIM,
          }}
        >
          NO TAKES YET
        </span>
      </div>
    );
  }
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: `0 ${STRIP_PAD_X}px`,
        fontFamily: MONO,
      }}
    >
      <span
        style={{
          flex: 1,
          minWidth: 0,
          overflow: "hidden",
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
          fontSize: 12.5,
          color: PHOSPHOR,
          textShadow: PHOSPHOR_GLOW,
        }}
      >
        {take.title}
      </span>
      <span style={{ fontSize: 11, letterSpacing: "0.08em", color: PHOSPHOR_DIM }}>{take.age}</span>
      <span
        style={{
          minWidth: 32,
          textAlign: "right",
          fontSize: 11.5,
          fontVariantNumeric: "tabular-nums",
          color: PHOSPHOR,
          textShadow: PHOSPHOR_GLOW,
        }}
      >
        {take.dur}
      </span>
    </div>
  );
}

/** Page 3 — the STRK readout: mini streak run + count. */
function StrkPage({ model }: { model: CompactModel }) {
  const run = useMemo(() => streakRun(model.micro), [model.micro]);
  const runSet = useMemo(() => new Set(run), [run]);
  const streak = run.length;
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: `0 ${STRIP_PAD_X}px`,
      }}
    >
      <span
        style={{
          fontFamily: MONO,
          fontSize: TERM_FONT,
          fontWeight: 600,
          letterSpacing: "0.08em",
          color: streak > 0 ? PHOSPHOR : PHOSPHOR_DIM,
          textShadow: streak > 0 ? PHOSPHOR_GLOW : "none",
        }}
      >
        STRK {streak}
      </span>
      <RunRow
        micro={model.micro}
        from={MICRO_TODAY - 6}
        to={MICRO_TODAY}
        runSet={runSet}
        size={GAUGE_CELL}
        gap={GAUGE_GAP}
        ghost={model.standby}
      />
      <span
        style={{
          marginLeft: "auto",
          fontFamily: MONO,
          fontSize: 8,
          fontWeight: 600,
          letterSpacing: "0.1em",
          color: model.standby ? P.accent : PHOSPHOR_DIM,
        }}
      >
        {model.standby ? "START TODAY" : streak > 0 ? `${streak} DAY RUN` : "STANDING BY"}
      </span>
    </div>
  );
}

/** One ticker page in its strip, tagged n/3. */
function TickerPage({
  index,
  model,
  which,
}: {
  index: number;
  model: CompactModel;
  which: "message" | "take" | "strk";
}) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div className="flex items-center gap-2 px-0.5">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.16em] text-stone-500">
          Page {index}/3
        </span>
        <span className="font-mono text-[9px] uppercase tracking-[0.12em] text-stone-400">
          {which === "message" ? "message" : which === "take" ? "freshest take" : "strk readout"}
        </span>
      </div>
      <Strip height={TICKER_H}>
        {which === "message" ? (
          <Phosphor
            text={model.standby ? "STANDING BY" : model.message}
            contentW={CONTENT_W - STRIP_PAD_X * 2}
          />
        ) : which === "take" ? (
          <TakePage take={model.take} />
        ) : (
          <StrkPage model={model} />
        )}
      </Strip>
    </div>
  );
}

function TickerVariant({ model }: { model: CompactModel }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <TickerPage index={1} model={model} which="message" />
      <TickerPage index={2} model={model} which="take" />
      <TickerPage index={3} model={model} which="strk" />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  VARIANT 4 (invention) — HUD STRIP · message + right-docked STRK gauge
// ─────────────────────────────────────────────────────────────────────────

const GAUGE_W = 118; // px — the docked gauge lane on the right of the strip

function StreakGauge({ model }: { model: CompactModel }) {
  const run = useMemo(() => streakRun(model.micro), [model.micro]);
  const runSet = useMemo(() => new Set(run), [run]);
  const streak = run.length;
  return (
    <div
      style={{
        position: "absolute",
        top: 0,
        bottom: 0,
        right: 0,
        width: GAUGE_W,
        zIndex: 1,
        display: "flex",
        alignItems: "center",
        justifyContent: "flex-end",
        gap: 6,
        paddingRight: STRIP_PAD_X,
        // a hairline divider + a whisper of glass so the gauge reads as its own lane
        borderLeft: "1px solid rgba(255,136,0,0.16)",
        background: "linear-gradient(90deg, transparent, rgba(255,140,0,0.05))",
      }}
    >
      <RunRow
        micro={model.micro}
        from={MICRO_TODAY - 6}
        to={MICRO_TODAY}
        runSet={runSet}
        size={GAUGE_CELL}
        gap={GAUGE_GAP}
        ghost={model.standby}
      />
      <span
        style={{
          fontFamily: MONO,
          fontSize: 10,
          fontWeight: 700,
          letterSpacing: "0.06em",
          color: streak > 0 ? P.accent : PHOSPHOR_DIM,
          textShadow: streak > 0 ? "0 0 5px rgba(255,136,0,0.5)" : "none",
        }}
      >
        {streak}
      </span>
    </div>
  );
}

function HudVariant({ model }: { model: CompactModel }) {
  // the gauge lane costs the message ~118px, so standby uses a shorter honest
  // form that fits without fading mid-word (see Standby Voice in the marginalia).
  const message = model.standby ? "STANDBY — ROLL TAPE" : model.message;
  return (
    <Strip height={HUD_H}>
      <Phosphor text={message} contentW={CONTENT_W - STRIP_PAD_X * 2 - GAUGE_W} padRight={GAUGE_W} />
      <StreakGauge model={model} />
    </Strip>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  VARIANT 5 — TWO-ROW BASELINE · the shipped incumbent, in the chassis
// ─────────────────────────────────────────────────────────────────────────
//
// Message Line over ONE slot at Roll height (the alternating slot showing the
// Roll). Kept inside the raised metal Chassis, like the shipped build — this
// is what "reserves too much space" and the reason the study exists.

const BASE = {
  chassisPad: 8,
  screenPad: 10,
  headerH: 22, // TALKIE · status · clock + margin
  msgH: 32,
  gap: 8,
  rollLabelH: 12,
  rollGap: 8,
  cell: 11,
  cgap: 3,
} as const;

// Roll grid: 7 rows tall → the slot's dominant cost.
const BASE_GRID_H = 7 * BASE.cell + 6 * BASE.cgap; // 95
const BASE_SLOT_H = BASE.rollLabelH + BASE.rollGap + BASE_GRID_H + 16; // + slot padding
const BASE_SCREEN_H = BASE.screenPad * 2 + BASE.headerH + BASE.msgH + BASE.gap + BASE_SLOT_H;
const BASELINE_H = BASE.chassisPad * 2 + BASE_SCREEN_H + 2; // + chassis borders ≈ 226

function BaselineRollSlot({ model }: { model: CompactModel }) {
  const run = useMemo(() => streakRun(model.micro), [model.micro]);
  // Reuse the Micro-Roll data but wrap it to a 3×6 block so the slot reads at
  // Roll height (the incumbent's cost). Static.
  const runSet = useMemo(() => new Set(run), [run]);
  const streak = run.length;
  const rows = [0, 1, 2, 3, 4, 5, 6];
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: BASE.rollGap,
        padding: 8,
        borderRadius: 6,
        background: "rgba(255,255,255,0.035)",
        border: "1px solid rgba(255,255,255,0.08)",
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontFamily: MONO,
          fontSize: 7,
          fontWeight: 600,
          letterSpacing: "0.08em",
          color: P.screenInkFaint,
        }}
      >
        <span>THE ROLL · SLOT</span>
        <span style={{ color: streak > 0 ? P.accent : P.screenInkFaint }}>STRK {streak}</span>
      </div>
      <div
        aria-hidden
        style={{
          display: "grid",
          gridTemplateRows: `repeat(7, ${BASE.cell}px)`,
          gridAutoFlow: "column",
          gridAutoColumns: `${BASE.cell}px`,
          gap: BASE.cgap,
          justifyContent: "center",
        }}
      >
        {rows.map((r) =>
          model.micro.map((intensity, c) => {
            // fan the 18-day row into a 7-row block deterministically so the
            // slot fills at Roll height — layout cost is the point, not the data
            const idx = (c * 7 + r) % MICRO_DAYS;
            const lit = (hash01(c * 7 + r + 1) < 0.42 ? model.micro[idx] : 0);
            const today = idx === MICRO_TODAY && r === 3 && c === MICRO_DAYS - 1;
            return (
              <Cell
                key={`${r}-${c}`}
                intensity={lit}
                today={today}
                inRun={today ? false : runSet.has(idx) && lit > 0}
                size={BASE.cell}
              />
            );
          })
        )}
      </div>
    </div>
  );
}

function BaselineVariant({ model }: { model: CompactModel }) {
  return (
    <div
      style={{
        width: CONTENT_W,
        borderRadius: 14,
        padding: BASE.chassisPad,
        background: `linear-gradient(180deg, ${P.matteEdge}, ${P.matte} 52%, #262626)`,
        border: "0.8px solid rgba(0,0,0,0.5)",
        boxShadow:
          "inset 0 1px 0 rgba(255,255,255,0.18), 0 10px 24px -14px rgba(0,0,0,0.55)",
      }}
    >
      <div
        style={{
          borderRadius: 12,
          padding: BASE.screenPad,
          overflow: "hidden",
          background: `radial-gradient(circle at 50% 40%, rgba(255,136,0,0.20), transparent 48%), linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02) 45%, rgba(0,0,0,0.24)), ${P.screen}`,
          border: `0.8px solid ${P.accentEdge}`,
          boxShadow:
            "inset 0 0.5px 0 rgba(255,255,255,0.14), inset 0 -18px 28px -28px rgba(0,0,0,0.85)",
        }}
      >
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
            color: P.screenInkFaint,
          }}
        >
          <span>TALKIE</span>
          <span style={{ color: P.accent }}>{model.take ? "READY" : "STANDBY"}</span>
          <span style={{ fontVariantNumeric: "tabular-nums" }}>20:04</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: BASE.gap }}>
          {/* message line — settled Terminal, at incumbent strip height */}
          <div
            style={{
              ...TERM_GLASS,
              position: "relative",
              height: BASE.msgH,
              borderRadius: 6,
              overflow: "hidden",
            }}
          >
            <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", padding: "0 9px" }}>
              <span
                style={{
                  whiteSpace: "nowrap",
                  fontFamily: MONO,
                  fontSize: 14,
                  fontWeight: 500,
                  letterSpacing: "0.06em",
                  lineHeight: 1,
                  color: PHOSPHOR,
                  textShadow: PHOSPHOR_GLOW,
                }}
              >
                {model.message.toUpperCase()}
              </span>
            </div>
            <Dither />
            <Scanlines />
          </div>
          <BaselineRollSlot model={model} />
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  VARIANT 6 — INSTRUMENT · the v2 hardware charm, recovered at compact scale
// ─────────────────────────────────────────────────────────────────────────
//
// The settled Message Line + the v2 cockpit's own vocabulary — a slim
// 12-segment meter (today vs 7-day average) under the line, and the Life-in-Dots
// module (last 12 days) docked on the right — seated back in a THIN metal bezel.
// Rendered as two sub-treatments so the chassis question is judged separately
// from the dots/meter question: BEZEL ON (metal wrap) vs BEZEL OFF (glass only).

/** today's intensity + the trailing 7-day average, on a 0..1 (peak = 3) scale. */
function meterStats(micro: number[]): { todayLevel: number; avgLevel: number } {
  const today = micro[MICRO_TODAY];
  let sum = 0;
  let n = 0;
  for (let i = MICRO_TODAY - 6; i <= MICRO_TODAY; i++) {
    if (i >= 0) {
      sum += micro[i];
      n++;
    }
  }
  const avg = n ? sum / n : 0;
  const SCALE = 3; // a full bar = a peak-intensity day
  return { todayLevel: Math.min(1, today / SCALE), avgLevel: Math.min(1, avg / SCALE) };
}

/** The slim 12-segment meter: fill = today's activity, amber tick = 7-day avg. */
function InstrumentMeter({ micro, standby }: { micro: number[]; standby: boolean }) {
  const { todayLevel, avgLevel } = meterStats(micro);
  const filled = standby ? 0 : Math.round(todayLevel * 12);
  const avgIndex = standby ? 0 : Math.round(avgLevel * 12); // 1..12 marks the avg segment
  const delta = todayLevel - avgLevel;
  const pace = standby ? "—" : delta > 0.02 ? "▲ ABOVE AVG" : delta < -0.02 ? "▼ BELOW AVG" : "= AT AVG";
  return (
    <div style={{ height: INST_METER_H, display: "flex", flexDirection: "column", gap: INST.meterGap }}>
      <div
        style={{
          height: INST.meterLabelH,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          fontFamily: MONO,
          fontSize: 7,
          fontWeight: 600,
          letterSpacing: "0.1em",
          color: PHOSPHOR_DIM,
        }}
      >
        <span>TODAY vs 7-DAY AVG</span>
        <span style={{ color: standby ? PHOSPHOR_DIM : delta > 0.02 ? P.accent : PHOSPHOR_DIM }}>
          {pace}
        </span>
      </div>
      <div style={{ display: "flex", gap: 2, height: INST.meterBarH, alignItems: "stretch" }}>
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
            // the 7-day-average mark — a mid-amber tick you read today against.
            if (!lit) background = "rgba(255,136,0,0.5)";
            boxShadow = "0 0 4px rgba(255,136,0,0.7)";
          }
          return (
            <span
              key={i}
              style={{
                flex: 1,
                borderRadius: 1.5,
                background,
                border,
                boxShadow,
                boxSizing: "border-box",
              }}
            />
          );
        })}
      </div>
    </div>
  );
}

/** The Life-in-Dots module — last 12 days as a 6×2 dot grid. Docked right. */
function InstrumentDots({ micro, standby }: { micro: number[]; standby: boolean }) {
  const run = useMemo(() => streakRun(micro), [micro]);
  const streak = run.length;
  const from = MICRO_TODAY - (INST_DOTS_DAYS - 1);
  const idxs = Array.from({ length: INST_DOTS_DAYS }, (_, i) => from + i);
  return (
    <div
      style={{
        width: INST.dotsW,
        flex: "0 0 auto",
        alignSelf: "stretch",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        gap: 6,
        padding: "5px 6px",
        borderRadius: 6,
        background: "rgba(255,255,255,0.035)",
        border: "1px solid rgba(255,255,255,0.08)",
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontFamily: MONO,
          fontSize: 7,
          fontWeight: 600,
          letterSpacing: "0.06em",
          color: PHOSPHOR_DIM,
        }}
      >
        <span>12D</span>
        <span style={{ color: standby || streak > 0 ? P.accent : PHOSPHOR_DIM }}>
          {standby ? "DAY 1" : `STRK ${streak}`}
        </span>
      </div>
      <div
        aria-hidden
        style={{
          display: "grid",
          gridTemplateColumns: `repeat(6, ${INST_DOT}px)`,
          gap: INST_DOT_GAP,
          justifyContent: "space-between",
        }}
      >
        {idxs.map((idx) => {
          const today = idx === MICRO_TODAY;
          const filled = micro[idx] > 0;
          let background = "transparent";
          let border = "1px solid rgba(255,255,255,0.16)";
          let boxShadow = "none";
          if (standby && today) {
            // the amber Today Seed — same "you are here" as the Roll's seed.
            border = `1.5px solid ${P.accent}`;
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
              style={{
                width: INST_DOT,
                height: INST_DOT,
                borderRadius: INST_DOT,
                background,
                border,
                boxShadow,
                boxSizing: "border-box",
              }}
            />
          );
        })}
      </div>
    </div>
  );
}

/** The instrument's dark glass — message + meter (left), Life-in-Dots (right). */
function InstrumentGlass({ model }: { model: CompactModel }) {
  const message = model.standby ? "STANDBY — ROLL TAPE" : model.message;
  return (
    <div
      style={{
        position: "relative",
        height: INST_GLASS_H,
        boxSizing: "border-box",
        padding: `${INST.glassPadY}px ${INST.glassPadX}px`,
        borderRadius: 12,
        overflow: "hidden",
        display: "flex",
        alignItems: "center",
        gap: INST.rowGap,
        background: `radial-gradient(circle at 50% 40%, rgba(255,136,0,0.20), transparent 48%), linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02) 45%, rgba(0,0,0,0.24)), ${P.screen}`,
        border: `0.8px solid ${P.accentEdge}`,
        boxShadow:
          "inset 0 0.5px 0 rgba(255,255,255,0.14), inset 0 -18px 28px -28px rgba(0,0,0,0.85)",
      }}
    >
      {/* power LED — hardware charm nod; amber lit at ready, dim ring at standby */}
      <span
        aria-hidden
        style={{
          position: "absolute",
          top: 6,
          right: 8,
          width: 4,
          height: 4,
          borderRadius: 4,
          background: model.standby ? "transparent" : P.accent,
          border: model.standby ? "1px solid rgba(255,136,0,0.5)" : "0",
          boxShadow: model.standby ? "none" : "0 0 5px rgba(255,136,0,0.9)",
          boxSizing: "border-box",
        }}
      />
      {/* left column — Message Line over the 12-segment meter */}
      <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: INST.colGap }}>
        <Strip height={INST.msgH} width="100%" style={{ borderRadius: 6 }}>
          <Phosphor text={message} contentW={210} />
        </Strip>
        <InstrumentMeter micro={model.micro} standby={!!model.standby} />
      </div>
      {/* right module — Life-in-Dots */}
      <InstrumentDots micro={model.micro} standby={!!model.standby} />
    </div>
  );
}

/** BEZEL ON = the glass inside a slimmed metal bezel; BEZEL OFF = glass alone. */
function InstrumentVariant({ model, bezel }: { model: CompactModel; bezel: boolean }) {
  if (!bezel) {
    return <div style={{ width: CONTENT_W }}><InstrumentGlass model={model} /></div>;
  }
  return (
    <div
      style={{
        width: CONTENT_W,
        boxSizing: "border-box",
        borderRadius: 14,
        padding: INST.bezelPad,
        background: `linear-gradient(180deg, ${P.matteEdge}, ${P.matte} 52%, #262626)`,
        border: "0.8px solid rgba(0,0,0,0.5)",
        boxShadow:
          "inset 0 1px 0 rgba(255,255,255,0.18), 0 10px 24px -14px rgba(0,0,0,0.55)",
      }}
    >
      <InstrumentGlass model={model} />
    </div>
  );
}

/** The variant-board comparison cell: BEZEL ON vs BEZEL OFF, side by side. */
function InstrumentPair({ model }: { model: CompactModel }) {
  const subs: [string, number, boolean][] = [
    ["BEZEL ON · metal wrap", INST_BEZEL_H, true],
    ["BEZEL OFF · glass only", INST_GLASS_H, false],
  ];
  return (
    <div className="flex gap-6">
      {subs.map(([label, h, bezel]) => (
        <div key={label} className="flex flex-col gap-1.5" style={{ width: CONTENT_W }}>
          <div className="flex items-baseline gap-2">
            <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-stone-500">
              {label}
            </span>
            <span
              className="rounded-full px-1.5 py-0.5 font-mono text-[10px] font-semibold tabular-nums"
              style={{ color: "#B45309", border: "1px solid rgba(180,83,9,0.3)", background: "rgba(255,136,0,0.06)" }}
            >
              {h}pt
            </span>
          </div>
          <InstrumentVariant model={model} bezel={bezel} />
        </div>
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Variant registry — geometry the whole board reads from
// ─────────────────────────────────────────────────────────────────────────

interface Variant {
  key: string;
  name: string;
  height: number;
  tagline: string;
  /** where the Roll / Take Log go when this form doesn't carry them */
  elsewhere: string;
  /** the canonical single render — used by the Context Board (and as fallback) */
  render: (model: CompactModel) => React.ReactNode;
  /** the Variant Board render, when it differs (INSTRUMENT shows both bezels) */
  boardRender?: (model: CompactModel) => React.ReactNode;
  /** the Variant Board cell width, when wider than one content column */
  boardW?: number;
  /** a second footprint to report on the Context Board (BEZEL OFF) */
  heightAlt?: number;
  heightAltLabel?: string;
  /** compact strips route a standby tap to the recorder, not the Library */
  standbyRoutes?: boolean;
}

const VARIANTS: Variant[] = [
  {
    key: "strip",
    name: "STRIP",
    height: STRIP_H,
    tagline: "the Message Line alone IS the cockpit — one terminal strip, nothing else.",
    elsewhere: "the Roll + Take Log move to the Library header (a Library tab is where you go to browse history anyway).",
    render: (m) => <StripVariant model={m} />,
    standbyRoutes: true,
  },
  {
    key: "micro",
    name: "LINE + MICRO-ROLL",
    height: MICRO_H,
    tagline: "Message Line over a one-row 18-day activity band — streak run + today marker kept at miniature scale.",
    elsewhere: "the Take Log moves to the Library header; the Roll survives here as the Micro-Roll.",
    render: (m) => <MicroRollVariant model={m} />,
    standbyRoutes: true,
  },
  {
    key: "ticker",
    name: "TICKER FUSION",
    height: TICKER_H,
    tagline: "ONE strip; message / freshest take / STRK alternate as static pages (drawn side-by-side, no scroll).",
    elsewhere: "nothing leaves — the Roll + Take Log fold INTO the strip as pages. Full history still lives in Library.",
    render: (m) => <TickerVariant model={m} />,
    standbyRoutes: true,
  },
  {
    key: "hud",
    name: "HUD STRIP",
    height: HUD_H,
    tagline: "invention — message + a right-docked live STRK gauge on the SAME strip (simultaneous, not alternating).",
    elsewhere: "the Take Log moves to the Library header; the streak pulse rides along on the strip.",
    render: (m) => <HudVariant model={m} />,
    standbyRoutes: true,
  },
  {
    key: "instrument",
    name: "INSTRUMENT",
    height: INST_BEZEL_H,
    heightAlt: INST_GLASS_H,
    heightAltLabel: "BEZEL OFF",
    tagline: "recovers the v2 cockpit's hardware charm at compact scale — Message Line + a slim 12-segment meter (today vs 7-day avg) + a right-docked Life-in-Dots module (last 12 days), seated in a THIN metal bezel. Two sub-treatments: BEZEL ON (80pt) vs BEZEL OFF / glass only (64pt).",
    elsewhere: "carries the streak (dots) + pace (meter) on the strip itself; the Take Log moves to the Library header. The context column seats BEZEL ON — the fuller footprint.",
    render: (m) => <InstrumentVariant model={m} bezel />,
    boardRender: (m) => <InstrumentPair model={m} />,
    boardW: CONTENT_W * 2 + 24,
    standbyRoutes: true,
  },
  {
    key: "baseline",
    name: "TWO-ROW BASELINE",
    height: BASELINE_H,
    tagline: "the shipped incumbent — Message Line over one Roll-height slot, inside the metal Chassis. Reference only.",
    elsewhere: "carries everything, in the Chassis — which is exactly why it reserves too much space at the top of Home.",
    render: (m) => <BaselineVariant model={m} />,
  },
];

// ─────────────────────────────────────────────────────────────────────────
//  Context board — seat each variant in a ghosted Home column
// ─────────────────────────────────────────────────────────────────────────

// Ghost Home chrome geometry — modelled off the shipped Home.tsx stack so the
// Recents-above-the-fold math is honest.
const COL_H = 740; // px — above-the-fold Home canvas
const BOTTOM_CHROME = 92; // px — reserved mic FAB / voice pivot band
const FOLD_Y = COL_H - BOTTOM_CHROME; // 648
const STATUSBAR_H = 20;
const HEADER_H = 44; // TALKIE wordmark row
const BLOCK_GAP = 10;
const ACTIONS_H = 78; // "Quick" eyebrow + 4-cell deck
const COMMAND_H = 62; // omni pill + hint
const RECENTS_EYEBROW_H = 28;
const RECENT_ROW_H = 38;

function recentsStartFor(variantH: number): number {
  return (
    STATUSBAR_H +
    HEADER_H +
    BLOCK_GAP +
    variantH +
    BLOCK_GAP +
    ACTIONS_H +
    BLOCK_GAP +
    COMMAND_H +
    BLOCK_GAP +
    RECENTS_EYEBROW_H
  );
}

const GHOST_INK = "rgba(15,12,8,0.09)";
const GHOST_LINE = "rgba(15,12,8,0.14)";

function GhostBar({ w, h = 8, r = 3 }: { w: number | string; h?: number; r?: number }) {
  return <span style={{ display: "block", width: w, height: h, borderRadius: r, background: GHOST_INK }} />;
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
      <div
        style={{
          flex: 1,
          display: "grid",
          gridTemplateColumns: "repeat(4, 1fr)",
          borderRadius: 12,
          overflow: "hidden",
          border: `1px solid ${GHOST_LINE}`,
          background: "rgba(15,12,8,0.02)",
        }}
      >
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              gap: 6,
              borderRight: i < 3 ? `1px solid ${GHOST_LINE}` : "0",
            }}
          >
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
      <div
        style={{
          height: 44,
          borderRadius: 22,
          border: `1px solid ${GHOST_LINE}`,
          background: "rgba(15,12,8,0.02)",
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "0 14px",
        }}
      >
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

function ContextColumn({ variant, model }: { variant: Variant; model: CompactModel }) {
  const start = recentsStartFor(variant.height);
  const rowsAvail = Math.max(0, FOLD_Y - start);
  const rowsFloat = rowsAvail / RECENT_ROW_H;
  const drawRows = Math.max(0, Math.ceil(rowsFloat) + 2);
  const rowsAltFloat =
    variant.heightAlt !== undefined
      ? Math.max(0, FOLD_Y - recentsStartFor(variant.heightAlt)) / RECENT_ROW_H
      : null;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <div className="flex items-baseline gap-2 px-0.5">
        <span className="font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-700">
          {variant.name}
        </span>
        <span
          className="rounded-full px-2 py-0.5 font-mono text-[10px] font-semibold tabular-nums"
          style={{ color: "#B45309", border: "1px solid rgba(180,83,9,0.3)", background: "rgba(255,136,0,0.06)" }}
        >
          {variant.height}pt
        </span>
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
        {/* the ghosted Home stack */}
        <div style={{ display: "flex", flexDirection: "column" }}>
          <GhostStatusBar />
          <GhostHeader />
          <div style={{ height: BLOCK_GAP }} />
          {/* the one lit element: the cockpit variant */}
          <div style={{ display: "flex", justifyContent: "center" }}>{variant.render(model)}</div>
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
        <div
          aria-hidden
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: FOLD_Y + 12, // + column padding
            height: 0,
            borderTop: "1.5px dashed rgba(220,38,38,0.7)",
          }}
        />
        <div
          aria-hidden
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: FOLD_Y + 12,
            bottom: 0,
            background: "linear-gradient(180deg, rgba(233,230,223,0), rgba(233,230,223,0.72) 40%)",
            pointerEvents: "none",
          }}
        />
        <span
          style={{
            position: "absolute",
            right: 14,
            top: FOLD_Y + 12 - 16,
            fontFamily: MONO,
            fontSize: 8,
            fontWeight: 700,
            letterSpacing: "0.12em",
            color: "rgba(220,38,38,0.85)",
          }}
        >
          FOLD
        </span>
      </div>

      <div
        className="rounded-md px-3 py-2"
        style={{ width: CONTENT_W + 24, background: "#FFFFFF", border: "0.5px solid #DEDEDD" }}
      >
        <div className="font-mono text-[11px] font-semibold uppercase tracking-[0.1em]" style={{ color: "#B45309" }}>
          RECENTS VISIBLE: {rowsFloat.toFixed(1)} rows
          {rowsAltFloat !== null && (
            <span className="text-stone-400">
              {"  ·  "}
              {variant.heightAltLabel ?? "ALT"} {variant.heightAlt}pt: {rowsAltFloat.toFixed(1)} rows
            </span>
          )}
        </div>
        <p className="mt-1 text-[11px] leading-snug text-stone-500">{variant.elsewhere}</p>
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

/** The variant board — each form at NOMINAL + FIRST-RUN, with exact height. */
function VariantBoard() {
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Variant board"
        hint="compact cockpit forms · each annotated with its exact height in pt at 366px content width · nominal + first-run"
      />
      <div className="flex flex-wrap gap-x-12 gap-y-10">
        {VARIANTS.map((v) => {
          const render = v.boardRender ?? v.render;
          return (
            <div key={v.key} className="flex flex-col gap-3" style={{ width: v.boardW ?? CONTENT_W }}>
              <div className="flex items-baseline gap-2">
                <span className="font-mono text-[13px] font-semibold uppercase tracking-[0.12em] text-stone-800">
                  {v.name}
                </span>
                <span
                  className="rounded-full px-2 py-0.5 font-mono text-[11px] font-semibold tabular-nums"
                  style={{ color: "#B45309", border: "1px solid rgba(180,83,9,0.32)", background: "rgba(255,136,0,0.06)" }}
                >
                  {v.height}pt
                </span>
                {v.heightAlt !== undefined && (
                  <span
                    className="rounded-full px-2 py-0.5 font-mono text-[11px] font-semibold tabular-nums text-stone-500"
                    style={{ border: "1px solid rgba(120,113,108,0.32)", background: "rgba(120,113,108,0.05)" }}
                  >
                    {v.heightAlt}pt
                  </span>
                )}
              </div>
              <p className="text-[12px] italic leading-snug text-stone-500">{v.tagline}</p>

              <div className="flex flex-col gap-1.5">
                <StateLabel>Nominal</StateLabel>
                {render(NOMINAL)}
              </div>
              <div className="flex flex-col gap-1.5">
                <StateLabel>First run · standby</StateLabel>
                {render(FIRST_RUN)}
                {v.standbyRoutes && (
                  <p className="text-[10px] leading-snug text-stone-400">
                    <span className="font-mono uppercase tracking-[0.1em]" style={{ color: "#B45309" }}>
                      standby ·{" "}
                    </span>
                    tapping the strip opens the recorder, not the Library — first-run has nothing to browse yet.
                  </p>
                )}
              </div>

              <p className="text-[11px] leading-snug text-stone-400">
                <span className="font-mono uppercase tracking-[0.1em] text-stone-500">elsewhere · </span>
                {v.elsewhere}
              </p>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** The context board — the decision tool. Recents-above-the-fold per variant. */
function ContextBoard() {
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Context board · the decision tool"
        hint="each variant seated in a ghosted Home column at iPhone proportions (~366×750) — the only lit element is the cockpit. Watch the Recents count above the FOLD."
      />
      <div className="flex flex-wrap gap-x-10 gap-y-12">
        {VARIANTS.map((v) => (
          <ContextColumn key={v.key} variant={v} model={NOMINAL} />
        ))}
      </div>
    </div>
  );
}

/**
 * Why Terminal at strip height — a demoted reference (like /cockpit-grid's
 * settled row). The shared LED Matrix board (ledBoard.tsx) has to shrink its
 * dots to fit a full line on a 36pt strip and reads as mush; the Terminal holds
 * a crisp phosphor line. The decision stays closed — this only shows WHY at
 * this smaller size.
 */
function MatrixStrip({ text }: { text: string }) {
  const mat: Material = { pitch: "fine", shape: "round", bloom: true, ghost: true };
  const boardW = CONTENT_W - STRIP_PAD_X * 2;
  const board = useMemo(() => computeLine(text, PITCH_PX.fine, boardW, 22), [text, boardW]);
  return (
    <div
      style={{
        width: CONTENT_W,
        height: STRIP_H,
        boxSizing: "border-box",
        borderRadius: 7,
        padding: `0 ${STRIP_PAD_X}px`,
        display: "flex",
        alignItems: "center",
        overflow: "hidden",
        background: "#080604",
        border: "1px solid rgba(255,136,0,0.16)",
        boxShadow: "inset 0 1px 4px rgba(0,0,0,0.7)",
      }}
    >
      <DotMatrix board={board} mat={mat} height={22} />
    </div>
  );
}

function SettledReference() {
  const text = "STANDING BY — ROLL TAPE TO BEGIN";
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Why Terminal at strip height"
        hint="settled — Terminal is the voice; the shared Matrix board (ledBoard.tsx) only shows why it can't hold a line this short"
      />
      <div className="flex flex-col gap-4">
        <div className="flex flex-col gap-1.5">
          <StateLabel>Matrix — LED dot-matrix · shrinks to mush at 36pt</StateLabel>
          <MatrixStrip text={text} />
        </div>
        <div className="flex flex-col gap-1.5">
          <StateLabel>Terminal — amber CRT · holds the line</StateLabel>
          <Strip height={STRIP_H}>
            <Phosphor text={text} contentW={CONTENT_W - STRIP_PAD_X * 2} />
          </Strip>
        </div>
      </div>
    </div>
  );
}

export function CockpitCompactStudio() {
  return (
    <div className="flex flex-col gap-12">
      <VariantBoard />
      <ContextBoard />
      <SettledReference />
    </div>
  );
}
