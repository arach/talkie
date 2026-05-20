"use client";

/**
 * IconRail — 52pt-wide minimized sidebar with the Talkie button at the
 * top and icon-only nav stacked below.
 *
 * Originally inline in `MacTalkieButton.tsx` Variant B. Promoted to a
 * primitive once `MacMemoDetail.tsx` needed it to show what the detail
 * pane looks like with persistent navigation in place.
 *
 * The rail's job: preserve the spatial "I know where things live"
 * affordance the full sidebar gives today, while demoting it from a
 * 220pt panel to a 52pt strip. The Talkie button at the top still owns
 * tap → palette, hold → voice, right-click → sectioned nav popover.
 *
 * If a third caller arrives that wants a different item list, we can
 * make the items prop-driven. For now the canonical set is hardcoded
 * to keep all studio surfaces in sync.
 */

import React from "react";

const AMBER = "#C47D1C";
const AMBER_GLOW = "#E89A3C";
const INK = "#2A2620";
const EDGE = "#E0DCD3";
const CREAM = "#FBFBFA";
const PAPER = "#F4F1EA";

const ITEMS: { icon: string; label: string; selectedKey: string; badge?: string }[] = [
  { icon: "⌂", label: "Home",       selectedKey: "home" },
  { icon: "▤", label: "Library",    selectedKey: "library" },
  { icon: "✎", label: "Compose",    selectedKey: "compose" },
  { icon: "◔", label: "Actions",    selectedKey: "actions" },
  { icon: "✦", label: "Learn",      selectedKey: "learn" },
  { icon: "⚙︎", label: "Models",     selectedKey: "models" },
  { icon: "✺", label: "Workflows",  selectedKey: "workflows", badge: "·" },
];

export type IconRailSelectionKey =
  | "home"
  | "library"
  | "compose"
  | "actions"
  | "learn"
  | "models"
  | "workflows"
  | "settings";

interface IconRailProps {
  /** Which entry should render as the currently active surface. */
  selected?: IconRailSelectionKey;
  /** Width of the rail. 52 is the canonical value; expose for tuning. */
  width?: number;
  /** Min height — lets the rail stretch to match the content pane. */
  minHeight?: number | string;
}

export function IconRail({
  selected = "home",
  width = 52,
  minHeight = 600,
}: IconRailProps) {
  return (
    <div
      className="flex flex-col items-center gap-2 py-3"
      style={{ width, background: PAPER, minHeight }}
    >
      {/* The Talkie button at the top */}
      <RailTalkieButton />
      <span aria-hidden className="my-2 h-px w-6" style={{ background: EDGE }} />

      {/* Icon nav */}
      <div className="flex flex-col items-center gap-1.5">
        {ITEMS.map((item) => (
          <RailItem
            key={item.selectedKey}
            icon={item.icon}
            label={item.label}
            selected={item.selectedKey === selected}
            badge={item.badge}
          />
        ))}
      </div>

      {/* Bottom: settings */}
      <div className="mt-auto flex flex-col items-center gap-1.5">
        <span aria-hidden className="h-px w-6" style={{ background: EDGE }} />
        <RailItem
          icon="⚙︎"
          label="Settings"
          selected={selected === "settings"}
        />
      </div>
    </div>
  );
}

// Rail-mode Talkie button — 36×36, mark only. The full state machine
// (idle/hover/listening/recording/etc.) lives in the floating button;
// the rail variant is the always-visible idle resting state.
function RailTalkieButton() {
  return (
    <div
      className="flex h-9 w-9 items-center justify-center rounded-[10px]"
      style={{
        background: INK,
        boxShadow: `0 0 0 3px ${AMBER}22, 0 4px 10px rgba(0,0,0,0.18)`,
      }}
      title="Talkie · tap to search · hold to speak"
    >
      <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden>
        <circle
          cx="7"
          cy="7"
          r="3"
          fill={AMBER_GLOW}
          style={{ filter: `drop-shadow(0 0 4px ${AMBER_GLOW})` }}
        />
        <circle
          cx="7"
          cy="7"
          r="5.5"
          fill="none"
          stroke={AMBER_GLOW}
          strokeOpacity="0.4"
          strokeWidth="1"
        />
      </svg>
    </div>
  );
}

function RailItem({
  icon,
  label,
  selected,
  badge,
}: {
  icon: string;
  label: string;
  selected: boolean;
  badge?: string;
}) {
  return (
    <div
      className="relative flex h-8 w-8 items-center justify-center rounded-[7px]"
      style={{
        background: selected ? CREAM : "transparent",
        border: selected ? `0.5px solid ${EDGE}` : "0.5px solid transparent",
        color: selected ? INK : "#5A554C",
      }}
      title={label}
    >
      <span className="font-mono text-[14px]">{icon}</span>
      {badge && (
        <span
          aria-hidden
          className="absolute right-0.5 top-0.5 h-1.5 w-1.5 rounded-full"
          style={{ background: AMBER_GLOW }}
        />
      )}
    </div>
  );
}
