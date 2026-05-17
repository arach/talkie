"use client";

import { cn } from "@/lib/utils";

/**
 * Agent Bay artifact — dark "instrument bay" panel from macOS Home.
 *
 * Top control rail · 4 stat tiles · bottom rail · optional layers
 * (sparkline / heatmap / timeline / brackets / bezel / compact).
 *
 * All visual state controlled by props (treatments). Reads scheme
 * CSS vars from a parent `<SchemeCard>`.
 */

export interface BayTreatments {
  sparkline: boolean;
  compact: boolean;
  heatmap: boolean;
  timeline: boolean;
  brackets: boolean;
  bezel: boolean;
  graticule: boolean;
}

const STATS = [
  { value: "0", label: "Memos · Today", seed: 0 },
  { value: "2", label: "Dictations · Today", seed: 1 },
  { value: "0d", label: "Streak", seed: 2 },
  { value: "1.5k", label: "Total Words", seed: 3 },
];

function sparklineSamples(seed: number) {
  const out: number[] = [];
  for (let i = 0; i < 7; i++) {
    const phase = seed * 0.9;
    const sine = Math.sin(i * 0.85 + phase) * 0.3 + 0.55;
    const jitter = (((seed * 31 + i * 17) & 0xff) / 255) * 0.18;
    out.push(Math.min(0.95, Math.max(0.08, sine + jitter - 0.09)));
  }
  return out;
}

function sparklinePath(seed: number, w = 60, h = 12) {
  const samples = sparklineSamples(seed);
  const step = w / (samples.length - 1);
  return samples
    .map((v, i) => {
      const x = i * step;
      const y = h - v * h;
      return (i === 0 ? "M" : "L") + x.toFixed(1) + " " + y.toFixed(1);
    })
    .join(" ");
}

function heatmapIntensity(row: number, col: number) {
  const base = ((col * 23 + row * 41 + 7) & 0xff) / 255;
  const bias = (col / 7) * 0.4;
  const v = base * 0.7 + bias;
  return Math.min(1.0, Math.max(0.05, v));
}

function timelineIntensity(slot: number) {
  const hour = slot / 2;
  const morning = Math.exp(-Math.pow((hour - 10) / 3.0, 2)) * 0.75;
  const evening = Math.exp(-Math.pow((hour - 20) / 2.5, 2)) * 0.55;
  const jitter = (((slot * 53 + 11) & 0xff) / 255) * 0.15;
  return Math.min(1.0, Math.max(0.04, morning + evening + jitter * 0.4));
}

export function Bay({ treatments: t }: { treatments: BayTreatments }) {
  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-lg font-mono shadow-artifact",
        t.compact ? "h-[158px]" : "h-[220px]"
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
          className="pointer-events-none absolute inset-0 opacity-45"
          style={{
            backgroundImage:
              "linear-gradient(to right, var(--scheme-graticule) 0.5px, transparent 0.5px), linear-gradient(to bottom, var(--scheme-graticule) 0.5px, transparent 0.5px)",
            backgroundSize: "28px 28px",
          }}
        />
      ) : null}

      <div className="relative z-[2] flex h-full flex-col">
        {/* top strip */}
        <div
          className="relative flex items-center px-4 py-2.5 text-[8px] font-semibold uppercase tracking-eyebrow"
          style={{ background: "var(--scheme-strip-top)" }}
        >
          <span
            aria-hidden
            className="mr-2 h-1.5 w-1.5 rounded-full"
            style={{
              background: "var(--scheme-accent)",
              boxShadow: "0 0 4px var(--scheme-accent-glow)",
            }}
          />
          <span style={{ color: "var(--scheme-ink-faint)" }}>
            Running · AG-01 / TALKIE.AGENT
          </span>
          <span
            className="ml-auto"
            style={{ color: "var(--scheme-ink-subtle)" }}
          >
            Local only · No telemetry
          </span>
          <span
            className="absolute bottom-0 left-4 right-4 h-px"
            style={{ background: "var(--scheme-edge)" }}
          />
        </div>

        {/* body */}
        <div className="relative flex flex-1 flex-col">
          <div className="flex flex-1 items-center px-4">
            {STATS.map((s, i) => (
              <div
                key={s.label}
                className={cn(
                  "flex flex-1 flex-col justify-center gap-1 px-3.5",
                  t.compact ? "min-h-[52px]" : "min-h-[88px]",
                  i < STATS.length - 1 && "border-r"
                )}
                style={i < STATS.length - 1 ? { borderColor: "var(--scheme-edge)" } : undefined}
              >
                <div
                  className={cn(
                    "font-display leading-none tracking-tight",
                    t.compact ? "text-[26px]" : "text-[34px]"
                  )}
                  style={{
                    color: "var(--scheme-ink)",
                    textShadow: "0 0 4px var(--scheme-accent-glow)",
                  }}
                >
                  {s.value}
                </div>
                <div
                  className="text-[8px] font-semibold uppercase tracking-eyebrow"
                  style={{ color: "var(--scheme-ink-faint)" }}
                >
                  {s.label}
                </div>
                {t.sparkline ? (
                  <svg
                    className="mt-0.5 h-3 w-full"
                    viewBox="0 0 60 12"
                    preserveAspectRatio="none"
                  >
                    <path
                      d={sparklinePath(s.seed)}
                      fill="none"
                      stroke="var(--scheme-accent)"
                      strokeOpacity={0.7}
                      strokeWidth={1}
                    />
                  </svg>
                ) : null}
              </div>
            ))}
          </div>

          {t.timeline ? (
            <div className="flex flex-col gap-1 px-7 pb-1.5">
              <div
                className="flex justify-between text-[7px] font-semibold tracking-[0.10em]"
                style={{ color: "var(--scheme-ink-subtle)" }}
              >
                <span>00</span>
                <span>06</span>
                <span>12</span>
                <span>18</span>
                <span>24</span>
              </div>
              <div className="flex h-3.5 items-end gap-px">
                {Array.from({ length: 48 }).map((_, i) => {
                  const intensity = timelineIntensity(i);
                  return (
                    <div
                      key={i}
                      className="flex-1 rounded-[0.5px]"
                      style={{
                        background: "var(--scheme-accent)",
                        height: `${(intensity * 100).toFixed(0)}%`,
                        opacity: `${(0.18 + 0.55 * intensity).toFixed(2)}`,
                      }}
                    />
                  );
                })}
              </div>
            </div>
          ) : null}

          {/* bottom strip */}
          <div
            className="relative flex items-center px-4 py-2.5 text-[8px] font-semibold uppercase tracking-eyebrow"
            style={{ background: "var(--scheme-strip-bottom)" }}
          >
            <span style={{ color: "var(--scheme-ink-faint)" }}>
              · Trig · Live · Signal Path · Local
            </span>
            <span
              className="ml-auto"
              style={{ color: "var(--scheme-ink-subtle)" }}
            >
              10:10 AM
            </span>
            <span
              className="absolute left-4 right-4 top-0 h-px"
              style={{ background: "var(--scheme-edge)" }}
            />
          </div>
        </div>
      </div>

      {/* heatmap */}
      {t.heatmap ? (
        <div className="pointer-events-none absolute right-[18px] top-[40px] z-[3] flex flex-col gap-1">
          <div
            className="text-[8px] font-semibold uppercase tracking-[0.10em]"
            style={{ color: "var(--scheme-ink-faint)" }}
          >
            Last 7d
          </div>
          <div
            className="grid gap-[2px]"
            style={{
              gridTemplateColumns: "repeat(7, 8px)",
              gridTemplateRows: "repeat(5, 8px)",
            }}
          >
            {Array.from({ length: 35 }).map((_, idx) => {
              const r = Math.floor(idx / 7);
              const c = idx % 7;
              const intensity = heatmapIntensity(r, c);
              return (
                <div
                  key={idx}
                  className="h-2 w-2 rounded-[1.5px]"
                  style={{
                    background: `color-mix(in srgb, var(--scheme-accent) ${(10 + 60 * intensity).toFixed(0)}%, transparent)`,
                  }}
                />
              );
            })}
          </div>
        </div>
      ) : null}

      {/* brackets */}
      {t.brackets ? (
        <div className="pointer-events-none absolute inset-x-1 inset-y-8 z-[3]">
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

      {/* bezel */}
      {t.bezel ? (
        <div
          className="pointer-events-none absolute inset-[0.5px] z-[4] rounded-[7.5px] p-px"
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
