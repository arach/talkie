"use client";

/**
 * Mac Capture · freeze overlay — the missing step before the crop.
 *
 * Today (ScreenCaptureOverlay.swift) the region drag runs against the
 * LIVE desktop: windows can still scroll, animations still play, and
 * the user chases a moving target. CleanShot · Shottr · Lightshot all
 * snapshot the desktop at overlay-show time and let the user drag
 * against the frozen image. This study mocks that behavior — a faked
 * desktop with two windows, a frozen-overlay backdrop, and the same
 * region-drag vocabulary the Swift overlay already paints (dim
 * surround, filled rect, 1px white border, crosshair, dimensions
 * label). The HUD pill at the top shows what's active.
 *
 * Two compositions:
 *   1. `drag-in-progress`  — user mid-crop, dimensions visible
 *   2. `armed-ready`       — overlay just mounted, no crop yet
 */

import React from "react";

export type FreezeState = "drag-in-progress" | "armed-ready";

interface MacCaptureFreezeProps {
  state?: FreezeState;
  /** When true, paints a subtle "FROZEN" hint to make the snapshot
   *  semantic visible — useful while reviewing the design, would not
   *  ship in the actual overlay. */
  showFrozenLabel?: boolean;
}

const STAGE_W = 880;
const STAGE_H = 540;

export function MacCaptureFreeze({
  state = "drag-in-progress",
  showFrozenLabel = true,
}: MacCaptureFreezeProps) {
  return (
    <div
      className="relative overflow-hidden"
      style={{
        width: STAGE_W,
        height: STAGE_H,
        borderRadius: 12,
        border: "0.5px solid rgba(35,36,35,0.18)",
        boxShadow:
          "0 1px 0 rgba(0,0,0,0.04), 0 18px 38px rgba(0,0,0,0.08)",
        // Faux desktop wallpaper — a light cool gradient typical of
        // macOS Sonoma. The freeze overlay sits ON TOP of this.
        background:
          "linear-gradient(135deg, #E8EAF0 0%, #D6DBE5 45%, #C6CBD7 100%)",
      }}
    >
      {/* Fake macOS menu bar so the "desktop" reads */}
      <FakeMenuBar />

      {/* Two fake windows on the desktop — they're what the user is
          trying to crop around. */}
      <FakeWindow
        x={48}
        y={64}
        w={420}
        h={300}
        title="Documents — q1-plan.md"
      />
      <FakeWindow
        x={500}
        y={150}
        w={320}
        h={220}
        title="Mail — Lina · re: Friday demo"
      />

      {/* Freeze backdrop — a near-transparent ink wash that signals
          "the desktop is now a snapshot". When a crop is in progress,
          this is replaced by the cropped-rect cutout treatment. */}
      {state === "armed-ready" && <FrozenBackdrop />}

      {/* The region-drag crop, when in progress. */}
      {state === "drag-in-progress" && (
        <RegionCrop x={210} y={140} w={460} h={260} />
      )}

      {/* Caption — the affordance vocabulary at the foot of the
          screen, the way CleanShot/Shottr show it. */}
      <FreezeFootCaption state={state} />

      {/* Optional "FROZEN" hint for the studio reviewer. */}
      {showFrozenLabel && <FrozenHint />}
    </div>
  );
}

// ─── Faux desktop chrome ────────────────────────────────────────────

function FakeMenuBar() {
  return (
    <div
      className="absolute left-0 right-0 top-0 flex items-center px-3"
      style={{
        height: 22,
        background: "rgba(255,255,255,0.55)",
        backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        borderBottom: "0.5px solid rgba(0,0,0,0.10)",
        zIndex: 1,
      }}
    >
      <span
        className="font-mono"
        style={{
          fontSize: 9,
          fontWeight: 700,
          color: "rgba(35,36,35,0.85)",
          letterSpacing: "0.06em",
        }}
      >

      </span>
      <span
        className="ml-3"
        style={{ fontSize: 10, fontWeight: 600, color: "rgba(35,36,35,0.85)" }}
      >
        Talkie
      </span>
      <span className="flex-1" />
      <span
        className="font-mono"
        style={{
          fontSize: 9,
          color: "rgba(35,36,35,0.7)",
          letterSpacing: "0.06em",
        }}
      >
        Wed 3:42 PM
      </span>
    </div>
  );
}

function FakeWindow({
  x,
  y,
  w,
  h,
  title,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  title: string;
}) {
  return (
    <div
      className="absolute"
      style={{
        left: x,
        top: y,
        width: w,
        height: h,
        borderRadius: 8,
        background: "#F8F8F7",
        border: "0.5px solid rgba(35,36,35,0.18)",
        boxShadow:
          "0 1px 0 rgba(0,0,0,0.05), 0 10px 22px rgba(0,0,0,0.10)",
        overflow: "hidden",
      }}
    >
      {/* Window chrome */}
      <div
        className="flex items-center gap-1.5 px-3"
        style={{
          height: 28,
          borderBottom: "0.5px solid rgba(35,36,35,0.10)",
          background: "rgba(255,255,255,0.6)",
        }}
      >
        <span className="block h-2.5 w-2.5 rounded-full bg-[#FF5F57]" />
        <span className="block h-2.5 w-2.5 rounded-full bg-[#FEBC2E]" />
        <span className="block h-2.5 w-2.5 rounded-full bg-[#28C840]" />
        <span
          className="ml-auto truncate font-mono"
          style={{
            fontSize: 9.5,
            color: "rgba(35,36,35,0.65)",
            letterSpacing: "0.04em",
          }}
        >
          {title}
        </span>
        <span className="ml-3" />
      </div>
      {/* Window body — fake content lines */}
      <div className="flex flex-col gap-1.5 px-4 pt-4">
        {[0.96, 0.78, 0.88, 0.62, 0.84, 0.46, 0.92].map((wpct, i) => (
          <span
            key={i}
            className="block rounded-full"
            style={{
              height: 6,
              width: `${wpct * 100}%`,
              background: "rgba(35,36,35,0.10)",
            }}
          />
        ))}
      </div>
    </div>
  );
}

// ─── Freeze backdrop (armed but no crop yet) ────────────────────────

function FrozenBackdrop() {
  return (
    <div
      className="pointer-events-none absolute inset-0"
      style={{
        // The whole desktop dims very slightly — just enough to feel
        // suspended, not enough to obscure what you're cropping.
        background: "rgba(0,0,0,0.06)",
        zIndex: 5,
      }}
    />
  );
}

// ─── Region crop overlay ────────────────────────────────────────────

/**
 * Mirrors `drawRegionSelection` in ScreenCaptureOverlay.swift line
 * 205: dim backdrop excluding the rect, fill the rect at low alpha,
 * 1px white border, crosshair at center, dimensions label above.
 */
function RegionCrop({
  x,
  y,
  w,
  h,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
}) {
  const label = `${w} × ${h}`;
  return (
    <>
      {/* Four-rect dim backdrop excluding the crop. Matches the
          Swift implementation's `drawRegionBackdrop(excluding:)`. */}
      <div
        className="pointer-events-none absolute"
        style={{
          left: 0,
          right: 0,
          top: 0,
          height: y,
          background: "rgba(0,0,0,0.18)",
          zIndex: 5,
        }}
      />
      <div
        className="pointer-events-none absolute"
        style={{
          left: 0,
          right: 0,
          top: y + h,
          bottom: 0,
          background: "rgba(0,0,0,0.18)",
          zIndex: 5,
        }}
      />
      <div
        className="pointer-events-none absolute"
        style={{
          left: 0,
          top: y,
          width: x,
          height: h,
          background: "rgba(0,0,0,0.18)",
          zIndex: 5,
        }}
      />
      <div
        className="pointer-events-none absolute"
        style={{
          left: x + w,
          right: 0,
          top: y,
          height: h,
          background: "rgba(0,0,0,0.18)",
          zIndex: 5,
        }}
      />

      {/* The crop rect itself — slight fill so it reads as "selected",
          plus the 1px white border the Swift code already paints. */}
      <div
        className="pointer-events-none absolute"
        style={{
          left: x,
          top: y,
          width: w,
          height: h,
          background: "rgba(0,0,0,0.06)",
          boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.92)",
          zIndex: 6,
        }}
      >
        {/* Crosshair at center (matches richCaptureUI in the Swift). */}
        <svg
          aria-hidden
          className="absolute"
          style={{
            left: w / 2 - 8,
            top: h / 2 - 8,
            width: 16,
            height: 16,
          }}
        >
          <line
            x1={2}
            y1={8}
            x2={14}
            y2={8}
            stroke="rgba(255,255,255,0.72)"
            strokeWidth={1}
          />
          <line
            x1={8}
            y1={2}
            x2={8}
            y2={14}
            stroke="rgba(255,255,255,0.72)"
            strokeWidth={1}
          />
        </svg>
      </div>

      {/* Dimensions label above the rect — same vocabulary as the
          Swift overlay (`label.draw(at: NSPoint(x: midX - w/2, y: maxY + 6))`). */}
      <div
        className="pointer-events-none absolute flex items-center justify-center font-mono"
        style={{
          left: x + w / 2 - 60,
          top: y - 22,
          width: 120,
          height: 18,
          background: "rgba(0,0,0,0.6)",
          color: "white",
          fontSize: 11,
          letterSpacing: "0.04em",
          borderRadius: 3,
          zIndex: 7,
        }}
      >
        {label}
      </div>
    </>
  );
}

// ─── Foot caption — affordance line ─────────────────────────────────

function FreezeFootCaption({ state }: { state: FreezeState }) {
  const cue =
    state === "drag-in-progress"
      ? "↵ capture · drag handles to adjust · ⎋ cancel"
      : "drag to crop · A region · S screen · D window · ⎋ cancel";
  return (
    <div
      className="pointer-events-none absolute bottom-4 left-1/2 -translate-x-1/2 font-mono"
      style={{
        padding: "6px 14px",
        borderRadius: 8,
        background: "rgba(20,24,30,0.78)",
        backdropFilter: "blur(12px)",
        WebkitBackdropFilter: "blur(12px)",
        color: "rgba(255,255,255,0.9)",
        fontSize: 10,
        letterSpacing: "0.10em",
        textTransform: "uppercase",
        boxShadow: "0 4px 14px rgba(0,0,0,0.25)",
        zIndex: 8,
      }}
    >
      {cue}
    </div>
  );
}

// ─── "FROZEN" hint for the studio reviewer ──────────────────────────

function FrozenHint() {
  return (
    <div
      className="pointer-events-none absolute right-4 top-7 font-mono"
      style={{
        padding: "3px 7px",
        borderRadius: 3,
        background: "rgba(255,255,255,0.86)",
        border: "0.5px solid rgba(35,36,35,0.18)",
        color: "rgba(35,36,35,0.78)",
        fontSize: 9,
        letterSpacing: "0.22em",
        textTransform: "uppercase",
        fontWeight: 700,
        zIndex: 9,
      }}
    >
      · Frozen snapshot ·
    </div>
  );
}
