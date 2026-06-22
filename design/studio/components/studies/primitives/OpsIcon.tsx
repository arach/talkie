"use client";

/**
 * OpsIcon — inline stroke icons for the TalkieAgent (OPS) studio mocks.
 *
 * Same lucide-style language the rest of the studio uses (16×16 grid,
 * 1.4 stroke, currentColor) so icons inherit the surrounding text color.
 * Kept as a shared primitive so agent surfaces don't each re-roll glyphs.
 */

import React from "react";

export type OpsIconName =
  | "home"
  | "history"
  | "chat"
  | "shield"
  | "docs"
  | "more"
  | "gear"
  | "memo"
  | "wave"
  | "capture"
  | "agents"
  | "work"
  | "external"
  | "drive"
  | "copy";

export function OpsIcon({
  name,
  size = 16,
}: {
  name: OpsIconName;
  size?: number;
}) {
  const s = size;
  const p = {
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.4,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
  };
  const svg = (children: React.ReactNode) => (
    <svg width={s} height={s} viewBox="0 0 16 16" aria-hidden>
      {children}
    </svg>
  );

  switch (name) {
    case "home":
      return svg(
        <>
          <path d="M2.6 7.4 8 2.8l5.4 4.6" {...p} />
          <path d="M4.2 6.6V13h7.6V6.6" {...p} />
        </>
      );
    case "history":
      return svg(
        <>
          <circle cx="8" cy="8" r="5.6" {...p} />
          <path d="M8 5v3l2 1.4" {...p} />
        </>
      );
    case "chat":
      return svg(
        <path
          d="M3 4.4h10a.9.9 0 0 1 .9.9v4.4a.9.9 0 0 1-.9.9H6.6L3.6 13v-2.4H3a.9.9 0 0 1-.9-.9V5.3A.9.9 0 0 1 3 4.4z"
          {...p}
        />
      );
    case "shield":
      return svg(
        <>
          <path d="M8 1.8 13 3.6v3.7c0 3-2.1 5.3-5 6.9-2.9-1.6-5-3.9-5-6.9V3.6z" {...p} />
          <path d="m5.8 8 1.6 1.6L10.4 6.6" {...p} />
        </>
      );
    case "docs":
      return svg(
        <>
          <path d="M5 4.5h8M5 8h8M5 11.5h8" {...p} />
          <path d="M2.9 4.5h0M2.9 8h0M2.9 11.5h0" {...p} />
        </>
      );
    case "more":
      return svg(
        <>
          <circle cx="3.5" cy="8" r="1.1" fill="currentColor" stroke="none" />
          <circle cx="8" cy="8" r="1.1" fill="currentColor" stroke="none" />
          <circle cx="12.5" cy="8" r="1.1" fill="currentColor" stroke="none" />
        </>
      );
    case "gear":
      return svg(
        <>
          <circle cx="8" cy="8" r="2.1" {...p} />
          <path
            d="M8 1.6v1.7M8 12.7v1.7M14.4 8h-1.7M3.3 8H1.6M12.5 3.5l-1.2 1.2M4.7 11.3l-1.2 1.2M12.5 12.5l-1.2-1.2M4.7 4.7 3.5 3.5"
            {...p}
          />
        </>
      );
    case "memo":
      return svg(
        <>
          <path d="M4 2.6h5l3 3V13a.4.4 0 0 1-.4.4H4a.4.4 0 0 1-.4-.4V3a.4.4 0 0 1 .4-.4z" {...p} />
          <path d="M9 2.6V5.6h3" {...p} />
          <path d="M5.8 8.4h4.4M5.8 10.6h4.4" {...p} />
        </>
      );
    case "wave":
      return svg(
        <path d="M3 8v0M5.5 5.5v5M8 3.5v9M10.5 5.5v5M13 8v0" {...p} />
      );
    case "capture":
      return svg(
        <>
          <path
            d="M2.5 5V3.2A.7.7 0 0 1 3.2 2.5H5M11 2.5h1.8a.7.7 0 0 1 .7.7V5M13.5 11v1.8a.7.7 0 0 1-.7.7H11M5 13.5H3.2a.7.7 0 0 1-.7-.7V11"
            {...p}
          />
          <circle cx="8" cy="8" r="1.6" {...p} />
        </>
      );
    case "agents":
      return svg(
        <>
          <circle cx="8" cy="8" r="2.2" {...p} />
          <circle cx="8" cy="2.3" r="1" {...p} />
          <circle cx="13" cy="11" r="1" {...p} />
          <circle cx="3" cy="11" r="1" {...p} />
          <path d="M8 4.5v1.3M11.3 9.6 9.7 8.9M4.7 9.6l1.6-.7" {...p} />
        </>
      );
    case "work":
      return svg(
        <>
          <path d="M12.6 5A5 5 0 1 0 13 8" {...p} />
          <path d="M13 2.8v2.4h-2.4" {...p} />
        </>
      );
    case "external":
      return svg(
        <>
          <path d="M7.6 3.5H4.3a.8.8 0 0 0-.8.8v7.4a.8.8 0 0 0 .8.8h7.4a.8.8 0 0 0 .8-.8V8.4" {...p} />
          <path d="M9.6 3.5H12.5V6.4" {...p} />
          <path d="M12.5 3.5 7.6 8.4" {...p} />
        </>
      );
    case "drive":
      return svg(
        <>
          <rect x="2.6" y="4.4" width="10.8" height="7.2" rx="1.4" {...p} />
          <path d="M4.4 9.4h3.4" {...p} />
          <circle cx="11" cy="9.4" r=".7" fill="currentColor" stroke="none" />
        </>
      );
    case "copy":
      return svg(
        <>
          <rect x="5.2" y="5.2" width="7.6" height="7.6" rx="1.2" {...p} />
          <path d="M3.2 9.4V4a.8.8 0 0 1 .8-.8h5.4" {...p} />
        </>
      );
  }
}
