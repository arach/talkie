"use client";

import type { CSSProperties } from "react";
import type { IOSTheme } from "@/lib/themes";

/**
 * iPhone phone-frame chassis. Renders a notched body with a
 * recessed screen, wrapped in a [data-theme] scope so the bundle
 * in globals.css remaps `--theme-*` vars on this subtree.
 *
 * Drop iPhone mock content into `children` — descendants read
 * `var(--theme-canvas)` / `var(--theme-paper)` / `var(--theme-ink)` /
 * `var(--theme-amber)` / `var(--theme-screen-*)` etc.
 */

interface PhoneFrameProps {
  theme: IOSTheme;
  children?: React.ReactNode;
}

// Prescriptive iPhone-realistic frame. 380 × ~823 — close to a real
// iPhone 15 Pro (logical 393 × 852) at studio scale. Fixed size
// means phones don't shift when the grid wraps — they just wrap.
const FRAME_STYLE: CSSProperties = {
  width: "380px",
  aspectRatio: "9 / 19.5",
  background: "#0a0a0a",
  borderRadius: "44px",
  padding: "8px",
  boxShadow:
    "0 0 0 1px rgba(0,0,0,0.2), 0 14px 36px -10px rgba(20,16,12,0.22), 0 30px 80px -20px rgba(20,16,12,0.10)",
  position: "relative",
  flex: "0 0 auto",
};

const SCREEN_STYLE: CSSProperties = {
  width: "100%",
  height: "100%",
  borderRadius: "36px",
  overflow: "hidden",
  background: "var(--theme-canvas)",
  color: "var(--theme-ink)",
  position: "relative",
};

const NOTCH_STYLE: CSSProperties = {
  position: "absolute",
  top: "14px",
  left: "50%",
  transform: "translateX(-50%)",
  width: "96px",
  height: "24px",
  background: "#000",
  borderRadius: "999px",
  zIndex: 2,
};

export function PhoneFrame({ theme, children }: PhoneFrameProps) {
  return (
    <div data-theme={theme.key} className="flex flex-col items-center gap-3">
      <div className="flex items-baseline gap-2.5 text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        <span
          aria-hidden
          className="inline-block h-[9px] w-[9px] rounded-full"
          style={{ background: theme.canvasHex, border: "0.5px solid var(--studio-edge, #E0DCD3)" }}
        />
        <span className="tracking-ch text-studio-ink">{theme.name}</span>
        <span className="text-studio-ink-faint">{theme.canvasHex}</span>
      </div>
      <div style={FRAME_STYLE}>
        <div style={NOTCH_STYLE} />
        <div style={SCREEN_STYLE}>
          {children ? (
            children
          ) : (
            <PhoneFramePlaceholder themeName={theme.name} />
          )}
        </div>
      </div>
      <p className="px-2 text-center text-[11px] leading-snug text-studio-ink-faint max-w-[260px]">
        {theme.blurb}
      </p>
    </div>
  );
}

function PhoneFramePlaceholder({ themeName }: { themeName: string }) {
  return (
    <div
      className="flex h-full flex-col items-center justify-center gap-2 px-6"
      style={{ color: "var(--theme-ink-faint)" }}
    >
      <div
        className="text-[8px] font-semibold uppercase tracking-eyebrow"
        style={{ color: "var(--theme-amber)" }}
      >
        · Slot · drop iPhone mock here
      </div>
      <div
        className="text-center font-display text-[14px] font-medium tracking-tight"
        style={{ color: "var(--theme-ink)" }}
      >
        {themeName}
      </div>
      <div
        className="text-center text-[10px] leading-relaxed"
        style={{ color: "var(--theme-ink-faint)" }}
      >
        Theme vars are wired. Drop content here and it
        inherits this theme's tokens via{" "}
        <code style={{ fontFamily: "var(--studio-mono, monospace)" }}>
          var(--theme-*)
        </code>
        .
      </div>
    </div>
  );
}
