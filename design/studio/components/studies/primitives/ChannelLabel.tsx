/**
 * The `· LABEL` lowercase amber smallcap. Strongest brand
 * primitive after the brass palette — apply ruthlessly to every
 * section header.
 *
 * Three tiers (size + tracking):
 *  - eyebrow: 10px / 0.26em — section labels (`· STATION`)
 *  - channel: 9px / 0.22em — list metadata (`CH-01`, type tags)
 *  - status:  8px / 0.28em — in-screen telemetry, status pills
 *
 * Per-theme color: --theme-amber (== theme accent).
 */

import { cn } from "@/lib/utils";

interface ChannelLabelProps {
  children: React.ReactNode;
  tier?: "eyebrow" | "channel" | "status";
  /** Prepend the leading `· ` glyph. Default true. */
  bullet?: boolean;
  className?: string;
}

const SIZE_BY_TIER = {
  eyebrow: "text-[10px] tracking-[0.26em]",
  channel: "text-[9px] tracking-[0.22em]",
  status: "text-[8px] tracking-[0.28em]",
} as const;

export function ChannelLabel({
  children,
  tier = "eyebrow",
  bullet = false,
  className,
}: ChannelLabelProps) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 font-semibold uppercase",
        SIZE_BY_TIER[tier],
        className
      )}
      style={{
        color: "var(--theme-amber)",
        fontFamily: "var(--theme-font-mono)",
        textShadow: "0 0 4px var(--theme-amber-glow)",
      }}
    >
      {bullet ? <span aria-hidden>·</span> : null}
      {children}
    </span>
  );
}
