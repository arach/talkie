"use client";

import { useState, type CSSProperties } from "react";
import { MacHome } from "@/components/studies/MacHome";
import { SCHEMES, type Scheme } from "@/lib/schemes";

/**
 * Mac Home — fullscreen canvas with a scheme picker.
 *
 * 2560px ≈ 27" external display @ 2x. Renders the Home composition
 * edge-to-edge so the layout's actual behavior at fullscreen is visible
 * without studio framing structure.
 *
 * The strip at the top lets you toggle between the five light-touch
 * schemes (PAPER / VELLUM / CHIFFON warm; PORCELAIN / PEARL cool) plus
 * a "Canvas" baseline (no scheme vars — the bare cream page bg).
 * Used to re-evaluate which material the surface should commit to.
 *
 * Scroll the page horizontally if your browser viewport is narrower
 * than the artifact width.
 */

const FULLSCREEN_WIDTH = 2560;

// Light-touch siblings only — the materials the page would actually
// commit to. Dark / metallic schemes (CARBON, SLATE, etc.) aren't
// relevant for a cream-canvas Home and are skipped on purpose.
const LIGHT_SCHEME_KEYS = [
  "paper",
  "vellum",
  "chiffon",
  "porcelain",
  "pearl",
  "frost",
];

export default function MacHomeWideStudy() {
  const [activeKey, setActiveKey] = useState<string | null>(null);
  const lightSchemes = SCHEMES.filter((s) => LIGHT_SCHEME_KEYS.includes(s.key));
  const active = lightSchemes.find((s) => s.key === activeKey) ?? null;

  return (
    <div className="min-h-screen overflow-x-auto" style={{ background: "#FBFBFA" }}>
      <SchemeBar
        width={FULLSCREEN_WIDTH}
        schemes={lightSchemes}
        activeKey={activeKey}
        onSelect={setActiveKey}
      />
      <div
        style={{
          width: FULLSCREEN_WIDTH,
          ...(active?.vars as CSSProperties | undefined),
        }}
      >
        <MacHome width={FULLSCREEN_WIDTH} />
      </div>
    </div>
  );
}

interface SchemeBarProps {
  width: number;
  schemes: Scheme[];
  activeKey: string | null;
  onSelect: (key: string | null) => void;
}

function SchemeBar({ width, schemes, activeKey, onSelect }: SchemeBarProps) {
  return (
    <div
      className="flex items-baseline gap-5 border-b border-studio-edge px-7 py-3 font-mono text-[9px] uppercase tracking-[0.20em]"
      style={{ width, background: "#F4F1EA" }}
    >
      <span className="text-studio-ink-faint">· Mac Home · Fullscreen · Scheme</span>
      <div className="flex items-center gap-3">
        <SchemeChip
          label="Canvas"
          swatch="#FBFBFA"
          bgHex="#FBFBFA"
          active={activeKey === null}
          onClick={() => onSelect(null)}
        />
        {schemes.map((s) => (
          <SchemeChip
            key={s.key}
            label={s.name}
            swatch={s.swatch}
            bgHex={s.bgHex}
            active={activeKey === s.key}
            onClick={() => onSelect(s.key)}
          />
        ))}
      </div>
      <span className="ml-auto text-studio-ink-faint">{width}px · scroll if needed</span>
    </div>
  );
}

interface SchemeChipProps {
  label: string;
  swatch: string;
  bgHex: string;
  active: boolean;
  onClick: () => void;
}

function SchemeChip({ label, swatch, bgHex, active, onClick }: SchemeChipProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex items-center gap-2 rounded-[2px] border px-2 py-[3px] transition-colors ${
        active
          ? "border-studio-ink text-studio-ink"
          : "border-studio-edge text-studio-ink-faint hover:text-studio-ink"
      }`}
      style={{ background: active ? bgHex : "transparent" }}
    >
      <span
        aria-hidden
        className="inline-block h-[8px] w-[8px] rounded-full"
        style={{ background: swatch }}
      />
      <span>{label}</span>
      <span className="text-[8px] tracking-[0.16em] opacity-60">{bgHex}</span>
    </button>
  );
}
