"use client";

import { cn } from "@/lib/utils";

/**
 * iPhone recording-sheet artifact.
 *
 * Layout (top → bottom):
 *  1. Top strip — ESC · REC (pulsing red dot)
 *  2. Trace band — waveform under iteration (see WaveformMode)
 *  3. Meter row — level · timer · sample rate
 *  4. Foot — details hint + brass stop button
 *
 * The `· REC` particle is preserved exactly as-is per direction.
 * Reads scheme CSS vars from a parent `<SchemeCard>`.
 */

export type WaveformMode =
  | "sparkle"
  | "printout"
  | "brass"
  | "phosphor"
  | "hybrid";

export interface SheetTreatments {
  waveform: WaveformMode;
  graticule: boolean;
  brackets: boolean;
  bezel: boolean;
  compact: boolean;
}

const W = 280;
const H = 80;

// Deterministic "captured utterance" path — lifted from
// usetalkie.com/components/HeroWaveform.jsx.
function tracePath() {
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
    const y = H / 2 - carrier * env * (H * 0.4);
    pts.push((nx * W).toFixed(2) + "," + y.toFixed(2));
  }
  return pts.join(" ");
}

const PATH = tracePath();

// Sparkle dots are static & seeded (no Math.random) for stable
// SSR. 70 dots is enough to read as the shipping baseline.
const SPARKLE_DOTS: Array<{ left: string; top: string; opacity: number }> = (() => {
  const out: Array<{ left: string; top: string; opacity: number }> = [];
  let s = 7 * 9301 + 49297;
  const r = () => {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
  for (let i = 0; i < 70; i++) {
    out.push({
      left: `${(r() * 100).toFixed(2)}%`,
      top: `${(r() * 100).toFixed(2)}%`,
      opacity: Number((0.5 + r() * 0.5).toFixed(2)),
    });
  }
  return out;
})();

export function RecordingSheet({ treatments: t }: { treatments: SheetTreatments }) {
  return (
    <div
      className={cn(
        "relative flex flex-col overflow-hidden rounded-[14px] font-mono shadow-artifact",
        t.compact ? "h-[180px]" : "h-[240px]"
      )}
      style={{
        background: "var(--scheme-bg)",
        border: "0.5px solid var(--scheme-edge)",
      }}
    >
      {/* graticule */}
      {t.graticule ? (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 z-[1] opacity-45"
          style={{
            backgroundImage:
              "linear-gradient(to right, var(--scheme-graticule) 0.5px, transparent 0.5px), linear-gradient(to bottom, var(--scheme-graticule) 0.5px, transparent 0.5px)",
            backgroundSize: "24px 24px",
          }}
        />
      ) : null}

      {/* Top strip */}
      <div
        className="relative z-[2] flex items-center justify-between px-4 py-2.5 text-[8px] font-semibold uppercase tracking-eyebrow"
        style={{ background: "var(--scheme-strip-top)" }}
      >
        <span style={{ color: "var(--scheme-ink-faint)" }}>ESC</span>
        <span
          className="inline-flex items-center gap-1.5"
          style={{ color: "var(--scheme-rec)" }}
        >
          <span
            aria-hidden
            className="inline-block h-[5px] w-[5px] animate-[rec-pulse_1.4s_ease-in-out_infinite] rounded-full"
            style={{
              background: "var(--scheme-rec)",
              boxShadow: "0 0 4px var(--scheme-rec-glow)",
            }}
          />
          REC
        </span>
        <span
          className="absolute bottom-0 left-4 right-4 h-px"
          style={{ background: "var(--scheme-edge)" }}
        />
      </div>

      {/* Trace band */}
      <div
        className={cn(
          "relative z-[2] flex-1 overflow-hidden",
          t.compact ? "mx-4 my-1.5" : "mx-4 my-2"
        )}
      >
        {/* labels */}
        <span
          className="absolute left-1.5 top-1.5 z-[4] text-[7px] font-semibold uppercase tracking-eyebrow"
          style={{ color: "var(--scheme-ink-faint)" }}
        >
          CH-01 · IN
        </span>
        <span
          className="absolute right-1.5 top-1.5 z-[4] text-[7px] font-semibold uppercase tracking-eyebrow"
          style={{ color: "var(--scheme-ink-faint)" }}
        >
          48 kHz
        </span>

        {/* waveform variant */}
        {t.waveform === "sparkle" ? (
          <div className="absolute inset-0">
            {SPARKLE_DOTS.map((d, i) => (
              <span
                key={i}
                className="absolute h-[2.5px] w-[2.5px] rounded-full"
                style={{
                  background: "var(--scheme-sparkle)",
                  left: d.left,
                  top: d.top,
                  opacity: d.opacity,
                }}
              />
            ))}
          </div>
        ) : null}

        {t.waveform === "printout" ? (
          <svg
            className="absolute inset-0 h-full w-full"
            viewBox={`0 0 ${W} ${H}`}
            preserveAspectRatio="none"
          >
            <line
              x1={0}
              y1={H / 2}
              x2={W}
              y2={H / 2}
              stroke="var(--scheme-edge)"
              strokeWidth={0.5}
              strokeDasharray="2 3"
            />
            <polyline
              fill="none"
              stroke="var(--scheme-ink)"
              strokeWidth={1.2}
              strokeOpacity={0.85}
              strokeLinecap="round"
              strokeLinejoin="round"
              points={PATH}
            />
          </svg>
        ) : null}

        {t.waveform === "brass" ? (
          <svg
            className="absolute inset-0 h-full w-full"
            viewBox={`0 0 ${W} ${H}`}
            preserveAspectRatio="none"
          >
            <line
              x1={0}
              y1={H / 2}
              x2={W}
              y2={H / 2}
              stroke="var(--scheme-edge)"
              strokeWidth={0.5}
              strokeDasharray="2 3"
            />
            <polyline
              fill="none"
              stroke="var(--scheme-accent)"
              strokeWidth={1.3}
              strokeOpacity={0.95}
              strokeLinecap="round"
              strokeLinejoin="round"
              points={PATH}
            />
          </svg>
        ) : null}

        {t.waveform === "phosphor" ? (
          <svg
            className="absolute inset-0 h-full w-full"
            viewBox={`0 0 ${W} ${H}`}
            preserveAspectRatio="none"
          >
            <line
              x1={0}
              y1={H / 2}
              x2={W}
              y2={H / 2}
              stroke="var(--scheme-edge)"
              strokeWidth={0.5}
              strokeDasharray="2 3"
            />
            <polyline
              fill="none"
              stroke="var(--scheme-accent)"
              strokeWidth={3.5}
              strokeOpacity={0.30}
              strokeLinecap="round"
              strokeLinejoin="round"
              points={PATH}
              style={{
                filter: "drop-shadow(0 0 5px var(--scheme-accent-glow))",
              }}
            />
            <polyline
              fill="none"
              stroke="var(--scheme-accent)"
              strokeWidth={1.4}
              strokeOpacity={0.98}
              strokeLinecap="round"
              strokeLinejoin="round"
              points={PATH}
            />
          </svg>
        ) : null}

        {t.waveform === "hybrid" ? (
          <svg
            className="absolute inset-0 h-full w-full"
            viewBox={`0 0 ${W} ${H}`}
            preserveAspectRatio="none"
          >
            <g stroke="var(--scheme-graticule)" strokeWidth={0.3}>
              <line x1={0} y1={H * 0.25} x2={W} y2={H * 0.25} />
              <line
                x1={0}
                y1={H * 0.5}
                x2={W}
                y2={H * 0.5}
                strokeOpacity={0.6}
              />
              <line x1={0} y1={H * 0.75} x2={W} y2={H * 0.75} />
              <line x1={W * 0.25} y1={0} x2={W * 0.25} y2={H} />
              <line
                x1={W * 0.5}
                y1={0}
                x2={W * 0.5}
                y2={H}
                strokeOpacity={0.6}
              />
              <line x1={W * 0.75} y1={0} x2={W * 0.75} y2={H} />
            </g>
            <polyline
              fill="none"
              stroke="var(--scheme-accent)"
              strokeWidth={3}
              strokeOpacity={0.28}
              strokeLinecap="round"
              strokeLinejoin="round"
              points={PATH}
              style={{
                filter: "drop-shadow(0 0 4px var(--scheme-accent-glow))",
              }}
            />
            <polyline
              fill="none"
              stroke="var(--scheme-accent)"
              strokeWidth={1.3}
              strokeOpacity={0.96}
              strokeLinecap="round"
              strokeLinejoin="round"
              points={PATH}
            />
            <line
              x1={W * 0.55}
              y1={5}
              x2={W * 0.55}
              y2={H - 5}
              stroke="var(--scheme-ink)"
              strokeWidth={0.7}
              opacity={0.55}
            />
            <circle
              cx={W * 0.55}
              cy={H / 2}
              r={1.6}
              fill="var(--scheme-ink)"
              opacity={0.75}
            />
          </svg>
        ) : null}

        {/* brackets */}
        {t.brackets ? (
          <div className="pointer-events-none absolute inset-0 z-[3]">
            <svg
              viewBox="0 0 100 100"
              preserveAspectRatio="none"
              className="h-full w-full"
            >
              <g
                fill="none"
                stroke="var(--scheme-edge-strong)"
                strokeWidth={1}
              >
                <path d="M 2 12 L 2 2 L 12 2" />
                <path d="M 88 2 L 98 2 L 98 12" />
                <path d="M 2 88 L 2 98 L 12 98" />
                <path d="M 88 98 L 98 98 L 98 88" />
              </g>
            </svg>
          </div>
        ) : null}
      </div>

      {/* Meter row */}
      <div className="relative z-[2] grid grid-cols-[auto_1fr_auto] items-center gap-3 px-4.5 px-[18px]">
        <span
          className="text-[8px] font-semibold uppercase tracking-eyebrow"
          style={{ color: "var(--scheme-ink-faint)" }}
        >
          L · -18 dB
        </span>
        <span
          className={cn(
            "text-center font-display font-medium leading-none tracking-tight tabular-nums",
            t.compact ? "text-[20px]" : "text-[26px]"
          )}
          style={{
            color: "var(--scheme-ink)",
            textShadow: "0 0 6px var(--scheme-accent-glow)",
          }}
        >
          0:11
        </span>
        <span
          className="text-right text-[8px] font-semibold uppercase tracking-eyebrow"
          style={{ color: "var(--scheme-ink-faint)" }}
        >
          48 kHz
        </span>
      </div>

      {/* Foot */}
      <div
        className={cn(
          "relative z-[2] flex items-center justify-between px-[18px]",
          t.compact ? "py-2 pb-3" : "px-[18px] pb-3.5 pt-2.5"
        )}
      >
        <span
          className="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[8px] font-semibold uppercase tracking-eyebrow"
          style={{
            background: "var(--scheme-details-bg)",
            color: "var(--scheme-ink-faint)",
          }}
        >
          <span
            aria-hidden
            className="inline-block h-[3px] w-[3px] rounded-full"
            style={{
              background: "var(--scheme-accent)",
              boxShadow: "0 0 3px var(--scheme-accent-glow)",
            }}
          />
          Details
        </span>
        <button
          aria-label="Stop"
          className={cn(
            "relative flex items-center justify-center rounded-full",
            t.compact ? "h-[26px] w-[26px]" : "h-8 w-8"
          )}
          style={{
            background: "transparent",
            border: "1.5px solid var(--scheme-accent)",
            boxShadow:
              "0 0 0 3px var(--scheme-accent-ring), inset 0 1px 0 var(--scheme-bezel-highlight)",
          }}
        >
          <span
            aria-hidden
            className={cn(
              "block rounded-[2px]",
              t.compact ? "h-[7px] w-[7px]" : "h-[9px] w-[9px]"
            )}
            style={{ background: "var(--scheme-accent)" }}
          />
        </button>
      </div>

      {/* bezel */}
      {t.bezel ? (
        <div
          className="pointer-events-none absolute inset-[0.5px] z-[5] rounded-[13.5px] p-px"
          style={{
            background:
              "linear-gradient(to bottom, var(--scheme-bezel-highlight) 0%, transparent 35%, transparent 65%, var(--scheme-bezel-shadow) 100%)",
            WebkitMask:
              "linear-gradient(black 0 0) content-box, linear-gradient(black 0 0)",
            WebkitMaskComposite: "xor",
            maskComposite: "exclude",
          }}
        />
      ) : null}
    </div>
  );
}
