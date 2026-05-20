"use client";

import { MacHome } from "@/components/studies/MacHome";

/**
 * Mac Home — fullscreen canvas (no studio chrome).
 *
 * 2560px ≈ 27" external display @ 2x. Renders the Home composition
 * edge-to-edge so the layout's actual behavior at fullscreen is visible
 * without studio framing structure.
 *
 * Scroll the page horizontally if your browser viewport is narrower
 * than the artifact width.
 */

const FULLSCREEN_WIDTH = 2560;

export default function MacHomeWideStudy() {
  return (
    <div className="min-h-screen overflow-x-auto" style={{ background: "#FBFBFA" }}>
      <StudioBand width={FULLSCREEN_WIDTH} label="Mac Home — Fullscreen" />
      <div style={{ width: FULLSCREEN_WIDTH }}>
        <MacHome width={FULLSCREEN_WIDTH} />
      </div>
    </div>
  );
}

// Thin metadata strip so the canvas isn't a context-free void. Studio-only.
function StudioBand({ width, label }: { width: number; label: string }) {
  return (
    <div
      className="flex items-baseline justify-between border-b border-studio-edge px-7 py-2 font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint"
      style={{ width, background: "#F4F1EA" }}
    >
      <span>· {label}</span>
      <span>{width}px · scroll horizontally if needed</span>
    </div>
  );
}
