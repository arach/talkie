"use client";

import { useEffect, useRef, useState } from "react";
import { SCHEMES } from "@/lib/schemes";

/**
 * Mac Recording HUD — proximity-aware overlay.
 *
 * Anatomy (one rounded surface, no stacked strips):
 *
 *   ┌──────────────────────────────────────────────┐
 *   │   · REC   0:11           CH-01 · 48 kHz      │  ← hover labels (faint pill)
 *   │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~   [▢] │  ← wave body + stop inline
 *   │   L · -18 dB                                 │  ← hover meter (faint pill)
 *   └──────────────────────────────────────────────┘
 *
 * At rest the chrome (panel bg, border, bezel, labels) is nearly
 * invisible — just the wave and the brass stop button float on the
 * cream canvas. As cursor proximity climbs:
 *
 *   far    →  wave + stop (faint)
 *   med    →  panel bg + border fade in, REC + timer appear top-left
 *   near   →  channel/sample-rate label, level meter, bezel
 *   over   →  full vocabulary, stop button picks up an outer ring
 *
 * No internal strips that cut across the wave — labels float as their
 * own tiny pills so the wave never gets a horizontal veil drawn over
 * its head.
 *
 * Surface scheme defaults to FROST. PEARL is the canonical Modern
 * sibling and reads slightly louder.
 */

const PROXIMITY_MAX = 460;
const W = 760;
const H = 124;
const BUTTON_SIZE = 60;
const BUTTON_RIGHT_PAD = 14;
const WAVE_LEFT_PAD = 28;
const WAVE_RIGHT_RESERVE = BUTTON_SIZE + BUTTON_RIGHT_PAD + 18;

// Deterministic waveform path. Coordinate space matches the wave
// drawing area (the SVG viewBox), not the full HUD width — that way
// the trace fills its allotted region without squishing.
const WAVE_W = W - WAVE_LEFT_PAD - WAVE_RIGHT_RESERVE;
const WAVE_H = H - 32;
function buildPath() {
  const n = 220;
  const pts: string[] = [];
  for (let i = 0; i < n; i++) {
    const nx = i / (n - 1);
    const burst = Math.exp(-Math.pow((nx - 0.30) * 4.0, 2)) * 0.90;
    const tail = Math.exp(-Math.pow((nx - 0.72) * 5.0, 2)) * 0.55;
    const env = burst + tail;
    const carrier =
      Math.sin(nx * 38 + 1.1) * 0.5 +
      Math.sin(nx * 71 + 3.3) * 0.28 +
      Math.sin(nx * 137 + 7.1) * 0.14;
    const y = WAVE_H / 2 - carrier * env * (WAVE_H * 0.42);
    pts.push((nx * WAVE_W).toFixed(2) + "," + y.toFixed(2));
  }
  return pts.join(" ");
}
const PATH = buildPath();

function clamp(v: number, lo: number, hi: number) {
  return Math.max(lo, Math.min(hi, v));
}
function ramp(p: number, lo: number, hi: number) {
  return clamp((p - lo) / (hi - lo), 0, 1);
}

export function RecordingHUD({ schemeKey = "frost" }: { schemeKey?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [proximity, setProximity] = useState(0);
  const scheme = SCHEMES.find((s) => s.key === schemeKey) ?? SCHEMES[0];

  useEffect(() => {
    const handle = (e: MouseEvent) => {
      const rect = ref.current?.getBoundingClientRect();
      if (!rect) return;
      // Edge-distance: 0 inside the HUD, growing as cursor leaves.
      const dx = Math.max(rect.left - e.clientX, 0, e.clientX - rect.right);
      const dy = Math.max(rect.top - e.clientY, 0, e.clientY - rect.bottom);
      const dist = Math.hypot(dx, dy);
      setProximity(clamp(1 - dist / PROXIMITY_MAX, 0, 1));
    };
    window.addEventListener("mousemove", handle, { passive: true });
    return () => window.removeEventListener("mousemove", handle);
  }, []);

  // Layer ramps — staggered so the page doesn't punch in all at once.
  // At rest (proximity 0): wave on a frosted-glass surface, nothing else.
  // Stop, labels, bezel are all hover-revealed.
  const waveOpacity   = 0.55 + 0.45 * proximity;       // always partly visible
  const stopOpacity   = ramp(proximity, 0.20, 0.55);   // 0 at rest → full near
  const borderOp      = ramp(proximity, 0.15, 0.55);
  const shadowOp      = ramp(proximity, 0.30, 0.70);
  const recPillOp     = ramp(proximity, 0.20, 0.55);
  const channelPillOp = ramp(proximity, 0.35, 0.70);
  const levelPillOp   = ramp(proximity, 0.55, 0.85);
  const bezelOp       = ramp(proximity, 0.45, 0.85);

  return (
    <div
      ref={ref}
      style={{
        ...(scheme.vars as React.CSSProperties),
        position: "absolute",
        top: "32%",
        left: "50%",
        transform: "translate(-50%, -50%)",
        width: W,
        zIndex: 50,
        pointerEvents: "auto",
      }}
    >
      {/* Surface — frosted glass at rest. The backdrop-filter blur is
          always on, so whatever sits behind the HUD reads as soft tone
          rather than legible content. The bg is a constant low-alpha
          scheme tint; border + shadow ramp with proximity so the panel
          gains weight as you reach for it. */}
      <div
        className="relative font-mono"
        style={{
          height: H,
          borderRadius: 28,
          background: "color-mix(in srgb, var(--scheme-bg) 32%, transparent)",
          backdropFilter: "blur(22px) saturate(1.4)",
          WebkitBackdropFilter: "blur(22px) saturate(1.4)",
          border: `0.5px solid color-mix(in srgb, var(--scheme-edge-strong) ${(borderOp * 100).toFixed(0)}%, transparent)`,
          boxShadow: `0 18px 44px -14px rgba(20,24,28,${(0.22 * shadowOp).toFixed(3)})`,
          transition: "border-color 140ms ease-out, box-shadow 140ms ease-out",
        }}
      >
        {/* Wave — fills the body, left-aligned, leaves room for stop on right */}
        <svg
          className="absolute"
          style={{
            left: WAVE_LEFT_PAD,
            top: 16,
            width: WAVE_W,
            height: WAVE_H,
            zIndex: 2,
          }}
          viewBox={`0 0 ${WAVE_W} ${WAVE_H}`}
          preserveAspectRatio="none"
        >
          {/* phosphor halo */}
          <polyline
            fill="none"
            stroke="var(--scheme-accent)"
            strokeWidth={5}
            strokeOpacity={0.22 * waveOpacity}
            strokeLinecap="round"
            strokeLinejoin="round"
            points={PATH}
            style={{ filter: "drop-shadow(0 0 8px var(--scheme-accent-glow))" }}
          />
          {/* trace */}
          <polyline
            fill="none"
            stroke="var(--scheme-accent)"
            strokeWidth={1.8}
            strokeOpacity={waveOpacity}
            strokeLinecap="round"
            strokeLinejoin="round"
            points={PATH}
          />
        </svg>

        {/* REC pulse + timer — floating pill at top-left */}
        <FloatingPill
          style={{ left: WAVE_LEFT_PAD - 6, top: -14, opacity: recPillOp }}
        >
          <span
            aria-hidden
            className="inline-block h-[6px] w-[6px] animate-[rec-pulse_1.4s_ease-in-out_infinite] rounded-full"
            style={{
              background: "var(--scheme-rec)",
              boxShadow: "0 0 4px var(--scheme-rec-glow)",
            }}
          />
          <span style={{ color: "var(--scheme-rec)" }}>REC</span>
          <span className="mx-1.5" style={{ color: "var(--scheme-edge-strong)" }}>·</span>
          <span className="tabular-nums" style={{ color: "var(--scheme-ink)" }}>0:11</span>
        </FloatingPill>

        {/* Channel + sample rate — floating pill at top-right (mirror of REC pill) */}
        <FloatingPill
          style={{
            right: WAVE_RIGHT_RESERVE - 6,
            top: -14,
            opacity: channelPillOp,
          }}
        >
          <span style={{ color: "var(--scheme-ink-faint)" }}>CH-01</span>
          <span className="mx-1.5" style={{ color: "var(--scheme-edge-strong)" }}>·</span>
          <span style={{ color: "var(--scheme-ink-faint)" }}>48 kHz</span>
        </FloatingPill>

        {/* Level meter — floating pill at bottom-left */}
        <FloatingPill
          style={{
            left: WAVE_LEFT_PAD - 6,
            bottom: -14,
            opacity: levelPillOp,
          }}
        >
          <span style={{ color: "var(--scheme-ink-faint)" }}>L · −18 dB</span>
        </FloatingPill>

        {/* Stop button — hidden at rest, fades in with proximity.
            pointer-events disabled when nearly invisible so the button
            can't be clicked through the wave area while at rest. */}
        <button
          aria-label="Stop"
          className="absolute flex items-center justify-center rounded-full"
          style={{
            right: BUTTON_RIGHT_PAD,
            top: (H - BUTTON_SIZE) / 2,
            width: BUTTON_SIZE,
            height: BUTTON_SIZE,
            opacity: stopOpacity,
            pointerEvents: stopOpacity > 0.4 ? "auto" : "none",
            background: "transparent",
            border: "2px solid var(--scheme-accent)",
            boxShadow: `
              0 0 0 4px var(--scheme-accent-ring),
              inset 0 1.5px 0 var(--scheme-bezel-highlight)
            `,
            transition: "opacity 160ms ease-out",
            zIndex: 3,
          }}
        >
          <span
            aria-hidden
            className="block rounded-[3px]"
            style={{
              width: 18,
              height: 18,
              background: "var(--scheme-accent)",
            }}
          />
        </button>

        {/* Bezel — subtle inner highlight, fades in late */}
        <div
          className="pointer-events-none absolute inset-[0.5px] z-[4] rounded-[27.5px] p-px"
          style={{
            opacity: bezelOp,
            background:
              "linear-gradient(to bottom, var(--scheme-bezel-highlight) 0%, transparent 35%, transparent 65%, var(--scheme-bezel-shadow) 100%)",
            WebkitMask:
              "linear-gradient(black 0 0) content-box, linear-gradient(black 0 0)",
            WebkitMaskComposite: "xor",
            maskComposite: "exclude",
            transition: "opacity 160ms ease-out",
          }}
        />
      </div>

      {/* Proximity readout (small dev affordance) */}
      <div
        className="mt-2 text-center font-mono text-[8px] uppercase tracking-[0.22em] text-studio-ink-faint"
        style={{ opacity: 0.35 + 0.65 * proximity }}
      >
        prox · {(proximity * 100).toFixed(0)}%
      </div>
    </div>
  );
}

// Floating mini-pill — anchors over the HUD edge so labels read as
// detached chrome rather than as bars that veil the wave.
function FloatingPill({
  children,
  style,
}: {
  children: React.ReactNode;
  style: React.CSSProperties;
}) {
  return (
    <div
      className="absolute z-[5] flex items-center gap-1 rounded-full px-2.5 py-1 text-[9px] font-semibold uppercase tracking-eyebrow"
      style={{
        background: "var(--scheme-bg)",
        border: "0.5px solid var(--scheme-edge-strong)",
        boxShadow: "0 2px 6px rgba(20,24,28,0.06)",
        transition: "opacity 160ms ease-out",
        ...style,
      }}
    >
      {children}
    </div>
  );
}
