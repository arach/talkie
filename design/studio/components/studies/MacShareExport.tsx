"use client";

/**
 * Mac Share Export — V1 screenshot Export Panel.
 *
 * Source of truth: docs/specs/tlk-032-share-export-studio.md (revised,
 * screenshot-only V1). This study is the visual seat for that panel
 * BEFORE any SwiftUI lands.
 *
 * Scope discipline (do not re-expand in this file):
 *   - screenshots only — no video, clips, recording cards, destinations.
 *   - no user-facing "Private" mode (privacy is out of V1 until real
 *     metadata/source redaction exists).
 *   - two presets only: Original (raw source pixels, no recompression)
 *     and Polished (background + padding + corners + shadow).
 *
 * Composition (matches the spec's surface):
 *   - left / main : large live preview of the framed screenshot.
 *   - right rail  : preset chips → background → padding → corner radius →
 *     shadow → format → JPEG quality → dimensions/size readout →
 *     Copy / Save As.
 *
 * Studio annotations (eyebrows, the A/B reference strip, porting notes)
 * are study chrome only. Nothing instructional is painted inside the
 * panel surface itself — what you see in the framed window is what the
 * shipped panel shows.
 *
 * Palette: SCOPE substrate (cool instrument gray). The synthetic capture
 * is "foreign" content (a grabbed app window) so it intentionally does
 * NOT use Scope tokens — a real screenshot is whatever the user shot.
 */

import React, { useMemo, useState } from "react";
import { SCOPE } from "@/lib/scope-tokens";

const T = {
  canvas:     SCOPE.canvas,
  pane:       SCOPE.pane,
  paneLift:   SCOPE.paneLifted,
  chrome:     SCOPE.chrome,
  rail:       SCOPE.rail,
  selection:  SCOPE.selection,
  ink:        SCOPE.ink,
  inkMid:     SCOPE.inkMid,
  inkFaint:   SCOPE.inkFaint,
  inkFainter: SCOPE.inkFainter,
  edge:       SCOPE.edge,
  edgeSubtle: SCOPE.edgeSubtle,
  rule:       SCOPE.rule,
  ruleSubtle: SCOPE.ruleSubtle,
  amber:      SCOPE.amber,
  amberDeep:  SCOPE.amberDeep,
  amberSoft:  SCOPE.amberSoft,
  white:      SCOPE.white,
};

// ── Control vocab ──────────────────────────────────────────────────────
// Each maps a user-facing tier to a concrete render value. The Swift port
// reads the same vocab off ExportRecipe; the numbers below are the design
// intent, not arbitrary.

type Preset = "original" | "polished";
type Background = "none" | "solid" | "theme" | "gradient" | "blur";
type Padding = "none" | "small" | "medium" | "large";
type Corner = "square" | "subtle" | "rounded";
type Shadow = "none" | "soft" | "presentation";
type Format = "png" | "jpeg";
type Quality = "small" | "medium" | "high";

const PAD_PX: Record<Padding, number> = { none: 0, small: 16, medium: 36, large: 64 };
const CORNER_PX: Record<Corner, number> = { square: 0, subtle: 8, rounded: 20 };
const SHADOW_CSS: Record<Shadow, string> = {
  none: "none",
  soft: "0 10px 30px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.10)",
  presentation: "0 34px 80px rgba(0,0,0,0.32), 0 8px 20px rgba(0,0,0,0.14)",
};

// Solid-background swatch (V1 ships one neutral default; custom color is
// a later track). Theme = Scope surface; gradient = soft warm wash.
const SOLID_FILL = "#FFFFFF";
const THEME_FILL = SCOPE.canvasAlt;
const GRADIENT_FILL = "linear-gradient(135deg, #F4F1EC 0%, #E8E6E2 55%, #DEDCD7 100%)";

// Source capture is treated as a 2× Retina grab. Output pixel dims =
// (source + padding on each side) at source-native scale.
const SOURCE_W = 1840;
const SOURCE_H = 1124;
const SCALE = 2;

const PRESET_MATRIX: Record<Preset, {
  background: Background; padding: Padding; corner: Corner; shadow: Shadow; format: Format; quality: Quality;
}> = {
  original: { background: "none", padding: "none", corner: "square", shadow: "none", format: "png", quality: "high" },
  polished: { background: "theme", padding: "medium", corner: "subtle", shadow: "soft", format: "png", quality: "high" },
};

// Synthetic estimated file size (KB). Deterministic, plausible — a stand-in
// for the real renderer's byte count. PNG scales with area; JPEG with the
// quality tier.
function estimateKB(outW: number, outH: number, format: Format, quality: Quality): number {
  const area = outW * outH;
  if (format === "png") return Math.round(area / 4500);
  const divisor = quality === "high" ? 14000 : quality === "medium" ? 26000 : 52000;
  return Math.round(area / divisor);
}

function fmtSize(kb: number): string {
  return kb >= 1024 ? `${(kb / 1024).toFixed(1)} MB` : `${kb} KB`;
}

// ── The study ──────────────────────────────────────────────────────────

export function MacShareExport() {
  return (
    <div className="flex flex-col items-center gap-10">
      <ExportPanelFrame />
      <ReferenceStrip />
      <PortingNotes />
    </div>
  );
}

// Window-framed Export Panel — the usable surface, rendered at a single
// true-pixel width on the Scope canvas.
function ExportPanelFrame() {
  return (
    <section className="flex w-full flex-col items-center gap-3" style={{ maxWidth: 1120 }}>
      <div className="flex w-full items-baseline justify-between font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
        <span>· export panel · screenshot · V1</span>
        <span>inspector over capture detail</span>
      </div>
      <div
        className="w-full overflow-hidden rounded-md"
        style={{
          background: T.canvas,
          border: `0.5px solid ${T.edge}`,
          boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
        }}
      >
        <WindowChrome />
        <ExportPanel />
      </div>
    </section>
  );
}

function WindowChrome() {
  return (
    <div className="flex items-center gap-2 px-4 py-2.5" style={{ borderBottom: `0.5px solid ${T.edge}`, background: T.chrome }}>
      <div className="flex gap-1.5">
        <span className="h-3 w-3 rounded-full" style={{ background: T.rail }} />
        <span className="h-3 w-3 rounded-full" style={{ background: T.rail }} />
        <span className="h-3 w-3 rounded-full" style={{ background: T.rail }} />
      </div>
      <div className="mx-auto font-mono text-[9px] uppercase tracking-[0.20em]" style={{ color: T.inkFaint }}>
        Export · bay-scheme-compare-9up.png
      </div>
      <div className="invisible flex gap-1.5">
        <span className="h-3 w-3 rounded-full" />
      </div>
    </div>
  );
}

function ExportPanel() {
  const [preset, setPreset] = useState<Preset>("polished");
  const m = PRESET_MATRIX.polished;
  const [background, setBackground] = useState<Background>(m.background);
  const [padding, setPadding] = useState<Padding>(m.padding);
  const [corner, setCorner] = useState<Corner>(m.corner);
  const [shadow, setShadow] = useState<Shadow>(m.shadow);
  const [format, setFormat] = useState<Format>(m.format);
  const [quality, setQuality] = useState<Quality>(m.quality);
  const [toast, setToast] = useState<string | null>(null);

  const isOriginal = preset === "original";

  // Selecting a preset stamps its full matrix. Adjusting any knob keeps the
  // current preset label (V1 is preset-first; "Custom" derivation is later).
  function applyPreset(p: Preset) {
    setPreset(p);
    const mm = PRESET_MATRIX[p];
    setBackground(mm.background);
    setPadding(mm.padding);
    setCorner(mm.corner);
    setShadow(mm.shadow);
    setFormat(mm.format);
    setQuality(mm.quality);
  }

  function flashToast(msg: string) {
    setToast(msg);
  }

  // Effective render values — Original locks to raw source pixels.
  const effBackground: Background = isOriginal ? "none" : background;
  const effPadding: Padding = isOriginal ? "none" : padding;
  const effCorner: Corner = isOriginal ? "square" : corner;
  const effShadow: Shadow = isOriginal ? "none" : shadow;

  const padPx = PAD_PX[effPadding];
  const outW = SOURCE_W + padPx * 2 * SCALE;
  const outH = SOURCE_H + padPx * 2 * SCALE;
  const effFormat: Format = isOriginal ? "png" : format;
  const sizeKB = isOriginal ? estimateKB(SOURCE_W, SOURCE_H, "png", "high") : estimateKB(outW, outH, effFormat, quality);

  return (
    <div className="grid" style={{ gridTemplateColumns: "1fr 312px", minHeight: 560 }}>
      {/* ── Left: live preview ─────────────────────────────────── */}
      <div className="relative flex items-center justify-center p-8" style={{ background: T.pane, borderRight: `0.5px solid ${T.edge}` }}>
        <PreviewStage background={effBackground} padPx={padPx} cornerPx={CORNER_PX[effCorner]} shadow={SHADOW_CSS[effShadow]} />
        {toast ? (
          <div
            className="absolute bottom-5 left-1/2 -translate-x-1/2 rounded-[6px] px-3 py-1.5 font-mono text-[11px] tracking-[0.06em]"
            style={{ background: T.ink, color: T.white, boxShadow: "0 6px 18px rgba(0,0,0,0.22)" }}
          >
            {toast}
          </div>
        ) : null}
      </div>

      {/* ── Right: inspector ───────────────────────────────────── */}
      <div className="flex flex-col" style={{ background: T.canvas }}>
        <div className="flex-1 overflow-y-auto px-4 py-4">
          {/* Presets */}
          <Group label="Preset">
            <div className="grid grid-cols-2 gap-1.5">
              <PresetChip label="Original" sub="source pixels" active={preset === "original"} onClick={() => applyPreset("original")} />
              <PresetChip label="Polished" sub="framed" active={preset === "polished"} onClick={() => applyPreset("polished")} />
            </div>
          </Group>

          {isOriginal ? (
            <div
              className="mt-3 rounded-[6px] px-3 py-2.5 font-mono text-[10px] leading-relaxed tracking-[0.04em]"
              style={{ background: T.pane, border: `0.5px solid ${T.edgeSubtle}`, color: T.inkFaint }}
            >
              ORIGINAL · emits source pixels · no styling · no recompression. Framing controls disabled.
            </div>
          ) : null}

          <Divider />

          {/* Framing controls (disabled under Original) */}
          <fieldset disabled={isOriginal} style={{ opacity: isOriginal ? 0.4 : 1, transition: "opacity 120ms" }}>
            <Group label="Background">
              <Segmented<Background>
                value={background}
                onChange={setBackground}
                options={[
                  { value: "none", label: "None" },
                  { value: "solid", label: "Solid" },
                  { value: "theme", label: "Theme" },
                  { value: "gradient", label: "Gradient" },
                  { value: "blur", label: "Blur" },
                ]}
              />
            </Group>

            <Group label="Padding">
              <Segmented<Padding>
                value={padding}
                onChange={setPadding}
                options={[
                  { value: "none", label: "None" },
                  { value: "small", label: "S" },
                  { value: "medium", label: "M" },
                  { value: "large", label: "L" },
                ]}
              />
            </Group>

            <Group label="Corner radius">
              <Segmented<Corner>
                value={corner}
                onChange={setCorner}
                options={[
                  { value: "square", label: "Square" },
                  { value: "subtle", label: "Subtle" },
                  { value: "rounded", label: "Rounded" },
                ]}
              />
            </Group>

            <Group label="Shadow">
              <Segmented<Shadow>
                value={shadow}
                onChange={setShadow}
                options={[
                  { value: "none", label: "None" },
                  { value: "soft", label: "Soft" },
                  { value: "presentation", label: "Present" },
                ]}
              />
            </Group>

            <Divider />

            <Group label="Format">
              <Segmented<Format>
                value={format}
                onChange={setFormat}
                options={[
                  { value: "png", label: "PNG" },
                  { value: "jpeg", label: "JPEG" },
                ]}
              />
            </Group>

            <div style={{ opacity: format === "jpeg" ? 1 : 0.4, transition: "opacity 120ms" }}>
              <Group label="JPEG quality">
                <fieldset disabled={format !== "jpeg"}>
                  <Segmented<Quality>
                    value={quality}
                    onChange={setQuality}
                    options={[
                      { value: "small", label: "Small" },
                      { value: "medium", label: "Medium" },
                      { value: "high", label: "High" },
                    ]}
                  />
                </fieldset>
              </Group>
            </div>
          </fieldset>

          <Divider />

          {/* Readout */}
          <div className="rounded-[6px] px-3 py-2.5" style={{ background: T.pane, border: `0.5px solid ${T.edgeSubtle}` }}>
            <ReadoutRow k="Dimensions" v={`${outW} × ${outH} px`} />
            <ReadoutRow k="Scale" v="@2× source · sRGB" />
            <ReadoutRow k={effFormat === "png" ? "PNG" : `JPEG · ${quality}`} v={`~${fmtSize(sizeKB)}`} />
          </div>
        </div>

        {/* Actions pinned to the bottom */}
        <div className="flex gap-2 px-4 py-3" style={{ borderTop: `0.5px solid ${T.edge}`, background: T.chrome }}>
          <button
            type="button"
            onClick={() => flashToast("Copied to clipboard")}
            className="flex-1 rounded-[7px] py-2 font-mono text-[12px] font-semibold uppercase tracking-[0.08em] transition-colors"
            style={{ background: T.amber, color: T.white }}
            onMouseDown={(e) => (e.currentTarget.style.background = T.amberDeep)}
            onMouseUp={(e) => (e.currentTarget.style.background = T.amber)}
          >
            Copy
          </button>
          <button
            type="button"
            onClick={() => flashToast("Saved · Reveal in Finder")}
            className="flex-1 rounded-[7px] py-2 font-mono text-[12px] font-semibold uppercase tracking-[0.08em] transition-colors"
            style={{ background: T.white, color: T.ink, border: `0.5px solid ${T.edge}` }}
          >
            Save As…
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Preview stage ──────────────────────────────────────────────────────

function PreviewStage({ background, padPx, cornerPx, shadow }: {
  background: Background; padPx: number; cornerPx: number; shadow: string;
}) {
  const fill =
    background === "none" ? "transparent" :
    background === "solid" ? SOLID_FILL :
    background === "theme" ? THEME_FILL :
    background === "gradient" ? GRADIENT_FILL :
    "transparent"; // blur handled by layer below

  // Transparent → checkerboard so "none" reads as transparency, not white.
  const checker =
    background === "none"
      ? {
          backgroundImage:
            "linear-gradient(45deg,#E3E3E2 25%,transparent 25%),linear-gradient(-45deg,#E3E3E2 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#E3E3E2 75%),linear-gradient(-45deg,transparent 75%,#E3E3E2 75%)",
          backgroundSize: "16px 16px",
          backgroundPosition: "0 0,0 8px,8px -8px,-8px 0",
        }
      : {};

  return (
    <div
      className="relative flex items-center justify-center overflow-hidden rounded-[10px]"
      style={{ background: fill, ...checker, padding: padPx, width: "100%", maxWidth: 760, aspectRatio: `${SOURCE_W} / ${SOURCE_H}`, border: `0.5px solid ${T.edgeSubtle}` }}
    >
      {background === "blur" ? (
        <div className="absolute inset-0" style={{ transform: "scale(1.4)", filter: "blur(28px) saturate(1.1)", opacity: 0.85 }}>
          <SyntheticCapture cornerPx={0} />
        </div>
      ) : null}
      <div className="relative" style={{ width: "100%", height: "100%", boxShadow: shadow, borderRadius: cornerPx }}>
        <SyntheticCapture cornerPx={cornerPx} />
      </div>
    </div>
  );
}

// A believable grabbed app window — stands in for the user's screenshot.
// Deliberately not Scope-token styled: a real capture is foreign content.
function SyntheticCapture({ cornerPx }: { cornerPx: number }) {
  return (
    <div className="h-full w-full overflow-hidden" style={{ borderRadius: cornerPx, background: "#FBFBFD", border: "0.5px solid rgba(0,0,0,0.08)" }}>
      {/* faux titlebar */}
      <div className="flex items-center gap-1.5 px-2.5 py-1.5" style={{ background: "#2B2D31" }}>
        <span className="h-2 w-2 rounded-full" style={{ background: "#FF5F57" }} />
        <span className="h-2 w-2 rounded-full" style={{ background: "#FEBC2E" }} />
        <span className="h-2 w-2 rounded-full" style={{ background: "#28C840" }} />
        <span className="ml-2 font-mono text-[7px] tracking-[0.1em]" style={{ color: "rgba(255,255,255,0.5)" }}>bay · scheme compare</span>
      </div>
      {/* faux content: 9-up swatch grid + caption lines */}
      <div className="flex h-full gap-2 p-3" style={{ background: "#F3F4F6" }}>
        <div className="grid flex-1 grid-cols-3 gap-1.5">
          {["#C9B79C", "#E8E6E2", "#D7C9B0", "#EAEEF1", "#F5F8FA", "#DCDCDB", "#EFE9D8", "#F7F4EC", "#F5F2E8"].map((c, i) => (
            <div key={i} className="rounded-[3px]" style={{ background: c, border: "0.5px solid rgba(0,0,0,0.06)", aspectRatio: "16/10" }} />
          ))}
        </div>
        <div className="flex w-[28%] flex-col gap-1.5 pt-0.5">
          <div className="h-1.5 w-3/4 rounded-full" style={{ background: "#C9CCD2" }} />
          <div className="h-1.5 w-full rounded-full" style={{ background: "#DADCE1" }} />
          <div className="h-1.5 w-2/3 rounded-full" style={{ background: "#DADCE1" }} />
          <div className="mt-2 h-1.5 w-1/2 rounded-full" style={{ background: "#C9CCD2" }} />
          <div className="h-1.5 w-full rounded-full" style={{ background: "#DADCE1" }} />
        </div>
      </div>
    </div>
  );
}

// ── Inspector primitives ───────────────────────────────────────────────

function Group({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="mb-3">
      <div className="mb-1.5 font-mono text-[9px] font-semibold uppercase tracking-[0.16em]" style={{ color: T.inkFaint }}>
        {label}
      </div>
      {children}
    </div>
  );
}

function Divider() {
  return <div className="my-3 h-px w-full" style={{ background: T.ruleSubtle }} />;
}

function Segmented<V extends string>({ value, onChange, options }: {
  value: V; onChange: (v: V) => void; options: { value: V; label: string }[];
}) {
  return (
    <div className="flex gap-1 rounded-[7px] p-1" style={{ background: T.pane, border: `0.5px solid ${T.edgeSubtle}` }}>
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={o.value}
            type="button"
            onClick={() => onChange(o.value)}
            className="flex-1 rounded-[5px] py-1.5 text-[11px] font-medium transition-colors"
            style={active
              ? { background: T.white, color: T.ink, boxShadow: "0 1px 2px rgba(0,0,0,0.10)" }
              : { background: "transparent", color: T.inkFaint }}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

function PresetChip({ label, sub, active, onClick }: { label: string; sub: string; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex flex-col items-start rounded-[8px] px-3 py-2 transition-colors"
      style={active
        ? { background: T.white, border: `1px solid ${T.amber}`, boxShadow: "0 1px 3px rgba(0,0,0,0.08)" }
        : { background: T.pane, border: `0.5px solid ${T.edgeSubtle}` }}
    >
      <span className="text-[13px] font-semibold" style={{ color: active ? T.ink : T.inkMid }}>{label}</span>
      <span className="font-mono text-[8px] uppercase tracking-[0.1em]" style={{ color: active ? T.amber : T.inkFainter }}>{sub}</span>
    </button>
  );
}

function ReadoutRow({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex items-baseline justify-between py-0.5">
      <span className="font-mono text-[9px] uppercase tracking-[0.12em]" style={{ color: T.inkFainter }}>{k}</span>
      <span className="font-mono text-[11px] tabular-nums" style={{ color: T.inkMid }}>{v}</span>
    </div>
  );
}

// ── Study chrome: Original vs Polished reference + porting notes ────────
// These two blocks are NOT part of the shipped surface. They exist so a
// reviewer can read the contrast and a Swift porter has the spec inline.

function ReferenceStrip() {
  return (
    <section className="w-full" style={{ maxWidth: 1120 }}>
      <div className="mb-2 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
        · reference · Original vs Polished · the V1 contrast
      </div>
      <div className="grid grid-cols-2 gap-4">
        <RefCard
          title="Original"
          note="No background · no padding · square (source) corners · no shadow · PNG source · no recompression."
          background="none" padPx={0} cornerPx={0} shadow="none"
        />
        <RefCard
          title="Polished"
          note="Theme surface · medium padding · subtle corners · soft shadow · PNG (or JPEG/High)."
          background="theme" padPx={28} cornerPx={8} shadow={SHADOW_CSS.soft}
        />
      </div>
    </section>
  );
}

function RefCard({ title, note, background, padPx, cornerPx, shadow }: {
  title: string; note: string; background: Background; padPx: number; cornerPx: number; shadow: string;
}) {
  return (
    <div className="rounded-[8px] p-3" style={{ background: T.pane, border: `0.5px solid ${T.edgeSubtle}` }}>
      <div className="mb-2 flex items-baseline justify-between">
        <span className="text-[12px] font-semibold" style={{ color: T.ink }}>{title}</span>
      </div>
      <div className="flex items-center justify-center rounded-[8px]" style={{ background: background === "theme" ? THEME_FILL : T.canvas, height: 220, padding: padPx + 20 }}>
        <div style={{ width: "100%", maxWidth: 320, aspectRatio: `${SOURCE_W} / ${SOURCE_H}`, boxShadow: shadow, borderRadius: cornerPx }}>
          <SyntheticCapture cornerPx={cornerPx} />
        </div>
      </div>
      <div className="mt-2 font-mono text-[9px] leading-relaxed tracking-[0.03em]" style={{ color: T.inkFaint }}>{note}</div>
    </div>
  );
}

function PortingNotes() {
  const rows: { k: string; v: string }[] = [
    { k: "Surface", v: "Right-side inspector over capture detail. Not modal, not a nav destination." },
    { k: "Input", v: "Resolved screenshot file URL (via CaptureMediaFileResolver) + ExportRecipe. Not a bare UUID." },
    { k: "Renderer", v: "ExportRecipe + ExportRenderer live in TalkieKit (Agent reuse). Views build the recipe; TalkieKit renders." },
    { k: "Copy", v: "Pasteboard: PNG (+ TIFF); JPEG bytes when format=JPEG. No file URL on Copy — that's Save As." },
    { k: "Save As", v: "NSSavePanel · default name from title/timestamp · offer Reveal in Finder on success." },
    { k: "Scale / color", v: "Export at source-native scale (@2× capture → full px). Preserve source color space; no silent sRGB shift." },
    { k: "Original", v: "Locks to raw source pixels. Styling + format/quality disabled. Never recompresses." },
    { k: "Missing file", v: "If resolver finds no file: show 'original no longer available', disable Copy/Save As. Resolve up front." },
    { k: "Out of V1", v: "No video/clips/recording cards · no destinations · no Private mode · no WebP/GIF/bundles." },
    { k: "Open Q", v: "Min macOS target gates ImageRenderer (13+) vs AppKit raster path — answer before the Swift renderer." },
  ];
  return (
    <section className="w-full rounded-[8px] p-4" style={{ maxWidth: 1120, background: T.pane, border: `0.5px solid ${T.edgeSubtle}` }}>
      <div className="mb-3 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
        · swift porting notes · tlk-032 · study chrome only
      </div>
      <div className="grid gap-x-6 gap-y-2" style={{ gridTemplateColumns: "auto 1fr" }}>
        {rows.map((r) => (
          <React.Fragment key={r.k}>
            <div className="font-mono text-[10px] font-semibold uppercase tracking-[0.1em]" style={{ color: T.inkMid }}>{r.k}</div>
            <div className="text-[12px] leading-snug" style={{ color: T.inkFaint }}>{r.v}</div>
          </React.Fragment>
        ))}
      </div>
    </section>
  );
}
