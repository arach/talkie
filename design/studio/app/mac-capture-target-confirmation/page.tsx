"use client";

/**
 * Mac Capture Target Confirmation — screen-aware lock acknowledgement.
 *
 * FOURTH AESTHETIC PASS · "Destination Token". A tiny Talkie routing
 * instrument rather than a generic toast: Talkie's fused tile emits an amber
 * trace toward the app name, a mint receiving bracket closes on the target,
 * and the silhouette points at the actual input below. There is still no
 * secondary sentence or decorative strip; the geometry and motion carry meaning.
 *
 * Two siblings, not one object travelling between two homes:
 *
 *   TRANSIENT CONFIRMATION — a compact caption slab that appears immediately
 *     above the chosen input, dwells ~1s, then fades in place. It confirms the
 *     *target lock*, never implies a screenshot was sent. Text only.
 *
 *   PERSISTENT LOCKED BADGE — stays in Talkie's overlay stack and quietly
 *     preserves state after the confirmation is gone. It keeps the richer glass
 *     (app glyph, mint count chip) precisely because it is the *other* object:
 *     captures accumulate against that target until the user sends or clears.
 *
 * Screen-aware material picks the tone from the pixels beneath the overlay,
 * mirroring ScreenAwareOverlayAppearance.swift:
 *
 *   GRAPHITE — dark glass, for LIGHT content.
 *   PEARL    — light glass, for DARK content.
 *   SAMPLED  — a neutral for MIXED content (Studio illustration only; the Swift
 *              toast folds this into the system fallback tone — no third
 *              LiveGlassTone is introduced for a ~1.3s object).
 *
 * Civilian and calm on purpose. No reticles, radar, crosshairs, giant locks,
 * arrows, neon, or fly-to-dock motion. The destination — not the container —
 * is what the eye should read.
 *
 * Tone tokens track LiveGlassTone (TalkieKit/UI/LivePill.swift); geometry and
 * motion track NOTES.md. Swift port targets:
 *   apps/macos/TalkieAgent/.../Views/Overlay/CaptureTargetLockOverlay.swift
 *   apps/macos/TalkieAgent/.../Views/Overlay/ScreenAwareOverlayAppearance.swift
 */

import { useEffect, useRef, useState } from "react";
import { StudioPage } from "@/components/StudioPage";

// ── Geometry (NOTES.md · the source of truth for the Swift port) ─────────
// Destination Token: a fused route instrument with a pointer to the real input.
const GEO = {
  height: 40,
  bodyHeight: 36,
  tailHeight: 4,
  minWidth: 140, // hug the route furniture + app name; size once at show
  maxWidth: 260,
  radius: 7,
  padX: 10,
  gapFromInput: 7,
  edge: 0.75,
};

const TALKIE_AMBER = "rgb(196,125,28)";

// ── Motion (NOTES.md) · slightly tighter for a thinner object ────────────
const MOTION = {
  enterMs: 150,
  dwellMs: 1000,
  exitMs: 170,
  riseY: 2, // enter travels y 2pt → 0 (was 4 — less "drop-in toast")
};
const CYCLE_MS = MOTION.enterMs + MOTION.dwellMs + MOTION.exitMs; // 1320

// ── Tones — mirror LiveGlassTone (pearl / graphite) plus a sampled neutral
// for the mixed case. Values are the Swift RGBs converted to CSS.

interface Tone {
  key: "graphite" | "pearl" | "sampled";
  name: string;
  scheme: "dark" | "light";
  surface: string; // base fill (pre-opacity)
  surfaceOpacity: number; // full glass (persistent badge)
  toastOpacity: number; // quieter plate for the transient slab
  raisedSurface: string; // app-icon well (badge only)
  primaryText: string;
  secondaryText: string;
  edge: string; // crisp inset hairline
  outerEdge: string; // badge only
  sheen: string; // badge only (top highlight gradient stop)
  highlight: string; // badge only (inner top-edge stroke)
  lockAccent: string; // mint — badge count chip only, never on the toast
  shadow: string;
};

const GRAPHITE: Tone = {
  key: "graphite",
  name: "Graphite",
  scheme: "dark",
  surface: "rgb(18,22,24)",
  surfaceOpacity: 0.62,
  toastOpacity: 0.55, // less milky plate than the hero glass
  raisedSurface: "rgb(27,32,34)",
  primaryText: "rgb(237,242,240)",
  secondaryText: "rgb(150,168,163)",
  edge: "rgba(255,255,255,0.13)",
  outerEdge: "rgba(0,0,0,0.35)",
  sheen: "rgba(255,255,255,0.10)",
  highlight: "rgba(255,255,255,0.10)",
  lockAccent: "rgb(79,212,176)",
  shadow: "rgba(0,0,0,0.42)",
};

const PEARL: Tone = {
  key: "pearl",
  name: "Pearl",
  scheme: "light",
  surface: "rgb(246,248,249)",
  surfaceOpacity: 0.72,
  toastOpacity: 0.64,
  raisedSurface: "rgb(253,252,249)",
  primaryText: "rgb(31,36,38)",
  secondaryText: "rgb(87,94,99)",
  edge: "rgba(0,0,0,0.14)",
  outerEdge: "rgba(0,0,0,0.12)",
  sheen: "rgba(255,255,255,0.55)",
  highlight: "rgba(255,255,255,0.82)",
  lockAccent: "rgb(20,145,122)",
  shadow: "rgba(0,0,0,0.20)",
};

// Sampled neutral — Studio illustration of the mixed case. In Swift this folds
// into the system fallback tone; no third LiveGlassTone is added for the toast.
const SAMPLED: Tone = {
  key: "sampled",
  name: "Sampled",
  scheme: "dark",
  surface: "rgb(58,62,68)",
  surfaceOpacity: 0.66,
  toastOpacity: 0.58,
  raisedSurface: "rgb(74,78,84)",
  primaryText: "rgb(238,240,242)",
  secondaryText: "rgb(178,184,190)",
  edge: "rgba(255,255,255,0.16)",
  outerEdge: "rgba(0,0,0,0.30)",
  sheen: "rgba(255,255,255,0.14)",
  highlight: "rgba(255,255,255,0.14)",
  lockAccent: "rgb(96,214,182)",
  shadow: "rgba(0,0,0,0.34)",
};

// ── Wallpapers — one per content class. The tone is what the sampler picks
// FOR that class, so each pairs a backdrop with the sibling that holds on it.

const WALLPAPERS = {
  light:
    "linear-gradient(140deg, #EEF1F6 0%, #DEE3EC 48%, #CCD3DF 100%)",
  dark:
    "radial-gradient(circle at 32% 22%, #263140 0%, #161C25 55%, #0B0F15 100%)",
  mixed:
    "linear-gradient(118deg, #5E4C42 0%, #8A7A68 26%, #C6A97F 50%, #56697A 76%, #2C3744 100%)",
} as const;

type WallKey = keyof typeof WALLPAPERS;

interface Context {
  wall: WallKey;
  tone: Tone;
  label: string;
  caption: string;
}

const CONTEXTS: Context[] = [
  {
    wall: "light",
    tone: GRAPHITE,
    label: "Light content → Graphite",
    caption: "dark glass over a light desktop",
  },
  {
    wall: "dark",
    tone: PEARL,
    label: "Dark content → Pearl",
    caption: "light glass over a dark desktop",
  },
  {
    wall: "mixed",
    tone: SAMPLED,
    label: "Mixed content → Sampled",
    caption: "neutral drawn from a busy backdrop",
  },
];

// The destination we're confirming, shared across the study.
const TARGET = {
  app: "ChatGPT",
  title: "Work with ChatGPT",
  // Badge-only destination glyph. The transient uses Talkie's own fused T mark;
  // the persistent sibling keeps the target app glyph because it lingers.
  iconGradient: "linear-gradient(155deg, #12A37F 0%, #0E7A63 100%)",
  iconGlyph: "✦",
};

// ── Destination Token — Talkie authorship, route, receiver, and input anchor.
function destinationTokenStyle(tone: Tone): React.CSSProperties {
  const fill = withOpacity(
    tone.surface,
    tone.key === "pearl" ? 0.92 : tone.key === "sampled" ? 0.88 : 0.9
  );
  const bottomLip =
    tone.scheme === "dark" ? "rgba(0,0,0,0.30)" : "rgba(0,0,0,0.10)";

  return {
    borderRadius: GEO.radius,
    overflow: "hidden",
    backgroundImage: [
      `linear-gradient(to bottom, ${withAlphaScale(tone.highlight, 0.16)} 0%, transparent 45%)`,
      `linear-gradient(${fill}, ${fill})`,
    ].join(", "),
    backdropFilter: "blur(24px) saturate(1.3)",
    WebkitBackdropFilter: "blur(24px) saturate(1.3)",
    boxShadow: [
      `inset 0 0 0 ${GEO.edge}px ${tone.edge}`,
      `inset 0 1px 0 ${withAlphaScale(tone.highlight, 0.9)}`,
      `inset 0 -1px 0 ${bottomLip}`,
      `0 2px 5px rgba(0,0,0,0.22)`,
      `0 12px 28px rgba(0,0,0,0.15)`,
    ].join(", "),
  };
}

// ── Full glass — CSS reproduction of `liveGlassSurface(...)`. Reserved for the
// PERSISTENT badge, which deliberately carries more chrome than the toast.
function glassStyle(tone: Tone, radius = GEO.radius): React.CSSProperties {
  return {
    borderRadius: radius,
    background: withOpacity(tone.surface, tone.surfaceOpacity),
    backdropFilter: "blur(22px) saturate(1.5)",
    WebkitBackdropFilter: "blur(22px) saturate(1.5)",
    boxShadow: [
      `inset 0 0 0 ${GEO.edge}px ${tone.edge}`,
      `inset 0 0.5px 0 0 ${tone.highlight}`,
      `0 0 0 0.5px ${tone.outerEdge}`,
      `0 10px 26px ${tone.shadow}`,
      `0 1px 2px ${tone.shadow}`,
    ].join(", "),
  };
}

function sheenStyle(tone: Tone, radius = GEO.radius): React.CSSProperties {
  return {
    position: "absolute",
    inset: 0,
    borderRadius: radius,
    pointerEvents: "none",
    background: `linear-gradient(to bottom, ${tone.sheen} 0%, ${withAlphaScale(
      tone.sheen,
      0.18
    )} 40%, transparent 70%)`,
  };
}

// ── The transient confirmation — a Talkie-owned destination token. ──────
function ConfirmationCard({
  tone,
  animateRoute = false,
}: {
  tone: Tone;
  animateRoute?: boolean;
}) {
  const surface = withOpacity(
    tone.surface,
    tone.key === "pearl" ? 0.92 : tone.key === "sampled" ? 0.88 : 0.9
  );
  return (
    <div
      className="relative font-sans"
      style={{
        minWidth: GEO.minWidth,
        maxWidth: GEO.maxWidth,
        height: GEO.height,
      }}
      role="status"
      aria-label={`Capture target locked, ${TARGET.app}, ${TARGET.title}`}
    >
      <span
        aria-hidden
        style={{
          position: "absolute",
          zIndex: 0,
          left: "50%",
          top: GEO.bodyHeight - 7,
          width: 10,
          height: 10,
          transform: "translateX(-50%) rotate(45deg)",
          background: surface,
          borderRight: `${GEO.edge}px solid ${tone.edge}`,
          borderBottom: `${GEO.edge}px solid ${tone.edge}`,
          borderRadius: 1,
          boxShadow: "2px 2px 5px rgba(0,0,0,0.10)",
        }}
      />
      <div
        style={{
          ...destinationTokenStyle(tone),
          position: "relative",
          zIndex: 1,
          height: GEO.bodyHeight,
          padding: `0 ${GEO.padX}px`,
          display: "flex",
          alignItems: "center",
          boxSizing: "border-box",
        }}
      >
        <span
          aria-hidden
          style={{
            width: 20,
            height: 20,
            flexShrink: 0,
            borderRadius: 5,
            display: "grid",
            placeItems: "center",
            background: "rgba(255,255,255,0.97)",
            boxShadow: [
              "inset 0 0 0 0.75px rgba(0,0,0,0.14)",
              `0 0 10px ${withOpacity(TALKIE_AMBER, 0.22)}`,
            ].join(", "),
            color: "rgba(0,0,0,0.92)",
            fontSize: 11,
            fontWeight: 800,
            lineHeight: 1,
            letterSpacing: "-0.6px",
          }}
        >
          T
        </span>
        <span
          aria-hidden
          style={{
            position: "relative",
            width: 18,
            height: 10,
            flexShrink: 0,
            marginLeft: 7,
            marginRight: 8,
          }}
        >
          <span
            style={{
              position: "absolute",
              insetInline: 0,
              top: "50%",
              height: 1,
              background: `linear-gradient(90deg, ${TALKIE_AMBER}, ${tone.lockAccent})`,
              opacity: 0.9,
            }}
          />
          <span
            className={animateRoute ? "ct-route-signal" : undefined}
            style={{
              position: "absolute",
              left: animateRoute ? 0 : 14.5,
              top: "50%",
              width: 3.5,
              height: 3.5,
              borderRadius: 999,
              transform: "translateY(-1.25px)",
              background: animateRoute ? TALKIE_AMBER : tone.lockAccent,
              boxShadow: `0 0 7px ${animateRoute ? TALKIE_AMBER : tone.lockAccent}`,
            }}
          />
        </span>
      <span
        style={{
          flex: 1,
          minWidth: 0,
          fontSize: 13.5,
          fontWeight: 640,
          lineHeight: "17px",
          letterSpacing: "-0.1px",
          textAlign: "left",
          color: withOpacity(tone.primaryText, 0.98),
          textShadow:
            tone.scheme === "light"
              ? "0 0.5px 0 rgba(255,255,255,0.55)"
              : "0 0.5px 0 rgba(0,0,0,0.40)",
          whiteSpace: "nowrap",
          overflow: "hidden",
          textOverflow: "ellipsis",
        }}
      >
        {TARGET.app}
      </span>
        <span
          aria-hidden
          className={animateRoute ? "ct-receiver" : undefined}
          style={{
            width: 7,
            height: 17,
            flexShrink: 0,
            marginLeft: 8,
            borderTop: `1.25px solid ${tone.lockAccent}`,
            borderRight: `1.25px solid ${tone.lockAccent}`,
            borderBottom: `1.25px solid ${tone.lockAccent}`,
            filter: `drop-shadow(0 0 3px ${withAlphaScale(tone.lockAccent, 0.3)})`,
          }}
        />
      </div>
      <span
        aria-hidden
        className={animateRoute ? "ct-destination-dot" : undefined}
        style={{
          position: "absolute",
          zIndex: 2,
          left: "50%",
          bottom: 0,
          width: 3,
          height: 3,
          borderRadius: 999,
          transform: "translateX(-50%)",
          background: tone.lockAccent,
          boxShadow: `0 0 6px ${tone.lockAccent}`,
        }}
      />
    </div>
  );
}

// ── Persistent locked badge — the sibling that stays behind. Richer glass on
// purpose: it keeps an app glyph and a mint count chip because it is the one
// that lingers and accumulates. It preserves state; it does not re-announce.
function PersistentBadge({
  tone,
  count = 3,
}: {
  tone: Tone;
  count?: number;
}) {
  return (
    <div
      className="relative font-sans"
      style={{
        ...glassStyle(tone, 11),
        height: 34,
        padding: "0 8px 0 7px",
        display: "inline-flex",
        alignItems: "center",
        gap: 8,
        boxSizing: "border-box",
      }}
      role="status"
      aria-label={`Locked to ${TARGET.app}, ${count} captures held`}
    >
      <span style={sheenStyle(tone, 11)} aria-hidden />
      <div
        aria-hidden
        style={{
          width: 20,
          height: 20,
          borderRadius: 6,
          flexShrink: 0,
          background: TARGET.iconGradient,
          boxShadow: `inset 0 0 0 0.5px ${tone.edge}`,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: "rgba(255,255,255,0.92)",
          fontSize: 10,
        }}
      >
        {TARGET.iconGlyph}
      </div>
      <span
        style={{
          fontSize: 11.5,
          fontWeight: 600,
          color: tone.primaryText,
          whiteSpace: "nowrap",
        }}
      >
        {TARGET.app}
      </span>
      {/* Accumulation chip — captures held against this target */}
      <span
        style={{
          fontSize: 10,
          fontWeight: 600,
          lineHeight: 1,
          color: tone.scheme === "light" ? "rgba(255,255,255,0.95)" : "rgb(20,24,26)",
          background: tone.lockAccent,
          borderRadius: 999,
          padding: "3px 6px",
          fontVariantNumeric: "tabular-nums",
        }}
        aria-hidden
      >
        {count}
      </span>
    </div>
  );
}

// ── Desktop tile — fakes a wallpaper with a text input near the bottom and
// the confirmation floating 10pt above it.
function DesktopTile({
  wall,
  tone,
  children,
  showInput = true,
  height = 300,
  label,
}: {
  wall: WallKey;
  tone: Tone;
  children: React.ReactNode;
  showInput?: boolean;
  height?: number;
  label?: string;
}) {
  const dark = wall === "dark";
  return (
    <div className="flex flex-col gap-2">
      {label ? (
        <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          · {label}
        </div>
      ) : null}
      <div
        className="relative overflow-hidden rounded-md"
        style={{
          height,
          background: WALLPAPERS[wall],
          border: "0.5px solid #DEDEDD",
          boxShadow: "0 6px 22px rgba(46,68,82,0.08)",
        }}
      >
        {/* Menu bar stripe — sells the "this is a desktop" framing */}
        <div
          className="flex items-center px-3"
          style={{
            height: 22,
            background: dark ? "rgba(20,24,28,0.55)" : "rgba(255,255,255,0.5)",
            backdropFilter: "blur(20px) saturate(1.4)",
            WebkitBackdropFilter: "blur(20px) saturate(1.4)",
            borderBottom: dark
              ? "0.5px solid rgba(255,255,255,0.10)"
              : "0.5px solid rgba(0,0,0,0.06)",
          }}
        >
          <span
            className="text-[9px]"
            style={{ color: dark ? "#E8EAEC" : "#1F2226" }}
          >
            {TARGET.app}
          </span>
        </div>

        {/* Input + confirmation, anchored to the lower third */}
        <div
          className="absolute inset-x-0 flex flex-col items-center"
          style={{ bottom: 26 }}
        >
          <div>{children}</div>
          {showInput ? (
            <div style={{ height: GEO.gapFromInput }} />
          ) : null}
          {showInput ? <FakeInput dark={dark} /> : null}
        </div>
      </div>
    </div>
  );
}

// A quiet chat-style composer the confirmation sits above.
function FakeInput({ dark }: { dark: boolean }) {
  return (
    <div
      className="flex items-center"
      style={{
        width: 300,
        height: 40,
        borderRadius: 12,
        padding: "0 12px",
        background: dark ? "rgba(28,33,40,0.78)" : "rgba(255,255,255,0.86)",
        backdropFilter: "blur(14px)",
        WebkitBackdropFilter: "blur(14px)",
        boxShadow: dark
          ? "inset 0 0 0 0.5px rgba(255,255,255,0.12)"
          : "inset 0 0 0 0.5px rgba(0,0,0,0.10)",
        color: dark ? "rgba(232,234,236,0.5)" : "rgba(31,34,38,0.42)",
        fontSize: 13,
      }}
    >
      Message {TARGET.app}…
    </div>
  );
}

// ── Section eyebrow (studio convention). ─────────────────────────────────
function SectionEyebrow({ label, help }: { label: string; help?: string }) {
  return (
    <div className="mb-3 flex items-baseline justify-between border-b border-studio-edge pb-2">
      <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em] text-studio-ink">
        {label}
      </div>
      {help ? (
        <div className="font-mono text-[9px] uppercase tracking-[0.12em] text-studio-ink-faint">
          {help}
        </div>
      ) : null}
    </div>
  );
}

// ── Page ─────────────────────────────────────────────────────────────────
export default function CaptureTargetConfirmationStudy() {
  const primary = CONTEXTS[0]; // Graphite / light — the default demo tone
  const [reduceMotion, setReduceMotion] = useState(false);

  return (
    <StudioPage
      eyebrow="· Capture Target Confirmation · locks a screenshot destination"
      title="Target locked, not fired"
      help="Talkie destination token above the input · persistent badge in the stack"
    >
      <StyleTag />

      {/* ── 00 · Authorship + destination meaning ────────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="00 · Talkie destination token"
          help="Talkie emits · route travels · receiver closes · pointer attaches"
        />
        <div className="grid grid-cols-2 gap-6">
          <DesktopTile
            wall="light"
            tone={GRAPHITE}
            height={210}
            label="Light content · Talkie routes into ChatGPT"
          >
            <ConfirmationCard tone={GRAPHITE} animateRoute />
          </DesktopTile>
          <DesktopTile
            wall="dark"
            tone={PEARL}
            height={210}
            label="Dark content · same authorship and destination grammar"
          >
            <ConfirmationCard tone={PEARL} animateRoute />
          </DesktopTile>
        </div>
        <p className="mt-3 max-w-[720px] text-[11px] leading-relaxed text-studio-ink-faint">
          The app name remains the only copy, but it no longer carries the whole
          semantic burden. Talkie&apos;s white T tile authors the event; the amber-to-mint
          route makes the transfer direction visible; the receiving bracket says
          “this is the destination”; and the lower point attaches the token to the
          exact input that will receive the next capture.
        </p>
      </section>

      {/* ── 01 · Screen-aware contexts ─────────────────────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="01 · Screen-aware contexts"
          help="graphite over light · pearl over dark · sampled over mixed"
        />
        <div className="grid grid-cols-3 gap-6">
          {CONTEXTS.map((ctx) => (
            <DesktopTile
              key={ctx.wall}
              wall={ctx.wall}
              tone={ctx.tone}
              label={`${ctx.label} · ${ctx.caption}`}
            >
              <ConfirmationCard tone={ctx.tone} />
            </DesktopTile>
          ))}
        </div>
      </section>

      {/* ── 02 · Transient states ──────────────────────────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="02 · Transient states"
          help={`enter ${MOTION.enterMs}ms · dwell ${MOTION.dwellMs}ms · exit ${MOTION.exitMs}ms`}
        />
        <div className="mb-4 flex items-center gap-3">
          <ReplayHarness reduceMotion={reduceMotion} tone={primary.tone} />
          <label className="flex items-center gap-1.5 font-mono text-[9px] uppercase tracking-[0.16em] text-studio-ink-faint">
            <input
              type="checkbox"
              checked={reduceMotion}
              onChange={(e) => setReduceMotion(e.target.checked)}
            />
            Reduce Motion (opacity only)
          </label>
        </div>
        <div className="grid grid-cols-3 gap-6">
          <StateFrame
            label={`Enter · y ${MOTION.riseY}pt → 0 · opacity 0 → 1`}
            tone={primary.tone}
            phase="enter"
          />
          <StateFrame
            label="Dwell · settled · no pulse / scale / drift"
            tone={primary.tone}
            phase="dwell"
          />
          <StateFrame
            label="Exit · fade in place · never implies a send"
            tone={primary.tone}
            phase="exit"
          />
        </div>
      </section>

      {/* ── 03 · Placement above the input ─────────────────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="03 · Placement"
          help={`${GEO.gapFromInput}pt above the chosen input · attached, not overlaid`}
        />
        <div className="grid grid-cols-2 gap-6">
          <DesktopTile
            wall="light"
            tone={GRAPHITE}
            height={320}
            label="Above a composer · graphite"
          >
            <ConfirmationCard tone={GRAPHITE} />
          </DesktopTile>
          <DesktopTile
            wall="dark"
            tone={PEARL}
            height={320}
            label="Above a composer · pearl"
          >
            <ConfirmationCard tone={PEARL} />
          </DesktopTile>
        </div>
      </section>

      {/* ── 04 · Persistent locked badge (the sibling) ─────────────────── */}
      <section className="mb-12">
        <SectionEyebrow
          label="04 · Persistent locked badge"
          help="stays in the overlay stack · holds state · counts held captures"
        />
        <p className="mb-4 max-w-[640px] text-[12px] leading-relaxed text-studio-ink-faint">
          Not the destination token relocated — a separate, deliberately richer object. It
          keeps an app glyph and a mint count chip because it is the one that
          lingers: it holds the target and shows how many captures are queued
          against it until the user sends or clears them. The transient owns the
          routing event; the badge owns the accumulated state.
        </p>
        <div className="grid grid-cols-3 gap-6">
          {CONTEXTS.map((ctx) => (
            <DesktopTile
              key={ctx.wall}
              wall={ctx.wall}
              tone={ctx.tone}
              showInput={false}
              height={150}
              label={`${ctx.tone.name} · in the stack`}
            >
              <PersistentBadge tone={ctx.tone} count={ctx.wall === "mixed" ? 7 : 3} />
            </DesktopTile>
          ))}
        </div>
      </section>

      {/* ── 05 · Siblings side by side ─────────────────────────────────── */}
      <section>
        <SectionEyebrow
          label="05 · The pair, at rest"
          help="destination token (fades) vs badge (stays) — one target, two jobs"
        />
        <div
          className="flex items-center gap-10 rounded-md p-8"
          style={{ background: WALLPAPERS.light, border: "0.5px solid #DEDEDD" }}
        >
          <div className="flex flex-col items-center gap-2">
            <ConfirmationCard tone={GRAPHITE} />
            <span className="font-mono text-[9px] uppercase tracking-[0.16em] text-studio-ink-faint">
              transient destination token
            </span>
          </div>
          <span className="text-studio-ink-faint text-[18px]">·</span>
          <div className="flex flex-col items-center gap-2">
            <PersistentBadge tone={GRAPHITE} count={3} />
            <span className="font-mono text-[9px] uppercase tracking-[0.16em] text-studio-ink-faint">
              persistent badge
            </span>
          </div>
        </div>
      </section>
    </StudioPage>
  );
}

// ── State frame — one still of a transient phase on a light desktop. ─────
function StateFrame({
  label,
  tone,
  phase,
}: {
  label: string;
  tone: Tone;
  phase: "enter" | "dwell" | "exit";
}) {
  const style: React.CSSProperties =
    phase === "enter"
      ? { opacity: 0.4, transform: `translateY(${MOTION.riseY}px)` }
      : phase === "exit"
      ? { opacity: 0.32, transform: "translateY(0)" }
      : { opacity: 1, transform: "translateY(0)" };
  return (
    <div className="flex flex-col gap-2">
      <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        · {label}
      </div>
      <div
        className="flex items-center justify-center rounded-md"
        style={{ height: 120, background: WALLPAPERS.light, border: "0.5px solid #DEDEDD" }}
      >
        <div style={style}>
          <ConfirmationCard tone={tone} />
        </div>
      </div>
    </div>
  );
}

// ── Replay harness — runs the full enter → dwell → exit cycle on click. ──
function ReplayHarness({
  reduceMotion,
  tone,
}: {
  reduceMotion: boolean;
  tone: Tone;
}) {
  const [runKey, setRunKey] = useState(0);
  const [running, setRunning] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const play = () => {
    if (timer.current) clearTimeout(timer.current);
    setRunKey((k) => k + 1);
    setRunning(true);
    timer.current = setTimeout(() => setRunning(false), CYCLE_MS + 60);
  };

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  const animClass = reduceMotion ? "ctcycle-rm" : "ctcycle";

  return (
    <div className="flex items-center gap-4">
      <button
        onClick={play}
        className="rounded-[4px] border border-studio-edge bg-white px-3 py-1 font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-studio-ink transition-colors hover:border-studio-ink"
      >
        {running ? "Playing…" : "▶ Replay cycle"}
      </button>
      <div
        className="flex items-center justify-center rounded-md"
        style={{
          width: 320,
          height: 96,
          background: WALLPAPERS.light,
          border: "0.5px solid #DEDEDD",
        }}
      >
        {running ? (
          <div key={runKey} className={animClass}>
            <ConfirmationCard
              tone={tone}
              animateRoute={!reduceMotion}
            />
          </div>
        ) : (
          <span className="font-mono text-[9px] uppercase tracking-[0.16em] text-studio-ink-faint">
            press replay
          </span>
        )}
      </div>
    </div>
  );
}

// ── Keyframes — enter/dwell/exit as fractions of the full cycle. ─────────
function StyleTag() {
  const enterPct = ((MOTION.enterMs / CYCLE_MS) * 100).toFixed(2);
  const exitPct = (((MOTION.enterMs + MOTION.dwellMs) / CYCLE_MS) * 100).toFixed(2);
  return (
    <style>{`
      @keyframes ctcycle-kf {
        0%          { opacity: 0; transform: translateY(${MOTION.riseY}px); }
        ${enterPct}% { opacity: 1; transform: translateY(0); }
        ${exitPct}% { opacity: 1; transform: translateY(0); }
        100%        { opacity: 0; transform: translateY(0); }
      }
      @keyframes ctcycle-rm-kf {
        0%          { opacity: 0; }
        ${enterPct}% { opacity: 1; }
        ${exitPct}% { opacity: 1; }
        100%        { opacity: 0; }
      }
      .ctcycle {
        animation: ctcycle-kf ${CYCLE_MS}ms cubic-bezier(0.22, 0.61, 0.36, 1) forwards;
      }
      .ctcycle-rm {
        animation: ctcycle-rm-kf ${CYCLE_MS}ms ease-in-out forwards;
      }
      @keyframes ct-route-signal-kf {
        0%   { left: 0; background: ${TALKIE_AMBER}; }
        76%  { background: ${TALKIE_AMBER}; }
        100% { left: 14.5px; background: rgb(79,212,176); }
      }
      @keyframes ct-receiver-kf {
        0%, 46% { opacity: 0; transform: scaleY(0.45); }
        100%    { opacity: 1; transform: scaleY(1); }
      }
      @keyframes ct-destination-dot-kf {
        0%, 58% { opacity: 0; transform: translateX(-50%) scale(0.5); }
        100%    { opacity: 1; transform: translateX(-50%) scale(1); }
      }
      .ct-route-signal {
        animation: ct-route-signal-kf 460ms cubic-bezier(0.22, 0.72, 0.24, 1) forwards;
      }
      .ct-receiver {
        transform-origin: center;
        animation: ct-receiver-kf 460ms cubic-bezier(0.22, 0.72, 0.24, 1) forwards;
      }
      .ct-destination-dot {
        animation: ct-destination-dot-kf 460ms cubic-bezier(0.22, 0.72, 0.24, 1) forwards;
      }
      @media (prefers-reduced-motion: reduce) {
        .ct-route-signal, .ct-receiver, .ct-destination-dot { animation: none; }
      }
    `}</style>
  );
}

// ── Color helpers. ───────────────────────────────────────────────────────
function withOpacity(rgb: string, opacity: number): string {
  // rgb(…) → rgba(…, opacity)
  const nums = rgb.match(/[\d.]+/g);
  if (!nums || nums.length < 3) return rgb;
  return `rgba(${nums[0]}, ${nums[1]}, ${nums[2]}, ${opacity})`;
}

function withAlphaScale(rgba: string, scale: number): string {
  const nums = rgba.match(/[\d.]+/g);
  if (!nums) return rgba;
  if (nums.length === 4) {
    return `rgba(${nums[0]}, ${nums[1]}, ${nums[2]}, ${(+nums[3] * scale).toFixed(3)})`;
  }
  return `rgba(${nums[0]}, ${nums[1]}, ${nums[2]}, ${scale})`;
}
