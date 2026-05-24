"use client";

/**
 * Mac Walkie — Scope.
 *
 * The walkie isn't a panel in the app; it's an instrument that
 * blooms in the center of the screen when Hyper+T is pressed. The
 * oscilloscope IS the surface. Single floating device, four
 * sequential moments of one transmission:
 *
 *   ready          modal just appeared, scope at rest, channel armed.
 *   transmitting   you're holding the key, voice-shape trace is hot.
 *   over           key released, trace sweeps to rest, "OVER" landing.
 *   receiving      agent speaks back; trace shows TTS waveform, short
 *                  answer caption sits beneath in display serif.
 *
 * Palette is the AMBER scheme from lib/schemes.ts — inlined here so
 * this study reads standalone. The whole device is one material; no
 * bays on substrate, no chrome around the instrument. The instrument
 * IS the chrome.
 */

export type ScopePhase = "ready" | "transmitting" | "over" | "receiving";

export const SCOPE_PHASES: { key: ScopePhase; label: string }[] = [
  { key: "ready", label: "Ready" },
  { key: "transmitting", label: "Transmitting" },
  { key: "over", label: "Over" },
  { key: "receiving", label: "Receiving" },
];

// AMBER scheme tokens (lib/schemes.ts → schemes[0]).
const AMBER = {
  body: "#14181A",
  display: "#08090A",
  trace: "#FFA940",
  traceDim: "#E89A3C",
  ink: "#C9A56B",
  inkDim: "#8A7A5A",
  inkSubtle: "#5A4D38",
  grid: "rgba(232, 154, 60, 0.07)",
  edge: "rgba(255, 169, 64, 0.18)",
  edgeFaint: "rgba(255, 169, 64, 0.08)",
  bezelTop: "rgba(255, 255, 255, 0.05)",
  bezelBottom: "rgba(0, 0, 0, 0.55)",
};

export function MacWalkieScope({ phase }: { phase: ScopePhase }) {
  return (
    <div
      className="flex h-full items-center justify-center"
      style={{
        background:
          "radial-gradient(ellipse at center, rgba(255,255,255,0.04) 0%, transparent 60%), linear-gradient(180deg, #E8E8E5 0%, #D4D4D0 100%)",
        backgroundBlendMode: "normal",
      }}
    >
      <BackdropTexture />
      <FloatingInstrument phase={phase} />
    </div>
  );
}

// ── Backdrop ──────────────────────────────────────────────────────

/** Hint that the modal floats over the user's actual screen. Not a
 *  pixel-accurate Mac desktop — just enough texture so the instrument
 *  reads as elevated, not embedded. */
function BackdropTexture() {
  return (
    <>
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          backgroundImage:
            "repeating-linear-gradient(45deg, rgba(0,0,0,0.015) 0px, rgba(0,0,0,0.015) 1px, transparent 1px, transparent 6px)",
        }}
      />
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse at center, transparent 30%, rgba(0,0,0,0.18) 100%)",
        }}
      />
    </>
  );
}

// ── The Instrument ────────────────────────────────────────────────

function FloatingInstrument({ phase }: { phase: ScopePhase }) {
  return (
    <div
      className="relative z-10 flex flex-col overflow-hidden"
      style={{
        width: 640,
        background: AMBER.body,
        borderRadius: 14,
        border: `1px solid ${AMBER.edge}`,
        boxShadow: [
          "0 24px 60px rgba(0,0,0,0.55)",
          "0 6px 18px rgba(0,0,0,0.35)",
          "0 0 0 1px rgba(0,0,0,0.4)",
          `inset 0 1px 0 ${AMBER.bezelTop}`,
          `inset 0 -1px 0 ${AMBER.bezelBottom}`,
        ].join(", "),
      }}
    >
      <StatusStrip phase={phase} />
      <Display phase={phase} />
      {phase === "receiving" && <Caption />}
      <Footer phase={phase} />
    </div>
  );
}

// ── Status strip ──────────────────────────────────────────────────

function StatusStrip({ phase }: { phase: ScopePhase }) {
  return (
    <div
      className="flex items-center justify-between px-5 py-2.5"
      style={{
        background:
          "linear-gradient(180deg, rgba(255,255,255,0.04) 0%, transparent 100%)",
        borderBottom: `0.5px solid ${AMBER.edgeFaint}`,
      }}
    >
      <div className="flex items-center gap-3">
        <ChannelPill code="CH-01" label="NIGHTOPS" phase={phase} />
        <span
          className="text-[9px] uppercase"
          style={{
            color: AMBER.inkSubtle,
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.22em",
          }}
        >
          T01
        </span>
      </div>

      <PhaseBadge phase={phase} />

      <div className="flex items-center gap-3">
        <span
          className="text-[9px] uppercase tabular-nums"
          style={{
            color: AMBER.inkSubtle,
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.14em",
          }}
        >
          {timecode(phase)}
        </span>
        <SignalDot phase={phase} />
      </div>
    </div>
  );
}

function ChannelPill({
  code,
  label,
  phase,
}: {
  code: string;
  label: string;
  phase: ScopePhase;
}) {
  const live = phase === "transmitting" || phase === "receiving";
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded px-1.5 py-[2px] text-[9px]"
      style={{
        color: AMBER.ink,
        border: `0.5px solid ${AMBER.edgeFaint}`,
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.10em",
      }}
    >
      <span
        className="relative inline-block h-1.5 w-1.5 rounded-full"
        style={{
          background: live ? AMBER.trace : AMBER.inkSubtle,
          boxShadow: live ? `0 0 6px ${AMBER.trace}` : "none",
        }}
      >
        {live && (
          <span
            className="absolute inset-0 animate-ping rounded-full"
            style={{ background: AMBER.trace, opacity: 0.6 }}
          />
        )}
      </span>
      {code} · {label}
    </span>
  );
}

function PhaseBadge({ phase }: { phase: ScopePhase }) {
  const label =
    phase === "ready"
      ? "READY"
      : phase === "transmitting"
        ? "TRANSMITTING"
        : phase === "over"
          ? "OVER"
          : "OUT · opus 4.7";

  const accent = phase === "transmitting" || phase === "receiving";

  return (
    <span
      className="text-[10px] uppercase"
      style={{
        color: accent ? AMBER.trace : AMBER.ink,
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.32em",
        textShadow: accent ? `0 0 8px ${AMBER.trace}` : "none",
      }}
    >
      {label}
    </span>
  );
}

function SignalDot({ phase }: { phase: ScopePhase }) {
  const live = phase === "transmitting";
  return (
    <span
      className={`inline-block h-1.5 w-1.5 rounded-full ${
        live ? "animate-pulse" : ""
      }`}
      style={{
        background: live ? "#D84A2C" : AMBER.inkSubtle,
        boxShadow: live ? "0 0 6px rgba(216,74,44,0.65)" : "none",
      }}
    />
  );
}

function timecode(phase: ScopePhase): string {
  switch (phase) {
    case "ready":
      return "0:00";
    case "transmitting":
      return "0:02.1";
    case "over":
      return "0:02.4";
    case "receiving":
      return "0:04.2";
  }
}

// ── Display ───────────────────────────────────────────────────────

function Display({ phase }: { phase: ScopePhase }) {
  return (
    <div
      className="relative overflow-hidden"
      style={{
        height: 200,
        background: AMBER.display,
        boxShadow: [
          "inset 0 2px 6px rgba(0,0,0,0.7)",
          "inset 0 0 24px rgba(255,169,64,0.04)",
        ].join(", "),
      }}
    >
      <Graticule />
      <Scanlines />
      <ScopeTrace phase={phase} />
      <ScopeCorner label="CH-01" position="tl" />
      <ScopeCorner label={phase === "receiving" ? "OUT" : "IN"} position="tr" />
      <ScopeCorner label="1.00 V/div" position="bl" />
      <ScopeCorner label="500 ms/div" position="br" />
    </div>
  );
}

function Graticule() {
  return (
    <svg
      className="absolute inset-0 h-full w-full"
      preserveAspectRatio="none"
      viewBox="0 0 640 200"
    >
      {/* Horizontal lines every 25px (8 divisions) */}
      {[25, 50, 75, 100, 125, 150, 175].map((y) => (
        <line
          key={`h${y}`}
          x1={0}
          x2={640}
          y1={y}
          y2={y}
          stroke={AMBER.grid}
          strokeWidth={0.5}
        />
      ))}
      {/* Vertical lines every 40px (16 divisions) */}
      {Array.from({ length: 15 }, (_, i) => (i + 1) * 40).map((x) => (
        <line
          key={`v${x}`}
          x1={x}
          x2={x}
          y1={0}
          y2={200}
          stroke={AMBER.grid}
          strokeWidth={0.5}
        />
      ))}
      {/* Center axes — slightly brighter */}
      <line
        x1={0}
        x2={640}
        y1={100}
        y2={100}
        stroke="rgba(232, 154, 60, 0.18)"
        strokeWidth={0.5}
      />
      <line
        x1={320}
        x2={320}
        y1={0}
        y2={200}
        stroke="rgba(232, 154, 60, 0.18)"
        strokeWidth={0.5}
      />
    </svg>
  );
}

function Scanlines() {
  return (
    <div
      className="pointer-events-none absolute inset-0"
      style={{
        backgroundImage:
          "repeating-linear-gradient(0deg, rgba(255,255,255,0.018) 0px, rgba(255,255,255,0.018) 1px, transparent 1px, transparent 3px)",
      }}
    />
  );
}

function ScopeTrace({ phase }: { phase: ScopePhase }) {
  const path =
    phase === "ready"
      ? READY_PATH
      : phase === "transmitting"
        ? TRANSMITTING_PATH
        : phase === "over"
          ? OVER_PATH
          : RECEIVING_PATH;

  const hot = phase === "transmitting" || phase === "receiving";
  const stroke = hot ? AMBER.trace : AMBER.traceDim;
  const glow = hot
    ? `drop-shadow(0 0 4px ${AMBER.trace}) drop-shadow(0 0 10px rgba(255,169,64,0.5))`
    : `drop-shadow(0 0 3px ${AMBER.traceDim})`;

  return (
    <svg
      className="absolute inset-0 h-full w-full"
      preserveAspectRatio="none"
      viewBox="0 0 640 200"
      style={{ filter: glow }}
    >
      <path
        d={path}
        fill="none"
        stroke={stroke}
        strokeWidth={1.4}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {phase === "transmitting" && <SweepDot />}
    </svg>
  );
}

function SweepDot() {
  return (
    <circle
      cx={520}
      cy={100}
      r={3}
      fill={AMBER.trace}
      style={{ filter: `drop-shadow(0 0 6px ${AMBER.trace})` }}
    >
      <animate
        attributeName="cx"
        values="40;600;40"
        dur="3s"
        repeatCount="indefinite"
      />
    </circle>
  );
}

// Hand-drawn scope paths — different signatures per phase.
const READY_PATH =
  "M 0 100 L 60 100 L 80 98 L 100 102 L 140 100 L 200 100 L 260 101 L 320 99 L 380 100 L 440 100 L 500 99 L 560 101 L 640 100";

const TRANSMITTING_PATH =
  "M 0 100 L 20 98 L 40 92 L 60 78 L 80 65 L 95 88 L 110 130 L 130 145 L 150 110 L 170 78 L 190 50 L 210 88 L 230 140 L 250 152 L 270 120 L 290 75 L 310 55 L 330 92 L 350 142 L 370 138 L 390 95 L 410 65 L 430 88 L 450 132 L 470 122 L 490 98 L 510 82 L 530 110 L 555 128 L 580 105 L 605 95 L 625 100 L 640 100";

const OVER_PATH =
  "M 0 100 L 80 100 L 120 96 L 160 110 L 200 92 L 240 108 L 280 96 L 320 102 L 360 99 L 400 101 L 440 100 L 480 100 L 520 100 L 640 100";

const RECEIVING_PATH =
  "M 0 100 L 30 100 L 50 88 L 70 112 L 90 78 L 110 122 L 130 88 L 150 112 L 175 100 L 200 100 L 230 85 L 255 115 L 280 80 L 305 120 L 330 85 L 355 115 L 385 100 L 415 100 L 445 90 L 470 110 L 495 82 L 520 118 L 545 92 L 570 108 L 600 100 L 640 100";

function ScopeCorner({
  label,
  position,
}: {
  label: string;
  position: "tl" | "tr" | "bl" | "br";
}) {
  const pos: React.CSSProperties =
    position === "tl"
      ? { top: 8, left: 12 }
      : position === "tr"
        ? { top: 8, right: 12 }
        : position === "bl"
          ? { bottom: 8, left: 12 }
          : { bottom: 8, right: 12 };

  return (
    <span
      className="absolute text-[8px] uppercase"
      style={{
        ...pos,
        color: AMBER.inkSubtle,
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.18em",
      }}
    >
      {label}
    </span>
  );
}

// ── Caption (receiving) ───────────────────────────────────────────

function Caption() {
  return (
    <div
      className="flex flex-col gap-2 px-7 py-4"
      style={{
        borderTop: `0.5px solid ${AMBER.edgeFaint}`,
        background:
          "linear-gradient(180deg, transparent 0%, rgba(255,169,64,0.025) 100%)",
      }}
    >
      <span
        className="text-[9px] uppercase"
        style={{
          color: AMBER.inkSubtle,
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.24em",
        }}
      >
        Talkie · spoken
      </span>
      <p
        className="text-[17px] leading-[1.4]"
        style={{
          color: AMBER.trace,
          fontFamily: "var(--theme-font-display)",
          fontStyle: "italic",
          fontWeight: 400,
        }}
      >
        “Alright, we gotcha. Vietnam's median age is twenty-nine —
        we checked it against the latest UN estimate.”
      </p>
    </div>
  );
}

// ── Footer ────────────────────────────────────────────────────────

function Footer({ phase }: { phase: ScopePhase }) {
  return (
    <div
      className="flex items-center justify-between px-5 py-2.5"
      style={{
        background:
          "linear-gradient(180deg, transparent 0%, rgba(0,0,0,0.35) 100%)",
        borderTop: `0.5px solid ${AMBER.edgeFaint}`,
      }}
    >
      <div className="flex items-center gap-1.5">
        {["⇧", "⌃", "⌥", "⌘"].map((k) => (
          <Keycap key={k} label={k} />
        ))}
        <Keycap label="T" wide accent />
        <span
          className="ml-2 text-[9px] uppercase"
          style={{
            color: AMBER.inkSubtle,
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.20em",
          }}
        >
          {phase === "ready" && "hold to transmit"}
          {phase === "transmitting" && "release to send"}
          {phase === "over" && "processing…"}
          {phase === "receiving" && "tap to dismiss"}
        </span>
      </div>

      <span
        className="text-[9px] uppercase"
        style={{
          color: AMBER.inkSubtle,
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.18em",
        }}
      >
        auto · ♪ verbal / ⟳ async
      </span>
    </div>
  );
}

function Keycap({
  label,
  wide = false,
  accent = false,
}: {
  label: string;
  wide?: boolean;
  accent?: boolean;
}) {
  return (
    <span
      className={`flex items-center justify-center text-[10px] font-medium ${
        wide ? "px-2" : "px-1.5"
      }`}
      style={{
        height: 20,
        minWidth: 20,
        borderRadius: 3,
        background: accent
          ? "linear-gradient(180deg, #FFC773 0%, #E89A3C 60%, #B57220 100%)"
          : "linear-gradient(180deg, #2A2E30 0%, #1C2022 60%, #14181A 100%)",
        color: accent ? "#241408" : AMBER.ink,
        border: `0.5px solid ${accent ? "#8A5A1A" : "rgba(255,255,255,0.06)"}`,
        boxShadow: accent
          ? "inset 0 1px 0 rgba(255,255,255,0.45), 0 1px 2px rgba(0,0,0,0.5)"
          : "inset 0 1px 0 rgba(255,255,255,0.04), 0 1px 2px rgba(0,0,0,0.4)",
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      {label}
    </span>
  );
}
