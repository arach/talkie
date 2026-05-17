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
    return (
      <button
        className={cn(
          "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[12px] font-medium transition-colors",
          className
        )}
        style={
          active
            ? {
                background: "var(--theme-amber)",
                color: "var(--theme-paper)",
                fontFamily: "var(--theme-font-body)",
                letterSpacing: "-0.005em",
              }
            : {
                background: "transparent",
                color: "var(--theme-ink-faint)",
                fontFamily: "var(--theme-font-body)",
                letterSpacing: "-0.005em",
              }
        }
      >
        {glyph}
        {children}
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
