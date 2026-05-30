"use client";

/**
 * Shared substrate for the recording-state treatments.
 *
 * Every treatment in this directory renders on top of the same paper
 * homescreen mock + memo list so the comparisons are honest. The
 * substrate is fixed; the only thing that varies is what the recording
 * surface looks like.
 *
 * Exports
 * -------
 *   Tokens          INK / PAPER / CREAM / AMBER / BRASS / REC_RED …
 *   Studio chrome   TreatmentSection · Stage · Note
 *   Homescreen      Homescreen · MemoListMock · FakeChrome
 *   Top-bar atoms   PillInline · MiniWaveform · RecMark
 *   Math            useElapsed · useTimeline · smoothstep · lerp
 *   Birth styles    KeyframeStyles  (mounts once at the page root)
 */

import React from "react";

// ─── Tokens ──────────────────────────────────────────────────────────

export const INK         = "#232423";
export const INK_FAINT   = "rgba(35,36,35,0.55)";
export const INK_FAINTER = "rgba(35,36,35,0.32)";
export const INK_SUBTLE  = "rgba(35,36,35,0.18)";
export const CREAM       = "#F8F8F7";
export const PAPER       = "#E7E7E6";
export const AMBER       = "#C47D1C";
export const AMBER_GLOW  = "#E89A3C";
export const BRASS       = "#9A6A22";
export const REC_RED     = "#C03A2A";

// ─── Studio chrome ───────────────────────────────────────────────────

export function TreatmentSection({
  eyebrow,
  title,
  hint,
  children,
}: {
  eyebrow: string;
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section>
      <div className="mb-4 flex items-baseline gap-4 border-b border-studio-edge pb-3">
        <div>
          <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
            {eyebrow}
          </div>
          <h2 className="m-0 font-display text-[19px] font-medium leading-none tracking-tight text-studio-ink">
            {title}
          </h2>
        </div>
        {hint && (
          <div className="ml-auto font-mono text-[10px] uppercase tracking-[0.18em] text-studio-ink-faint">
            {hint}
          </div>
        )}
      </div>
      <div className="flex flex-col gap-3">{children}</div>
    </section>
  );
}

export function Note({ children }: { children: React.ReactNode }) {
  return (
    <p className="m-0 max-w-[820px] text-[12.5px] leading-[1.65] text-studio-ink">
      {children}
    </p>
  );
}

export function Stage({
  children,
  tall,
  flush,
}: {
  children: React.ReactNode;
  tall?: boolean;
  /** When true, removes inner padding — useful for treatments that
   *  want to render edge-to-edge into the stage. */
  flush?: boolean;
}) {
  return (
    <div
      className="flex items-center justify-center rounded-md"
      style={{
        background: CREAM,
        border: `0.5px dashed rgba(26,22,18,0.10)`,
        minHeight: tall ? 720 : 540,
        padding: flush ? 0 : 24,
      }}
    >
      {children}
    </div>
  );
}

// ─── Homescreen mock ─────────────────────────────────────────────────

/**
 * The paper homescreen every treatment lands on. Children render
 * inside a `position: relative` host so treatments can absolute-
 * position their overlay freely (top-center card, left gutter pen,
 * full-width strip, etc.). The treatment owns its own positioning.
 *
 * `highlightSlot` swaps the top memo row for a placeholder slot the
 * settle animation can fill. `memoOpacity` lets the treatment dim or
 * brighten the underlying list — defaults to the resting opacity used
 * in the current page (0.62).
 */
export function Homescreen({
  children,
  highlightSlot = false,
  memoOpacity = 0.62,
}: {
  children: React.ReactNode;
  highlightSlot?: boolean;
  memoOpacity?: number;
}) {
  return (
    <div
      className="relative w-full"
      style={{
        maxWidth: 960,
        background: PAPER,
        borderRadius: 14,
        padding: "12px 18px 20px",
        boxShadow: "0 1px 0 rgba(0,0,0,0.04), 0 14px 30px rgba(0,0,0,0.06)",
        border: "0.5px solid rgba(35,36,35,0.10)",
      }}
    >
      <FakeChrome />
      <div style={{ opacity: memoOpacity }}>
        <MemoListMock highlightTop={highlightSlot} />
      </div>
      {children}
    </div>
  );
}

export function FakeChrome() {
  return (
    <div className="flex items-center justify-between pb-3">
      <div className="flex items-center gap-1.5">
        <span className="block h-2.5 w-2.5 rounded-full bg-[#FF5F57]" />
        <span className="block h-2.5 w-2.5 rounded-full bg-[#FEBC2E]" />
        <span className="block h-2.5 w-2.5 rounded-full bg-[#28C840]" />
      </div>
      <PillInline />
      <span style={{ width: 36 }} />
    </div>
  );
}

export function MemoListMock({ highlightTop }: { highlightTop: boolean }) {
  const rows: {
    title: string;
    duration: string;
    time: string;
    placeholder?: boolean;
  }[] = [
    highlightTop
      ? { title: "—", duration: "0:14", time: "now", placeholder: true }
      : { title: "Q1 plan recap with Sam", duration: "0:14", time: "3:42 PM" },
    { title: "Notes on the onboarding cut", duration: "1:08", time: "11:20 AM" },
    { title: "Sketch ideas for the timer surface", duration: "0:42", time: "Yesterday" },
    { title: "Walking thoughts on pricing", duration: "2:17", time: "Mon" },
    { title: "Voice memo · 2 follow-ups for Lina", duration: "0:53", time: "Sun" },
    { title: "Reading on quiet UI vs. busy UI", duration: "1:42", time: "Sat" },
  ];
  return (
    <div className="flex flex-col" style={{ borderTop: `0.5px solid rgba(35,36,35,0.10)` }}>
      <div
        className="flex items-center justify-between py-2 font-mono text-[10px] uppercase tracking-[0.22em]"
        style={{ color: INK_FAINT }}
      >
        <span>Memos</span>
        <span style={{ color: INK_FAINTER }}>4 today</span>
      </div>
      {rows.map((r, i) => (
        <div
          key={i}
          className="flex items-center gap-3 py-2"
          style={{
            borderTop: `0.5px solid rgba(35,36,35,0.08)`,
            background: r.placeholder ? "rgba(196,125,28,0.06)" : "transparent",
            transition: "background 240ms ease-out",
          }}
        >
          <span
            className="block h-1.5 w-1.5 rounded-full"
            style={{ background: r.placeholder ? AMBER : INK_FAINTER }}
          />
          <span
            className="flex-1 truncate font-display text-[13px]"
            style={{
              color: r.placeholder ? INK_FAINTER : INK,
              fontStyle: r.placeholder ? "italic" : "normal",
            }}
          >
            {r.title}
          </span>
          <span
            className="font-mono text-[10px] tabular-nums"
            style={{ color: INK_FAINT }}
          >
            {r.duration}
          </span>
          <span
            className="font-mono text-[10px] uppercase tracking-[0.18em]"
            style={{ color: INK_FAINTER }}
          >
            {r.time}
          </span>
        </div>
      ))}
    </div>
  );
}

/** Vertical position of the homescreen "overlay slot" — top of the
 *  memo list area, below the chrome strip. Treatments that float a
 *  card top-center can use this number to align consistently. */
export const HOMESCREEN_OVERLAY_TOP = 88;

/** Layout constants for the first memo row, used by settle
 *  animations that need to fade content into the slot. */
export const HOMESCREEN_FIRST_ROW_TOP = 12 + 36 + 28; // top pad + chrome + memos header
export const HOMESCREEN_ROW_HEIGHT = 28;

// ─── Top-bar atoms ───────────────────────────────────────────────────

export function PillInline() {
  return (
    <div
      className="flex items-center gap-2 rounded-full px-3.5 py-1.5"
      style={{ background: INK }}
    >
      <RecMark active />
      <span
        className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em]"
        style={{ color: REC_RED, opacity: 0.92 }}
      >
        REC
      </span>
      <span
        className="font-mono text-[10px] font-medium tracking-[0.06em] tabular-nums"
        style={{ color: CREAM }}
      >
        0:14
      </span>
      <MiniWaveform />
    </div>
  );
}

export function RecMark({ active = true }: { active?: boolean }) {
  return (
    <span
      className="block h-2 w-2 rounded-full"
      style={{
        background: active ? REC_RED : INK_FAINTER,
        boxShadow: active
          ? "0 0 0 2px rgba(192,58,42,0.25), 0 0 4px rgba(192,58,42,0.6)"
          : "none",
      }}
    />
  );
}

export function MiniWaveform() {
  const bars = React.useMemo(
    () =>
      Array.from({ length: 14 }, (_, i) =>
        2 + Math.round(7 * Math.abs(Math.sin(i * 1.618)))
      ),
    []
  );
  return (
    <span className="flex items-center gap-[2px]" aria-hidden>
      {bars.map((h, i) => (
        <span
          key={i}
          className="block w-[2px] rounded-full"
          style={{
            height: `${h}px`,
            background: "rgba(251,251,250,0.55)",
          }}
        />
      ))}
    </span>
  );
}

// ─── Math + hooks ────────────────────────────────────────────────────

export function useElapsed(active: boolean, start: number) {
  const [t, setT] = React.useState(start);
  React.useEffect(() => {
    if (!active) return;
    const id = setInterval(() => {
      setT((x) => (x >= start + 60 ? start : x + 1));
    }, 1000);
    return () => clearInterval(id);
  }, [active, start]);
  return t;
}

export function useTimeline(durationMs: number) {
  const [progress, setProgress] = React.useState(0);
  React.useEffect(() => {
    let raf = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const t = ((now - start) % durationMs) / durationMs;
      setProgress(t);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [durationMs]);
  return progress;
}

export function smoothstep(x: number, a: number, b: number) {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}

export function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}

// ─── Wave primitives (treatments may import or roll their own) ───────

/**
 * Phosphor-amber waveform that breathes on a fake voice envelope.
 * Used by instrument treatments. Width/height in CSS pixels; the SVG
 * viewBox matches so strokes stay crisp at any size.
 */
export function LiveFlourish({
  width,
  height,
  strokeWidth = 2.4,
  ampBase = 0.5,
  ampVariance = 0.25,
  phaseSpeed = 4.5,
  color = AMBER,
  glow = AMBER_GLOW,
}: {
  width: number;
  height: number;
  strokeWidth?: number;
  ampBase?: number;
  ampVariance?: number;
  phaseSpeed?: number;
  color?: string;
  glow?: string;
}) {
  const ref = React.useRef<SVGPolylineElement | null>(null);

  React.useEffect(() => {
    let raf = 0;
    const start = performance.now();
    const N = 220;

    const tick = (now: number) => {
      const t = (now - start) / 1000;
      const breath =
        ampBase +
        ampVariance * 0.65 * Math.sin(t * 1.6) +
        ampVariance * 0.35 * Math.sin(t * 3.9 + 1.1);
      const amp = (height / 2) * Math.max(0.06, breath);
      const mid = height / 2;
      const phase = t * phaseSpeed;
      const pts: string[] = [];
      for (let i = 0; i <= N; i++) {
        const x = (i / N) * width;
        const u = i / N;
        const fade = Math.sin(Math.PI * u);
        const y =
          mid +
          fade *
            (Math.sin(i * 0.10 + phase) * (amp * 0.50) +
              Math.sin(i * 0.04 + 1.2 + phase * 0.55) * (amp * 0.30) +
              Math.sin(i * 0.24 + 0.5 + phase * 0.85) * (amp * 0.16) +
              Math.sin(i * 0.55 + 0.3 + phase * 1.3) * (amp * 0.06));
        pts.push(`${x.toFixed(2)},${y.toFixed(2)}`);
      }
      if (ref.current) ref.current.setAttribute("points", pts.join(" "));
      raf = requestAnimationFrame(tick);
    };

    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [width, height, ampBase, ampVariance, phaseSpeed]);

  const gradId = `live-flourish-${width}-${height}-${color.replace("#", "")}`;
  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      aria-hidden
      style={{ flexShrink: 0 }}
    >
      <defs>
        <linearGradient id={gradId} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor={color} stopOpacity="0" />
          <stop offset="6%" stopColor={color} stopOpacity="0.95" />
          <stop offset="94%" stopColor={color} stopOpacity="0.9" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polyline
        ref={ref}
        points=""
        fill="none"
        stroke={`url(#${gradId})`}
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        style={{ filter: `drop-shadow(0 0 2.5px ${glow}55)` }}
      />
    </svg>
  );
}

/** Static draw-in variant for birth animations. Hooks up to the
 *  `.cs-birth-wave` class in KeyframeStyles below for the stroke
 *  dash reveal. */
export function DrawInFlourish({
  width,
  height,
  color = AMBER,
  glow = AMBER_GLOW,
}: {
  width: number;
  height: number;
  color?: string;
  glow?: string;
}) {
  const pts = React.useMemo(() => {
    const out: string[] = [];
    const N = 220;
    const amp = (height / 2) * 0.5;
    const mid = height / 2;
    for (let i = 0; i <= N; i++) {
      const x = (i / N) * width;
      const u = i / N;
      const fade = Math.sin(Math.PI * u);
      const y =
        mid +
        fade *
          (Math.sin(i * 0.18) * (amp * 0.46) +
            Math.sin(i * 0.07 + 1.2) * (amp * 0.28) +
            Math.sin(i * 0.42 + 0.5) * (amp * 0.18));
      out.push(`${x.toFixed(2)},${y.toFixed(2)}`);
    }
    return out.join(" ");
  }, [width, height]);
  const gradId = `drawin-flourish-${width}-${height}-${color.replace("#", "")}`;
  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      aria-hidden
      style={{ flexShrink: 0 }}
    >
      <defs>
        <linearGradient id={gradId} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor={color} stopOpacity="0" />
          <stop offset="6%" stopColor={color} stopOpacity="0.95" />
          <stop offset="94%" stopColor={color} stopOpacity="0.9" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polyline
        className="cs-birth-wave"
        points={pts}
        fill="none"
        stroke={`url(#${gradId})`}
        strokeWidth={2.4}
        strokeLinecap="round"
        style={{ filter: `drop-shadow(0 0 2.5px ${glow}55)` }}
      />
    </svg>
  );
}

// ─── Birth keyframe styles ───────────────────────────────────────────

/**
 * Shared birth animation: the surface materializes from a blurred,
 * lifted, transparent state to its resting position. Each treatment
 * wraps its arming-state composition in `<div className="cs-birth">`
 * (optionally keyed for retrigger) and any internal SVG path that
 * should draw in gets `className="cs-birth-wave"`.
 *
 * Mount once at the page root.
 */
export function KeyframeStyles() {
  return (
    <style>{`
      .cs-birth {
        animation: cs-birth-surface 7s cubic-bezier(0.22, 1, 0.36, 1);
        transform-origin: center top;
      }
      @keyframes cs-birth-surface {
        0%   { opacity: 0; transform: translateY(14px) scale(0.93); filter: blur(22px); }
        12%  { opacity: 0.55; transform: translateY(6px) scale(0.97); filter: blur(12px); }
        28%  { opacity: 1; transform: translateY(0) scale(1); filter: blur(0); }
        100% { opacity: 1; transform: translateY(0) scale(1); filter: blur(0); }
      }
      .cs-birth-wave {
        stroke-dasharray: 1200;
        stroke-dashoffset: 1200;
        animation: cs-birth-draw 7s cubic-bezier(0.22, 1, 0.36, 1);
      }
      @keyframes cs-birth-draw {
        0%, 14% { stroke-dashoffset: 1200; }
        32%     { stroke-dashoffset: 0; }
        100%    { stroke-dashoffset: 0; }
      }
    `}</style>
  );
}

/** Birth re-triggers itself every 7s by keying its mount. Drop a
 *  treatment's arming composition inside this and it'll loop. */
export function BirthAnimator({ children }: { children: React.ReactNode }) {
  const [k, setK] = React.useState(0);
  React.useEffect(() => {
    const id = setInterval(() => setK((x) => x + 1), 7000);
    return () => clearInterval(id);
  }, []);
  return (
    <div key={k} className="cs-birth">
      {children}
    </div>
  );
}
