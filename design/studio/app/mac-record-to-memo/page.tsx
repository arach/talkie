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

const TALKIE_INK = "#232423";
const TALKIE_INK_FAINT = "rgba(35,36,35,0.55)";
const TALKIE_INK_FAINTER = "rgba(35,36,35,0.32)";
const TALKIE_CREAM = "#F8F8F7";
const TALKIE_PAPER = "#E7E7E6";
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
  const [forceHover, setForceHover] = useState(false);
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
    // Hold "recording" long enough to actually read the wave + cluster
    // hover-reveal; the previous timing blew past it in under 2s.
    schedule(3600, () => setPhase("stopping"));
    schedule(3600 + 800, () => setPhase("settling"));
    schedule(3600 + 800 + 700, () => setPhase("emerging"));
    schedule(3600 + 800 + 700 + 1800, () => setPhase("memo"));
  }

  function reset() {
    clearScheduled();
    setPhase("idle");
  }

  function jumpTo(target: Phase) {
    clearScheduled();
    setPhase(target);
  }

  useEffect(() => () => clearScheduled(), []);

  return (
    <StudioPage
      eyebrow="Recording → Memo · animated transition"
      title="Wave settles into the transcript"
      help="Press Play to watch the wave decelerate, flatten, and reveal text in place. Source of truth for the Swift port."
    >
      <div className="flex flex-col gap-7 py-4">
        <Controls
          phase={phase}
          onPlay={play}
          onReset={reset}
          forceHover={forceHover}
          onToggleForceHover={() => setForceHover((v) => !v)}
        />

        <Stage phase={phase} forceHover={forceHover} />

        <PhaseLegend phase={phase} onJump={jumpTo} />

        <PipIteration />


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
  forceHover,
  onToggleForceHover,
}: {
  phase: Phase;
  onPlay: () => void;
  onReset: () => void;
  forceHover: boolean;
  onToggleForceHover: () => void;
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
      <button
        type="button"
        onClick={onToggleForceHover}
        aria-pressed={forceHover}
        className="rounded-sm border px-3 py-1.5 font-mono text-[10px] font-semibold uppercase tracking-[0.22em] transition-colors"
        style={{
          borderColor: forceHover ? "#232423" : "rgba(35,36,35,0.16)",
          background: forceHover ? "#232423" : "transparent",
          color: forceHover ? "#F8F8F7" : "rgba(35,36,35,0.55)",
        }}
      >
        {forceHover ? "Hover · ON" : "Show hover"}
      </button>

      <div className="ml-auto flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
        <span>Phase</span>
        <span className="text-studio-ink">{phase}</span>
      </div>
    </div>
  );
}

function PhaseLegend({
  phase,
  onJump,
}: {
  phase: Phase;
  onJump: (p: Phase) => void;
}) {
  return (
    <div className="flex items-stretch gap-0 rounded-md border border-studio-edge font-mono text-[9px] font-semibold uppercase tracking-[0.22em]">
      {PHASE_ORDER.map((p, i) => {
        const active = p === phase;
        const reached =
          PHASE_ORDER.indexOf(phase) >= PHASE_ORDER.indexOf(p);
        return (
          <button
            key={p}
            type="button"
            onClick={() => onJump(p)}
            className="flex-1 cursor-pointer border-r border-studio-edge px-3 py-2.5 text-center transition-colors last:border-r-0 hover:bg-[rgba(35,36,35,0.06)]"
            style={{
              background: active
                ? "rgba(196,125,28,0.12)"
                : reached
                ? "rgba(35,36,35,0.04)"
                : "transparent",
              color: active
                ? SCOPE_AMBER
                : reached
                ? TALKIE_INK
                : TALKIE_INK_FAINTER,
            }}
          >
            {i}&nbsp;·&nbsp;{p}
          </button>
        );
      })}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Stage — the actual visual surface that morphs through phases

function Stage({
  phase,
  forceHover,
}: {
  phase: Phase;
  forceHover: boolean;
}) {
  return (
    <div
      className="relative overflow-hidden rounded-lg"
      style={{
        background: TALKIE_CREAM,
        border: `0.5px solid rgba(35,36,35,0.10)`,
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
          <RecordingCompanion phase={phase} forceHover={forceHover} />
        )}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Recording companion that decays through phases

function RecordingCompanion({
  phase,
  forceHover = false,
}: {
  phase: Phase;
  forceHover?: boolean;
}) {
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

  const visible = phase !== "idle";
  const recording = phase === "recording";

  // Corner cluster + STOP rest near-invisible; hover sharpens them
  // to full presence. The waveform owns the center — every glyph
  // that isn't the wave is barely felt until the cursor lands on it.
  const restOpacity = 0.06;

  return (
    <div
      className="group relative flex-1 transition-opacity duration-300"
      style={{
        opacity: visible ? 1 : 0,
        padding: "32px 80px",
      }}
    >
      {/* Top hairline */}
      <div style={{ height: 0.5, background: "rgba(35,36,35,0.16)" }} />

      {/* Center: waveform / baseline / emerging text — no surrounding
          chrome. Decorations live in the corners. */}
      <div className="flex flex-1 items-center justify-center py-9">
        <div className="relative" style={{ width: 880, height: 196 }}>
          <div className="absolute inset-0 flex items-center justify-center">
            <MorphingFlourish
              amplitude={amplitude}
              strokeWidth={strokeWidth}
              strokeColor={SCOPE_AMBER}
            />
          </div>
          <div className="absolute inset-0 flex items-center justify-center">
            <EmergingTranscript active={phase === "emerging"} />
          </div>
        </div>
      </div>

      {/* Bottom hairline */}
      <div style={{ height: 0.5, background: "rgba(35,36,35,0.16)" }} />

      {/* Top-right cluster: RECORDING dot + label · LIBRARY · SCOPE · timer · close.
          Hover-reveal — at rest this is a quiet stripe; under the cursor
          (or with forceHover on) it sharpens. */}
      <div
        className="absolute right-[88px] top-[58px] flex items-center gap-3 transition-opacity duration-200 group-hover:opacity-100"
        style={{ opacity: forceHover ? 1 : restOpacity }}
      >
        <DetailsCluster phase={phase} />
        <CloseButton />
      </div>

      {/* Bottom-right: STOP. Only present while recording; hover-reveal. */}
      <div
        className="absolute bottom-[58px] right-[88px] transition-opacity duration-200 group-hover:opacity-100"
        style={{
          opacity: recording ? (forceHover ? 1 : restOpacity) : 0,
        }}
      >
        <StopButton />
      </div>
    </div>
  );
}

/**
 * Top-right details — phase-aware label + channel chips + timer.
 * No more centered eyebrow / centered caption; the waveform owns the
 * center, the corner owns the metadata.
 */
function DetailsCluster({ phase }: { phase: Phase }) {
  const isRecording = phase === "recording";
  const label = isRecording
    ? "RECORDING"
    : phase === "stopping"
    ? "STOPPING"
    : phase === "settling" || phase === "emerging"
    ? "TRANSCRIBING"
    : "—";

  return (
    <div
      className="flex items-baseline gap-2.5 font-mono text-[10px] font-semibold uppercase tracking-[0.28em]"
      style={{ color: TALKIE_INK_FAINT }}
    >
      <span className="tabular-nums" style={{ color: TALKIE_INK }}>
        0:14
      </span>
      <Dot />
      <RecDot active={isRecording} />
      <span style={{ color: isRecording ? TALKIE_INK : TALKIE_INK_FAINT }}>
        {label}
      </span>
      <Dot />
      <span>LIBRARY</span>
      <Dot />
      <span>SCOPE</span>
    </div>
  );
}

function Dot() {
  return <span style={{ color: TALKIE_INK_FAINTER }}>·</span>;
}

function CloseButton() {
  return (
    <button
      type="button"
      aria-label="Close"
      className="flex h-6 w-6 items-center justify-center rounded-full border transition-colors"
      style={{
        borderColor: "rgba(35,36,35,0.20)",
        color: TALKIE_INK_FAINT,
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.borderColor = TALKIE_INK;
        e.currentTarget.style.color = TALKIE_INK;
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.borderColor = "rgba(35,36,35,0.20)";
        e.currentTarget.style.color = TALKIE_INK_FAINT;
      }}
    >
      <span aria-hidden className="text-[13px] leading-none">
        ×
      </span>
    </button>
  );
}

function StopButton() {
  return (
    <button
      type="button"
      aria-label="Stop recording"
      className="flex items-center gap-2 rounded-full px-3.5 py-1.5 font-mono text-[10px] font-semibold uppercase tracking-[0.22em] transition-colors"
      style={{
        background: REC_RED,
        color: "#FFF7F5",
        boxShadow: "0 1px 0 rgba(255,255,255,0.18) inset, 0 2px 6px rgba(192,58,42,0.25)",
      }}
    >
      <span
        aria-hidden
        className="inline-block h-2 w-2"
        style={{ background: "#FFF7F5" }}
      />
      <span>STOP</span>
      <span style={{ color: "rgba(255,247,245,0.65)" }}>⌘.</span>
    </button>
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
        style={{ borderColor: "rgba(35,36,35,0.10)" }}
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
        borderBottom: "0.5px solid #DEDEDD",
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
// PiP iteration — minimized recording state for moving around the app.
// Same data (REC dot, timer, mini wave, STOP) compressed into a floating
// capsule that anchors to a window corner while the rest of the app
// stays usable underneath. The expand glyph returns you to the full
// overlay; close ends the recording.

function PipIteration() {
  return (
    <div className="flex flex-col gap-3">
      <SubHeader
        eyebrow="· PiP · minimized while you keep working"
        title="Recording follows you around the app"
        hint="floating capsule · live wave · STOP + expand affordances · hover-reveal pattern"
      />
      <div
        className="relative overflow-hidden rounded-lg"
        style={{
          background: TALKIE_CREAM,
          border: `0.5px solid rgba(35,36,35,0.10)`,
          minHeight: 320,
        }}
      >
        {/* Background app surface — desaturated mock so the PiP capsule
            reads as foreground without us having to render a real app. */}
        <PipBackdrop />

        {/* The PiP capsule, anchored bottom-right of the fake window. */}
        <div className="absolute bottom-6 right-6">
          <PipCapsule />
        </div>
      </div>
    </div>
  );
}

function PipBackdrop() {
  return (
    <div className="absolute inset-0 flex flex-col" style={{ opacity: 0.55 }}>
      {/* Faux chrome */}
      <div
        className="flex items-center gap-2 border-b px-4 py-2.5"
        style={{ borderColor: "rgba(35,36,35,0.10)", background: TALKIE_PAPER }}
      >
        <div className="flex gap-1.5">
          <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
          <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
          <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
        </div>
        <div
          className="ml-auto font-mono text-[9px] uppercase tracking-[0.20em]"
          style={{ color: TALKIE_INK_FAINTER }}
        >
          Talkie · Memo · Chrome bar consolidation
        </div>
        <div className="ml-auto" />
      </div>
      {/* Body lines — suggest a memo detail being read while recording continues */}
      <div className="flex flex-col gap-2 px-8 pt-6">
        <div
          className="h-3 w-1/3 rounded-sm"
          style={{ background: "rgba(35,36,35,0.10)" }}
        />
        <div
          className="h-2 w-2/3 rounded-sm"
          style={{ background: "rgba(35,36,35,0.06)" }}
        />
        <div
          className="mt-3 h-2 w-11/12 rounded-sm"
          style={{ background: "rgba(35,36,35,0.06)" }}
        />
        <div
          className="h-2 w-10/12 rounded-sm"
          style={{ background: "rgba(35,36,35,0.06)" }}
        />
        <div
          className="h-2 w-9/12 rounded-sm"
          style={{ background: "rgba(35,36,35,0.06)" }}
        />
        <div
          className="mt-3 h-2 w-11/12 rounded-sm"
          style={{ background: "rgba(35,36,35,0.06)" }}
        />
        <div
          className="h-2 w-7/12 rounded-sm"
          style={{ background: "rgba(35,36,35,0.06)" }}
        />
      </div>
    </div>
  );
}

/**
 * Floating recording capsule. Always-visible (no hover-gate) since it's
 * the only persistent reminder that you're still recording while you
 * navigate elsewhere. Hover sharpens the affordances and exposes the
 * mini-waveform; rest state shows a slim REC dot · timer pair with the
 * STOP + expand glyphs ghosted to ~40%.
 */
function PipCapsule() {
  return (
    <div
      className="group flex items-center gap-3 rounded-full pl-3 pr-1 py-1.5 transition-shadow"
      style={{
        background: "rgba(255,255,255,0.92)",
        border: "0.5px solid rgba(35,36,35,0.16)",
        backdropFilter: "blur(18px) saturate(1.4)",
        WebkitBackdropFilter: "blur(18px) saturate(1.4)",
        boxShadow: "0 8px 24px rgba(0,0,0,0.10), 0 1px 0 rgba(255,255,255,0.6) inset",
      }}
    >
      {/* Always-visible: REC dot + timer. The minimum honest signal that
          a recording is still happening. */}
      <div className="flex items-center gap-1.5">
        <span
          className="block h-2 w-2 rounded-full"
          style={{ background: REC_RED, boxShadow: "0 0 6px rgba(192,58,42,0.45)" }}
        />
        <span
          className="font-mono text-[10px] font-semibold tabular-nums uppercase tracking-[0.16em]"
          style={{ color: TALKIE_INK }}
        >
          0:14
        </span>
      </div>

      {/* Mini waveform — sharpens on hover. */}
      <div
        className="transition-opacity duration-200"
        style={{ opacity: 0.55, width: 80, height: 16 }}
      >
        <PipMiniWave />
      </div>

      {/* Action cluster: expand + STOP. Ghosted at rest, full on hover. */}
      <div
        className="ml-1 flex items-center gap-1 transition-opacity duration-200 group-hover:opacity-100"
        style={{ opacity: 0.4 }}
      >
        <button
          type="button"
          aria-label="Expand recording overlay"
          className="flex h-7 w-7 items-center justify-center rounded-full transition-colors hover:bg-[rgba(35,36,35,0.06)]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          <span aria-hidden className="text-[11px] leading-none">
            ↗
          </span>
        </button>
        <button
          type="button"
          aria-label="Stop recording"
          className="flex h-7 items-center gap-1 rounded-full px-2.5 font-mono text-[9px] font-semibold uppercase tracking-[0.20em]"
          style={{
            background: REC_RED,
            color: "#FFF7F5",
            boxShadow: "0 1px 0 rgba(255,255,255,0.18) inset",
          }}
        >
          <span
            aria-hidden
            className="inline-block h-1.5 w-1.5"
            style={{ background: "#FFF7F5" }}
          />
          <span>STOP</span>
        </button>
      </div>
    </div>
  );
}

function PipMiniWave() {
  return (
    <svg width="80" height="16" viewBox="0 0 80 16" fill="none" aria-hidden>
      <path
        d="M0 8 Q 4 4, 8 8 T 16 8 T 24 6 T 32 8 T 40 9 T 48 5 T 56 8 T 64 7 T 72 8 T 80 8"
        stroke={SCOPE_AMBER}
        strokeWidth="1.5"
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  );
}

function SubHeader({
  eyebrow,
  title,
  hint,
}: {
  eyebrow: string;
  title: string;
  hint?: string;
}) {
  return (
    <div className="flex flex-col gap-1">
      <div
        className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]"
        style={{ color: TALKIE_INK_FAINTER }}
      >
        {eyebrow}
      </div>
      <div className="flex items-baseline justify-between gap-4">
        <h3
          className="m-0 font-display text-[18px] font-medium tracking-tight"
          style={{ color: TALKIE_INK }}
        >
          {title}
        </h3>
        {hint ? (
          <span
            className="font-mono text-[10px] tracking-[0.12em]"
            style={{ color: TALKIE_INK_FAINT }}
          >
            {hint}
          </span>
        ) : null}
      </div>
    </div>
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
