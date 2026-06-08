"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

/**
 * TAPE TRANSPORT — Talkie's signature voice-waveform gesture.
 *
 * The magnetic-tape / analog-instrument expression of a memo's voice.
 * Replaces the unanchored particle cloud with a *transport*: a fine
 * amber Centerline running through the trace + an amber Tape-head
 * Needle that travels left→right as a persistent character across the
 * three phases of a memo's life.
 *
 * Two physically-true transport models, switched by phase:
 *   1. Recording    — FIXED HEAD · TAPE FLOWS. The Tape-head Needle is
 *                     bolted at a fixed Head position; the captured tape
 *                     scrolls right→left past it. The newest sample is
 *                     written AT the head; history flows away to the left
 *                     and off-screen. Tape to the right of the head is
 *                     unwritten. The needle does NOT travel.
 *   2. Transcribing — TRAVELLING HEAD · TAPE FIXED. The trace is static
 *                     and the head paces L→R re-reading the capture
 *                     (a single forward pace — the AI reading the voice).
 *   3. Playback     — TRAVELLING HEAD · TAPE FIXED. Trace static; the
 *                     head tracks currentTime / duration, scrubbable.
 *
 * Crossing tick: a soft Crossing Tick fires when needle + Peak meet —
 * in Playback/Transcribing the travelling needle passes a static Peak;
 * in Recording a flowing Peak passes under the fixed head. Either way:
 * a visual pulse on that bar + a marker on the Tick Rail (+ an optional
 * mute-able WebAudio click). On device this is the 40ms tape-tick +
 * haptic.
 *
 * Built to *tune the look/timing before Swift*, so every part is a
 * labelled control. Named parts are spelled out in <NamesMarginalia>
 * so studio / Swift / chat share one vocabulary.
 *
 * Amber-on-dark canon, AMBER scheme tokens inlined (this study reads
 * standalone — no <SchemeCard> upstream).
 */

// ─── AMBER scheme (inlined from lib/schemes.ts · "amber") ────────────
const A = {
  bg: "#14181A",
  panel: "#171C1E",
  stripTop: "linear-gradient(to bottom, #1F2426 0%, #1A1F22 35%, #0F1416 100%)",
  ink: "#E89A3C",
  inkFaint: "#7A8B85",
  inkSubtle: "#6B7A75",
  accent: "#E89A3C",
  accentDeep: "#C8801F",
  edge: "rgba(232, 154, 60, 0.10)",
  edgeStrong: "rgba(232, 154, 60, 0.28)",
  graticule: "rgba(232, 154, 60, 0.07)",
  rec: "#FF5A4A",
  recGlow: "rgba(255, 90, 74, 0.55)",
};

// Needle color presets — amber default, plus a couple of tuning options.
const NEEDLE_COLORS: { key: string; label: string; hex: string }[] = [
  { key: "amber", label: "Amber", hex: "#E89A3C" },
  { key: "brass", label: "Brass", hex: "#E5B040" },
  { key: "ember", label: "Ember", hex: "#FF7A3C" },
  { key: "bone", label: "Bone", hex: "#F0EDE6" },
];

type Phase = "recording" | "transcribing" | "playback";

const PHASES: { key: Phase; label: string; hint: string }[] = [
  { key: "recording", label: "Recording", hint: "fixed head · tape flows R→L into it" },
  { key: "transcribing", label: "Transcribing", hint: "head paces L→R · tape fixed" },
  { key: "playback", label: "Playback", hint: "head tracks currentTime · tape fixed" },
];

// Transport model — Recording is the one fixed-head/flowing-tape model;
// Transcribing + Playback share the travelling-head/fixed-tape model.
type TransportModel = "fixed-head" | "travelling-head";

function modelForPhase(phase: Phase): TransportModel {
  return phase === "recording" ? "fixed-head" : "travelling-head";
}

const MODEL_LABEL: Record<TransportModel, string> = {
  "fixed-head": "Fixed head · tape flows",
  "travelling-head": "Travelling head · tape fixed",
};

// Head position presets (used in fixed-head / Recording mode): where the
// bolted head sits across the bay. Default RIGHT — a "now" write point
// with recorded history flowing left into it.
type HeadPos = "left" | "center" | "right";

const HEAD_POSITIONS: { key: HeadPos; label: string; frac: number }[] = [
  { key: "left", label: "Left", frac: 0.18 },
  { key: "center", label: "Center", frac: 0.5 },
  { key: "right", label: "Right", frac: 0.82 },
];

function headFrac(pos: HeadPos): number {
  return HEAD_POSITIONS.find((h) => h.key === pos)?.frac ?? 0.82;
}

// ─── Captured trace — a deterministic ~120-bar utterance ─────────────
// Seeded (no Math.random) so SSR + client agree. An envelope of two
// bursts (a word + a trailing word) modulated by a few carriers — reads
// as a believable captured memo rather than noise.
const BAR_COUNT = 120;

const CAPTURED: number[] = (() => {
  const out: number[] = [];
  let s = 1337 * 9301 + 49297;
  const rnd = () => {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
  for (let i = 0; i < BAR_COUNT; i++) {
    const nx = i / (BAR_COUNT - 1);
    const burst = Math.exp(-Math.pow((nx - 0.28) * 3.4, 2)) * 0.95;
    const mid = Math.exp(-Math.pow((nx - 0.55) * 6.0, 2)) * 0.5;
    const tail = Math.exp(-Math.pow((nx - 0.78) * 4.6, 2)) * 0.62;
    const env = burst + mid + tail;
    const carrier =
      Math.abs(Math.sin(nx * 41 + 1.1)) * 0.55 +
      Math.abs(Math.sin(nx * 97 + 3.3)) * 0.3 +
      rnd() * 0.18;
    const v = Math.min(1, Math.max(0.05, carrier * env + 0.04));
    out.push(Number(v.toFixed(4)));
  }
  return out;
})();

// "Peaks" = local maxima the Needle ticks against on crossing. We mark
// bars that are a local max AND above a floor, so ticks land on the
// meaningful syllable peaks rather than every bar.
const PEAK_INDEXES: number[] = (() => {
  const peaks: number[] = [];
  for (let i = 1; i < BAR_COUNT - 1; i++) {
    if (
      CAPTURED[i] > 0.34 &&
      CAPTURED[i] >= CAPTURED[i - 1] &&
      CAPTURED[i] > CAPTURED[i + 1]
    ) {
      peaks.push(i);
    }
  }
  return peaks;
})();
const PEAK_SET = new Set(PEAK_INDEXES);

// ─── Tunable controls model ──────────────────────────────────────────
interface Tune {
  phase: Phase;
  needleColor: string; // hex
  needleWidth: number; // px
  glowRadius: number; // px
  centerWeight: number; // px
  centerOpacity: number; // 0..1
  speed: number; // sweep multiplier (recording / transcribing)
  position: number; // 0..1 scrubber (playback / paused)
  playing: boolean;
  tickCadence: number; // min ms between accepted ticks
  ticksMuted: boolean; // mute optional WebAudio click
  sprocketRail: boolean; // show the sprocket rail texture
  headPos: HeadPos; // fixed-head x position (Recording / fixed-head model)
}

const DEFAULTS: Tune = {
  phase: "recording",
  needleColor: "#E89A3C",
  needleWidth: 3,
  glowRadius: 9,
  centerWeight: 0.5,
  centerOpacity: 0.55,
  speed: 1,
  position: 0,
  playing: true,
  tickCadence: 90,
  ticksMuted: true,
  sprocketRail: true,
  // Head bolted at center: blank tape feeds from the right, gets written under
  // the head, written tape spools off left — the authentic tape path, and what
  // "waves flow through it" reads as. Toggle left/right live in the rack.
  headPos: "center",
};

const DECK_W = 720;
const DECK_H = 220;

export function TapeTransport() {
  const [t, setT] = useState<Tune>(DEFAULTS);
  // Needle head position, 0..1, owned by the rAF loop.
  const [head, setHead] = useState(0);
  // Bars currently flashing from a crossing tick: index → flash start ms.
  const [flashes, setFlashes] = useState<Record<number, number>>({});
  // Tick Rail event log (most recent crossings).
  const [tickLog, setTickLog] = useState<{ id: number; bar: number; at: number }[]>([]);

  // Mutable refs the rAF loop reads without re-subscribing.
  const tuneRef = useRef(t);
  tuneRef.current = t;
  const headRef = useRef(0);
  const lastTickRef = useRef(0);
  const lastCrossedRef = useRef(-1);
  const tickIdRef = useRef(0);
  const audioRef = useRef<AudioContext | null>(null);

  // WebAudio tape-tick — short filtered click. Lazily created on first
  // unmuted tick (must follow a user gesture; tuning controls suffice).
  const playTick = useCallback(() => {
    if (tuneRef.current.ticksMuted) return;
    if (typeof window === "undefined") return;
    try {
      if (!audioRef.current) {
        const Ctor =
          window.AudioContext ||
          (window as unknown as { webkitAudioContext?: typeof AudioContext })
            .webkitAudioContext;
        if (!Ctor) return;
        audioRef.current = new Ctor();
      }
      const ctx = audioRef.current;
      if (ctx.state === "suspended") void ctx.resume();
      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "triangle";
      osc.frequency.setValueAtTime(2100, now);
      osc.frequency.exponentialRampToValueAtTime(640, now + 0.03);
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.exponentialRampToValueAtTime(0.14, now + 0.004);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.04);
      osc.connect(gain).connect(ctx.destination);
      osc.start(now);
      osc.stop(now + 0.05);
    } catch {
      /* audio is best-effort */
    }
  }, []);

  // Register a crossing tick on `bar` — flash + rail marker + audio.
  const fireTick = useCallback(
    (bar: number, nowMs: number) => {
      const tn = tuneRef.current;
      if (nowMs - lastTickRef.current < tn.tickCadence) return;
      lastTickRef.current = nowMs;
      const id = ++tickIdRef.current;
      setFlashes((prev) => ({ ...prev, [bar]: nowMs }));
      setTickLog((prev) => [{ id, bar, at: nowMs }, ...prev].slice(0, 7));
      playTick();
    },
    [playTick]
  );

  // ── rAF transport loop ──────────────────────────────────────────────
  useEffect(() => {
    let raf = 0;
    let prev = performance.now();
    const tick = (nowMs: number) => {
      const dt = Math.min(64, nowMs - prev) / 1000; // clamp tab-switch jumps
      prev = nowMs;
      const tn = tuneRef.current;

      let h = headRef.current;
      if (tn.phase === "recording") {
        // FIXED HEAD · TAPE FLOWS. `h` is write-progress 0→1: how much
        // tape has flowed past the bolted head. The head stays put; the
        // trace scrolls R→L so the sample at `h` sits under the head.
        // Loops back to 0 to re-capture.
        if (tn.playing) {
          h += dt * 0.22 * tn.speed;
          if (h >= 1) h = 0;
        }
      } else if (tn.phase === "transcribing") {
        // TRAVELLING HEAD · TAPE FIXED. The head paces a single forward
        // L→R pass re-reading the static capture, then loops to re-read.
        if (tn.playing) {
          h += dt * 0.3 * tn.speed;
          if (h >= 1) h = 0;
        }
      } else {
        // Playback — driven by the scrubber unless playing.
        if (tn.playing) {
          h += dt * 0.16 * tn.speed;
          if (h >= 1) {
            h = 1;
          }
        } else {
          h = tn.position;
        }
      }

      // Detect a peak crossing between last frame's bar and this one.
      const barF = h * (BAR_COUNT - 1);
      const curBar = Math.round(barF);
      const lastBar = lastCrossedRef.current;
      if (curBar !== lastBar) {
        const lo = Math.min(lastBar, curBar);
        const hi = Math.max(lastBar, curBar);
        for (let b = lo; b <= hi; b++) {
          if (b >= 0 && PEAK_SET.has(b)) {
            fireTick(b, nowMs);
            break; // one tick per frame keeps cadence honest
          }
        }
        lastCrossedRef.current = curBar;
      }

      headRef.current = h;
      setHead(h);

      // In playback while playing, keep the scrubber synced so the UI
      // and the loop agree when the user pauses.
      if (tn.phase === "playback" && tn.playing && Math.abs(tn.position - h) > 0.001) {
        setT((p) => (p.phase === "playback" && p.playing ? { ...p, position: h } : p));
      }

      // Expire flashes older than 260ms.
      setFlashes((prev) => {
        let changed = false;
        const next: Record<number, number> = {};
        for (const k in prev) {
          if (nowMs - prev[k] < 260) next[k] = prev[k];
          else changed = true;
        }
        return changed ? next : prev;
      });

      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [fireTick]);

  // When the user scrubs in a paused playback, drive the head directly.
  const onScrub = (v: number) => {
    setT((p) => ({ ...p, position: v, playing: false, phase: "playback" }));
    headRef.current = v;
    lastCrossedRef.current = Math.round(v * (BAR_COUNT - 1));
    setHead(v);
  };

  const set = <K extends keyof Tune>(k: K, v: Tune[K]) =>
    setT((p) => ({ ...p, [k]: v }));

  const onPhase = (phase: Phase) => {
    headRef.current = 0;
    lastCrossedRef.current = -1;
    setHead(0);
    setFlashes({});
    setT((p) => ({ ...p, phase, position: 0, playing: true }));
  };

  return (
    <div className="flex flex-col gap-5">
      {/* Phase selector + transport row */}
      <PhaseBar tune={t} onPhase={onPhase} set={set} />

      <div className="flex flex-col gap-5 lg:flex-row">
        {/* The deck */}
        <div className="flex shrink-0 flex-col gap-2">
          <Deck tune={t} head={head} flashes={flashes} />
          <TransportReadout phase={t.phase} headPos={t.headPos} />
        </div>

        {/* Tuning rack */}
        <TuningRack tune={t} set={set} onScrub={onScrub} />
      </div>

      {/* Tick rail log + crossings */}
      <TickRail tickLog={tickLog} muted={t.ticksMuted} />

      {/* Named parts */}
      <NamesMarginalia />
    </div>
  );
}

// ─── Deck — the tape transport itself ────────────────────────────────
function Deck({
  tune,
  head,
  flashes,
}: {
  tune: Tune;
  head: number;
  flashes: Record<number, number>;
}) {
  const barW = DECK_W / BAR_COUNT;
  const cy = DECK_H / 2;
  const model = modelForPhase(tune.phase);
  const fixedHead = model === "fixed-head";

  // The bar currently aligned with the head (the "now" sample).
  const headBar = head * (BAR_COUNT - 1);

  // Needle x.
  //  · fixed-head (Recording): bolted at the tuned Head position.
  //  · travelling-head (Transcribe/Playback): tracks the head 0→1.
  const headX = fixedHead ? headFrac(tune.headPos) * DECK_W : head * DECK_W;

  // Tape flow offset (fixed-head only): translate the whole trace so the
  // bar at `headBar` lands under the bolted needle. Newest sample sits at
  // the head; recorded history flows left, unwritten tape sits right.
  const headCenterX = headBar * barW + barW / 2;
  const flowOffset = fixedHead ? headX - headCenterX : 0;

  return (
    <div
      className="relative shrink-0 overflow-hidden rounded-[14px] font-mono"
      style={{
        width: DECK_W,
        background: A.bg,
        border: `0.5px solid ${A.edgeStrong}`,
        boxShadow: "0 6px 22px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,0.04)",
      }}
    >
      {/* Top strip — channel + phase + REC */}
      <div
        className="flex items-center justify-between px-4 py-2.5 text-[8px] font-semibold uppercase tracking-[0.22em]"
        style={{ background: A.stripTop, color: A.inkFaint }}
      >
        <span>CH-01 · TAPE</span>
        <span style={{ color: A.accent }}>{tune.phase.toUpperCase()}</span>
        {tune.phase === "recording" ? (
          <span className="inline-flex items-center gap-1.5" style={{ color: A.rec }}>
            <span
              className="inline-block h-[5px] w-[5px] rounded-full"
              style={{ background: A.rec, boxShadow: `0 0 5px ${A.recGlow}` }}
            />
            REC
          </span>
        ) : (
          <span style={{ color: A.inkSubtle }}>
            {(head * 100).toFixed(0).padStart(2, "0")} %
          </span>
        )}
      </div>

      {/* Trace bay */}
      <div className="relative" style={{ height: DECK_H }}>
        {/* Sprocket rail — perforated edge texture top + bottom */}
        {tune.sprocketRail ? <SprocketRail /> : null}

        <svg
          className="absolute inset-0 h-full w-full"
          viewBox={`0 0 ${DECK_W} ${DECK_H}`}
          preserveAspectRatio="none"
        >
          {/* faint graticule verticals */}
          {[0.25, 0.5, 0.75].map((g) => (
            <line
              key={g}
              x1={g * DECK_W}
              y1={14}
              x2={g * DECK_W}
              y2={DECK_H - 14}
              stroke={A.graticule}
              strokeWidth={0.5}
            />
          ))}

          {/* VU bars — mirrored around the centerline. In fixed-head
              (Recording) the whole group is translated by `flowOffset`
              so the trace flows R→L past the bolted needle. */}
          <g transform={fixedHead ? `translate(${flowOffset} 0)` : undefined}>
            {CAPTURED.map((v, i) => {
              const x = i * barW + barW / 2;
              // Fixed-head: bars at/behind the head are written (history),
              // bars ahead are unwritten tape. Travelling-head: all written.
              const captured = !fixedHead || i <= headBar;
              const peak = PEAK_SET.has(i);
              const flashing = flashes[i] !== undefined;
              const h = v * (DECK_H * 0.42);
              const baseOpacity = captured ? (peak ? 0.95 : 0.62) : 0.14;
              return (
                <line
                  key={i}
                  x1={x}
                  y1={cy - h}
                  x2={x}
                  y2={cy + h}
                  stroke={flashing ? "#FFF1DC" : A.accent}
                  strokeWidth={Math.max(1, barW * 0.5)}
                  strokeOpacity={flashing ? 1 : baseOpacity}
                  strokeLinecap="round"
                  style={
                    flashing
                      ? { filter: `drop-shadow(0 0 6px ${tune.needleColor})` }
                      : undefined
                  }
                />
              );
            })}
          </g>

          {/* CENTERLINE — permanent fine amber line through the trace */}
          <line
            x1={0}
            y1={cy}
            x2={DECK_W}
            y2={cy}
            stroke={A.accent}
            strokeWidth={tune.centerWeight}
            strokeOpacity={tune.centerOpacity}
          />
        </svg>

        {/* TAPE-HEAD NEEDLE — travelling marker + glow */}
        <div
          className="pointer-events-none absolute top-0 bottom-0"
          style={{
            left: headX,
            width: tune.needleWidth,
            transform: "translateX(-50%)",
            background: tune.needleColor,
            boxShadow: `0 0 ${tune.glowRadius}px ${tune.glowRadius * 0.32}px ${hexA(
              tune.needleColor,
              0.55
            )}`,
            borderRadius: 2,
          }}
        >
          {/* Tape-head shoe — a small cap riding the centerline crossing */}
          <span
            className="absolute left-1/2 h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full"
            style={{
              top: "50%",
              background: tune.needleColor,
              boxShadow: `0 0 ${tune.glowRadius}px ${hexA(tune.needleColor, 0.7)}`,
            }}
          />
        </div>

        {/* Phase caption */}
        <span
          className="absolute left-3 top-2.5 text-[7px] font-semibold uppercase tracking-[0.22em]"
          style={{ color: A.inkFaint }}
        >
          {PHASES.find((p) => p.key === tune.phase)?.hint}
        </span>
      </div>

      {/* Meter foot */}
      <div
        className="grid grid-cols-[auto_1fr_auto] items-center gap-3 px-[18px] py-3"
        style={{ borderTop: `0.5px solid ${A.edge}` }}
      >
        <span
          className="text-[8px] font-semibold uppercase tracking-[0.22em]"
          style={{ color: A.inkFaint }}
        >
          L · -18 dB
        </span>
        <span
          className="text-center font-display text-[22px] font-medium leading-none tracking-tight tabular-nums"
          style={{ color: A.ink, textShadow: `0 0 6px ${hexA(A.accent, 0.4)}` }}
        >
          {fmtTime(head)}
        </span>
        <span
          className="text-right text-[8px] font-semibold uppercase tracking-[0.22em]"
          style={{ color: A.inkFaint }}
        >
          48 kHz
        </span>
      </div>
    </div>
  );
}

// Sprocket rail — perforated film edge top + bottom.
function SprocketRail() {
  const holes = Array.from({ length: 36 }, (_, i) => i);
  return (
    <>
      {(["top", "bottom"] as const).map((edge) => (
        <div
          key={edge}
          className="pointer-events-none absolute left-0 right-0 flex items-center justify-between px-[6px]"
          style={{
            [edge]: 0,
            height: 9,
          }}
        >
          {holes.map((i) => (
            <span
              key={i}
              className="block h-[3px] w-[3px] rounded-[1px]"
              style={{ background: A.graticule }}
            />
          ))}
        </div>
      ))}
    </>
  );
}

// ─── Transport-model readout — names the active physical model ───────
function TransportReadout({ phase, headPos }: { phase: Phase; headPos: HeadPos }) {
  const model = modelForPhase(phase);
  const fixedHead = model === "fixed-head";
  return (
    <div
      className="flex items-center gap-2.5 rounded-[8px] px-3 py-2 font-mono"
      style={{ background: A.panel, border: `0.5px solid ${A.edge}` }}
    >
      <span
        className="text-[8px] font-semibold uppercase tracking-[0.22em]"
        style={{ color: A.inkFaint }}
      >
        · Transport
      </span>
      <span
        className="inline-flex items-center gap-1.5 rounded-[3px] px-2 py-0.5 text-[9px] font-semibold uppercase tracking-[0.08em]"
        style={{
          background: hexA(A.accent, 0.14),
          border: `0.5px solid ${A.edgeStrong}`,
          color: A.accent,
        }}
      >
        <span
          className="block h-1.5 w-1.5 rounded-full"
          style={{ background: A.accent, boxShadow: `0 0 5px ${hexA(A.accent, 0.7)}` }}
        />
        {MODEL_LABEL[model]}
      </span>
      <span className="text-[9px]" style={{ color: A.inkSubtle }}>
        {fixedHead
          ? `head bolted ${headPos} · trace flows R→L past it · peaks tick under the head`
          : "trace bolted · head travels L→R · needle ticks passing peaks"}
      </span>
    </div>
  );
}

// ─── Phase bar ───────────────────────────────────────────────────────
function PhaseBar({
  tune,
  onPhase,
  set,
}: {
  tune: Tune;
  onPhase: (p: Phase) => void;
  set: <K extends keyof Tune>(k: K, v: Tune[K]) => void;
}) {
  return (
    <div
      className="flex flex-wrap items-center gap-1.5 rounded-[4px] px-3 py-2.5"
      style={{
        background: "#14181A",
        border: `1px solid ${A.edge}`,
        boxShadow: `inset 2px 0 0 ${hexA(A.accent, 0.6)}`,
      }}
    >
      <span
        className="mr-1 text-[9px] font-semibold uppercase tracking-[0.18em]"
        style={{ color: A.inkFaint }}
      >
        · Phase
      </span>
      {PHASES.map((p) => (
        <button
          key={p.key}
          onClick={() => onPhase(p.key)}
          className="rounded-[3px] border px-2.5 py-1 font-mono text-[9px] font-semibold uppercase tracking-[0.10em] transition-colors"
          style={
            tune.phase === p.key
              ? { borderColor: A.accent, background: A.accent, color: "#14181A" }
              : { borderColor: A.edge, background: "transparent", color: "#9AA8A4" }
          }
        >
          {p.label}
        </button>
      ))}

      <div className="mx-2 h-4 w-px" style={{ background: A.edge }} />

      <button
        onClick={() => set("playing", !tune.playing)}
        className="rounded-[3px] border px-2.5 py-1 font-mono text-[9px] font-semibold uppercase tracking-[0.10em] transition-colors"
        style={
          tune.playing
            ? { borderColor: A.accent, background: "transparent", color: A.accent }
            : { borderColor: A.edge, background: "transparent", color: "#9AA8A4" }
        }
      >
        {tune.playing ? "❚❚ Pause" : "▶ Run"}
      </button>

      <span
        className="ml-auto text-[9px] font-semibold uppercase tracking-[0.10em]"
        style={{ color: A.inkSubtle }}
      >
        {PHASES.find((p) => p.key === tune.phase)?.hint}
      </span>
    </div>
  );
}

// ─── Tuning rack — the labelled controls ─────────────────────────────
function TuningRack({
  tune,
  set,
  onScrub,
}: {
  tune: Tune;
  set: <K extends keyof Tune>(k: K, v: Tune[K]) => void;
  onScrub: (v: number) => void;
}) {
  return (
    <div
      className="flex flex-1 flex-col gap-3.5 rounded-[12px] px-4 py-4 font-mono"
      style={{
        background: A.panel,
        border: `0.5px solid ${A.edge}`,
        minWidth: 280,
      }}
    >
      <RackTitle>· Tuning rack</RackTitle>

      {/* Head position — where the bolted head sits in fixed-head /
          Recording mode. Dimmed in travelling-head phases. */}
      {(() => {
        const fixedHead = modelForPhase(tune.phase) === "fixed-head";
        return (
          <div className={cn("flex flex-col gap-1.5", !fixedHead && "opacity-40")}>
            <span className="flex items-baseline justify-between">
              <Label>Head position</Label>
              <span
                className="text-[8px] font-semibold uppercase tracking-[0.10em]"
                style={{ color: A.inkSubtle }}
              >
                {fixedHead ? "fixed-head" : "Recording only"}
              </span>
            </span>
            <div className="flex gap-1.5">
              {HEAD_POSITIONS.map((h) => (
                <button
                  key={h.key}
                  onClick={() => set("headPos", h.key)}
                  disabled={!fixedHead}
                  className="flex-1 rounded-[3px] border px-2 py-1 text-[9px] font-semibold uppercase tracking-[0.08em] transition-colors"
                  style={
                    tune.headPos === h.key
                      ? { borderColor: A.accent, background: A.accent, color: "#14181A" }
                      : { borderColor: A.edge, color: A.inkFaint, background: "transparent" }
                  }
                >
                  {h.label}
                </button>
              ))}
            </div>
          </div>
        );
      })()}

      {/* Needle color */}
      <div className="flex flex-col gap-1.5">
        <Label>Needle color</Label>
        <div className="flex flex-wrap gap-1.5">
          {NEEDLE_COLORS.map((c) => (
            <button
              key={c.key}
              onClick={() => set("needleColor", c.hex)}
              className="flex items-center gap-1.5 rounded-[3px] border px-2 py-1 text-[9px] font-semibold uppercase tracking-[0.08em] transition-colors"
              style={
                tune.needleColor === c.hex
                  ? { borderColor: c.hex, color: c.hex, background: hexA(c.hex, 0.1) }
                  : { borderColor: A.edge, color: A.inkFaint, background: "transparent" }
              }
            >
              <span
                className="block h-2.5 w-2.5 rounded-full"
                style={{ background: c.hex }}
              />
              {c.label}
            </button>
          ))}
        </div>
      </div>

      <Slider
        label="Needle width"
        value={tune.needleWidth}
        min={1}
        max={8}
        step={0.5}
        unit="pt"
        onChange={(v) => set("needleWidth", v)}
      />
      <Slider
        label="Glow radius"
        value={tune.glowRadius}
        min={0}
        max={24}
        step={1}
        unit="px"
        onChange={(v) => set("glowRadius", v)}
      />
      <Slider
        label="Centerline weight"
        value={tune.centerWeight}
        min={0}
        max={3}
        step={0.25}
        unit="pt"
        onChange={(v) => set("centerWeight", v)}
      />
      <Slider
        label="Centerline opacity"
        value={tune.centerOpacity}
        min={0}
        max={1}
        step={0.05}
        unit=""
        onChange={(v) => set("centerOpacity", v)}
      />
      <Slider
        label={
          modelForPhase(tune.phase) === "fixed-head"
            ? "Tape flow speed"
            : "Sweep speed"
        }
        value={tune.speed}
        min={0.25}
        max={3}
        step={0.25}
        unit="×"
        onChange={(v) => set("speed", v)}
      />
      <Slider
        label={tune.phase === "playback" ? "Position (scrub)" : "Position"}
        value={tune.phase === "playback" ? tune.position : 0}
        min={0}
        max={1}
        step={0.001}
        unit=""
        disabled={tune.phase !== "playback"}
        format={(v) => `${(v * 100).toFixed(0)}%`}
        onChange={onScrub}
      />
      <Slider
        label="Tick cadence (min gap)"
        value={tune.tickCadence}
        min={20}
        max={300}
        step={10}
        unit="ms"
        onChange={(v) => set("tickCadence", v)}
      />

      {/* Toggles */}
      <div className="mt-1 flex flex-wrap gap-1.5">
        <Toggle
          on={!tune.ticksMuted}
          label={tune.ticksMuted ? "Tick · muted" : "Tick · audible"}
          onClick={() => set("ticksMuted", !tune.ticksMuted)}
        />
        <Toggle
          on={tune.sprocketRail}
          label="Sprocket rail"
          onClick={() => set("sprocketRail", !tune.sprocketRail)}
        />
      </div>
    </div>
  );
}

// ─── Tick rail — the crossing log ────────────────────────────────────
function TickRail({
  tickLog,
  muted,
}: {
  tickLog: { id: number; bar: number; at: number }[];
  muted: boolean;
}) {
  return (
    <div
      className="flex items-center gap-3 rounded-[10px] px-4 py-3 font-mono"
      style={{ background: A.panel, border: `0.5px solid ${A.edge}` }}
    >
      <span
        className="text-[9px] font-semibold uppercase tracking-[0.22em]"
        style={{ color: A.accent }}
      >
        · Tick rail
      </span>
      <span
        className="text-[10px]"
        style={{ color: A.inkFaint }}
      >
        crossing ticks {muted ? "(visual only)" : "(audible + visual)"} — 40ms tape-tick + soft haptic on device
      </span>
      <div className="ml-auto flex items-center gap-1.5">
        {tickLog.length === 0 ? (
          <span className="text-[9px]" style={{ color: A.inkSubtle }}>
            waiting for a peak crossing…
          </span>
        ) : (
          tickLog.map((e, i) => (
            <span
              key={e.id}
              className="rounded-[3px] px-1.5 py-0.5 text-[9px] font-semibold tabular-nums"
              style={{
                background: i === 0 ? hexA(A.accent, 0.18) : "transparent",
                border: `0.5px solid ${A.edge}`,
                color: i === 0 ? A.accent : A.inkFaint,
              }}
            >
              bar {String(e.bar).padStart(3, "0")}
            </span>
          ))
        )}
      </div>
    </div>
  );
}

// ─── Names · marginalia ──────────────────────────────────────────────
function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Tape Transport", "the whole gesture — centerline + needle + crossing ticks across a memo's 3 phases"],
    ["Transport Model", "the physical model. Recording = Fixed head · tape flows · Transcribe/Playback = Travelling head · tape fixed"],
    ["Centerline", "permanent fine amber line (~0.5pt) through the trace — the tape's datum / zero axis"],
    ["VU Bars", "captured-level bars mirrored around the centerline; syllable Peaks read brighter"],
    ["Peak", "a local-maximum bar above the floor — where needle + tape meet, a Crossing Tick fires"],
    ["Tape-head Needle", "the amber marker (~3pt) for the head. FIXED in Recording (bolted); TRAVELS L→R in Transcribe/Playback"],
    ["Head position", "where the bolted needle sits in fixed-head Recording — left / center / right (default right: a 'now' point)"],
    ["Tape Flow", "the R→L scroll of captured tape PAST the fixed head in Recording — newest at the head, history flows off-left, unwritten tape to the right"],
    ["Needle Glow", "the soft amber bloom around the needle; tunable radius, reads as the head's heat"],
    ["Tape-head Shoe", "the small cap riding the needle/centerline intersection — the contact point under the head"],
    ["Crossing Tick", "needle + Peak meet → bar flash + rail marker + 40ms tick + haptic. Recording: peak flows under head · Playback: head passes peak"],
    ["Tick Rail", "the log strip below the deck — recent crossings, most-recent highlighted"],
    ["Sprocket Rail", "perforated film-edge texture top + bottom — frames the trace as physical tape"],
    ["Sweep", "the relative motion. Recording: the TAPE sweeps R→L past a fixed head · Transcribe/Playback: the NEEDLE sweeps L→R. Speed tunable"],
  ];
  return (
    <div>
      <div className="mb-3 flex items-baseline gap-3">
        <span
          className="font-mono text-[9px] font-semibold uppercase tracking-[0.30em]"
          style={{ color: A.accent }}
        >
          · names
        </span>
        <span
          className="font-display italic"
          style={{ color: "#76767A", fontSize: 12 }}
        >
          one vocabulary for studio · Swift · chat
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: "#DEDEDD" }} />
      </div>
      <div
        className="grid"
        style={{
          gridTemplateColumns: "168px 1fr",
          rowGap: 8,
          columnGap: 18,
          padding: "16px 20px",
          background: "#FFFFFF",
          border: "0.5px solid #DEDEDD",
          borderRadius: 8,
        }}
      >
        {rows.map(([name, def]) => (
          <div key={name} className="contents">
            <span
              className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em]"
              style={{ color: A.accentDeep }}
            >
              {name}
            </span>
            <span
              className="font-display italic"
              style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}
            >
              {def}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Small primitives ────────────────────────────────────────────────
function RackTitle({ children }: { children: React.ReactNode }) {
  return (
    <span
      className="text-[9px] font-semibold uppercase tracking-[0.22em]"
      style={{ color: A.accent }}
    >
      {children}
    </span>
  );
}

function Label({ children }: { children: React.ReactNode }) {
  return (
    <span
      className="text-[9px] font-semibold uppercase tracking-[0.12em]"
      style={{ color: A.inkFaint }}
    >
      {children}
    </span>
  );
}

function Slider({
  label,
  value,
  min,
  max,
  step,
  unit,
  disabled,
  format,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  unit: string;
  disabled?: boolean;
  format?: (v: number) => string;
  onChange: (v: number) => void;
}) {
  const display = format ? format(value) : `${round2(value)}${unit ? " " + unit : ""}`;
  return (
    <label className={cn("flex flex-col gap-1", disabled && "opacity-40")}>
      <span className="flex items-baseline justify-between">
        <Label>{label}</Label>
        <span
          className="text-[9px] font-semibold tabular-nums"
          style={{ color: A.accent }}
        >
          {display}
        </span>
      </span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        className="tape-range h-1 w-full appearance-none rounded-full"
        style={{
          background: `linear-gradient(to right, ${A.accent} 0%, ${A.accent} ${
            ((value - min) / (max - min)) * 100
          }%, ${hexA(A.accent, 0.14)} ${((value - min) / (max - min)) * 100}%, ${hexA(
            A.accent,
            0.14
          )} 100%)`,
          accentColor: A.accent,
        }}
      />
    </label>
  );
}

function Toggle({
  on,
  label,
  onClick,
}: {
  on: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="rounded-[3px] border px-2 py-1 text-[9px] font-semibold uppercase tracking-[0.08em] transition-colors"
      style={
        on
          ? { borderColor: A.accent, background: A.accent, color: "#14181A" }
          : { borderColor: A.edge, background: "transparent", color: A.inkFaint }
      }
    >
      {label}
    </button>
  );
}

// ─── helpers ─────────────────────────────────────────────────────────
function round2(v: number) {
  return Math.round(v * 100) / 100;
}

function fmtTime(frac: number) {
  // Treat the captured memo as a 18s clip for the readout.
  const total = 18;
  const s = Math.floor(frac * total);
  return `0:${String(s).padStart(2, "0")}`;
}

// hex (#RRGGBB) → rgba string at alpha a.
function hexA(hex: string, a: number) {
  const h = hex.replace("#", "");
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}
