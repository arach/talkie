/**
 * Cream-paper card with optional channel-label heading + body slot.
 * Used for STATION cards, CONTENT cards, DETAILS rows, etc.
 *
 * Reads:
 *   --theme-paper        card surface
 *   --theme-edge-faint   border
 *   --theme-amber-glow   subtle inner highlight (paper feel)
 */

import { ChannelLabel } from "./ChannelLabel";

interface SectionCardProps {
  label?: string;
  /** Show the leading `· ` glyph on the label. Default true. */
  labelBullet?: boolean;
  rightSlot?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}

export function SectionCard({
  label,
  labelBullet = true,
  rightSlot,
  children,
  className,
}: SectionCardProps) {
  return (
    <div
      className={"rounded-[10px] " + (className ?? "")}
      style={{
        background: "var(--theme-paper)",
        border: "0.5px solid var(--theme-edge-faint)",
        boxShadow:
          "0 1px 0 rgba(255, 255, 255, 0.4), inset 0 0.5px 0 rgba(255, 255, 255, 0.45)",
      }}
    >
      {label ? (
        <div className="flex items-center justify-between px-3 pt-2.5 pb-1">
          <ChannelLabel tier="eyebrow" bullet={labelBullet}>
            {label}
          </ChannelLabel>
          {rightSlot ? <div className="text-[10px]">{rightSlot}</div> : null}
        </div>
      ) : null}
      <div className="px-3 pb-3">{children}</div>
    </div>
  );
}
