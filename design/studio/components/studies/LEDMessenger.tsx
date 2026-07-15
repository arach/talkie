"use client";

/**
 * LED Messenger — a non-animating dot-matrix message board.
 *
 * The whole job of this surface is to WRITE A SHORT MESSAGE to the user, in a
 * generated 5×7 LED font: "WELCOME BACK", "5 DAY STREAK", "STANDING BY". Think
 * a small piece of hardware — dark glass, lit amber dots forming the glyphs, a
 * faint unlit dot grid behind them. It is deliberately STATIC: no marquee
 * scroll, no blink, no animation of any kind.
 *
 * The harness is three parts:
 *   1. Writer — type any message, see it rendered live on the Board.
 *   2. Message board — the canned cockpit-marquee messages at iPhone width.
 *   3. Material variants — swappable dot treatments (Pitch / Cell shape /
 *      Bloom / Ghost Grid) over a frozen layout.
 *
 * The board itself — the fit engine (wrap + shrink) and the DotMatrix renderer
 * — lives in ./ledBoard, shared with /cockpit-grid; the 5×7 glyph table lives
 * in ./ledFont, shared with every LED surface. Neither is duplicated here.
 * Palette values are the shipped HomeTacticalPalette raws.
 */

import { useMemo, useState } from "react";

import { LED_PALETTE } from "./ledFont";
import {
  DotMatrix,
  PITCH_PX,
  computeBoard,
  countUnknown,
  type Material,
  type Pitch,
  type Shape,
} from "./ledBoard";

// ── Palette — LED_PALETTE (accent / screen / faint ink) + chassis metals ──
const P = {
  accent: LED_PALETTE.accent, // #FF8800
  screen: LED_PALETTE.screen, // #050505
  faintInk: LED_PALETTE.faintInk, // #A6A29A
  canvas: "#E9E6DF", // home paper the chassis sits on
  matte: "#303030", // bezelChassis metal fill
  matteEdge: "#454545",
  accentEdge: "rgba(255,136,0,0.34)",
} as const;

const MONO = "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace";

// ─────────────────────────────────────────────────────────────────────────
//  Panel — the message Board as it sits on Home. Frozen geometry.
// ─────────────────────────────────────────────────────────────────────────

/**
 * Panel — the message Board as it sits on Home: `· MESSENGER` eyebrow over a
 * raised metal chassis wrapping the dark instrument glass. True iPhone content
 * width (366). Static — the board writes, it does not animate.
 */
function Panel({ text, mat }: { text: string; mat: Material }) {
  const board = useMemo(
    () => computeBoard(text, PITCH_PX[mat.pitch]),
    [text, mat.pitch]
  );
  return (
    <div
      style={{
        width: 366,
        background: P.canvas,
        padding: "10px 12px 14px",
        borderRadius: 20,
      }}
    >
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
        · Messenger
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
        {/* dark instrument glass — always-dark, the dots sit on this */}
        <div
          style={{
            borderRadius: 12,
            padding: "10px 12px",
            overflow: "hidden",
            background: `radial-gradient(circle at 50% 46%, rgba(255,136,0,0.13), transparent 55%), linear-gradient(180deg, rgba(255,255,255,0.05), rgba(255,255,255,0.01) 45%, rgba(0,0,0,0.28)), ${P.screen}`,
            border: `0.8px solid ${P.accentEdge}`,
            boxShadow:
              "inset 0 0.5px 0 rgba(255,255,255,0.12), inset 0 -16px 26px -26px rgba(0,0,0,0.85)",
          }}
        >
          {/* slim ident strip — keeps the cockpit family tell, nothing more */}
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
              color: P.faintInk,
            }}
          >
            <span>TALKIE</span>
            <span style={{ color: P.accent }}>MSG</span>
          </div>
          <DotMatrix board={board} mat={mat} />
        </div>
      </div>
    </div>
  );
}

/** Studio caption under a Board — reports how Fit handled the message. */
function FitCaption({ text, mat }: { text: string; mat: Material }) {
  const board = computeBoard(text, PITCH_PX[mat.pitch]);
  const unknown = countUnknown(text);
  const bits = [
    `PITCH ${board.dotSize}px`,
    `${board.lines.length} ${board.lines.length === 1 ? "LINE" : "LINES"}`,
  ];
  if (board.wrapped) bits.push("WRAPPED");
  if (board.shrunk) bits.push("SHRUNK TO FIT");
  if (unknown > 0) bits.push(`${unknown} UNKNOWN`);
  return (
    <p
      className="px-1 font-mono text-[10px] uppercase tracking-[0.12em] text-stone-400"
      style={{ maxWidth: 366 }}
    >
      {bits.join(" · ")}
    </p>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Studio chrome
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
              on
                ? "bg-stone-900 text-white"
                : "text-stone-500 hover:text-stone-800"
            }`}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

function Knob({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: { value: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.18em] text-stone-500">
        {label}
      </span>
      <Segmented options={options} value={value} onChange={onChange} />
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

// ─────────────────────────────────────────────────────────────────────────
//  1 · Writer — type any message, render it live.
// ─────────────────────────────────────────────────────────────────────────

function Writer() {
  const [text, setText] = useState("WELCOME BACK");
  const [pitch, setPitch] = useState<Pitch>("medium");
  const [shape, setShape] = useState<Shape>("round");
  const [bloom, setBloom] = useState(true);
  const [ghost, setGhost] = useState(true);
  const mat: Material = { pitch, shape, bloom, ghost };
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Live writer"
        hint="type any message — it renders straight to the board in the LED font"
      />
      <input
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Write to the user…"
        spellCheck={false}
        className="w-full max-w-[520px] rounded-lg border border-stone-200 bg-white px-3.5 py-2.5 font-mono text-[13px] uppercase tracking-[0.1em] text-stone-800 outline-none focus:border-stone-400"
      />
      <div className="flex flex-wrap items-start gap-x-7 gap-y-4">
        <Knob
          label="Pitch"
          value={pitch}
          onChange={(v) => setPitch(v as Pitch)}
          options={[
            { value: "fine", label: "Fine" },
            { value: "medium", label: "Medium" },
            { value: "coarse", label: "Coarse" },
          ]}
        />
        <Knob
          label="Cell"
          value={shape}
          onChange={(v) => setShape(v as Shape)}
          options={[
            { value: "round", label: "Round" },
            { value: "square", label: "Square" },
          ]}
        />
        <Knob
          label="Bloom"
          value={bloom ? "on" : "off"}
          onChange={(v) => setBloom(v === "on")}
          options={[
            { value: "on", label: "Glow" },
            { value: "off", label: "Flat" },
          ]}
        />
        <Knob
          label="Ghost grid"
          value={ghost ? "on" : "off"}
          onChange={(v) => setGhost(v === "on")}
          options={[
            { value: "on", label: "Ghost" },
            { value: "off", label: "Dark" },
          ]}
        />
      </div>
      <div className="flex flex-col gap-2">
        <Panel text={text} mat={mat} />
        <FitCaption text={text} mat={mat} />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  2 · Message board — the cockpit-marquee messages at iPhone width.
// ─────────────────────────────────────────────────────────────────────────

const SCENARIO_MESSAGES: string[] = [
  "WELCOME BACK",
  "LAST TAKE 2H AGO",
  "5 DAY STREAK",
  "TAKE #100 ON TAPE",
  "STANDING BY — ROLL TAPE TO BEGIN",
  "PARAKEET WARMED UP",
];

const SCENARIO_MAT: Material = {
  pitch: "medium",
  shape: "round",
  bloom: true,
  ghost: true,
};

function ScenarioBoard() {
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Message board"
        hint="the canned messages the cockpit marquee rotates — one frozen material, six contents"
      />
      <div className="flex flex-wrap gap-7">
        {SCENARIO_MESSAGES.map((m) => (
          <div key={m} className="flex flex-col gap-2">
            <Panel text={m} mat={SCENARIO_MAT} />
            <FitCaption text={m} mat={SCENARIO_MAT} />
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  3 · Material variants — swappable dot treatments, layout frozen.
// ─────────────────────────────────────────────────────────────────────────

const SAMPLE = "5 DAY STREAK";

const MATERIAL_PRESETS: { label: string; note: string; mat: Material }[] = [
  {
    label: "Fine · Round · Glow · Ghost",
    note: "the lit-sign default — small round dots, soft bloom, faint ghost grid behind.",
    mat: { pitch: "fine", shape: "round", bloom: true, ghost: true },
  },
  {
    label: "Coarse · Round · Glow · Dark",
    note: "chunky beads on pure black — no ghost grid, the message floats.",
    mat: { pitch: "coarse", shape: "round", bloom: true, ghost: false },
  },
  {
    label: "Medium · Square · Flat · Ghost",
    note: "pixel-panel look — square cells, no glow, full ghost matrix visible.",
    mat: { pitch: "medium", shape: "square", bloom: false, ghost: true },
  },
  {
    label: "Fine · Square · Flat · Dark",
    note: "dot-printer look — tight square cells, flat, dark ground.",
    mat: { pitch: "fine", shape: "square", bloom: false, ghost: false },
  },
];

function MaterialBoard() {
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Material variants"
        hint={`same message ("${SAMPLE}"), same board — only the dot treatment changes`}
      />
      <div className="flex flex-wrap gap-7">
        {MATERIAL_PRESETS.map((preset) => (
          <div key={preset.label} className="flex flex-col gap-2">
            <div className="px-1 font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-700">
              {preset.label}
            </div>
            <Panel text={SAMPLE} mat={preset.mat} />
            <p
              className="px-1 text-[11px] leading-snug text-stone-400"
              style={{ maxWidth: 366 }}
            >
              {preset.note}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────
//  Study
// ─────────────────────────────────────────────────────────────────────────

export function LEDMessengerStudio() {
  return (
    <div className="flex flex-col gap-12">
      <Writer />
      <ScenarioBoard />
      <MaterialBoard />
    </div>
  );
}
