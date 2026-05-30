"use client";

/**
 * Light-touch instrument — pure wave on stronger glass.
 *
 * The chrome is gone. No cancel, no REC chip, no mic/engine whisper,
 * no STOP pill. Just a single glass disc with the wave living on it.
 * The disc is more substantial than the previous draft — heavier
 * blur, more opacity — so the transparency stops leaking through to
 * the homescreen content and dashed Stage edges behind it. Stop +
 * cancel live on the keyboard (⌘.) in this treatment; the surface
 * itself stays the wave.
 */

import React from "react";
import {
  TreatmentSection,
  Stage,
  Note,
  Homescreen,
  HOMESCREEN_OVERLAY_TOP,
  INK,
  INK_FAINT,
  INK_FAINTER,
  LiveFlourish,
  BirthAnimator,
} from "./shared";

const CARD_W = 560;
const CARD_RADIUS = 22;

// Glass recipe — a heavier pour and a much deeper blur than the
// previous draft so the disc reads as its own surface. Stays
// translucent enough to feel glass; just no longer transparent in
// the wrong places.
const GLASS_BG =
  "linear-gradient(180deg, rgba(255,255,255,0.82) 0%, rgba(255,255,255,0.68) 50%, rgba(255,255,255,0.55) 100%)";
const GLASS_BLUR = "blur(64px) saturate(1.6)";
const GLASS_SHADOW =
  "0 18px 48px rgba(0,0,0,0.12), inset 0 0.5px 0 rgba(255,255,255,0.90)";

export function LightInstrument() {
  return (
    <TreatmentSection
      eyebrow="· Light Instrument · pure wave"
      title="Just the wave, on glass"
      hint="no chrome · stronger pour · keyboard for stop"
    >
      <Stage>
        <Homescreen>
          <DiscMount>
            <BirthAnimator>
              <FloatingDisc />
            </BirthAnimator>
          </DiscMount>
        </Homescreen>
      </Stage>
      <Note>
        Birth re-runs every 7s: blur 22 → 0, scale 0.93 → 1, stroke
        draws in left → right. Decorations rest near-invisible (REC
        timer + close top-right, STOP bottom-right) and sharpen on
        hover; the resting state is the wave, full stop. ⌘. and esc
        still drive stop / cancel from the keyboard.
      </Note>
    </TreatmentSection>
  );
}

// ── Hero composition — the wave, alone ──────────────────────────────

/**
 * Mounts the disc absolutely inside the Homescreen and centers it
 * horizontally at the canonical overlay slot. Lives OUTSIDE the
 * BirthAnimator so the birth wrapper's transform doesn't capture the
 * positioning context — without this, the disc anchors to the
 * BirthAnimator's natural block position (which sits below the memo
 * list) and ends up floating in the page's note text region.
 */
function DiscMount({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="absolute left-1/2"
      style={{
        top: HOMESCREEN_OVERLAY_TOP,
        transform: "translateX(-50%)",
        width: CARD_W,
      }}
    >
      {children}
    </div>
  );
}

function FloatingDisc() {
  // Corner decorations rest near-invisible (0.06) and sharpen on hover.
  // Light-instrument's contract is "the surface is the wave" — even the
  // close + stop affordances live like marginalia, barely felt until
  // the cursor lands on them.
  const restOpacity = 0.06;

  return (
    <div
      className="group relative flex items-center justify-center"
      style={{
        padding: "44px 56px",
        borderRadius: CARD_RADIUS,
        background: GLASS_BG,
        backdropFilter: GLASS_BLUR,
        WebkitBackdropFilter: GLASS_BLUR,
        boxShadow: GLASS_SHADOW,
      }}
    >
      <div style={{ width: CARD_W - 112, height: 96 }}>
        <LiveFlourish
          width={CARD_W - 112}
          height={96}
          strokeWidth={2.4}
          ampBase={0.5}
          ampVariance={0.25}
        />
      </div>

      {/* Top-right: timer + REC label + close. Hover-reveal. */}
      <div
        className="absolute right-4 top-3 flex items-center gap-2 transition-opacity duration-200 group-hover:opacity-100"
        style={{ opacity: restOpacity }}
      >
        <DiscDetails />
        <DiscClose />
      </div>

      {/* Bottom-right: STOP. Hover-reveal. */}
      <div
        className="absolute bottom-3 right-4 transition-opacity duration-200 group-hover:opacity-100"
        style={{ opacity: restOpacity }}
      >
        <DiscStop />
      </div>
    </div>
  );
}

function DiscDetails() {
  return (
    <div
      className="flex items-baseline gap-2 font-mono text-[9px] font-semibold uppercase tracking-[0.22em]"
      style={{ color: INK_FAINT }}
    >
      <span
        className="inline-block h-1.5 w-1.5 rounded-full"
        style={{ background: "#C03A2A" }}
      />
      <span style={{ color: INK }}>REC</span>
      <span style={{ color: INK_FAINTER }}>·</span>
      <span className="tabular-nums" style={{ color: INK }}>
        0:14
      </span>
    </div>
  );
}

function DiscClose() {
  return (
    <button
      type="button"
      aria-label="Cancel recording"
      className="flex h-5 w-5 items-center justify-center rounded-full border transition-colors"
      style={{
        borderColor: "rgba(35,36,35,0.20)",
        color: INK_FAINT,
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.borderColor = INK;
        e.currentTarget.style.color = INK;
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.borderColor = "rgba(35,36,35,0.20)";
        e.currentTarget.style.color = INK_FAINT;
      }}
    >
      <span aria-hidden className="text-[11px] leading-none">
        ×
      </span>
    </button>
  );
}

function DiscStop() {
  return (
    <button
      type="button"
      aria-label="Stop recording"
      className="flex items-center gap-1.5 rounded-full px-2.5 py-1 font-mono text-[9px] font-semibold uppercase tracking-[0.20em]"
      style={{
        background: "#C03A2A",
        color: "#FFF7F5",
        boxShadow:
          "0 1px 0 rgba(255,255,255,0.18) inset, 0 2px 6px rgba(192,58,42,0.22)",
      }}
    >
      <span
        aria-hidden
        className="inline-block h-1.5 w-1.5"
        style={{ background: "#FFF7F5" }}
      />
      <span>STOP</span>
      <span style={{ color: "rgba(255,247,245,0.65)" }}>⌘.</span>
    </button>
  );
}

