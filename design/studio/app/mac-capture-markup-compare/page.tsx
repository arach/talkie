"use client";

import { useState } from "react";
import { StudioPage } from "@/components/StudioPage";
import {
  MacCaptureMarkupAskNarrow,
  MacCaptureMarkupSpeakStrip,
} from "@/components/studies/MacCaptureMarkup";

/**
 * Parity check for the Speak Strip — Swift screenshot (top/left) vs the
 * studio's "1c · AskStateNarrow" SpeakStrip that the Swift port targets.
 *
 * The Swift snapshot can be a tight region crop of the strip (height ≈
 * 125) or a wider region/window capture that includes the markup canvas
 * above the strip. When the snapshot is taller than `stripHeight`, the
 * stacked / side-by-side / overlay panes CSS-crop the Swift image to
 * its bottom band (`object-position: bottom`) so the strip lines up
 * with the studio render. `swift-only` mode shows the full screenshot.
 *
 * To refresh: drop a new PNG into `public/swift-snapshots/` and update
 * `SNAPSHOT` below. `note` should record what build state the snapshot
 * reflects ("pre-parity-pass" vs "post" vs "after caret") so old
 * captures stay legible without re-reading chat history.
 */
const SNAPSHOT = {
  src: "/swift-snapshots/mac-capture-markup-2026-05-25-1443.png",
  width: 1186,
  height: 761,
  date: "2026-05-25 14:43",
  note: "post-parity-pass · dashed-pill chips + inset highlights landed",
};

type Mode = "stacked" | "side-by-side" | "overlay" | "swift-only" | "studio-only";
type Surface = "ask-narrow" | "speak-strip";

function StudioSurface({ surface, width }: { surface: Surface; width: number }) {
  return (
    <div style={{ width }}>
      {surface === "ask-narrow" ? <MacCaptureMarkupAskNarrow /> : <MacCaptureMarkupSpeakStrip />}
    </div>
  );
}

export default function MacCaptureMarkupComparePage() {
  const [mode, setMode] = useState<Mode>("stacked");
  const [surface, setSurface] = useState<Surface>("ask-narrow");
  const [opacity, setOpacity] = useState(0.5);

  return (
    <StudioPage
      eyebrow="Capture Markup · Parity check"
      title="Mac Capture Markup · compare"
      help={`screenshot ${SNAPSHOT.date} · ${SNAPSHOT.note}`}
    >
      <div className="mb-4 flex flex-wrap items-center gap-3 text-[11px]">
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

        <span className="ml-4 font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          studio surface
        </span>
        {(["ask-narrow", "speak-strip"] as Surface[]).map((s) => (
          <button
            key={s}
            onClick={() => setSurface(s)}
            className={`px-2 py-1 font-mono text-[10px] uppercase tracking-[0.16em] ${
              surface === s
                ? "border border-studio-ink text-studio-ink"
                : "border border-studio-edge text-studio-ink-faint hover:text-studio-ink"
            }`}
          >
            {s}
          </button>
        ))}

        {mode === "overlay" && (
          <label className="ml-4 flex items-center gap-2 text-[10px] uppercase tracking-[0.16em] text-studio-ink-faint">
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
        <div className="flex flex-col gap-6">
          <Pane label={`Swift · screenshot · ${SNAPSHOT.width}×${SNAPSHOT.height}`}>
            <SwiftFull />
          </Pane>
          <Pane label={`Studio · ${surface}`}>
            <StudioSurface surface={surface} width={SNAPSHOT.width} />
          </Pane>
        </div>
      )}

      {mode === "side-by-side" && (
        <div className="overflow-x-auto" style={{ width: "100%" }}>
          <div
            className="grid gap-6"
            style={{
              gridTemplateColumns: `${SNAPSHOT.width}px ${SNAPSHOT.width}px`,
              width: SNAPSHOT.width * 2 + 24,
            }}
          >
            <Pane label={`Swift · screenshot · ${SNAPSHOT.width}×${SNAPSHOT.height}`}>
              <SwiftFull />
            </Pane>
            <Pane label={`Studio · ${surface}`}>
              <StudioSurface surface={surface} width={SNAPSHOT.width} />
            </Pane>
          </div>
        </div>
      )}

      {/*
        Overlay anchors at top-left for the full-window `ask-narrow`
        surface (matches the screenshot's window-chrome alignment), and
        bottom-left for `speak-strip` (the Swift strip sits at the
        bottom of the screenshot). No embedded offset metadata in the
        capture, so this is a visual heuristic — drag the opacity to
        see how the chrome / chips / strip elements line up.
      */}
      {mode === "overlay" && (
        <Pane
          label={`Overlay · studio ${surface} at ${Math.round(opacity * 100)}% — ${
            surface === "ask-narrow" ? "anchored top-left" : "anchored bottom-left"
          }`}
        >
          <div
            style={{
              position: "relative",
              width: SNAPSHOT.width,
              height: SNAPSHOT.height,
            }}
          >
            <SwiftFull />
            <div
              style={{
                position: "absolute",
                left: 0,
                ...(surface === "ask-narrow" ? { top: 0 } : { bottom: 0 }),
                width: SNAPSHOT.width,
                opacity,
                pointerEvents: opacity > 0.5 ? "auto" : "none",
              }}
            >
              <StudioSurface surface={surface} width={SNAPSHOT.width} />
            </div>
          </div>
        </Pane>
      )}

      {mode === "swift-only" && (
        <Pane label={`Swift · screenshot · ${SNAPSHOT.width}×${SNAPSHOT.height}`}>
          <SwiftFull />
        </Pane>
      )}

      {mode === "studio-only" && (
        <Pane label={`Studio · ${surface}`}>
          <StudioSurface surface={surface} width={SNAPSHOT.width} />
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

function SwiftFull() {
  return (
    <img
      src={SNAPSHOT.src}
      alt="Swift markup window screenshot"
      width={SNAPSHOT.width}
      height={SNAPSHOT.height}
      style={{ display: "block" }}
    />
  );
}
