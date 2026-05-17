"use client";

/**
 * Complications — the action-placement language for the iPhone.
 *
 * Talkie's iPhone interaction uses "complications" (borrowed from
 * watchOS): fixed action affordances at defined positions on the
 * screen — typically the 4 corners + center FAB — instead of a
 * classic nav bar. Each complication is one tap-target tied to one
 * action (voice cmd, keyboard, mic, settings, ⋯).
 *
 * Current pattern (corners): 4 corner buttons + 1 center FAB = 5
 * tap-targets. Generous; lets the content area breathe; but corner
 * targets are far from each other and the mic FAB requires a
 * long-press to actually record (no visual affordance for "hold").
 *
 * Proposed alternative (tray): a 3-slot liquid-glass navigator at the
 * bottom — translucent backdrop blur, subtle hairline rim, center
 * slot lifted as the mic FAB. Trades freedom-of-positioning for
 * always-visible affordance + iOS-26-native glass language.
 *
 * Each variant renders the SAME content area (a sample memo) so the
 * comparison is about the COMPLICATION PATTERN, not the content.
 *
 * Theme-aware via `--theme-*` CSS vars.
 */

import type { CSSProperties } from "react";
import { StatusBar } from "./primitives/StatusBar";

export type ComplicationVariant =
  | "corners"
  | "tray"
  | "full"
  | "summon-idle"
  | "summon-active"
  | "voice-resting"
  | "voice-expanded"
  | "voice-listening";

/**
 * The app-wide interaction model. THREE STATES, one ambient
 * button. This is the pattern — no alternatives shown in the
 * picker. (Earlier exploration variants are preserved in the
 * source as `corners` / `tray` / `full` / `summon-*` for the
 * decisions-log; see NOTES.md.)
 */
export const COMPLICATION_VARIANTS: {
  key: ComplicationVariant;
  label: string;
}[] = [
  { key: "voice-resting", label: "1 · resting" },
  { key: "voice-expanded", label: "2 · tap → chrome up" },
  { key: "voice-listening", label: "3 · long-press → talk" },
];

interface ComplicationsProps {
  variant: ComplicationVariant;
}

export function Complications({ variant }: ComplicationsProps) {
  return (
    <div
      className="relative flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />

      {/* Content backdrop — the surface the complications float over.
       *  Picks the variant a real document so the action chrome reads
       *  in context, not over an empty rectangle. */}
      <ContentBackdrop />

      {/* Variant overlays */}
      {variant === "corners" ? <CornersLayout /> : null}
      {variant === "tray" ? <TrayLayout /> : null}
      {variant === "full" ? <FullLayout /> : null}
      {variant === "summon-idle" ? <SummonIdle /> : null}
      {variant === "summon-active" ? <SummonActive /> : null}
      {variant === "voice-resting" ? <VoicePivot state="resting" /> : null}
      {variant === "voice-expanded" ? <VoicePivot state="expanded" /> : null}
      {variant === "voice-listening" ? (
        <VoicePivot state="listening" />
      ) : null}
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Content backdrop — a sample memo so complications have a real
 * subject to float over. Keep it consistent across variants so
 * only the chrome differs.
 * ────────────────────────────────────────────────────────────────── */

function ContentBackdrop() {
  return (
    <div className="flex-1 overflow-hidden px-5 pt-6 pb-32">
      <div
        className="text-[10px] font-semibold uppercase tracking-[0.22em]"
        style={{
          color: "var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
          textShadow: "0 0 4px var(--theme-amber-glow)",
        }}
      >
        editing
      </div>
      <h1
        className="m-0 mt-1.5 text-[24px] leading-tight"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-display)",
          fontWeight: "var(--theme-display-weight, 500)",
          letterSpacing: "var(--theme-display-tracking, -0.018em)",
        }}
      >
        Conference Bio
      </h1>
      <p
        className="m-0 mt-4 text-[14px] leading-relaxed"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-body)",
        }}
      >
        Art is the founder of Talkie, an everywhere-capture system that
        turns voice into structured artifacts.
      </p>
      <p
        className="m-0 mt-3 text-[14px] leading-relaxed"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-body)",
        }}
      >
        Previously at Notion (design) and Linear (notifications). He's
        been building voice-first software since 2014.
      </p>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Variant A — CORNERS + CENTER FAB (current shipping pattern)
 *
 * 4 corner pills + 1 center FAB. Mic in center is the primary
 * affordance; corners are secondary (settings, more, voice cmd,
 * keyboard).
 * ────────────────────────────────────────────────────────────────── */

function CornersLayout() {
  return (
    <>
      <CornerSlot position="top-left" glyph={<DoneGlyph />} />
      <CornerSlot position="top-right" glyph={<MoreGlyph />} />
      <CornerSlot position="bottom-left" glyph={<VoiceCmdGlyph />} />
      <CornerSlot position="bottom-right" glyph={<KeyboardGlyph />} />
      <CenterFAB />
    </>
  );
}

function CornerSlot({
  position,
  glyph,
}: {
  position: "top-left" | "top-right" | "bottom-left" | "bottom-right";
  glyph: React.ReactNode;
}) {
  // Status bar is ~38px tall — keep top complications below it.
  const STATUS_BAR_OFFSET = 50;
  const SAFE_INSET = 20;
  const FAB_INSET = 28;

  const style: CSSProperties = {
    position: "absolute",
    width: 40,
    height: 40,
    borderRadius: "50%",
    background: "var(--theme-paper)",
    color: "var(--theme-ink-dim)",
    border: "0.5px solid var(--theme-edge-faint)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    boxShadow:
      "var(--theme-card-shadow-strong, 0 2px 6px rgba(0,0,0,0.10))",
    zIndex: 10,
  };

  if (position === "top-left") {
    style.top = STATUS_BAR_OFFSET;
    style.left = SAFE_INSET;
  } else if (position === "top-right") {
    style.top = STATUS_BAR_OFFSET;
    style.right = SAFE_INSET;
  } else if (position === "bottom-left") {
    style.bottom = FAB_INSET;
    style.left = SAFE_INSET;
  } else {
    style.bottom = FAB_INSET;
    style.right = SAFE_INSET;
  }

  return <button style={style}>{glyph}</button>;
}

function CenterFAB() {
  return (
    <button
      aria-label="Dictate"
      style={{
        position: "absolute",
        left: "50%",
        bottom: 24,
        transform: "translateX(-50%)",
        width: 56,
        height: 56,
        borderRadius: "50%",
        background: "var(--theme-paper)",
        color: "var(--theme-amber)",
        border: "1px solid var(--theme-amber-soft)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        boxShadow:
          "0 6px 16px -6px var(--theme-amber-glow), inset 0 0.5px 0 rgba(255,255,255,0.30)",
        zIndex: 11,
      }}
    >
      <MicGlyph />
    </button>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Variant B — LIQUID GLASS TRAY (proposed)
 *
 * Bottom-anchored 3-slot navigator with translucent backdrop-blur
 * glass. Center slot is lifted as the primary mic FAB. iOS 26
 * native glass language; trades corner freedom for always-visible
 * affordance + tight tap-target proximity.
 * ────────────────────────────────────────────────────────────────── */

function TrayLayout() {
  return (
    <>
      <CornerSlot position="top-left" glyph={<DoneGlyph />} />
      <CornerSlot position="top-right" glyph={<MoreGlyph />} />
      <LiquidGlassTray />
    </>
  );
}

function LiquidGlassTray() {
  // Three quick-actions: Record memo (centered hero) · Camera · Compose.
  // These are CREATE actions — each launches a new capture/creation
  // flow. Chrome (Back, More) stays in the corners.
  return (
    <div
      style={{
        position: "absolute",
        left: "50%",
        bottom: 22,
        transform: "translateX(-50%)",
        display: "flex",
        alignItems: "center",
        gap: 18,
        padding: "10px 14px",
        borderRadius: 999,
        background:
          "color-mix(in srgb, var(--theme-paper) 70%, transparent)",
        border: "0.5px solid var(--theme-edge-faint)",
        boxShadow:
          "0 8px 24px -8px rgba(0,0,0,0.15), inset 0 0.5px 0 rgba(255,255,255,0.40)",
        backdropFilter: "blur(20px) saturate(160%)",
        WebkitBackdropFilter: "blur(20px) saturate(160%)",
        zIndex: 10,
      }}
    >
      <TraySlot glyph={<CameraGlyph />} label="Camera" />
      <TrayFAB />
      <TraySlot glyph={<ComposeGlyph />} label="Compose" />
    </div>
  );
}

function TraySlot({
  glyph,
  label,
}: {
  glyph: React.ReactNode;
  label?: string;
}) {
  return (
    <button
      aria-label={label}
      style={{
        width: 36,
        height: 36,
        borderRadius: "50%",
        background: "transparent",
        color: "var(--theme-ink-dim)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      {glyph}
    </button>
  );
}

function TrayFAB() {
  // Center slot — the mic. Slightly larger + filled with brass so
  // the primary affordance reads even inside the glass tray.
  return (
    <button
      aria-label="Dictate"
      style={{
        width: 48,
        height: 48,
        borderRadius: "50%",
        background: "var(--theme-amber)",
        color: "var(--theme-paper)",
        border: "0.5px solid var(--theme-amber-soft)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        boxShadow:
          "0 4px 10px -4px var(--theme-amber-glow), inset 0 0.5px 0 rgba(255,255,255,0.30)",
      }}
    >
      <MicGlyph />
    </button>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Variant C — FULL (all 4 corners + tray)
 *
 * The articulated model: corners hold chrome / destinations
 * (Back · Settings · Keyboard · Share), tray holds create-actions
 * (Camera · Record · Compose). Maximum affordance density; tests
 * whether the bottom-corners + tray spatially feel right or
 * crowd each other.
 * ────────────────────────────────────────────────────────────────── */

function FullLayout() {
  return (
    <>
      <CornerSlot position="top-left" glyph={<DoneGlyph />} />
      <CornerSlot position="top-right" glyph={<SettingsGlyph />} />
      <CornerSlot position="bottom-left" glyph={<KeyboardGlyph />} />
      <CornerSlot position="bottom-right" glyph={<ShareGlyph />} />
      <LiquidGlassTray />
    </>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Variants D & E — ON-DEMAND (chrome hidden, summon to reveal)
 *
 * Most of the time the content is full-bleed. A tiny gesture
 * affordance (hairline at bottom + dot) tells the user "pull up
 * here to summon" (or long-press, edge-swipe, etc.). When
 * summoned, the full corners + tray fade in over the content.
 *
 * Two static states for comparison: idle (just the hint) and
 * active (chrome fully revealed).
 * ────────────────────────────────────────────────────────────────── */

function SummonIdle() {
  return (
    <>
      {/* Tiny gesture affordance — a hairline + center pill at the
       *  bottom edge. Says "pull up / long-press" without bringing
       *  in any chrome. */}
      <div
        style={{
          position: "absolute",
          left: "50%",
          bottom: 10,
          transform: "translateX(-50%)",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 6,
          zIndex: 10,
        }}
      >
        <div
          style={{
            width: 60,
            height: 4,
            borderRadius: 2,
            background: "var(--theme-edge-dim)",
          }}
        />
        <span
          style={{
            fontFamily: "var(--theme-font-mono)",
            fontSize: 9,
            fontWeight: 600,
            letterSpacing: "0.18em",
            textTransform: "uppercase",
            color: "var(--theme-ink-subtle)",
          }}
        >
          Pull up to summon
        </span>
      </div>
    </>
  );
}

function SummonActive() {
  // Mid-summon: chrome appears but the entire surface is dimmed
  // slightly (as if the user is touching to summon) and the chrome
  // has a brief brass scrim behind it.
  return (
    <>
      {/* Dim scrim over content while summoned */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(to bottom, transparent 40%, color-mix(in srgb, var(--theme-canvas) 60%, transparent) 100%)",
          zIndex: 5,
          pointerEvents: "none",
        }}
      />
      <CornerSlot position="top-left" glyph={<DoneGlyph />} />
      <CornerSlot position="top-right" glyph={<SettingsGlyph />} />
      <CornerSlot position="bottom-left" glyph={<KeyboardGlyph />} />
      <CornerSlot position="bottom-right" glyph={<ShareGlyph />} />
      <LiquidGlassTray />
    </>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * VOICE-PIVOT — a single ambient button in the bottom-left that
 * escalates through three states on successive taps:
 *
 *   resting   · only the voice button visible; content full-bleed
 *   expanded  · 1st tap → corners + tray fade in; voice button lights
 *               brass to signal "tap again to talk"
 *   listening · 2nd tap → voice-command modal opens above the
 *               button; mic glow pulses while listening
 *
 * The point: a single always-available affordance that handles
 * BOTH "summon chrome" and "issue voice command" without crowding
 * the screen at rest.
 * ────────────────────────────────────────────────────────────────── */

function VoicePivot({
  state,
}: {
  state: "resting" | "expanded" | "listening";
}) {
  const expanded = state !== "resting";
  const listening = state === "listening";

  return (
    <>
      {/* Chrome fades in when expanded */}
      {expanded ? (
        <>
          <CornerSlot position="top-left" glyph={<DoneGlyph />} />
          <CornerSlot position="top-right" glyph={<SettingsGlyph />} />
          <CornerSlot position="bottom-right" glyph={<KeyboardGlyph />} />
          <LiquidGlassTray />
        </>
      ) : null}

      {/* Voice button — ambient, escalates per state */}
      <VoicePivotButton state={state} />

      {/* Listening modal — bubble above the button */}
      {listening ? <ListeningBubble /> : null}

      {/* Resting hint caption */}
      {state === "resting" ? (
        <span
          style={{
            position: "absolute",
            bottom: 26,
            left: 72,
            fontFamily: "var(--theme-font-mono)",
            fontSize: 9,
            fontWeight: 600,
            letterSpacing: "0.18em",
            textTransform: "uppercase",
            color: "var(--theme-ink-subtle)",
            zIndex: 9,
          }}
        >
          Tap to summon
        </span>
      ) : null}
    </>
  );
}

function VoicePivotButton({
  state,
}: {
  state: "resting" | "expanded" | "listening";
}) {
  const baseStyle: CSSProperties = {
    position: "absolute",
    bottom: 22,
    left: 20,
    width: 48,
    height: 48,
    borderRadius: "50%",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    zIndex: 12,
    transition: "all 0.2s ease",
  };

  if (state === "resting") {
    return (
      <button
        aria-label="Summon chrome"
        style={{
          ...baseStyle,
          background: "var(--theme-paper)",
          color: "var(--theme-ink-dim)",
          border: "0.5px solid var(--theme-edge-faint)",
          boxShadow:
            "var(--theme-card-shadow-strong, 0 2px 6px rgba(0,0,0,0.10))",
        }}
      >
        <VoiceCmdGlyph />
      </button>
    );
  }

  if (state === "expanded") {
    return (
      <button
        aria-label="Tap to talk"
        style={{
          ...baseStyle,
          background: "var(--theme-paper)",
          color: "var(--theme-amber)",
          border: "1px solid var(--theme-amber-soft)",
          boxShadow:
            "0 0 0 3px var(--theme-amber-faint), 0 4px 12px -4px var(--theme-amber-glow)",
        }}
      >
        <VoiceCmdGlyph />
      </button>
    );
  }

  // listening
  return (
    <button
      aria-label="Listening — tap to stop"
      style={{
        ...baseStyle,
        background: "var(--theme-amber)",
        color: "var(--theme-paper)",
        border: "1px solid var(--theme-amber-soft)",
        boxShadow:
          "0 0 0 5px var(--theme-amber-faint), 0 6px 18px -4px var(--theme-amber-glow)",
        animation: "rec-pulse 1.4s ease-in-out infinite",
      }}
    >
      <VoiceCmdGlyph />
    </button>
  );
}

function ListeningBubble() {
  // Floats above the voice button — captures what the user is saying.
  // Tail points down toward the button.
  return (
    <div
      style={{
        position: "absolute",
        bottom: 84,
        left: 20,
        right: 20,
        zIndex: 11,
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "10px 14px",
          borderRadius: 12,
          background:
            "color-mix(in srgb, var(--theme-paper) 88%, transparent)",
          border: "0.5px solid var(--theme-amber-soft)",
          boxShadow:
            "0 12px 32px -8px rgba(0,0,0,0.18), inset 0 0.5px 0 rgba(255,255,255,0.40)",
          backdropFilter: "blur(20px) saturate(160%)",
          WebkitBackdropFilter: "blur(20px) saturate(160%)",
        }}
      >
        {/* Live waveform — 4 bars */}
        <span style={{ display: "inline-flex", gap: 2, alignItems: "center" }}>
          {[0, 1, 2, 3].map((i) => (
            <span
              key={i}
              style={{
                display: "inline-block",
                width: 2,
                height: 6 + (i % 3) * 4,
                background: "var(--theme-amber)",
                borderRadius: 1,
                animation: `bus-pulse 1.2s ease-in-out ${i * 0.12}s infinite`,
              }}
            />
          ))}
        </span>
        <span
          style={{
            fontFamily: "var(--theme-font-mono)",
            fontSize: 9,
            fontWeight: 600,
            letterSpacing: "0.18em",
            textTransform: "uppercase",
            color: "var(--theme-amber)",
          }}
        >
          Hold · listening
        </span>
        <span
          style={{
            fontFamily: "var(--theme-font-body)",
            fontSize: 13,
            fontStyle: "italic",
            color: "var(--theme-ink-dim)",
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
            flex: 1,
            minWidth: 0,
          }}
        >
          "tighten the second paragraph…"
        </span>
      </div>
      {/* Tail */}
      <div
        aria-hidden
        style={{
          width: 0,
          height: 0,
          borderLeft: "6px solid transparent",
          borderRight: "6px solid transparent",
          borderTop:
            "6px solid color-mix(in srgb, var(--theme-paper) 88%, transparent)",
          marginLeft: 24,
          marginTop: -1,
        }}
      />
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Glyphs
 * ────────────────────────────────────────────────────────────────── */

function DoneGlyph() {
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
      <path
        d="M 10 4 L 5 8 L 10 12"
        stroke="currentColor"
        strokeWidth={1.4}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function MoreGlyph() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" className="h-4 w-4">
      <circle cx={3.5} cy={8} r={1.1} />
      <circle cx={8} cy={8} r={1.1} />
      <circle cx={12.5} cy={8} r={1.1} />
    </svg>
  );
}

function SettingsGlyph() {
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
      <circle cx={8} cy={8} r={2} stroke="currentColor" strokeWidth={1} />
      <path
        d="M 8 1.5 L 8 3.5 M 8 12.5 L 8 14.5 M 1.5 8 L 3.5 8 M 12.5 8 L 14.5 8
           M 3.05 3.05 L 4.4 4.4 M 11.6 11.6 L 12.95 12.95
           M 3.05 12.95 L 4.4 11.6 M 11.6 4.4 L 12.95 3.05"
        stroke="currentColor"
        strokeWidth={1}
        strokeLinecap="round"
      />
    </svg>
  );
}

function ShareGlyph() {
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
      <path
        d="M 8 2 L 8 10 M 5 5 L 8 2 L 11 5
           M 3 9 L 3 13 L 13 13 L 13 9"
        stroke="currentColor"
        strokeWidth={1.1}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function CameraGlyph() {
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
      <path
        d="M 2.5 5.5 L 5 5.5 L 6 4 L 10 4 L 11 5.5 L 13.5 5.5 L 13.5 12.5 L 2.5 12.5 Z"
        stroke="currentColor"
        strokeWidth={1}
        strokeLinejoin="round"
        fill="none"
      />
      <circle cx={8} cy={9} r={2.2} stroke="currentColor" strokeWidth={1} />
    </svg>
  );
}

function ComposeGlyph() {
  // Sparkle — Talkie's brand glyph for AI / compose moments.
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
      <path
        d="M 8 2 L 9 6 L 13 7 L 9 8 L 8 12 L 7 8 L 3 7 L 7 6 Z"
        fill="currentColor"
        stroke="currentColor"
        strokeWidth={0.5}
        strokeLinejoin="round"
      />
    </svg>
  );
}

function VoiceCmdGlyph() {
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
      <g stroke="currentColor" strokeWidth={1.1} strokeLinecap="round" fill="none">
        <path d="M 4 4 a 5 5 0 0 0 0 8" />
        <path d="M 12 4 a 5 5 0 0 1 0 8" />
        <path d="M 6 6 a 2.5 2.5 0 0 0 0 4" />
        <path d="M 10 6 a 2.5 2.5 0 0 1 0 4" />
      </g>
      <circle cx={8} cy={8} r={1.3} fill="currentColor" />
    </svg>
  );
}

function KeyboardGlyph() {
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
      <rect x={2} y={4.5} width={12} height={7} rx={1.2} stroke="currentColor" strokeWidth={0.9} />
      <g stroke="currentColor" strokeWidth={0.7} strokeLinecap="round">
        <line x1={4} y1={7} x2={4.4} y2={7} />
        <line x1={6.5} y1={7} x2={6.9} y2={7} />
        <line x1={9} y1={7} x2={9.4} y2={7} />
        <line x1={11.5} y1={7} x2={11.9} y2={7} />
        <line x1={5} y1={9.5} x2={11} y2={9.5} />
      </g>
    </svg>
  );
}

function MicGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-6 w-6">
      <rect x={9} y={3} width={6} height={11} rx={3} stroke="currentColor" strokeWidth={1.4} />
      <path
        d="M 6 11 v 1 a 6 6 0 0 0 12 0 v-1 M 12 18 v 3 M 8 21 h 8"
        stroke="currentColor"
        strokeWidth={1.4}
        strokeLinecap="round"
      />
    </svg>
  );
}
