/**
 * Theme-aware iOS chip — for tab-style nav, filter rows, model picker.
 * Distinct from the studio's ToggleBar chips (those are studio chrome).
 *
 * Variants:
 *  - tab     · pill with amber active state (Library tabs)
 *  - filter  · subtle outlined pill, accent on active
 *  - command · text + small glyph (Quick Commands row)
 */

import { cn } from "@/lib/utils";

interface ChipProps {
  children: React.ReactNode;
  variant?: "tab" | "filter" | "command";
  active?: boolean;
  glyph?: React.ReactNode;
  className?: string;
}

export function Chip({
  children,
  variant = "filter",
  active = false,
  glyph,
  className,
}: ChipProps) {
  if (variant === "tab") {
    // Softer iOS-segmented-control feel: active = brass text + 2px
    // brass underline (no full amber fill — that read as signage-y).
    return (
      <button
        className={cn(
          "relative inline-flex items-center gap-1.5 px-2.5 pb-2 pt-1 text-[13px] font-medium transition-colors",
          className
        )}
        style={{
          background: "transparent",
          color: active ? "var(--theme-amber)" : "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-body)",
          letterSpacing: "-0.005em",
        }}
      >
        {glyph}
        {children}
        {active ? (
          <span
            aria-hidden
            className="absolute bottom-0 left-2.5 right-2.5 h-[2px] rounded-full"
            style={{ background: "var(--theme-amber)" }}
          />
        ) : null}
      </button>
    );
  }

  if (variant === "command") {
    return (
      <button
        className={cn(
          "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-medium",
          className
        )}
        style={{
          background: "var(--theme-paper)",
          color: "var(--theme-ink-dim)",
          border: "0.5px solid var(--theme-edge-faint)",
          fontFamily: "var(--theme-font-body)",
        }}
      >
        {glyph}
        {children}
      </button>
    );
  }

  // filter
  return (
    <button
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-[0.14em]",
        className
      )}
      style={
        active
          ? {
              background: "var(--theme-amber-faint)",
              color: "var(--theme-amber)",
              border: "0.5px solid var(--theme-amber-soft)",
              fontFamily: "var(--theme-font-mono)",
            }
          : {
              background: "transparent",
              color: "var(--theme-ink-faint)",
              border: "0.5px solid var(--theme-edge-faint)",
              fontFamily: "var(--theme-font-mono)",
            }
      }
    >
      {glyph}
      {children}
    </button>
  );
}
