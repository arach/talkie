"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import { MacHome } from "@/components/studies/MacHome";

/**
 * Side-by-side parity check: Swift screenshot (left) vs studio MacHome
 * (right) at the same target width. Use this to walk element-by-element
 * deltas — border radii, paddings, inset highlights, type weight, etc.
 *
 * To refresh the screenshot, drop a new PNG into
 * `public/swift-snapshots/` and update SNAPSHOT below. Keep the date in
 * the filename so old snapshots are recoverable.
 */
const SNAPSHOT = {
  src: "/swift-snapshots/mac-home-2026-05-25.png",
  width: 1280,
  height: 903,
  date: "2026-05-25 14:31",
};

type Mode = "stacked" | "side-by-side" | "overlay" | "swift-only" | "studio-only";

export default function MacHomeComparePage() {
  const [mode, setMode] = useState<Mode>("stacked");
  const [opacity, setOpacity] = useState(0.5);

  return (
    <StudioPage
      eyebrow="Home · macOS · Parity check · Swift vs Studio"
      title="Mac Home · compare"
      help={`screenshot ${SNAPSHOT.date} · width ${SNAPSHOT.width}`}
    >
      <div className="mb-4 flex items-center gap-3 text-[11px]">
        <span className="font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          mode
        </span>
        {(["stacked", "side-by-side", "overlay", "swift-only", "studio-only"] as Mode[]).map((m) => (
          <button
            key={m}
            onClick={() => setMode(m)}
            className={`px-2 py-1 font-mono text-[10px] uppercase tracking-[0.16em] ${
              mode === m
                ? "border border-studio-ink text-studio-ink"
                : "border border-studio-edge text-studio-ink-faint hover:text-studio-ink"
            }`}
          >
            {m}
          </button>
        ))}
        {mode === "overlay" && (
          <label className="ml-2 flex items-center gap-2 text-[10px] uppercase tracking-[0.16em] text-studio-ink-faint">
            studio opacity
            <input
              type="range"
              min={0}
              max={1}
              step={0.05}
              value={opacity}
              onChange={(e) => setOpacity(parseFloat(e.target.value))}
              className="w-32"
            />
            <span className="font-mono">{Math.round(opacity * 100)}%</span>
          </label>
        )}
      </div>

      {mode === "stacked" && (
        <div className="flex flex-col gap-8">
          <Pane label="Swift · screenshot">
            <img
              src={SNAPSHOT.src}
              alt="Swift Home screenshot"
              width={SNAPSHOT.width}
              height={SNAPSHOT.height}
              style={{ display: "block" }}
            />
          </Pane>
          <Pane label="Studio · MacHome">
            <div style={{ width: SNAPSHOT.width }}>
              <MacHome width={SNAPSHOT.width} />
            </div>
          </Pane>
        </div>
      )}

      {mode === "side-by-side" && (
        <div
          className="overflow-x-auto"
          style={{ width: "100%" }}
        >
          <div className="grid gap-6" style={{ gridTemplateColumns: `${SNAPSHOT.width}px ${SNAPSHOT.width}px`, width: SNAPSHOT.width * 2 + 24 }}>
            <Pane label="Swift · screenshot">
              <img
                src={SNAPSHOT.src}
                alt="Swift Home screenshot"
                width={SNAPSHOT.width}
                height={SNAPSHOT.height}
                style={{ display: "block" }}
              />
            </Pane>
            <Pane label="Studio · MacHome">
              <div style={{ width: SNAPSHOT.width }}>
                <MacHome width={SNAPSHOT.width} />
              </div>
            </Pane>
          </div>
        </div>
      )}

      {mode === "overlay" && (
        <Pane label={`Overlay · studio at ${Math.round(opacity * 100)}%`}>
          <div style={{ position: "relative", width: SNAPSHOT.width, height: SNAPSHOT.height }}>
            <img
              src={SNAPSHOT.src}
              alt="Swift Home screenshot"
              width={SNAPSHOT.width}
              height={SNAPSHOT.height}
              style={{ position: "absolute", inset: 0, display: "block" }}
            />
            <div
              style={{
                position: "absolute",
                inset: 0,
                width: SNAPSHOT.width,
                opacity,
                pointerEvents: opacity > 0.5 ? "auto" : "none",
              }}
            >
              <MacHome width={SNAPSHOT.width} />
            </div>
          </div>
        </Pane>
      )}

      {mode === "swift-only" && (
        <Pane label="Swift · screenshot">
          <img
            src={SNAPSHOT.src}
            alt="Swift Home screenshot"
            width={SNAPSHOT.width}
            height={SNAPSHOT.height}
            style={{ display: "block" }}
          />
        </Pane>
      )}

      {mode === "studio-only" && (
        <Pane label="Studio · MacHome">
          <div style={{ width: SNAPSHOT.width }}>
            <MacHome width={SNAPSHOT.width} />
          </div>
        </Pane>
      )}
    </StudioPage>
  );
}

function Pane({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="mb-2 font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        {label}
      </div>
      <div className="border border-studio-edge bg-white">{children}</div>
    </div>
  );
}
