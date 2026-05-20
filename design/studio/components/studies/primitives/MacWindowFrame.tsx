"use client";

/**
 * MacWindowFrame — width-parameterized macOS window chrome wrapper.
 *
 * Studio artifacts for the mac app are usually rendered at a single
 * "true pixel" width on the cream canvas (see MacHome, MacMemoDetail).
 * This primitive generalizes that pattern so the same composition can
 * be stamped at multiple widths inside one study page — the responsive
 * behavior of a screen reads at a glance instead of requiring window
 * resizing.
 *
 * Used by:
 *   - app/mac-home       — Home at 820 / 1180 / 1440
 *   - app/mac-library    — Library at 820 / 1180 / 1440 (crosses 880 breakpoint)
 *   - app/mac-compose    — Compose at 820 / 1180 / 1440
 *
 * The frame draws faint Mac chrome (traffic-lights row + center title)
 * so the artifact reads as "the app in a window" not a free-floating
 * panel. The width-class eyebrow above the frame (`· 820 · COMPACT`)
 * is studio-only — it's the spec annotation, not part of the design.
 */

import React from "react";

export type MacWindowSize = {
  /** Pixel width of the simulated window. */
  width: number;
  /** Short label, e.g. "COMPACT", "DEFAULT", "WIDE". */
  label: string;
  /** Optional eyebrow note shown alongside the label. */
  note?: string;
};

/** Canonical sizes used across the mac studies. The numbers are chosen
 *  to bracket the Swift breakpoints we already ship:
 *  - 820  — just below the Library 880 breakpoint (compact mode).
 *  - 1180 — current "standard" studio width (matches MacMemoDetail).
 *  - 1440 — typical 14"/16" MBP scaled width (wide).
 *  - 1920 — external display near-fullscreen; surfaces the "huge open
 *           spaces" problem at large widths so we can prototype fills. */
export const MAC_SIZES: MacWindowSize[] = [
  { width: 820,  label: "Compact",  note: "below the Library 880 breakpoint" },
  { width: 1180, label: "Default",  note: "studio standard · single MBP scaled" },
  { width: 1440, label: "Wide",     note: "external display · two-pane luxury" },
  { width: 1920, label: "External", note: "near-fullscreen · stress-test fills" },
];

interface MacWindowFrameProps {
  size: MacWindowSize;
  /** Chrome title shown in the window's center title slot. */
  title: string;
  /** The artifact's body — should fill the frame (no internal max-width). */
  children: React.ReactNode;
  /** Override the inner background. Defaults to studio canvas cream. */
  background?: string;
}

export function MacWindowFrame({
  size,
  title,
  children,
  background = "#FBFBFA",
}: MacWindowFrameProps) {
  return (
    <section className="mx-auto flex flex-col items-center gap-3" style={{ width: size.width }}>
      <WidthAnnotation size={size} />
      <div
        className="overflow-hidden rounded-md"
        style={{
          width: size.width,
          background,
          boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
          border: "0.5px solid #E0DCD3",
        }}
      >
        <WindowChrome title={title} />
        {children}
      </div>
    </section>
  );
}

// Eyebrow line that labels the artifact width. Studio-only metadata —
// the user never sees this; it tells the designer/reviewer what they
// are looking at. Sits above the frame, mono caps, sparse tracking.
function WidthAnnotation({ size }: { size: MacWindowSize }) {
  return (
    <div className="flex w-full items-baseline justify-between font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
      <span>
        · {size.width} · {size.label}
      </span>
      {size.note ? <span className="text-studio-ink-faint">{size.note}</span> : null}
    </div>
  );
}

// macOS traffic-light row + title. Faint — the chrome is context, not focus.
function WindowChrome({ title }: { title: string }) {
  return (
    <div
      className="flex items-center gap-2 border-b px-4 py-2.5"
      style={{ borderColor: "#E0DCD3", background: "#F4F1EA" }}
    >
      <div className="flex gap-1.5">
        <span className="h-3 w-3 rounded-full" style={{ background: "#E0DCD3" }} />
        <span className="h-3 w-3 rounded-full" style={{ background: "#E0DCD3" }} />
        <span className="h-3 w-3 rounded-full" style={{ background: "#E0DCD3" }} />
      </div>
      <div className="mx-auto text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
        {title}
      </div>
      <div className="invisible flex gap-1.5">
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
      </div>
    </div>
  );
}

/**
 * Convenience wrapper: render the same artifact at all three canonical
 * widths, stacked vertically with a slug between each. Studies call
 * this with a render-prop that returns the artifact body for a given
 * width — the body can branch on `size.width` to model breakpoints.
 */
export function MacWindowGrid({
  title,
  sizes = MAC_SIZES,
  render,
}: {
  title: string;
  sizes?: MacWindowSize[];
  render: (size: MacWindowSize) => React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-14">
      {sizes.map((size) => (
        <MacWindowFrame key={size.width} size={size} title={title}>
          {render(size)}
        </MacWindowFrame>
      ))}
    </div>
  );
}
