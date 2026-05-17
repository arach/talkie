"use client";

import { cn } from "@/lib/utils";

/**
 * Two flavors:
 *  - `dark` — black instrument bar (matches agent-bay legacy). Use for
 *            the primary controls.
 *  - `light` — neutral outlined bar on the studio canvas. Use for
 *            secondary treatments (independent toggles).
 *
 * Each toggle is a string key. Parent owns the on/off state — this is
 * purely presentational.
 */

export interface Toggle {
  key: string;
  label: string;
  on: boolean;
  onClick: () => void;
}

interface ToggleBarProps {
  label: string;
  toggles: Toggle[];
  variant?: "dark" | "light";
  className?: string;
}

export function ToggleBar({
  label,
  toggles,
  variant = "dark",
  className,
}: ToggleBarProps) {
  const dark = variant === "dark";
  return (
    <div
      className={cn(
        "mb-3 flex flex-wrap items-center gap-1.5 rounded-[4px] px-3 py-2.5",
        dark
          ? "border border-[rgba(232,154,60,0.15)] bg-[#14181A] shadow-[inset_2px_0_0_rgba(232,154,60,0.6)]"
          : "border border-studio-edge bg-transparent",
        className
      )}
    >
      <span
        className={cn(
          "mr-1 text-[9px] font-semibold uppercase tracking-ch",
          dark ? "text-[#7A8B85]" : "text-studio-ink-faint"
        )}
      >
        {label}
      </span>
      {toggles.map((t) => (
        <button
          key={t.key}
          onClick={t.onClick}
          className={cn(
            "rounded-[3px] border px-2 py-1 font-mono text-[9px] font-semibold uppercase tracking-[0.10em] transition-colors",
            dark
              ? t.on
                ? "border-[#E89A3C] bg-[#E89A3C] text-[#14181A]"
                : "border-[rgba(232,154,60,0.15)] bg-transparent text-[#9AA8A4] hover:border-[rgba(232,154,60,0.32)] hover:text-[#E89A3C]"
              : t.on
                ? "border-studio-ink bg-studio-ink text-studio-canvas"
                : "border-studio-edge bg-transparent text-studio-ink-faint hover:border-studio-ink hover:text-studio-ink"
          )}
        >
          {t.label}
        </button>
      ))}
    </div>
  );
}
