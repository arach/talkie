"use client";

/**
 * Mac Capture HUD — top-center floating chord menu for Hyper+S / Hyper+R.
 *
 * Why this study exists
 * ---------------------
 * The shipping HUD (apps/macos/Talkie/Services/Capture/CaptureHUDPanel.swift)
 * is one tone — a constant near-black glass surface with white text. On a
 * light desktop wallpaper it lands hard: a heavy dark slab over an airy
 * background, no relationship to the canvas behind it. We can do better.
 *
 * The instrument-bay vocabulary (top/bottom strip gradient, graticule,
 * warm metal accent against a cool case, bezel highlight) reads as a piece
 * of hardware that belongs on the screen rather than a generic blur panel.
 * The 9-scheme ladder gives us a path to ship LIGHT variants (PORCELAIN /
 * PEARL / BONE) that actually breathe over a white desktop, plus the
 * DARK siblings (AMBER / CARBON) for dark wallpapers.
 *
 * Anatomy (one rounded surface, hardware feel):
 *
 *   ┌─ TOP STRIP (gradient) ──────────────────────────────────────┐
 *   │  ● Screenshot              · region · screen · window        │  ← Row 1
 *   ├─ GRATICULE FIELD (3 cells) ──────────────────────────────────┤
 *   │   [⌘]            [⌘]            [⌘]                          │
 *   │    A              S              D                           │  ← Row 2
 *   │  Region        Screen         Window                         │
 *   ├─ BOTTOM STRIP (gradient mirror) ─────────────────────────────┤
 *   │  ⇥ Mode    C Camera   N Save    F Paste    W Tray            │  ← Row 3
 *   └──────────────────────────────────────────────────────────────┘
 *
 * Scheme reads
 * ------------
 * Every color references `var(--scheme-*)` so the SchemeCard in the
 * route can swap the entire treatment with no per-scheme branching.
 */

import React, { useState } from "react";

export type CaptureHUDMode = "screenshot" | "video";

interface MacCaptureHUDProps {
  /** "screenshot" (default) or "video" — controls REC dot and tint. */
  mode?: CaptureHUDMode;
  /** Tray item count surfaced in the W cell label. */
  trayCount?: number;
  /** When false, hide F (Paste) and W (Tray) extras. */
  showTray?: boolean;
  /** When false, hide N (Save Selection) extra. */
  showSelection?: boolean;
}

const W = 360;

export function MacCaptureHUD({
  mode = "screenshot",
  trayCount = 4,
  showTray = true,
  showSelection = true,
}: MacCaptureHUDProps) {
  const isVideo = mode === "video";
  const [hover, setHover] = useState<string | null>(null);

  return (
    <div
      className="font-mono"
      style={{
        width: W,
        borderRadius: 14,
        overflow: "hidden",
        background: "var(--scheme-bg)",
        // Outer shadow: HUDs sit on a desktop; give them weight so they
        // detach from whatever wallpaper is behind, light OR dark.
        boxShadow: `
          0 1px 0 var(--scheme-bezel-highlight) inset,
          0 -1px 0 var(--scheme-bezel-shadow) inset,
          0 0 0 0.5px var(--scheme-edge-strong),
          0 18px 44px -10px rgba(0,0,0,0.32),
          0 4px 14px -2px rgba(0,0,0,0.18)
        `,
        position: "relative",
      }}
    >
      {/* TOP STRIP — gradient + graticule overlay */}
      <TopStrip isVideo={isVideo} />

      {/* PRIMARY ACTIONS — 3 cells */}
      <div
        className="grid grid-cols-3"
        style={{
          padding: "10px 10px 12px 10px",
          gap: 8,
          // Graticule wash behind the cells.
          backgroundImage: `
            linear-gradient(var(--scheme-graticule) 1px, transparent 1px),
            linear-gradient(90deg, var(--scheme-graticule) 1px, transparent 1px)
          `,
          backgroundSize: "12px 12px",
          backgroundPosition: "center",
        }}
      >
        <PrimaryCell
          chord="A"
          icon={IconCrop}
          label="Region"
          isHover={hover === "A"}
          onHover={(v) => setHover(v ? "A" : null)}
          isVideo={isVideo}
        />
        <PrimaryCell
          chord="S"
          icon={IconDisplay}
          label="Screen"
          isHover={hover === "S"}
          onHover={(v) => setHover(v ? "S" : null)}
          isVideo={isVideo}
        />
        <PrimaryCell
          chord="D"
          icon={IconWindow}
          label="Window"
          isHover={hover === "D"}
          onHover={(v) => setHover(v ? "D" : null)}
          isVideo={isVideo}
        />
      </div>

      {/* BOTTOM STRIP — gradient mirror + extras row */}
      <BottomStrip>
        <ExtraCell chord="⇥" label="Mode" tone="ink" />
        <ExtraCell chord="C" label="Camera" tone="accent" />
        {showSelection ? <ExtraCell chord="N" label="Save" tone="ink" /> : null}
        {showTray ? <ExtraCell chord="F" label="Paste" tone="ink" /> : null}
        {showTray ? (
          <ExtraCell chord="W" label={`Tray ${trayCount}`} tone="ink" />
        ) : null}
      </BottomStrip>

      {/* INNER BEZEL — subtle inner highlight/shadow so the panel
          feels like a milled part rather than a flat sticker. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          borderRadius: 14,
          boxShadow: `
            inset 0 0.5px 0 var(--scheme-bezel-highlight),
            inset 0 -0.5px 0 var(--scheme-bezel-shadow)
          `,
        }}
      />
    </div>
  );
}

// ───────────────────────────────────────────────────────────────────────
// Top strip — mode badge.

function TopStrip({ isVideo }: { isVideo: boolean }) {
  return (
    <div
      className="flex items-center px-3"
      style={{
        height: 26,
        background: "var(--scheme-strip-top)",
        borderBottom: "0.5px solid var(--scheme-edge)",
      }}
    >
      <div className="flex items-center gap-1.5">
        {isVideo ? (
          <>
            <span
              aria-hidden
              className="inline-block h-[7px] w-[7px] animate-[hudpulse_1.4s_ease-in-out_infinite] rounded-full"
              style={{
                background: "var(--scheme-rec)",
                boxShadow: "0 0 6px var(--scheme-rec-glow)",
              }}
            />
            <span
              className="text-[9px] font-semibold uppercase tracking-[0.18em]"
              style={{ color: "var(--scheme-rec)" }}
            >
              Video · Record
            </span>
          </>
        ) : (
          <>
            <span
              aria-hidden
              className="inline-block h-[7px] w-[7px] rounded-full"
              style={{
                background: "var(--scheme-accent)",
                boxShadow: "0 0 6px var(--scheme-accent-glow)",
              }}
            />
            <span
              className="text-[9px] font-semibold uppercase tracking-[0.18em]"
              style={{ color: "var(--scheme-accent)" }}
            >
              Screenshot
            </span>
          </>
        )}
      </div>
      <span
        className="ml-auto text-[8.5px] uppercase tracking-[0.22em]"
        style={{ color: "var(--scheme-ink-faint)" }}
      >
        ⎋ dismiss
      </span>
      <style jsx>{`
        @keyframes hudpulse {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0.35; }
        }
      `}</style>
    </div>
  );
}

// ───────────────────────────────────────────────────────────────────────
// Primary cell — A / S / D.

function PrimaryCell({
  chord,
  icon: Icon,
  label,
  isHover,
  onHover,
  isVideo,
}: {
  chord: string;
  icon: (props: { size: number; color: string }) => React.ReactElement;
  label: string;
  isHover: boolean;
  onHover: (v: boolean) => void;
  isVideo: boolean;
}) {
  return (
    <button
      type="button"
      onMouseEnter={() => onHover(true)}
      onMouseLeave={() => onHover(false)}
      className="group relative flex flex-col items-center justify-center"
      style={{
        padding: "10px 6px 9px 6px",
        borderRadius: 8,
        background: isHover
          ? "var(--scheme-details-bg)"
          : "color-mix(in srgb, var(--scheme-bg) 50%, transparent)",
        border: `0.5px solid ${
          isHover ? "var(--scheme-edge-strong)" : "var(--scheme-edge)"
        }`,
        boxShadow: isHover
          ? `inset 0 0.5px 0 var(--scheme-bezel-highlight),
             0 1px 0 var(--scheme-bezel-shadow)`
          : "none",
        transition: "background 120ms ease-out, border-color 120ms ease-out",
        cursor: "pointer",
      }}
    >
      {/* Icon */}
      <Icon
        size={18}
        color={
          isHover
            ? isVideo
              ? "var(--scheme-rec)"
              : "var(--scheme-accent)"
            : "var(--scheme-ink)"
        }
      />

      {/* Key chip */}
      <div
        className="mt-2 flex items-center justify-center text-[10.5px] font-bold tabular-nums"
        style={{
          width: 22,
          height: 18,
          borderRadius: 4,
          background: "var(--scheme-details-bg)",
          border: "0.5px solid var(--scheme-edge-strong)",
          color: "var(--scheme-ink)",
          boxShadow: `
            inset 0 0.5px 0 var(--scheme-bezel-highlight),
            0 0.5px 0 var(--scheme-bezel-shadow)
          `,
        }}
      >
        {chord}
      </div>

      {/* Label */}
      <span
        className="mt-1.5 text-[9.5px] font-medium uppercase tracking-[0.14em]"
        style={{ color: "var(--scheme-ink-faint)" }}
      >
        {label}
      </span>
    </button>
  );
}

// ───────────────────────────────────────────────────────────────────────
// Bottom strip — extras (Tab / C / N / F / W).

function BottomStrip({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="flex items-center px-2"
      style={{
        height: 28,
        background: "var(--scheme-strip-bottom)",
        borderTop: "0.5px solid var(--scheme-edge)",
        gap: 2,
      }}
    >
      {children}
    </div>
  );
}

function ExtraCell({
  chord,
  label,
  tone,
}: {
  chord: string;
  label: string;
  tone: "ink" | "accent";
}) {
  return (
    <button
      type="button"
      className="flex flex-1 items-center justify-center gap-1.5 py-1"
      style={{
        borderRadius: 4,
        cursor: "pointer",
      }}
    >
      <span
        className="flex items-center justify-center text-[9.5px] font-bold tabular-nums"
        style={{
          minWidth: 14,
          height: 14,
          padding: chord.length > 1 ? "0 3px" : 0,
          borderRadius: 3,
          background: "var(--scheme-details-bg)",
          border: "0.5px solid var(--scheme-edge-strong)",
          color: tone === "accent" ? "var(--scheme-accent)" : "var(--scheme-ink)",
        }}
      >
        {chord}
      </span>
      <span
        className="truncate text-[9px] font-medium uppercase tracking-[0.10em]"
        style={{ color: "var(--scheme-ink-faint)" }}
      >
        {label}
      </span>
    </button>
  );
}

// ───────────────────────────────────────────────────────────────────────
// Icons — inline SVG so they react to currentColor / our scheme vars.

function IconCrop({ size, color }: { size: number; color: string }) {
  // crop marks — two ⌐ brackets
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none">
      <path
        d="M5 1.5v11.5h11.5"
        stroke={color}
        strokeWidth="1.2"
        strokeLinecap="square"
      />
      <path
        d="M1.5 5h11.5v11.5"
        stroke={color}
        strokeWidth="1.2"
        strokeOpacity={0.5}
        strokeLinecap="square"
      />
    </svg>
  );
}

function IconDisplay({ size, color }: { size: number; color: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none">
      <rect
        x="1.5"
        y="3"
        width="15"
        height="10"
        rx="1.2"
        stroke={color}
        strokeWidth="1.2"
      />
      <path d="M6 16h6M9 13v3" stroke={color} strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  );
}

function IconWindow({ size, color }: { size: number; color: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" fill="none">
      <rect
        x="2"
        y="3"
        width="14"
        height="12"
        rx="1.4"
        stroke={color}
        strokeWidth="1.2"
      />
      <path d="M2 6.5h14" stroke={color} strokeWidth="1.2" />
      <circle cx="4.4" cy="5" r="0.7" fill={color} />
      <circle cx="6.6" cy="5" r="0.7" fill={color} opacity={0.55} />
      <circle cx="8.8" cy="5" r="0.7" fill={color} opacity={0.35} />
    </svg>
  );
}
