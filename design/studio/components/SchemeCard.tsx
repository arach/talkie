import type { CSSProperties } from "react";
import type { Scheme } from "@/lib/schemes";

/**
 * One card in a scheme grid: label row (swatch + name + bg hex) +
 * the artifact slot. The artifact inherits the scheme's CSS vars
 * via an inline style applied to its wrapper, so any descendant
 * can read `var(--scheme-bg)` etc.
 */

interface SchemeCardProps {
  scheme: Scheme;
  children: React.ReactNode;
}

export function SchemeCard({ scheme, children }: SchemeCardProps) {
  return (
    // swift: VStack(alignment: .leading, spacing: 10)
    <div className="flex flex-col gap-2.5">
      {/* swift: HStack(alignment: .firstTextBaseline, spacing: 10) — eyebrow row, 9px caps */}
      <div className="flex items-baseline gap-2.5 text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        <span
          aria-hidden
          className="inline-block h-[9px] w-[9px] rounded-full"
          style={{ background: scheme.swatch }}
        />
        <span className="tracking-ch text-studio-ink">{scheme.name}</span>
        <span className="text-studio-ink-faint">{scheme.bgHex}</span>
      </div>
      <div style={scheme.vars as CSSProperties}>{children}</div>
    </div>
  );
}
