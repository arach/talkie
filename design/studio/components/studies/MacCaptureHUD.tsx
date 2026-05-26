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

export type CaptureChord = "A" | "S" | "D";

interface MacCaptureHUDProps {
  /** "screenshot" (default) or "video" — controls REC dot and tint. */
  mode?: CaptureHUDMode;
  /** Tray item count surfaced in the W cell label. */
  trayCount?: number;
  /** When false, hide F (Paste) and W (Tray) extras. */
  showTray?: boolean;
  /** When false, hide N (Save Selection) extra. */
  showSelection?: boolean;
  /** Currently active mode (Region/Screen/Window). When provided, the
   *  matching cell renders in its `active` state — accent-tinted border,
   *  brighter background, accent key chip — so the HUD reads as a
   *  picker (REGION preselected) rather than three stateless triggers.
   *  Default "A" (Region). Pass `null` to opt out and revert to the
   *  hover-only behaviour the original chord launcher had. */
  activeChord?: CaptureChord | null;
  /** Wires up the Screenshot ↔ Video tabs at the top of the HUD. When
   *  provided, the tabs are clickable; without it they render visually
   *  but no-op. The default ToggleBar above the HUD remains as a
   *  fallback when only one HUD is on screen, but each HUD now owns its
   *  own mode-switch surface so single-shot demos work too. */
  onModeChange?: (mode: CaptureHUDMode) => void;
}

const W = 360;

export function MacCaptureHUD({
  mode = "screenshot",
  trayCount = 4,
  showTray = true,
  showSelection = true,
  activeChord = "A",
  onModeChange,
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
      <TopStrip
        isVideo={isVideo}
        showCommitCue={activeChord !== null}
        onModeChange={onModeChange}
      />

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
          isActive={activeChord === "A"}
          onHover={(v) => setHover(v ? "A" : null)}
          isVideo={isVideo}
        />
        <PrimaryCell
          chord="S"
          icon={IconDisplay}
          label="Screen"
          isHover={hover === "S"}
          isActive={activeChord === "S"}
          onHover={(v) => setHover(v ? "S" : null)}
          isVideo={isVideo}
        />
        <PrimaryCell
          chord="D"
          icon={IconWindow}
          label="Window"
          isHover={hover === "D"}
          isActive={activeChord === "D"}
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

function TopStrip({
  isVideo,
  showCommitCue,
  onModeChange,
}: {
  isVideo: boolean;
  /** When true (i.e. the HUD has a preselected mode), the right
   *  caption shows `↵ capture · ⎋ dismiss` so the user knows Enter
   *  commits the active cell. When false, just the dismiss cue. */
  showCommitCue: boolean;
  /** Wires the tab clicks. When omitted the tabs render but no-op. */
  onModeChange?: (mode: CaptureHUDMode) => void;
}) {
  return (
    <div
      className="flex items-center px-2.5"
      style={{
        height: 26,
        background: "var(--scheme-strip-top)",
        borderBottom: "0.5px solid var(--scheme-edge)",
      }}
    >
      <div className="flex items-center gap-1">
        <ModeTab
          kind="screenshot"
          active={!isVideo}
          onClick={() => onModeChange?.("screenshot")}
        />
        <ModeTab
          kind="video"
          active={isVideo}
          onClick={() => onModeChange?.("video")}
        />
      </div>
      <span
        className="ml-auto text-[8.5px] uppercase tracking-[0.22em]"
        style={{ color: "var(--scheme-ink-faint)" }}
      >
        {showCommitCue ? "↵ capture · ⎋ dismiss" : "⎋ dismiss"}
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

/**
 * One of the two top-strip tabs. Active = lit dot + accent text, sits
 * on a faint accent-tinted background so the selection reads at a
 * glance. Inactive = hollow dot + faint text, clickable to switch.
 * Video's dot pulses when active to echo the live REC feel.
 */
function ModeTab({
  kind,
  active,
  onClick,
}: {
  kind: CaptureHUDMode;
  active: boolean;
  onClick: () => void;
}) {
  const isVideo = kind === "video";
  const accent = isVideo ? "var(--scheme-rec)" : "var(--scheme-accent)";
  const accentGlow = isVideo
    ? "var(--scheme-rec-glow)"
    : "var(--scheme-accent-glow)";
  const label = isVideo ? "Video · Record" : "Screenshot";
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex items-center gap-1.5 rounded transition-colors"
      style={{
        padding: "3px 7px",
        background: active
          ? `color-mix(in srgb, ${accent} 14%, transparent)`
          : "transparent",
        border: active
          ? `0.5px solid color-mix(in srgb, ${accent} 45%, var(--scheme-edge))`
          : "0.5px solid transparent",
        cursor: "pointer",
      }}
    >
      <span
        aria-hidden
        className={
          active && isVideo
            ? "inline-block h-[6px] w-[6px] animate-[hudpulse_1.4s_ease-in-out_infinite] rounded-full"
            : "inline-block h-[6px] w-[6px] rounded-full"
        }
        style={
          active
            ? {
                background: accent,
                boxShadow: `0 0 5px ${accentGlow}`,
              }
            : {
                background: "transparent",
                border: "0.5px solid var(--scheme-ink-faint)",
              }
        }
      />
      <span
        className="text-[9px] font-semibold uppercase tracking-[0.18em]"
        style={{ color: active ? accent : "var(--scheme-ink-faint)" }}
      >
        {label}
      </span>
    </button>
  );
}

// ───────────────────────────────────────────────────────────────────────
// Primary cell — A / S / D.

function PrimaryCell({
  chord,
  icon: Icon,
  label,
  isHover,
  isActive,
  onHover,
  isVideo,
}: {
  chord: string;
  icon: (props: { size: number; color: string }) => React.ReactElement;
  label: string;
  isHover: boolean;
  isActive: boolean;
  onHover: (v: boolean) => void;
  isVideo: boolean;
}) {
  // Lit color cascades the same way the HUD's top-strip dot does: video
  // mode uses the rec/red token, screenshot uses accent (amber/scheme).
  const lit = isVideo ? "var(--scheme-rec)" : "var(--scheme-accent)";
  const litGlow = isVideo ? "var(--scheme-rec-glow)" : "var(--scheme-accent-glow)";

  // Active beats hover for icon color, but hover still adds the
  // glass-lift so the user feels "I can switch to this one too."
  const iconColor = isActive || isHover ? lit : "var(--scheme-ink)";

  return (
    <button
      type="button"
      onMouseEnter={() => onHover(true)}
      onMouseLeave={() => onHover(false)}
      className="group relative flex flex-col items-center justify-center"
      style={{
        padding: "10px 6px 9px 6px",
        borderRadius: 8,
        background: isActive
          ? `color-mix(in srgb, ${lit} 14%, var(--scheme-details-bg))`
          : isHover
            ? "var(--scheme-details-bg)"
            : "color-mix(in srgb, var(--scheme-bg) 50%, transparent)",
        border: `0.5px solid ${
          isActive
            ? `color-mix(in srgb, ${lit} 60%, var(--scheme-edge-strong))`
            : isHover
              ? "var(--scheme-edge-strong)"
              : "var(--scheme-edge)"
        }`,
        boxShadow: isActive
          ? `inset 0 0.5px 0 var(--scheme-bezel-highlight),
             0 1px 0 var(--scheme-bezel-shadow),
             0 0 0 0.5px ${lit}33,
             0 0 12px -2px ${litGlow}`
          : isHover
            ? `inset 0 0.5px 0 var(--scheme-bezel-highlight),
               0 1px 0 var(--scheme-bezel-shadow)`
            : "none",
        transition: "background 120ms ease-out, border-color 120ms ease-out, box-shadow 160ms ease-out",
        cursor: "pointer",
      }}
    >
      {/* Icon */}
      <Icon size={18} color={iconColor} />

      {/* Key chip — when active, the chip itself lights up so the
          keyboard feedback loop is obvious: "A is what's armed." */}
      <div
        className="mt-2 flex items-center justify-center text-[10.5px] font-bold tabular-nums"
        style={{
          width: 22,
          height: 18,
          borderRadius: 4,
          background: isActive
            ? `color-mix(in srgb, ${lit} 22%, var(--scheme-details-bg))`
            : "var(--scheme-details-bg)",
          border: `0.5px solid ${
            isActive
              ? `color-mix(in srgb, ${lit} 70%, var(--scheme-edge-strong))`
              : "var(--scheme-edge-strong)"
          }`,
          color: isActive ? lit : "var(--scheme-ink)",
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
        style={{
          color: isActive ? lit : "var(--scheme-ink-faint)",
        }}
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
