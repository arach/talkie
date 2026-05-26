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
  HOMESCREEN_FIRST_ROW_TOP,
  HOMESCREEN_ROW_HEIGHT,
  AMBER,
  INK,
  INK_FAINT,
  INK_FAINTER,
  useTimeline,
  smoothstep,
  lerp,
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
        The chrome is gone. No cancel, no REC chip, no mic/engine
        whisper, no STOP pill — the surface is the wave, full stop.
        The glass disc is a stronger pour than before so the
        transparency stays felt but never leaks through to homescreen
        content or stage edges behind it. Stop and cancel live on the
        keyboard (<code>⌘.</code> / <code>esc</code>) in this
        treatment; the surface refuses to compete with what it&rsquo;s
        recording. Birth re-runs every 7s: blur 22 → 0, scale 0.93 →
        1, stroke draws in left → right.
      </Note>

      <Stage tall>
        <SettleHomescreen />
      </Stage>
      <Note>
        Settle: trace decays AND fades to zero before the transcript
        shows so text never reads against an ugly baseline. The line
        emerges as italic display serif inside what was the card, then
        the card itself compacts down into the placeholder row in the
        memos list. The amber dot stays as the row leader. Loop ~11s.
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
  return (
    <div
      className="relative flex items-center justify-center"
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
    </div>
  );
}

// ── Settle stage — wave → transcript → row ──────────────────────────

function SettleHomescreen() {
  const progress = useTimeline(11000);

  const decay = smoothstep(progress, 0.10, 0.22);
  const waveOpacity = 1 - smoothstep(progress, 0.14, 0.26);
  const transcript = smoothstep(progress, 0.30, 0.56);
  const land = smoothstep(progress, 0.56, 0.78);
  const filled = smoothstep(progress, 0.74, 0.92);

  const cardScale = 1 - land * 0.58;
  const cardOffsetY = land * 24;
  const cardOpacity = 1 - filled * 0.95;

  return (
    <Homescreen highlightSlot>
      <div
        className="absolute left-1/2"
        style={{
          top: HOMESCREEN_OVERLAY_TOP,
          transform: `translate(-50%, ${cardOffsetY}px) scale(${cardScale})`,
          transformOrigin: "center top",
          opacity: cardOpacity,
          width: CARD_W,
        }}
      >
        <div
          className="relative flex items-center justify-center"
          style={{
            padding: "44px 56px",
            borderRadius: CARD_RADIUS,
            background: GLASS_BG,
            backdropFilter: GLASS_BLUR,
            WebkitBackdropFilter: GLASS_BLUR,
            boxShadow: GLASS_SHADOW,
          }}
        >
          <div style={{ width: CARD_W - 112, height: 96, position: "relative" }}>
            <div className="absolute inset-0" style={{ opacity: waveOpacity }}>
              <LiveFlourish
                width={CARD_W - 112}
                height={96}
                strokeWidth={2.4}
                ampBase={lerp(0.5, 0.04, decay)}
                ampVariance={lerp(0.25, 0.0, decay)}
              />
            </div>
            <div
              className="pointer-events-none absolute inset-0 flex items-center justify-center px-3 text-center"
              style={{
                opacity: transcript,
                transform: `translateY(${(1 - transcript) * 4}px)`,
              }}
            >
              <span
                className="font-display"
                style={{
                  color: INK,
                  fontSize: 17,
                  lineHeight: 1.42,
                  fontStyle: "italic",
                  fontWeight: 400,
                  maxWidth: "96%",
                }}
              >
                &ldquo;Q1 plan recap with Sam — agreed on the Tuesday ship date.&rdquo;
              </span>
            </div>
          </div>
        </div>
      </div>

      <FillReveal filled={filled} />
    </Homescreen>
  );
}

function FillReveal({ filled }: { filled: number }) {
  if (filled <= 0.01) return null;
  return (
    <div
      className="pointer-events-none absolute left-[18px] right-[18px] flex items-center gap-3 py-2"
      style={{
        top: HOMESCREEN_FIRST_ROW_TOP,
        height: HOMESCREEN_ROW_HEIGHT,
        opacity: filled,
        transition: "opacity 160ms ease-out",
      }}
    >
      <span
        className="block h-1.5 w-1.5 rounded-full"
        style={{ background: AMBER }}
      />
      <span
        className="flex-1 truncate font-display text-[13px]"
        style={{ color: INK }}
      >
        Q1 plan recap with Sam
      </span>
      <span
        className="font-mono text-[10px] tabular-nums"
        style={{ color: INK_FAINT }}
      >
        0:14
      </span>
      <span
        className="font-mono text-[10px] uppercase tracking-[0.18em]"
        style={{ color: INK_FAINTER }}
      >
        just now
      </span>
    </div>
  );
}
