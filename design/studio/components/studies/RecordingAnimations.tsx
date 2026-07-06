"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { TapeTransportDeckEmbed } from "@/components/studies/TapeTransport";
import { cn } from "@/lib/utils";

/**
 * Cross-platform recording animation canon.
 *
 * Maps the four live states that matter during capture:
 *   iOS · recording     — TapeWaveformView or ParticlesWaveformView + live preview
 *   iOS · transcribing  — PulsingAccentDot + italic label (detail view)
 *   Mac · recording     — LiveWaveformBars (red) + monospaced timer
 *   Mac · transcribing  — TranscribingSweep + pipeline steps
 *
 * Swift port targets:
 *   apps/ios/Talkie iOS/Views/Next/RecordingSheetNext.swift
 *   apps/ios/Talkie iOS/Views/Next/VoiceMemoDetailNext.swift
 *   apps/macos/Talkie/Views/MacRecordingView.swift
 *   apps/macos/Talkie/Views/RecordingCompanionSurface.swift
 */

// ─── Tokens (aligned with mac-recording-state/shared + iOS scope) ───

export const RA = {
  ink: "#232423",
  inkFaint: "rgba(35,36,35,0.55)",
  inkFainter: "rgba(35,36,35,0.32)",
  cream: "#F8F8F7",
  paper: "#FCFBF8",
  amber: "#C47D1C",
  amberGlow: "#E89A3C",
  rec: "#FF3B30",
  recGlow: "rgba(255, 59, 48, 0.55)",
  iosCanvas: "#141416",
  iosInk: "#F2F0EB",
  iosInkFaint: "rgba(242,240,235,0.55)",
  iosAccent: "#C47D1C",
};

export type RecordingPhase = "recording" | "transcribing";
export type RecordingPlatform = "ios" | "mac";
export type IOSWaveformMode = "tape" | "particles";

export const IOS_WAVEFORM_MODES: {
  key: IOSWaveformMode;
  label: string;
  hint: string;
}[] = [
  {
    key: "tape",
    label: "Tape",
    hint: "TapeTransport · center head · tape flows R→L · crossing ticks",
  },
  {
    key: "particles",
    label: "Particles",
    hint: "RecordingView donor · flowing red cloud",
  },
];

export const PHASES: { key: RecordingPhase; label: string; hint: string }[] = [
  { key: "recording", label: "Recording", hint: "mic live · waveform reactive" },
  { key: "transcribing", label: "Transcribing", hint: "post-stop · read head / pulse" },
];

export const PLATFORMS: { key: RecordingPlatform; label: string }[] = [
  { key: "ios", label: "iPhone" },
  { key: "mac", label: "Mac" },
];

// Frozen idle snapshots — SSR + first client paint must match exactly.
// (Node vs browser Math.sin can differ past ~1e-14 without rounding.)
const IDLE_MAC_LEVELS = [
  0.6511, 0.5792, 0.4739, 0.3744, 0.5485, 0.6977, 0.8088, 0.8711, 0.8783, 0.8287,
  0.7254, 0.5759, 0.392, 0.1882, 0.2746, 0.3618, 0.5296, 0.6575, 0.7369, 0.7636,
  0.738, 0.6652, 0.5542, 0.4173, 0.5221, 0.663, 0.7689, 0.829, 0.8362, 0.7878,
  0.6861, 0.5379, 0.3542, 0.149, 0.2088, 0.4085, 0.5818, 0.7155, 0.8002, 0.8305,
  0.8059, 0.7307, 0.6133, 0.4658, 0.4735, 0.6052, 0.706, 0.7647,
] as const;

const PARTICLE_W = 320;
const PARTICLE_H = 56;

type ParticleDot = { cx: number; cy: number; r: number; o: number };

// Frozen t=0 / base-count snapshot for hydration-safe first paint.
const IDLE_PARTICLES: ParticleDot[] = [
  { cx: 0, cy: 28, r: 1.58, o: 0.553 },
  { cx: 197.77, cy: 25.28, r: 1.91, o: 0.501 },
  { cx: 75.54, cy: 32.84, r: 1.43, o: 0.538 },
  { cx: 273.31, cy: 22.1, r: 1.33, o: 0.602 },
  { cx: 151.08, cy: 33.67, r: 1.85, o: 0.582 },
  { cx: 28.85, cy: 23.8, r: 1.71, o: 0.513 },
  { cx: 226.63, cy: 29.81, r: 1.25, o: 0.513 },
  { cx: 104.4, cy: 28.98, r: 1.61, o: 0.582 },
  { cx: 302.17, cy: 24.45, r: 1.9, o: 0.602 },
  { cx: 179.94, cy: 33.35, r: 1.41, o: 0.538 },
  { cx: 57.71, cy: 22.03, r: 1.35, o: 0.501 },
  { cx: 255.48, cy: 33.28, r: 1.87, o: 0.554 },
  { cx: 133.25, cy: 24.56, r: 1.68, o: 0.606 },
  { cx: 11.02, cy: 28.85, r: 1.25, o: 0.568 },
  { cx: 208.79, cy: 29.93, r: 1.64, o: 0.504 },
  { cx: 86.56, cy: 23.71, r: 1.89, o: 0.525 },
  { cx: 284.33, cy: 33.71, r: 1.38, o: 0.594 },
  { cx: 162.1, cy: 22.12, r: 1.37, o: 0.593 },
  { cx: 39.88, cy: 32.76, r: 1.88, o: 0.524 },
  { cx: 237.65, cy: 25.41, r: 1.66, o: 0.505 },
  { cx: 115.42, cy: 27.86, r: 1.25, o: 0.569 },
  { cx: 313.19, cy: 30.84, r: 1.66, o: 0.606 },
  { cx: 190.96, cy: 23.08, r: 1.88, o: 0.552 },
  { cx: 68.73, cy: 33.92, r: 1.36, o: 0.5 },
  { cx: 266.5, cy: 22.38, r: 1.39, o: 0.54 },
  { cx: 144.27, cy: 32.1, r: 1.89, o: 0.602 },
  { cx: 22.04, cy: 26.32, r: 1.63, o: 0.581 },
  { cx: 219.81, cy: 26.89, r: 1.25, o: 0.512 },
  { cx: 97.58, cy: 31.66, r: 1.69, o: 0.514 },
  { cx: 295.36, cy: 22.59, r: 1.86, o: 0.584 },
  { cx: 173.13, cy: 33.97, r: 1.34, o: 0.601 },
  { cx: 50.9, cy: 22.78, r: 1.41, o: 0.537 },
  { cx: 248.67, cy: 31.33, r: 1.9, o: 0.501 },
  { cx: 126.44, cy: 27.29, r: 1.6, o: 0.555 },
  { cx: 4.21, cy: 25.94, r: 1.26, o: 0.606 },
  { cx: 201.98, cy: 32.39, r: 1.72, o: 0.566 },
  { cx: 79.75, cy: 22.25, r: 1.85, o: 0.504 },
  { cx: 277.52, cy: 33.85, r: 1.33, o: 0.526 },
  { cx: 155.29, cy: 23.33, r: 1.44, o: 0.595 },
  { cx: 33.06, cy: 30.47, r: 1.91, o: 0.592 },
];

// ─── Root study ─────────────────────────────────────────────────────

export function RecordingAnimations({
  focusPlatform,
  focusPhase,
}: {
  focusPlatform?: RecordingPlatform;
  focusPhase?: RecordingPhase;
}) {
  const [platform, setPlatform] = useState<RecordingPlatform>(
    focusPlatform ?? "ios"
  );
  const [phase, setPhase] = useState<RecordingPhase>(focusPhase ?? "recording");
  const [iosWaveform, setIosWaveform] = useState<IOSWaveformMode>("tape");
  const grid = focusPlatform === undefined && focusPhase === undefined;

  const iosRecordingCaption =
    iosWaveform === "tape"
      ? "TapeTransport · center head · sprocket rail"
      : "RecordingView · ParticlesWaveformView";

  return (
    <div className="flex flex-col gap-8">
      {grid ? (
        <div className="flex flex-wrap items-center gap-2">
          <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.18em] text-studio-ink-faint">
            iPhone waveform
          </span>
          {IOS_WAVEFORM_MODES.map((m) => (
            <Chip
              key={m.key}
              active={iosWaveform === m.key}
              onClick={() => setIosWaveform(m.key)}
            >
              {m.label}
            </Chip>
          ))}
          <span className="font-mono text-[9px] text-studio-ink-faint">
            {IOS_WAVEFORM_MODES.find((m) => m.key === iosWaveform)?.hint}
          </span>
        </div>
      ) : null}

      {grid ? (
        <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
          <AnimationCell
            platform="ios"
            phase="recording"
            caption={iosRecordingCaption}
            iosWaveform={iosWaveform}
          />
          <AnimationCell
            platform="ios"
            phase="transcribing"
            caption="VoiceMemoDetailNext · pulse while pass runs"
          />
          <AnimationCell
            platform="mac"
            phase="recording"
            caption="MacRecordingView · LiveWaveformBars"
          />
          <AnimationCell
            platform="mac"
            phase="transcribing"
            caption="MacRecordingView · sweep + pipeline"
          />
        </div>
      ) : (
        <AnimationCell
          platform={platform}
          phase={phase}
          large
          iosWaveform={iosWaveform}
          caption={
            platform === "ios" && phase === "recording"
              ? iosWaveform === "tape"
                ? "TapeTransport → RecordingSheetNext.swift"
                : "RecordingView.swift · ParticlesWaveformView"
              : platform === "ios" && phase === "transcribing"
                ? "VoiceMemoDetailNext.swift"
                : platform === "mac" && phase === "recording"
                  ? "MacRecordingView.swift · LiveWaveformBars"
                  : "MacRecordingView.swift · TranscribingSweep"
          }
        />
      )}

      {!grid ? (
        <div className="flex flex-wrap gap-2">
          {PLATFORMS.map((p) => (
            <Chip
              key={p.key}
              active={platform === p.key}
              onClick={() => setPlatform(p.key)}
            >
              {p.label}
            </Chip>
          ))}
          <span className="mx-1 self-center text-studio-ink-faint">·</span>
          {PHASES.map((p) => (
            <Chip
              key={p.key}
              active={phase === p.key}
              onClick={() => setPhase(p.key)}
            >
              {p.label}
            </Chip>
          ))}
          {platform === "ios" && phase === "recording" ? (
            <>
              <span className="mx-1 self-center text-studio-ink-faint">·</span>
              {IOS_WAVEFORM_MODES.map((m) => (
                <Chip
                  key={m.key}
                  active={iosWaveform === m.key}
                  onClick={() => setIosWaveform(m.key)}
                >
                  {m.label}
                </Chip>
              ))}
            </>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

// ─── Cell wrapper ───────────────────────────────────────────────────

function AnimationCell({
  platform,
  phase,
  caption,
  large,
  iosWaveform = "tape",
}: {
  platform: RecordingPlatform;
  phase: RecordingPhase;
  caption: string;
  large?: boolean;
  iosWaveform?: IOSWaveformMode;
}) {
  return (
    <div
      className={cn(
        "flex flex-col gap-3",
        large ? "max-w-[720px]" : undefined
      )}
    >
      <div className="flex items-baseline gap-2 pl-0.5">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.2em] text-studio-ink">
          {platform === "ios" ? "iPhone" : "Mac"} · {phase}
        </span>
        <span className="font-mono text-[9px] text-studio-ink-faint">
          {caption}
        </span>
      </div>
      <div
        className="overflow-hidden rounded-md"
        style={{
          border: "0.5px solid rgba(35,36,35,0.12)",
          background: platform === "ios" ? RA.iosCanvas : RA.cream,
          minHeight: large ? 280 : 220,
        }}
      >
        {platform === "ios" && phase === "recording" ? (
          <IOSRecordingPanel waveform={iosWaveform} />
        ) : null}
        {platform === "ios" && phase === "transcribing" ? (
          <IOSTranscribingPanel />
        ) : null}
        {platform === "mac" && phase === "recording" ? (
          <MacRecordingPanel />
        ) : null}
        {platform === "mac" && phase === "transcribing" ? (
          <MacTranscribingPanel />
        ) : null}
      </div>
    </div>
  );
}

function Chip({
  children,
  active,
  onClick,
}: {
  children: React.ReactNode;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "rounded-full px-3 py-1 font-mono text-[10px] font-semibold uppercase tracking-[0.14em] transition-colors",
        active
          ? "bg-studio-ink text-white"
          : "border border-studio-edge bg-white text-studio-ink-faint hover:text-studio-ink"
      )}
    >
      {children}
    </button>
  );
}

// ─── iOS · Recording ────────────────────────────────────────────────

function IOSRecordingPanel({ waveform }: { waveform: IOSWaveformMode }) {
  const mounted = useMounted();
  const t = useRafTime(mounted);
  const liveLevels = useSimulatedLevels(t, 0.55);
  const currentLevel = liveLevels[liveLevels.length - 1] ?? 0.12;
  const isParticles = waveform === "particles";
  const waveColor = isParticles ? RA.rec : RA.iosAccent;
  const transcript =
    "…plan recap with Sam agreed on the Tuesday ship date and follow-ups";

  return (
    <div className="flex h-full min-h-[220px] flex-col px-5 pb-5 pt-4">
      {/* drag handle */}
      <div className="mx-auto mb-3 h-1 w-9 rounded-full bg-white/20" />

      {/* waveform — TapeTransport embed or particles (donor RecordingView) */}
      <div
        className="relative -mx-5 overflow-hidden rounded-md"
        style={{
          background: isParticles ? "rgba(255,255,255,0.04)" : "#14181A",
        }}
      >
        {isParticles ? (
          <ParticlesWaveform
            t={t}
            level={currentLevel}
            color={waveColor}
            mounted={mounted}
          />
        ) : (
          <TapeTransportDeckEmbed traceHeight={112} />
        )}
      </div>

      {/* live transcript slot — reserved height */}
      <p
        className="mt-3 line-clamp-2 font-mono text-[11px] leading-[1.35]"
        style={{ color: RA.iosInkFaint, minHeight: 34 }}
      >
        {transcript}
      </p>

      {/* timer row */}
      <div className="mt-3 flex items-center justify-center gap-2">
        <RecordingPulseDot color={waveColor} />
        <span
          className="font-mono text-[22px] font-medium tabular-nums tracking-tight"
          style={{ color: RA.iosInk }}
        >
          {mounted ? formatElapsed(t, true) : "00:00.0"}
        </span>
      </div>

      <p
        className="mt-2 text-center font-mono text-[8px] font-semibold uppercase tracking-[0.22em]"
        style={{ color: "rgba(242,240,235,0.38)" }}
      >
        · REC · HQ · 44.1k · MEMO
      </p>

      {/* transport hint */}
      <div className="mt-auto flex justify-center gap-4 pt-4 opacity-40">
        <TransportGhost label="Cancel" />
        <TransportGhost label="Stop" primary />
        <TransportGhost label="Save" />
      </div>
    </div>
  );
}

/**
 * Donor ParticlesWaveformView — seeded dots drift on x, oscillate on y,
 * count + size swell with the current mic level. Recording red in the
 * legacy sheet; still the nicest "voice as weather" read.
 */
function ParticlesWaveform({
  t,
  level,
  color,
  mounted,
}: {
  t: number;
  level: number;
  color: string;
  mounted: boolean;
}) {
  const liveDots = useMemo(
    () => buildParticleDots(t, level, PARTICLE_W, PARTICLE_H),
    [Math.floor(t * 60), snap(level, 3)]
  );
  const dots = mounted ? liveDots : IDLE_PARTICLES;

  return (
    <svg
      width="100%"
      height={PARTICLE_H}
      viewBox={`0 0 ${PARTICLE_W} ${PARTICLE_H}`}
      preserveAspectRatio="none"
      aria-hidden
      className="block"
    >
      {dots.map((d, i) => (
        <circle
          key={i}
          cx={d.cx}
          cy={d.cy}
          r={d.r}
          fill={color}
          opacity={d.o}
        />
      ))}
    </svg>
  );
}

function buildParticleDots(
  t: number,
  level: number,
  width: number,
  height: number
): ParticleDot[] {
  const centerY = height / 2;
  const baseCount = 40;
  const bonusCount = Math.floor(level * 60);
  const particleCount = baseCount + bonusCount;
  const out: ParticleDot[] = [];

  for (let i = 0; i < particleCount; i++) {
    const seed = i * 1.618033988749;
    const speed = 0.2 + (seed % 1) * 0.6;
    const xProgress = (t * speed + seed) % 1;
    const x = xProgress * width;
    const baseY =
      Math.sin(t * 2 + seed * 10) * level * centerY * 0.8;
    const y = centerY + baseY;
    const baseSize = 2.5;
    const levelBonus = level * 5;
    const particleSize =
      baseSize + levelBonus * (0.5 + Math.sin(seed * 5) * 0.5);
    const opacity =
      0.5 + level * 0.4 * (0.5 + Math.sin(seed * 3) * 0.5);
    out.push({
      cx: snap(x),
      cy: snap(y),
      r: snap(particleSize / 2),
      o: snap(opacity, 3),
    });
  }

  return out;
}

function TransportGhost({
  label,
  primary,
}: {
  label: string;
  primary?: boolean;
}) {
  return (
    <div className="flex flex-col items-center gap-1">
      <div
        className="rounded-full"
        style={{
          width: primary ? 44 : 32,
          height: primary ? 44 : 32,
          background: primary ? RA.iosAccent : "rgba(255,255,255,0.08)",
          border: primary ? "none" : "0.5px solid rgba(255,255,255,0.12)",
        }}
      />
      <span
        className="font-mono text-[7px] uppercase tracking-[0.16em]"
        style={{ color: "rgba(242,240,235,0.35)" }}
      >
        {label}
      </span>
    </div>
  );
}

// ─── iOS · Transcribing ─────────────────────────────────────────────

function IOSTranscribingPanel() {
  return (
    <div className="flex min-h-[220px] flex-col px-5 py-6">
      <p
        className="font-mono text-[9px] font-semibold uppercase tracking-[0.2em]"
        style={{ color: RA.iosInkFaint }}
      >
        Memo detail · reading body
      </p>
      <div
        className="mt-4 rounded-lg px-4 py-3.5"
        style={{ background: "rgba(255,255,255,0.04)" }}
      >
        <div className="flex items-center gap-2">
          <AccentPulseDot color={RA.iosAccent} />
          <span
            className="font-mono text-[12px] italic"
            style={{ color: RA.iosInkFaint }}
          >
            Transcribing…
          </span>
        </div>
      </div>
      <p
        className="mt-6 max-w-[280px] font-mono text-[10px] leading-[1.6]"
        style={{ color: "rgba(242,240,235,0.28)" }}
      >
        No sweep, no pipeline — the pass runs off-screen after save. The detail
        view holds a reserved slot with a breathing accent dot until text lands.
      </p>
    </div>
  );
}

// ─── Mac · Recording ────────────────────────────────────────────────

function MacRecordingPanel() {
  const mounted = useMounted();
  const t = useRafTime(mounted);
  const barCount = 48;
  const liveLevels = useScrollingBars(t, barCount, 0.92);
  const levels = mounted ? liveLevels : IDLE_MAC_LEVELS;

  return (
    <div className="flex min-h-[220px] flex-col items-center px-8 py-8">
      {/* glass pane */}
      <div
        className="w-full max-w-[400px] rounded-xl px-6 py-5"
        style={{
          background: "rgba(255,255,255,0.55)",
          border: "0.5px solid rgba(35,36,35,0.10)",
          boxShadow: "inset 0 1px 0 rgba(255,255,255,0.65)",
        }}
      >
        <MacWaveformBars levels={levels} color={RA.rec} t={t} />
      </div>

      <span
        className="mt-5 font-mono text-[40px] font-extralight tabular-nums"
        style={{ color: RA.ink, letterSpacing: "-0.02em" }}
      >
        {mounted ? formatElapsed(t, true) : "00:00.0"}
      </span>

      <div className="mt-6 flex items-center gap-5">
        <MacCircleButton kind="cancel" />
        <MacStopButton />
        <div className="w-11" />
      </div>
    </div>
  );
}

function MacWaveformBars({
  levels,
  color,
  t,
}: {
  levels: readonly number[];
  color: string;
  t: number;
}) {
  const h = 80;
  const barW = 3;
  const gap = 4;

  return (
    <svg width="100%" height={h} viewBox={`0 0 340 ${h}`} aria-hidden>
      {levels.map((lv, i) => {
        const position = i / (levels.length - 1);
        const shape = 0.4 + 0.6 * Math.sin(position * Math.PI);
        const wave =
          Math.sin(t * 2.3 + i * 0.55) * 0.6 +
          Math.sin(t * 0.9 + i * 0.23) * 0.4;
        const ripple = wave * 0.5 + 0.5;
        const ambient = (0.045 + lv * 0.05) * ripple;
        const level = Math.max(lv, ambient) * shape;
        const barH = Math.max(3, level * h * 0.96);
        const x = 8 + i * (barW + gap);
        const opacity = 0.45 + Math.min(1, level) * 0.55;
        return (
          <rect
            key={i}
            x={snap(x)}
            y={snap(h / 2 - barH / 2)}
            width={barW}
            height={snap(barH)}
            rx={barW / 2}
            fill={color}
            opacity={snap(opacity, 3)}
          />
        );
      })}
    </svg>
  );
}

function MacStopButton() {
  return (
    <div className="relative flex h-[76px] w-[76px] items-center justify-center">
      <div
        className="absolute inset-0 rounded-full blur-[20px]"
        style={{ background: RA.rec, opacity: 0.5 }}
      />
      <div
        className="flex h-[70px] w-[70px] items-center justify-center rounded-full"
        style={{ border: `3px solid ${RA.rec}` }}
      >
        <div
          className="rounded-[4px]"
          style={{ width: 22, height: 22, background: RA.rec }}
        />
      </div>
    </div>
  );
}

function MacCircleButton({ kind }: { kind: "cancel" }) {
  return (
    <div
      className="flex h-11 w-11 items-center justify-center rounded-full text-[14px]"
      style={{
        background: "rgba(35,36,35,0.06)",
        color: RA.inkFaint,
      }}
    >
      ×
    </div>
  );
}

// ─── Mac · Transcribing ─────────────────────────────────────────────

const PIPELINE_STEPS = [
  { id: "recorded", title: "Recorded", subtitle: "0:14", status: "done" as const },
  { id: "saved", title: "File saved", subtitle: undefined, status: "done" as const },
  {
    id: "transcribing",
    title: "Transcribing",
    subtitle: "Using whisper-large",
    status: "active" as const,
  },
  { id: "complete", title: "Memo created", subtitle: undefined, status: "pending" as const },
];

function MacTranscribingPanel() {
  const mounted = useMounted();
  const t = useRafTime(mounted);
  const sweepPhase = mounted ? (t % 1.8) / 1.8 : 0;

  return (
    <div className="flex min-h-[220px] flex-col items-center px-8 py-6">
      <div
        className="relative w-full max-w-[440px] overflow-hidden rounded-xl px-5 py-4"
        style={{
          background: "rgba(255,255,255,0.55)",
          border: "0.5px solid rgba(35,36,35,0.10)",
          minHeight: 160,
        }}
      >
        {/* transcribing sweep */}
        <div
          className="pointer-events-none absolute inset-0"
          aria-hidden
        >
          <div
            className="absolute top-0 h-full w-[32%]"
            style={{
              left: `${-32 + sweepPhase * 132}%`,
              background: `linear-gradient(90deg, transparent, ${RA.amber}2E, transparent)`,
            }}
          />
        </div>

        {/* pipeline */}
        <div className="relative flex flex-col gap-2">
          {PIPELINE_STEPS.map((step) => (
            <div key={step.id} className="flex items-center gap-2">
              <StepIcon status={step.status} />
              <span
                className="font-mono text-[11px] font-medium"
                style={{
                  color:
                    step.status === "pending" ? RA.inkFainter : RA.ink,
                }}
              >
                {step.title}
              </span>
              {step.subtitle ? (
                <span
                  className="truncate font-mono text-[9px]"
                  style={{ color: RA.inkFaint }}
                >
                  {step.subtitle}
                </span>
              ) : null}
            </div>
          ))}
        </div>
      </div>

      <span
        className="mt-4 font-mono text-[12px]"
        style={{ color: RA.inkFaint }}
      >
        Transcribing…
      </span>

      <p
        className="mt-4 max-w-[400px] text-center font-mono text-[9px] leading-[1.55]"
        style={{ color: RA.inkFainter }}
      >
        Companion surface uses wave-settle → baseline reveal instead — see{" "}
        <code>/mac-record-to-memo</code>
      </p>
    </div>
  );
}

function StepIcon({
  status,
}: {
  status: "done" | "active" | "pending";
}) {
  if (status === "done") {
    return (
      <span
        className="flex h-4 w-4 items-center justify-center rounded-full text-[9px]"
        style={{ color: "#34C759" }}
      >
        ✓
      </span>
    );
  }
  if (status === "active") {
    return (
      <span
        className="inline-block h-3.5 w-3.5 animate-pulse rounded-full"
        style={{ background: "#FF9500" }}
      />
    );
  }
  return (
    <span
      className="inline-block h-3.5 w-3.5 rounded-full"
      style={{ border: `1.5px solid ${RA.inkFainter}` }}
    />
  );
}

// ─── Shared atoms ───────────────────────────────────────────────────

function RecordingPulseDot({ color }: { color: string }) {
  return (
    <span
      className="inline-block h-2 w-2 animate-[rec-pulse_1.4s_ease-in-out_infinite] rounded-full"
      style={{
        background: color,
        boxShadow: `0 0 6px ${color}88`,
      }}
    />
  );
}

function AccentPulseDot({ color }: { color: string }) {
  return (
    <span
      className="inline-block h-[7px] w-[7px] animate-[rec-pulse_1.8s_ease-in-out_infinite] rounded-full"
      style={{
        background: color,
        boxShadow: `0 0 5px ${color}66`,
      }}
    />
  );
}

// ─── Animation hooks ────────────────────────────────────────────────

/** True after hydration — rAF-driven SVG must not diverge on first paint. */
function useMounted() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
  }, []);
  return mounted;
}

function useRafTime(active: boolean) {
  const [t, setT] = useState(0);
  const start = useRef(0);

  useEffect(() => {
    if (!active) {
      start.current = 0;
      setT(0);
      return;
    }
    let raf = 0;
    const tick = (now: number) => {
      if (!start.current) start.current = now;
      setT((now - start.current) / 1000);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [active]);

  return t;
}

/** Round SVG attrs so Node SSR and browser agree on string form. */
function snap(n: number, places = 2) {
  const p = 10 ** places;
  return Math.round(n * p) / p;
}

/** Tape-style level buffer — newest sample at the end. */
function useSimulatedLevels(t: number, rate: number) {
  return useMemo(() => {
    const count = 28;
    const out: number[] = [];
    for (let i = 0; i < count; i++) {
      const age = (count - 1 - i) / count;
      const env =
        Math.exp(-Math.pow((age - 0.2) * 4, 2)) * 0.85 +
        Math.exp(-Math.pow((age - 0.65) * 5, 2)) * 0.45;
      const carrier =
        Math.abs(Math.sin(t * 3.2 + i * 0.4)) * 0.5 +
        Math.abs(Math.sin(t * 1.1 + i * 0.17)) * 0.35;
      out.push(
        snap(Math.min(1, Math.max(0.08, env * carrier * rate + 0.06)), 4)
      );
    }
    return out;
  }, [Math.floor(t * 24), rate]);
}

/** Scrolling bar history for Mac LiveWaveformBars. */
function useScrollingBars(t: number, count: number, sensitivity: number) {
  const idx = Math.floor(t * 30);
  return useMemo(() => {
    const out: number[] = [];
    for (let i = 0; i < count; i++) {
      const phase = idx - (count - 1 - i);
      const raw =
        Math.abs(Math.sin(phase * 0.31 + 1.1)) * 0.55 +
        Math.abs(Math.sin(phase * 0.17 + 2.3)) * 0.35 +
        0.08;
      out.push(snap(Math.min(1, raw * sensitivity), 4));
    }
    return out;
  }, [idx, count, sensitivity]);
}

function formatElapsed(t: number, tenths: boolean) {
  const total = Math.floor(t);
  const m = Math.floor(total / 60);
  const s = total % 60;
  if (!tenths) return `${m}:${String(s).padStart(2, "0")}`;
  const tenth = Math.floor((t - total) * 10);
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}.${tenth}`;
}