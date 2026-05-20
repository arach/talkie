"use client";

import React, { useEffect, useRef, useState } from "react";
import { StudioPage } from "@/components/StudioPage";

/**
 * Mac Talkie — Recording → Memo transition.
 *
 * Idea (2026-05-19): the wave isn't a separate UI from the transcript —
 * it IS the transcript being written. When recording ends, the wave
 * doesn't just disappear; it accelerates into a structured form, settles
 * into a baseline, and the transcribed text emerges in place — landing
 * the surface naturally on the memo detail layout.
 *
 * Phase timeline (mock durations — port will tune):
 *
 *   0  idle        : surface hidden / page baseline
 *   1  recording   : wave traversing at audio-reactive amplitude (∞)
 *   2  stopping    : phase accelerates briefly, amplitude crashes (400ms)
 *   3  settling    : amber line flattens at the baseline (300ms hold)
 *   4  emerging    : transcript text reveals along the baseline (1100ms)
 *   5  memo        : surface reflows into memo detail (header / body /
 *                    margin metadata)                                 (500ms)
 */

const TALKIE_INK = "#2A2620";
const TALKIE_INK_FAINT = "rgba(42,38,32,0.55)";
const TALKIE_INK_FAINTER = "rgba(42,38,32,0.32)";
const TALKIE_CREAM = "#FBFBFA";
const TALKIE_PAPER = "#F4F1EA";
const SCOPE_AMBER = "#C47D1C";
const SCOPE_AMBER_GLOW = "#E89A3C";
const REC_RED = "#C03A2A";

type Phase = "idle" | "recording" | "stopping" | "settling" | "emerging" | "memo";

const PHASE_ORDER: Phase[] = [
  "idle",
  "recording",
  "stopping",
  "settling",
  "emerging",
  "memo",
];

// Mock transcript that emerges from the wave.
const SAMPLE_TRANSCRIPT =
  "Move the chrome bar Talkie pill to permanent center, add a hover-revealed nav strip, and surface Settings as a gear in the toolbar trailing slot.";

const SAMPLE_TITLE = "Chrome bar consolidation";

export default function MacRecordToMemoStudy() {
  const [phase, setPhase] = useState<Phase>("idle");
  const timeoutsRef = useRef<number[]>([]);

  function clearScheduled() {
    timeoutsRef.current.forEach((id) => window.clearTimeout(id));
    timeoutsRef.current = [];
  }

  function schedule(ms: number, run: () => void) {
    const id = window.setTimeout(run, ms);
    timeoutsRef.current.push(id);
  }

  function play() {
    clearScheduled();
    setPhase("recording");
    // Hold "recording" for a beat so the wave reads as active.
    schedule(1800, () => setPhase("stopping"));
    schedule(1800 + 400, () => setPhase("settling"));
    schedule(1800 + 400 + 300, () => setPhase("emerging"));
    schedule(1800 + 400 + 300 + 1100, () => setPhase("memo"));
  }

  function reset() {
    clearScheduled();
    setPhase("idle");
  }

  useEffect(() => () => clearScheduled(), []);

  return (
    <StudioPage
      eyebrow="Recording → Memo · animated transition"
      title="Wave settles into the transcript"
      help="Press Play to watch the wave decelerate, flatten, and reveal text in place. Source of truth for the Swift port."
    >
      <div className="flex flex-col gap-7 py-4">
        <Controls phase={phase} onPlay={play} onReset={reset} />

        <Stage phase={phase} />

        <PhaseLegend phase={phase} />

        <SpecNotes />
      </div>
    </StudioPage>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Controls

function Controls({
  phase,
  onPlay,
  onReset,
}: {
  phase: Phase;
  onPlay: () => void;
  onReset: () => void;
}) {
  const isPlaying = phase !== "idle" && phase !== "memo";
  return (
    <div className="flex items-center gap-4 rounded-md border border-studio-edge px-4 py-3">
      <button
        type="button"
        onClick={onPlay}
        className="rounded-sm border border-studio-ink px-3 py-1.5 font-mono text-[10px] font-semibold uppercase tracking-[0.22em] text-studio-ink transition-colors hover:bg-studio-ink hover:text-studio-paper"
      >
        {isPlaying ? "Restart" : "Play"}
      </button>
      <button
        type="button"
        onClick={onReset}
        className="rounded-sm border border-studio-edge px-3 py-1.5 font-mono text-[10px] font-semibold uppercase tracking-[0.22em] text-studio-ink-faint transition-colors hover:text-studio-ink"
      >
        Reset
      </button>

      <div className="ml-auto flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
        <span>Phase</span>
        <span className="text-studio-ink">{phase}</span>
      </div>
    </div>
  );
}

function PhaseLegend({ phase }: { phase: Phase }) {
  return (
    <div className="flex items-stretch gap-0 rounded-md border border-studio-edge font-mono text-[9px] font-semibold uppercase tracking-[0.22em]">
      {PHASE_ORDER.map((p, i) => {
        const active = p === phase;
        const reached =
          PHASE_ORDER.indexOf(phase) >= PHASE_ORDER.indexOf(p);
        return (
          <div
            key={p}
            className="flex-1 border-r border-studio-edge px-3 py-2.5 text-center last:border-r-0"
            style={{
              background: active
                ? "rgba(196,125,28,0.12)"
                : reached
                ? "rgba(42,38,32,0.04)"
                : "transparent",
              color: active
                ? SCOPE_AMBER
                : reached
                ? TALKIE_INK
                : TALKIE_INK_FAINTER,
            }}
          >
            {i}&nbsp;·&nbsp;{p}
          </div>
        );
      })}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Stage — the actual visual surface that morphs through phases

function Stage({ phase }: { phase: Phase }) {
  return (
    <div
      className="relative overflow-hidden rounded-lg"
      style={{
        background: TALKIE_CREAM,
        border: `0.5px solid rgba(42,38,32,0.10)`,
        minHeight: 540,
      }}
    >
      {/* Chrome bar (constant — pill stays anchored across all phases) */}
      <ChromeBarMock phase={phase} />

      {/* The morphing core */}
      <div className="absolute inset-x-0 top-[68px] bottom-0 flex flex-col">
        {phase === "memo" ? (
          <MemoDetailLayout />
        ) : (
          <RecordingCompanion phase={phase} />
        )}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Recording companion that decays through phases

function RecordingCompanion({ phase }: { phase: Phase }) {
  // Phase-driven amplitude target. CSS transitions interpolate.
  const amplitude =
    phase === "recording"
      ? 0.65
      : phase === "stopping"
      ? 0.18
      : phase === "settling" || phase === "emerging"
      ? 0.0
      : 0; // idle / memo handled elsewhere

  // Stroke weight tapers as amplitude flattens.
  const strokeWidth =
    phase === "recording"
      ? 2.4
      : phase === "stopping"
      ? 1.8
      : 1.2;

  // The line color shifts subtly from amber to a more anchored amber-ink
  // as it settles — gives a sense of resolve.
  const strokeColor = SCOPE_AMBER;

  const visible = phase !== "idle";

  return (
    <div
      className="flex flex-col items-stretch transition-opacity duration-300"
      style={{
        opacity: visible ? 1 : 0,
        padding: "32px 80px",
      }}
    >
      {/* Top hairline */}
      <div style={{ height: 0.5, background: "rgba(42,38,32,0.16)" }} />

      <div
        className="flex flex-col items-center gap-7 py-9"
        style={{ flex: "1 1 auto" }}
      >
        {/* Eyebrow — caption changes with phase */}
        <EyebrowRow phase={phase} />

        {/* The wave / baseline / emerging text — same vertical slot */}
        <div className="relative" style={{ width: 880, height: 196 }}>
          {/* Animated wave / baseline */}
          <div className="absolute inset-0 flex items-center justify-center">
            <MorphingFlourish
              amplitude={amplitude}
              strokeWidth={strokeWidth}
              strokeColor={strokeColor}
            />
          </div>

          {/* Emerging text — sits on top once we're at "emerging" */}
          <div className="absolute inset-0 flex items-center justify-center">
            <EmergingTranscript active={phase === "emerging"} />
          </div>
        </div>

        {/* Caption row */}
        <CaptionRow phase={phase} />
      </div>

      {/* Bottom hairline */}
      <div style={{ height: 0.5, background: "rgba(42,38,32,0.16)" }} />
    </div>
  );
}

function EyebrowRow({ phase }: { phase: Phase }) {
  const eyebrowText =
    phase === "stopping" || phase === "settling" || phase === "emerging"
      ? "TRANSCRIBING"
      : "RECORDING";

  return (
    <div
      className="flex items-center gap-3 font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
      style={{ color: TALKIE_INK_FAINT }}
    >
      <RecDot active={phase === "recording"} />
      <span>{eyebrowText}</span>
      <span style={{ color: TALKIE_INK_FAINTER }}>·</span>
      <span>LIBRARY</span>
      <span style={{ color: TALKIE_INK_FAINTER }}>·</span>
      <span>SCOPE</span>
    </div>
  );
}

function CaptionRow({ phase }: { phase: Phase }) {
  const elapsed = "0:14";
  const status =
    phase === "recording"
      ? "RECORDING MEMO"
      : phase === "stopping"
      ? "STOPPING"
      : phase === "settling" || phase === "emerging"
      ? "TRANSCRIBING…"
      : "—";

  return (
    <div
      className="flex w-full items-baseline justify-between font-mono text-[10px] uppercase tracking-[0.28em]"
      style={{ color: TALKIE_INK_FAINT }}
    >
      <span>
        <span className="tabular-nums">{elapsed}</span>
        &nbsp;·&nbsp;
        <span>{status}</span>
      </span>
      <span style={{ opacity: phase === "recording" ? 1 : 0 }}>⌘. STOP</span>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Morphing flourish — same shape primitive as the real surface, with
// CSS-animated amplitude / stroke so the wave decays smoothly.

function MorphingFlourish({
  amplitude,
  strokeWidth,
  strokeColor,
}: {
  amplitude: number;
  strokeWidth: number;
  strokeColor: string;
}) {
  // Static path with N samples; we compute it once but interpolate the
  // amplitude visually by squashing the path vertically via transform.
  // This keeps the "shape" stable while the swing decays — reads as
  // settling, not redrawing.
  const path = React.useMemo(() => buildFlourishPath(880, 196, 0.7), []);
  // The viewBox is 880x196; we scale the wave around its midline so
  // the flat-out state lands cleanly on the baseline.
  const scaleY = Math.max(0.0001, amplitude / 0.7);

  return (
    <svg
      width={880}
      height={196}
      viewBox="0 0 880 196"
      aria-hidden
      style={{
        transition:
          "filter 600ms ease-out",
        filter: amplitude > 0.05
          ? `drop-shadow(0 0 3px ${SCOPE_AMBER_GLOW}55)`
          : "none",
      }}
    >
      <defs>
        <linearGradient id="morphGradient" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor={strokeColor} stopOpacity="0" />
          <stop offset="4%" stopColor={strokeColor} stopOpacity="0.95" />
          <stop offset="96%" stopColor={strokeColor} stopOpacity="0.9" />
          <stop offset="100%" stopColor={strokeColor} stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* Wrap the path in a group transformed around the midline so that
          decreasing scaleY collapses the wave to the baseline. */}
      <g
        style={{
          transformOrigin: "440px 98px",
          transform: `scaleY(${scaleY})`,
          transition:
            "transform 700ms cubic-bezier(0.22, 0.61, 0.36, 1), stroke-width 500ms ease-out",
        }}
      >
        <path
          d={path}
          fill="none"
          stroke="url(#morphGradient)"
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          style={{
            transition: "stroke-width 500ms ease-out",
          }}
        />
      </g>

      {/* Baseline rule — fades in as the wave flattens, so settling reads
          as the wave becoming a line (continuous), not the wave vanishing. */}
      <line
        x1="0"
        x2="880"
        y1="98"
        y2="98"
        stroke="url(#morphGradient)"
        strokeWidth={1.2}
        style={{
          opacity: scaleY < 0.06 ? 0.85 : 0,
          transition: "opacity 400ms ease-out",
        }}
      />
    </svg>
  );
}

function buildFlourishPath(width: number, height: number, amp: number) {
  const n = 280;
  const mid = height / 2;
  const A = (height / 2) * amp;
  const points: string[] = [];
  for (let i = 0; i <= n; i++) {
    const x = (i / n) * width;
    const t = i / n;
    const fade = Math.sin(Math.PI * t);
    const y =
      mid +
      fade *
        (Math.sin(i * 0.18) * (A * 0.46) +
          Math.sin(i * 0.07 + 1.2) * (A * 0.28) +
          Math.sin(i * 0.42 + 0.5) * (A * 0.18) +
          Math.sin(i * 0.91 + 0.3) * (A * 0.08));
    points.push(`${i === 0 ? "M" : "L"} ${x.toFixed(2)} ${y.toFixed(2)}`);
  }
  return points.join(" ");
}

// ──────────────────────────────────────────────────────────────────────
// Emerging transcript — text reveals along the baseline

function EmergingTranscript({ active }: { active: boolean }) {
  // Use a left-to-right clip-path sweep to reveal the text, paired with
  // a baseline-rise opacity so each character feels like it's lifting
  // off the wave-baseline rather than appearing flat.
  return (
    <div
      className="font-display text-center"
      style={{
        color: TALKIE_INK,
        fontSize: 22,
        lineHeight: 1.45,
        letterSpacing: "-0.005em",
        maxWidth: 720,
        padding: "0 24px",
        opacity: active ? 1 : 0,
        transform: active ? "translateY(0)" : "translateY(6px)",
        clipPath: active
          ? "inset(0 0% 0 0)"
          : "inset(0 100% 0 0)",
        transition:
          "clip-path 1100ms cubic-bezier(0.22, 0.61, 0.36, 1), opacity 500ms ease-out 100ms, transform 800ms ease-out",
      }}
    >
      {SAMPLE_TRANSCRIPT}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Memo detail layout — the final landing state

function MemoDetailLayout() {
  return (
    <div
      className="flex flex-col items-stretch transition-opacity duration-500"
      style={{
        opacity: 1,
        padding: "40px 72px",
      }}
    >
      {/* Eyebrow */}
      <div
        className="flex items-center gap-3 font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
        style={{ color: TALKIE_INK_FAINT }}
      >
        <span>· MEMO · LIBRARY · SCOPE</span>
      </div>

      {/* Headline */}
      <h1
        className="m-0 mt-4 font-display"
        style={{
          color: TALKIE_INK,
          fontSize: 38,
          lineHeight: 1.15,
          letterSpacing: "-0.012em",
          fontWeight: 500,
          maxWidth: 640,
        }}
      >
        {SAMPLE_TITLE}
      </h1>

      <div
        className="mt-2 font-display italic"
        style={{
          color: TALKIE_INK_FAINT,
          fontSize: 14,
          letterSpacing: "0.005em",
        }}
      >
        recorded 3:42 PM · 19 May 2026 · 0:14
      </div>

      {/* Body grid: transcript + marginalia */}
      <div
        className="mt-7 grid"
        style={{
          gridTemplateColumns: "1fr 220px",
          columnGap: 40,
        }}
      >
        <p
          className="m-0 font-display"
          style={{
            color: TALKIE_INK,
            fontSize: 17,
            lineHeight: 1.65,
            letterSpacing: "-0.002em",
          }}
        >
          {SAMPLE_TRANSCRIPT}
        </p>

        <aside className="flex flex-col gap-5">
          <MetaGroup
            label="Filed"
            rows={[
              ["created", "3:42 PM"],
              ["modified", "just now"],
            ]}
          />
          <MetaGroup
            label="Runtime"
            rows={[
              ["duration", "0:14"],
              ["words", "32"],
            ]}
          />
          <MetaGroup
            label="Source"
            rows={[
              ["device", "MacBook Pro"],
              ["app", "iTerm2"],
            ]}
          />
        </aside>
      </div>

      {/* Player rail — pinned to bottom of the canvas (mt-auto) */}
      <div
        className="mt-auto flex items-center gap-4 border-t pt-4"
        style={{ borderColor: "rgba(42,38,32,0.10)" }}
      >
        <div
          className="font-mono text-[10px] uppercase tracking-[0.22em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          ▶ PLAY · 0:00 / 0:14
        </div>
        <div
          className="ml-auto font-mono text-[10px] uppercase tracking-[0.22em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          COPY · SHARE · EXPORT · ⋯
        </div>
      </div>
    </div>
  );
}

function MetaGroup({
  label,
  rows,
}: {
  label: string;
  rows: [string, string][];
}) {
  return (
    <div>
      <div
        className="mb-2 font-mono text-[9px] font-semibold uppercase tracking-[0.32em]"
        style={{ color: TALKIE_INK_FAINTER }}
      >
        {label}
      </div>
      <div className="flex flex-col gap-1">
        {rows.map(([k, v]) => (
          <div
            key={k}
            className="flex items-baseline justify-between font-mono text-[10px] uppercase tracking-[0.06em]"
          >
            <span style={{ color: TALKIE_INK_FAINT }}>{k}</span>
            <span
              style={{ color: TALKIE_INK }}
              className="tabular-nums"
            >
              {v}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Chrome bar mock — the constant across all phases

function ChromeBarMock({ phase }: { phase: Phase }) {
  const isRecording = phase === "recording";
  const isStopping = phase === "stopping";
  const elapsed = "0:14";
  return (
    <div
      className="flex items-center justify-center"
      style={{
        background: TALKIE_PAPER,
        borderBottom: "0.5px solid #E0DCD3",
        height: 58,
      }}
    >
      <div
        className="flex items-center gap-2 rounded-full px-3.5 py-1.5"
        style={{ background: TALKIE_INK }}
      >
        <span
          className="block h-2 w-2 rounded-full"
          style={{
            background: REC_RED,
            boxShadow:
              "0 0 0 2px rgba(192,58,42,0.25), 0 0 4px rgba(192,58,42,0.6)",
            opacity: isRecording || isStopping ? 1 : 0.4,
          }}
        />
        {(isRecording || isStopping) ? (
          <>
            <span
              className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em]"
              style={{ color: REC_RED, opacity: 0.92 }}
            >
              REC
            </span>
            <span
              className="font-mono text-[10px] font-medium tracking-[0.06em] tabular-nums"
              style={{ color: TALKIE_CREAM }}
            >
              {elapsed}
            </span>
          </>
        ) : (
          <>
            <span
              className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em]"
              style={{ color: TALKIE_CREAM }}
            >
              TALKIE
            </span>
            <span
              className="font-mono text-[9px] tracking-[0.06em]"
              style={{ color: TALKIE_CREAM, opacity: 0.5 }}
            >
              ⌘K
            </span>
          </>
        )}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Atomic decorations

function RecDot({ active }: { active: boolean }) {
  return (
    <span
      className="inline-block h-2 w-2 rounded-full"
      style={{
        background: REC_RED,
        boxShadow: active
          ? "0 0 0 2px rgba(192,58,42,0.25), 0 0 5px rgba(192,58,42,0.6)"
          : "none",
        opacity: active ? 1 : 0.55,
        transition: "opacity 400ms ease-out, box-shadow 400ms ease-out",
      }}
    />
  );
}

// ──────────────────────────────────────────────────────────────────────
// Spec notes — for the porter

function SpecNotes() {
  return (
    <div className="rounded-md border border-studio-edge p-5">
      <div className="mb-3 font-mono text-[9px] font-semibold uppercase tracking-[0.32em] text-studio-ink-faint">
        Port notes
      </div>
      <ul className="m-0 list-none space-y-2 p-0 text-[12.5px] leading-[1.65] text-studio-ink">
        <li>
          <strong>Wave decay:</strong> animate{" "}
          <code>InkFlourishShape.amplitude</code> from current value → 0
          over 400ms with <code>easeOut</code>. Phase continues advancing
          but at decelerating rate (or freeze and let amplitude do the
          settling work — simpler, indistinguishable visually).
        </li>
        <li>
          <strong>Baseline emergence:</strong> as amplitude crosses ~0.06,
          fade in a 1.2pt horizontal stroke at the midline. The wave
          collapsing INTO a line (rather than disappearing) is the
          load-bearing visual move.
        </li>
        <li>
          <strong>Text reveal:</strong> SwiftUI{" "}
          <code>.mask(Rectangle().offset(x:))</code> animated from{" "}
          <code>-width</code> → <code>0</code> over 1.1s with{" "}
          <code>cubic-bezier(0.22, 0.61, 0.36, 1)</code>; pair with a 6pt
          baseline rise on the text via{" "}
          <code>.offset(y:).animation()</code>.
        </li>
        <li>
          <strong>Reflow to memo:</strong> once the text is fully revealed,
          translate the eyebrow up, drop the headline in above, expand the
          marginalia from the right. Use SwiftUI{" "}
          <code>.matchedGeometryEffect</code> where possible so the
          emergent transcript paragraph keeps its position as the
          surrounding chrome settles around it.
        </li>
        <li>
          <strong>Chrome bar:</strong> pill swaps from REC state back to
          idle (TALKIE / ⌘K) as soon as we enter "settling." No animation
          on the pill swap — instant — so the chrome reads as "the
          recording is done; the canvas is finishing up."
        </li>
        <li>
          <strong>Title:</strong> derived after transcription (model
          generates ≤ 6-word title). Until ready, leave the headline slot
          empty and let it pop in once available.
        </li>
      </ul>
    </div>
  );
}
