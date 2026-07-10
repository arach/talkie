"use client";

/**
 * Home · Cockpit v2 — content pass over the shipped iOS comms instrument.
 *
 * The chassis / screen / three-lane column / right-hand module / single
 * detail line KEEP their exact geometry from the shipped Swift
 * (`HomeCockpit` in HomeNextView.swift, lines 453-791). This is a
 * MATERIAL/CONTENT swap, not a layout redesign:
 *
 *  - the three placeholder lanes (BRIDGE / SHARES / REPLIES) become
 *    TAKES / ENGINE / SYSTEMS, each backed by a real iOS data source
 *  - the Life-in-Dots module is repurposed to a 12-day capture grid + streak
 *  - the plain detail line becomes a pixelized LED dot-matrix Marquee
 *  - a REC override turns the meters into mag-tape VU meters
 *
 * The harness varies DATA SCENARIOS (layout is frozen): a scenario picker
 * plus a side-by-side board comparing all six at once. Palette values are
 * the shipped HomeTacticalPalette raw values — the screen is always-dark
 * and ignores light/dark, so nothing themes here.
 */

import { useState } from "react";

import { LED_FONT } from "./ledFont";

// ── Shipped tactical palette (HomeTacticalPalette, HomeNextView.swift:365) ──
const P = {
  accent: "#FF8800",
  accentSoft: "rgba(255,136,0,0.14)",
  accentEdge: "rgba(255,136,0,0.34)",
  matte: "#303030", // bezelChassis metal fill (light); dark = #181818
  matteEdge: "#454545",
  screen: "#050505",
  screenAlt: "#121212",
  screenInk: "#F3F1EA",
  screenInkFaint: "#A6A29A",
  canvas: "#E9E6DF", // the home paper the chassis sits on
} as const;

const MONO =
  "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace";

// ─────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────

type ScenarioKey =
  | "nominal"
  | "quiet"
  | "first-run"
  | "downloading"
  | "hold"
  | "rec";

interface Lane {
  /** TAKES / ENGINE / SYSTEMS */
  label: string;
  value: string;
  meta: string;
  /** 0…1 — semantics differ per lane, see legend. */
  level: number;
}

interface CockpitModel {
  /** header center readout */
  status: string;
  statusTone: "accent" | "dim" | "warn" | "rec";
  /** header right readout — wall clock, or elapsed while REC */
  clock: string;
  lanes: [Lane, Lane, Lane];
  /** 12 dots = last 12 days (oldest→newest), true = captured something */
  days: boolean[];
  /** marker dot index (today) */
  todayIndex: number;
  /** consecutive-day capture streak */
  streak: number;
  /** rotating dot-matrix messages */
  marquee: string[];
  /** REC override — meters become VU, header flips to REC */
  rec: boolean;
}

interface Scenario {
  key: ScenarioKey;
  label: string;
  intent: string;
  model: CockpitModel;
}

function days(pattern: string): boolean[] {
  return pattern.split("").map((c) => c === "1");
}

const SCENARIOS: Scenario[] = [
  {
    key: "nominal",
    label: "Nominal",
    intent:
      "Active day, engine hot, all systems go. Today's activity pins the TAKES meter.",
    model: {
      status: "READY",
      statusTone: "accent",
      clock: "20:04",
      lanes: [
        { label: "TAKES", value: "3 takes · 4m 12s", meta: "+2 DICT", level: 0.84 },
        { label: "ENGINE", value: "Parakeet", meta: "HOT", level: 1.0 },
        { label: "SYSTEMS", value: "All go", meta: "GO", level: 1.0 },
      ],
      days: days("110111011111"),
      todayIndex: 11,
      streak: 5,
      marquee: [
        "LAST TAKE 2H AGO · 5 DAY STREAK",
        "TALKIE · DAY SHIFT",
        "PARAKEET WARMED UP",
        "TAKE #128 ON TAPE",
      ],
      rec: false,
    },
  },
  {
    key: "quiet",
    label: "Quiet",
    intent:
      "No takes today but the streak is alive. TAKES meter sits low, engine still warm.",
    model: {
      status: "READY",
      statusTone: "accent",
      clock: "18:47",
      lanes: [
        { label: "TAKES", value: "No takes yet", meta: "ROLL TAPE", level: 0.06 },
        { label: "ENGINE", value: "Parakeet", meta: "HOT", level: 1.0 },
        { label: "SYSTEMS", value: "All go", meta: "GO", level: 1.0 },
      ],
      days: days("010010111110"),
      todayIndex: 11,
      streak: 5,
      marquee: [
        "STREAK ALIVE · 5 DAYS · ROLL TAPE TODAY",
        "TALKIE · QUIET HOURS",
        "LAST TAKE YESTERDAY",
      ],
      rec: false,
    },
  },
  {
    key: "first-run",
    label: "First run",
    intent:
      "Empty library. Marquee leads with STANDING BY. Parakeet not downloaded → Apple Speech, permissions ungranted.",
    model: {
      status: "STANDBY",
      statusTone: "dim",
      clock: "06:12",
      lanes: [
        { label: "TAKES", value: "No takes yet", meta: "ROLL TAPE", level: 0.0 },
        { label: "ENGINE", value: "Apple Speech", meta: "COLD", level: 0.14 },
        { label: "SYSTEMS", value: "Grant mic access", meta: "WARN", level: 0.4 },
      ],
      days: days("000000000000"),
      todayIndex: 11,
      streak: 0,
      marquee: ["STANDING BY — ROLL TAPE TO BEGIN", "TALKIE · FIRST LIGHT"],
      rec: false,
    },
  },
  {
    key: "downloading",
    label: "Downloading",
    intent:
      "Parakeet model pulling down — ENGINE meta shows DL 47%, meter tracks download progress.",
    model: {
      status: "PREP",
      statusTone: "accent",
      clock: "09:31",
      lanes: [
        { label: "TAKES", value: "1 take · 0m 48s", meta: "LAST 20M", level: 0.3 },
        { label: "ENGINE", value: "Parakeet", meta: "DL 47%", level: 0.47 },
        { label: "SYSTEMS", value: "All go", meta: "GO", level: 1.0 },
      ],
      days: days("001011010111"),
      todayIndex: 11,
      streak: 3,
      marquee: [
        "PARAKEET DOWNLOADING · 47%",
        "APPLE SPEECH ON DECK",
        "TALKIE · WARMING UP",
      ],
      rec: false,
    },
  },
  {
    key: "hold",
    label: "Hold",
    intent:
      "Mic permission blocked. SYSTEMS surfaces the first blocker, meta HOLD; meter = fraction of checks passing.",
    model: {
      status: "HOLD",
      statusTone: "warn",
      clock: "14:22",
      lanes: [
        { label: "TAKES", value: "2 takes · 3m 05s", meta: "LAST 1H", level: 0.5 },
        { label: "ENGINE", value: "Parakeet", meta: "HOT", level: 1.0 },
        { label: "SYSTEMS", value: "Mic access off", meta: "HOLD", level: 0.8 },
      ],
      days: days("101100100011"),
      todayIndex: 11,
      streak: 2,
      marquee: ["MIC ACCESS OFF · TAP TO FIX", "SYSTEMS ON HOLD", "TALKIE · STANDBY"],
      rec: false,
    },
  },
  {
    key: "rec",
    label: "Rec (live)",
    intent:
      "Recording. Whole screen goes live — meters become mag-tape VU, header flips to REC + elapsed.",
    model: {
      status: "REC",
      statusTone: "rec",
      clock: "00:14",
      lanes: [
        { label: "TAKES", value: "Recording…", meta: "LIVE", level: 0.9 },
        { label: "ENGINE", value: "Parakeet", meta: "STREAM", level: 0.85 },
        { label: "SYSTEMS", value: "All go", meta: "GO", level: 1.0 },
      ],
      days: days("110111011111"),
      todayIndex: 11,
      streak: 5,
      marquee: ["● REC · TAPE ROLLING", "LEVELS HOT"],
      rec: true,
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────
//  5×7 dot-matrix font (LED marquee glyphs)
// ─────────────────────────────────────────────────────────────────────────
//
//  The glyph table lives in ./ledFont.ts — shared with the /led-messenger
//  study so the two LED surfaces never duplicate or drift the font.

const DOT = 2; // px — dot diameter
const GAP = 1; // px — dot gap

function Glyph({ char }: { char: string }) {
  const rows = LED_FONT[char] ?? LED_FONT[" "];
  return (
    <div
      aria-hidden
      style={{
        display: "grid",
        gridTemplateColumns: `repeat(5, ${DOT}px)`,
        gridTemplateRows: `repeat(7, ${DOT}px)`,
        gap: GAP,
        flex: "0 0 auto",
      }}
    >
      {rows.map((row, r) =>
        row.split("").map((cell, c) => {
          const lit = cell === "1";
          return (
            <span
              key={`${r}-${c}`}
              style={{
                width: DOT,
                height: DOT,
                borderRadius: DOT,
                background: lit ? P.accent : "rgba(255,136,0,0.09)",
                boxShadow: lit ? `0 0 2px rgba(255,136,0,0.7)` : "none",
              }}
            />
          );
        })
      )}
    </div>
  );
}

function MarqueeRun({ text }: { text: string }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 3, flex: "0 0 auto" }}>
      {text.split("").map((ch, i) => (
        <Glyph key={i} char={ch.toUpperCase()} />
      ))}
    </div>
  );
}

/**
 * Marquee — the pixelized LED dot-matrix line under the screen. Replaces the
 * plain detail text. Scrolls the rotating message set when `scroll`, else
 * shows the primary message statically (comparison board). Amber-on-dark
 * LED matrix substrate.
 */
function Marquee({ messages, scroll }: { messages: string[]; scroll: boolean }) {
  const joined = messages.join("     ·     ") + "     ·     ";
  return (
    <div
      style={{
        position: "relative",
        overflow: "hidden",
        borderRadius: 6,
        padding: "5px 8px",
        background: "#080604",
        border: "1px solid rgba(255,136,0,0.14)",
        boxShadow: "inset 0 1px 4px rgba(0,0,0,0.7)",
      }}
    >
      <div
        style={{
          display: "flex",
          width: scroll ? "max-content" : "100%",
          whiteSpace: "nowrap",
          animation: scroll ? "cockpit-marquee 22s linear infinite" : "none",
        }}
      >
        <MarqueeRun text={scroll ? joined : messages[0]} />
        {scroll ? <MarqueeRun text={joined} /> : null}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Meters
// ─────────────────────────────────────────────────────────────────────────

/** Normal 12-segment level bar (frozen geometry from CockpitLaneRow). */
function LevelBar({ level }: { level: number }) {
  const filled = Math.round(level * 12);
  return (
    <div style={{ display: "flex", gap: 3, marginTop: 5 }} aria-hidden>
      {Array.from({ length: 12 }, (_, i) => (
        <span
          key={i}
          style={{
            flex: 1,
            height: 3,
            borderRadius: 1.5,
            background: i < filled ? P.accent : "rgba(255,255,255,0.12)",
            boxShadow:
              i === filled - 1 ? `0 0 3px rgba(255,136,0,0.5)` : "none",
          }}
        />
      ))}
    </div>
  );
}

/** REC override: the meter becomes a mag-tape VU — bars swinging off an
 *  amber centerline with a travelling tape-head marker. */
function VUMeter({ seed }: { seed: number }) {
  return (
    <div
      aria-hidden
      style={{
        position: "relative",
        height: 16,
        marginTop: 5,
        display: "flex",
        alignItems: "center",
        gap: 3,
      }}
    >
      {/* amber centerline */}
      <span
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: "50%",
          height: 1,
          background: "rgba(255,136,0,0.45)",
          transform: "translateY(-0.5px)",
        }}
      />
      {Array.from({ length: 12 }, (_, i) => (
        <span
          key={i}
          style={{
            flex: 1,
            height: 14,
            borderRadius: 1.5,
            background: P.accent,
            transformOrigin: "center",
            animation: `cockpit-vu 0.9s ease-in-out infinite`,
            animationDelay: `${((i * 7 + seed * 3) % 10) * 0.06}s`,
            boxShadow: `0 0 3px rgba(255,136,0,0.5)`,
          }}
        />
      ))}
      {/* tape-head marker sweeping across */}
      <span
        style={{
          position: "absolute",
          top: -1,
          bottom: -1,
          width: 2,
          background: "#FFD8A0",
          boxShadow: "0 0 6px rgba(255,180,90,0.9)",
          animation: "cockpit-tapehead 2.4s linear infinite",
        }}
      />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Lanes + Life-in-Dots
// ─────────────────────────────────────────────────────────────────────────

function LaneRow({ lane, rec, index }: { lane: Lane; rec: boolean; index: number }) {
  return (
    <div
      style={{
        padding: "6px 8px",
        borderRadius: 6,
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,136,0,0.12)",
      }}
    >
      <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
        <span
          style={{
            width: 52,
            flex: "0 0 auto",
            fontFamily: MONO,
            fontSize: 8,
            fontWeight: 600,
            letterSpacing: "0.1em",
            textTransform: "uppercase",
            color: P.screenInkFaint,
          }}
        >
          {lane.label}
        </span>
        <span
          style={{
            flex: 1,
            minWidth: 0,
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
            fontSize: 12,
            color: P.screenInk,
          }}
        >
          {lane.value}
        </span>
        <span
          style={{
            flex: "0 0 auto",
            fontFamily: MONO,
            fontSize: 8,
            fontWeight: 700,
            letterSpacing: "0.08em",
            textTransform: "uppercase",
            color: P.accent,
          }}
        >
          {lane.meta}
        </span>
      </div>
      {rec ? <VUMeter seed={index} /> : <LevelBar level={lane.level} />}
    </div>
  );
}

/**
 * Life-in-Dots — repurposed. Keeps the 6×2 dot-grid geometry, but the 12 dots
 * now read as the LAST 12 DAYS (filled = captured something that day, amber
 * marker on today). The old % readout becomes a streak count.
 */
function LifeInDots({ model }: { model: CockpitModel }) {
  return (
    <div
      style={{
        width: 84,
        flex: "0 0 auto",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        gap: 8,
        padding: 8,
        borderRadius: 8,
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
          textTransform: "uppercase",
          color: P.screenInkFaint,
        }}
      >
        <span>12 DAYS</span>
        <span style={{ color: model.streak > 0 ? P.accent : P.screenInkFaint }}>
          STRK {model.streak}
        </span>
      </div>
      <div
        aria-hidden
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(6, 1fr)",
          gap: 4,
          justifyItems: "center",
        }}
      >
        {model.days.map((filled, i) => {
          const marker = i === model.todayIndex;
          return (
            <span
              key={i}
              style={{
                width: 6,
                height: 6,
                borderRadius: 6,
                background: marker
                  ? P.accent
                  : filled
                    ? "rgba(255,255,255,0.92)"
                    : "transparent",
                border:
                  !marker && !filled ? "1px solid rgba(255,255,255,0.18)" : "0",
                boxShadow: marker ? `0 0 5px rgba(255,136,0,0.8)` : "none",
              }}
            />
          );
        })}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  The instrument
// ─────────────────────────────────────────────────────────────────────────

function statusColor(tone: CockpitModel["statusTone"]): string {
  switch (tone) {
    case "accent":
      return P.accent;
    case "rec":
      return P.accent;
    case "warn":
      return "#FFB74D";
    case "dim":
      return P.screenInkFaint;
  }
}

/** CockpitScreen — the always-dark instrument glass. Frozen geometry. */
function Screen({ model, scroll }: { model: CockpitModel; scroll: boolean }) {
  return (
    <div
      style={{
        borderRadius: 14,
        padding: "10px 12px",
        overflow: "hidden",
        background: `radial-gradient(circle at 50% 44%, rgba(255,136,0,0.22), transparent 46%), linear-gradient(180deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02) 45%, rgba(0,0,0,0.24)), ${P.screen}`,
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
        <span
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 4,
            color: statusColor(model.statusTone),
          }}
        >
          {model.statusTone === "rec" ? (
            <span
              style={{
                width: 6,
                height: 6,
                borderRadius: 6,
                background: P.accent,
                boxShadow: `0 0 5px rgba(255,136,0,0.9)`,
                animation: "cockpit-recdot 1s ease-in-out infinite",
              }}
            />
          ) : null}
          {model.status}
        </span>
        <span style={{ fontVariantNumeric: "tabular-nums" }}>{model.clock}</span>
      </div>

      {/* body: lane column + Life-in-Dots */}
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 6 }}>
          {model.lanes.map((lane, i) => (
            <LaneRow key={lane.label} lane={lane} rec={model.rec} index={i} />
          ))}
        </div>
        <LifeInDots model={model} />
      </div>

      {/* marquee lives under the header/body inside the screen-adjacent stack;
          rendered by the chassis so it reads as one detail line. */}
      <div style={{ marginTop: 8 }}>
        <Marquee messages={model.marquee} scroll={scroll} />
      </div>
    </div>
  );
}

/**
 * HomeCockpitV2 — the full instrument as it sits on Home: `· COCKPIT` eyebrow
 * over the raised metal chassis (bezelChassis metal matte). Rendered at true
 * iPhone content width. `scroll` animates the marquee (picker view); the
 * comparison board holds it static.
 */
function HomeCockpitV2({ model, scroll = true }: { model: CockpitModel; scroll?: boolean }) {
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
        · Cockpit
      </div>
      {/* raised metal chassis — bezelChassis(padding:10, corner:14, metal:true) */}
      <div
        style={{
          borderRadius: 14,
          padding: 10,
          background: `linear-gradient(180deg, ${P.matteEdge}, ${P.matte} 52%, #262626)`,
          border: "0.8px solid rgba(0,0,0,0.5)",
          boxShadow:
            "inset 0 1px 0 rgba(255,255,255,0.18), 0 10px 24px -14px rgba(0,0,0,0.55)",
          display: "flex",
          flexDirection: "column",
          gap: 8,
        }}
      >
        <Screen model={model} scroll={scroll} />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Harness
// ─────────────────────────────────────────────────────────────────────────

const KEYFRAMES = `
@keyframes cockpit-marquee { from { transform: translateX(0); } to { transform: translateX(-50%); } }
@keyframes cockpit-vu { 0%, 100% { transform: scaleY(0.22); } 50% { transform: scaleY(1); } }
@keyframes cockpit-tapehead { from { left: 2%; } to { left: 98%; } }
@keyframes cockpit-recdot { 0%, 100% { opacity: 1; } 50% { opacity: 0.2; } }
`;

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

/** Data-source legend — proves nothing on the instrument is a placeholder. */
const SOURCES: [string, string][] = [
  [
    "TAKES lane",
    "HomeFeed.todayStats (memos + dictations + captures today) + VoiceMemo.duration sums. Meter = today's activity vs. trailing 7-day average.",
  ],
  [
    "ENGINE lane",
    "ParakeetModelManager.shared.state (.notDownloaded / .downloading(progress) / .loading / .ready) + .isWarmedUp. Meta flips to PROCESSING n from VoiceMemo.isTranscribing count.",
  ],
  [
    "SYSTEMS lane",
    "DictationReadinessChecker.readiness — 5 checks (Microphone, Speech Recognition, Keyboard Mode, Audio Session, State Health). Value = first blocker; meter = fraction .ready.",
  ],
  [
    "Life-in-Dots",
    "createdAt across VoiceMemo + KeyboardDictationStore + CaptureStore, last 12 days. Marker = today; STRK n = consecutive capture-day streak.",
  ],
  [
    "Marquee",
    "Derived line: freshest fact, streak, milestone (TAKE #100), time-of-day station ident, engine event. Empty library ⇒ STANDING BY.",
  ],
  [
    "REC Override",
    "RecordingSheetController.shared.isPresented gates the override; DictationMicMonitor.level drives the mag-tape VU bars.",
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
        hint="pick a data scenario — layout is frozen, only the content + state change"
      />
      <Segmented
        options={SCENARIOS.map((s) => ({ value: s.key, label: s.label }))}
        value={key}
        onChange={(v) => setKey(v as ScenarioKey)}
      />
      <p className="max-w-[680px] text-[12.5px] italic leading-relaxed text-stone-500">
        <span className="font-mono not-italic uppercase tracking-[0.14em] text-stone-700">
          {active.label}
        </span>
        {" — "}
        {active.intent}
      </p>
      <div className="flex justify-start">
        <HomeCockpitV2 model={active.model} scroll />
      </div>
    </div>
  );
}

function Board() {
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="All scenarios"
        hint="the six data states side by side — one frozen layout, six contents"
      />
      <div className="flex flex-wrap gap-7">
        {SCENARIOS.map((s) => (
          <div key={s.key} className="flex flex-col gap-2">
            <div className="flex items-baseline gap-2 px-1">
              <span className="font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-700">
                {s.label}
              </span>
            </div>
            {/* board holds marquee static for stable comparison; VU still animates */}
            <HomeCockpitV2 model={s.model} scroll={false} />
            <p className="max-w-[366px] px-1 text-[11px] leading-snug text-stone-400">
              {s.intent}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

export function HomeCockpitStudio() {
  return (
    <div className="flex flex-col gap-12">
      <style>{KEYFRAMES}</style>
      <Picker />
      <Board />
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
