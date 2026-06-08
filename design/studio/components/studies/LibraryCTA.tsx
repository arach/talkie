"use client";

/**
 * LibraryCTA — the studio harness for the Library's contextual primary
 * action: a round button that swaps with the active tab (mic to record a
 * memo · keyboard to type a dictation · viewfinder to grab a capture).
 *
 * Three axes to compare, layout frozen:
 *   • Material — Accent (filled, the shipped look) · Glass (dark, like the
 *     shell summon) · Ring (ghost outline).
 *   • Size — 52 / 62 / 72.
 *   • Label — icon only, or a tiny caption underneath.
 *
 * Port target: LibraryCTA in apps/ios/Talkie iOS/Views/Next/LibraryNextView.swift
 */

import { useState, type CSSProperties } from "react";
import { IOS_THEMES } from "@/lib/themes";

export type CTAMaterial = "accent" | "glass" | "ring";
export type CTATab = "memos" | "dictations" | "items";
export type CTASize = "sm" | "md" | "lg";

export const MATERIAL_LIST: { key: CTAMaterial; name: string; blurb: string }[] = [
  {
    key: "accent",
    name: "Accent",
    blurb:
      "The shipped look — accent-filled with a top sheen + the deck's two-layer lift. Reads as the one tappable thing on a quiet surface.",
  },
  {
    key: "glass",
    name: "Glass",
    blurb:
      "Dark translucent with an accent ring + accent glyph — matches the shell's bottom-left summon, so the two bottom buttons read as one family.",
  },
  {
    key: "ring",
    name: "Ring",
    blurb:
      "Ghost outline — accent ring + glyph, no fill. Quietest; recedes until you look for it.",
  },
];

export const TAB_LIST: { key: CTATab; name: string }[] = [
  { key: "memos", name: "Memos" },
  { key: "dictations", name: "Dictations" },
  { key: "items", name: "Items" },
];

const TAB_META: Record<CTATab, { label: string; Icon: () => React.ReactElement }> = {
  memos: { label: "Record", Icon: MicIcon },
  dictations: { label: "Dictate", Icon: KeyboardIcon },
  items: { label: "Capture", Icon: ViewfinderIcon },
};

const SIZE_PX: Record<CTASize, number> = { sm: 52, md: 62, lg: 72 };

// ── The button ──────────────────────────────────────────────────
export function Fab({
  material,
  tab,
  size = "md",
  withLabel = false,
}: {
  material: CTAMaterial;
  tab: CTATab;
  size?: CTASize;
  withLabel?: boolean;
}) {
  const px = SIZE_PX[size];
  const { label, Icon } = TAB_META[tab];
  const glyph = px * 0.36;

  const surface = MATERIAL_STYLE[material];

  return (
    <div className="flex flex-col items-center gap-2">
      <button
        aria-label={`${label} (${tab})`}
        className="relative grid place-items-center rounded-full"
        style={{
          width: px,
          height: px,
          color: surface.glyph,
          ...surface.box,
        }}
      >
        {/* top sheen — catches light from above */}
        <span
          aria-hidden
          className="pointer-events-none absolute inset-0 rounded-full"
          style={{ background: surface.sheen }}
        />
        <span style={{ width: glyph, height: glyph }} className="relative grid place-items-center">
          <Icon />
        </span>
      </button>
      {withLabel && (
        <span
          className="text-[9px] font-semibold uppercase tracking-[0.16em]"
          style={{
            color:
              material === "accent"
                ? "var(--theme-ink-faint)"
                : "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {label}
        </span>
      )}
    </div>
  );
}

const MATERIAL_STYLE: Record<
  CTAMaterial,
  { box: CSSProperties; sheen: string; glyph: string }
> = {
  accent: {
    box: {
      background: "var(--theme-amber)",
      boxShadow:
        "inset 0 0 0 0.5px rgba(255,255,255,0.16), 0 7px 16px -2px color-mix(in srgb, var(--theme-amber) 45%, transparent), 0 1px 3px rgba(0,0,0,0.34)",
    },
    sheen:
      "linear-gradient(180deg, rgba(255,255,255,0.22), transparent 50%)",
    glyph: "rgba(0,0,0,0.82)",
  },
  glass: {
    box: {
      background:
        "color-mix(in srgb, var(--theme-screen-bg, #141416) 86%, #000)",
      boxShadow:
        "inset 0 0 0 1px color-mix(in srgb, var(--theme-amber) 40%, transparent), 0 6px 16px rgba(0,0,0,0.45), 0 1px 2px rgba(0,0,0,0.4)",
    },
    sheen:
      "linear-gradient(180deg, rgba(255,255,255,0.07), transparent 50%)",
    glyph: "var(--theme-amber)",
  },
  ring: {
    box: {
      background: "rgba(255,255,255,0.02)",
      boxShadow: "inset 0 0 0 1.5px var(--theme-amber)",
    },
    sheen: "transparent",
    glyph: "var(--theme-amber)",
  },
};

// ── Context stage — the bottom of the Library, where the FAB lives ──
function Stage({
  themeKey,
  children,
}: {
  themeKey: string;
  children: React.ReactNode;
}) {
  return (
    <div
      data-theme={themeKey}
      className="relative flex h-[200px] w-[260px] flex-col justify-end overflow-hidden rounded-2xl"
      style={{ background: "var(--theme-canvas)" }}
    >
      {/* a whisper of list context up top so the button reads in place */}
      <div className="absolute inset-x-0 top-0 flex flex-col gap-2 p-3">
        <div
          className="h-9 rounded-xl"
          style={{
            background: "var(--theme-paper)",
            boxShadow: "inset 0 0 0 0.5px var(--theme-edge-faint, rgba(255,255,255,0.06))",
          }}
        />
        <div
          className="h-7 rounded-full opacity-60"
          style={{ background: "var(--theme-paper)" }}
        />
      </div>
      <div className="relative flex items-center justify-center pb-6">
        {children}
      </div>
    </div>
  );
}

// ── Studio views ────────────────────────────────────────────────
const PLAYGROUND_THEME_KEYS = ["scope", "lift", "midnight", "graphite"];
const BOARD_THEME_KEY = "midnight";

function themesByKey(keys: string[]) {
  return keys
    .map((k) => IOS_THEMES.find((t) => t.key === k))
    .filter((t): t is (typeof IOS_THEMES)[number] => Boolean(t));
}

export function LibraryCTAStudio() {
  return (
    <div className="flex flex-col gap-12">
      <Playground />
      <PerThemeBoard />
      <Board />
    </div>
  );
}

// Each theme picks its own permutation — the divergence vision. Today the
// app ships one shared default (Accent · 62 · no label); this is the room
// we're leaving for themes to increasingly stand out over time.
const PER_THEME: Record<string, { material: CTAMaterial; size: CTASize; withLabel: boolean }> = {
  scope: { material: "ring", size: "sm", withLabel: false },
  lift: { material: "accent", size: "md", withLabel: false },
  midnight: { material: "glass", size: "lg", withLabel: true },
  graphite: { material: "accent", size: "lg", withLabel: false },
};

function PerThemeBoard() {
  const themes = themesByKey(PLAYGROUND_THEME_KEYS);
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Per-theme permutations"
        hint="the seam — each theme free to pick its own material / size / label over time"
      />
      <div className="flex flex-wrap gap-6">
        {themes.map((theme) => {
          const p = PER_THEME[theme.key] ?? {
            material: "accent" as CTAMaterial,
            size: "md" as CTASize,
            withLabel: false,
          };
          return (
            <div key={theme.key} className="flex flex-col gap-2">
              <div className="flex items-baseline gap-2 px-1">
                <span
                  aria-hidden
                  className="inline-block h-[9px] w-[9px] rounded-full"
                  style={{ background: theme.canvasHex, border: "0.5px solid #E0DCD3" }}
                />
                <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-stone-600">
                  {theme.name}
                </span>
                <span className="font-mono text-[9px] uppercase tracking-[0.1em] text-stone-400">
                  {p.material} · {SIZE_PX[p.size]}
                  {p.withLabel ? " · label" : ""}
                </span>
              </div>
              <Stage themeKey={theme.key}>
                <Fab material={p.material} tab="memos" size={p.size} withLabel={p.withLabel} />
              </Stage>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Playground() {
  const [material, setMaterial] = useState<CTAMaterial>("accent");
  const [tab, setTab] = useState<CTATab>("memos");
  const [size, setSize] = useState<CTASize>("md");
  const [withLabel, setWithLabel] = useState(false);
  const themes = themesByKey(PLAYGROUND_THEME_KEYS);
  const active = MATERIAL_LIST.find((m) => m.key === material);

  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Playground"
        hint="pick a material + tab + size — see it across cream / white / dark / neutral"
      />

      <div className="flex flex-wrap items-center gap-3">
        <Segmented
          options={MATERIAL_LIST.map((m) => ({ value: m.key, label: m.name }))}
          value={material}
          onChange={(v) => setMaterial(v as CTAMaterial)}
        />
        <Segmented
          options={TAB_LIST.map((t) => ({ value: t.key, label: t.name }))}
          value={tab}
          onChange={(v) => setTab(v as CTATab)}
        />
        <Segmented
          options={[
            { value: "sm", label: "52" },
            { value: "md", label: "62" },
            { value: "lg", label: "72" },
          ]}
          value={size}
          onChange={(v) => setSize(v as CTASize)}
        />
        <Segmented
          options={[
            { value: "off", label: "Icon" },
            { value: "on", label: "+ Label" },
          ]}
          value={withLabel ? "on" : "off"}
          onChange={(v) => setWithLabel(v === "on")}
        />
      </div>

      {active && (
        <p className="max-w-[680px] text-[12.5px] italic leading-relaxed text-stone-500">
          <span className="font-mono not-italic uppercase tracking-[0.14em] text-stone-700">
            {active.name}
          </span>
          {" — "}
          {active.blurb}
        </p>
      )}

      <div className="flex flex-wrap gap-6">
        {themes.map((theme) => (
          <div key={theme.key} className="flex flex-col gap-2">
            <div className="flex items-baseline gap-2 px-1">
              <span
                aria-hidden
                className="inline-block h-[9px] w-[9px] rounded-full"
                style={{ background: theme.canvasHex, border: "0.5px solid #E0DCD3" }}
              />
              <span className="font-mono text-[10px] uppercase tracking-[0.14em] text-stone-600">
                {theme.name}
              </span>
            </div>
            <Stage themeKey={theme.key}>
              <Fab material={material} tab={tab} size={size} withLabel={withLabel} />
            </Stage>
          </div>
        ))}
      </div>
    </div>
  );
}

function Board() {
  const theme = themesByKey([BOARD_THEME_KEY])[0];
  if (!theme) return null;
  return (
    <div className="flex flex-col gap-5">
      <SectionHeading
        label="Material × Tab · Midnight"
        hint="every material against every tab glyph, icon-only, on the dark library"
      />
      <div
        data-theme={theme.key}
        className="grid gap-x-10 gap-y-8 rounded-2xl p-8"
        style={{
          gridTemplateColumns: `120px repeat(${TAB_LIST.length}, 1fr)`,
          background: "var(--theme-canvas)",
        }}
      >
        <div />
        {TAB_LIST.map((t) => (
          <div
            key={t.key}
            className="text-center font-mono text-[10px] uppercase tracking-[0.16em]"
            style={{ color: "var(--theme-ink-faint)" }}
          >
            {t.name}
          </div>
        ))}
        {MATERIAL_LIST.map((m) => (
          <div key={m.key} className="contents">
            <div
              className="flex items-center font-mono text-[10px] uppercase tracking-[0.16em]"
              style={{ color: "var(--theme-ink-faint)" }}
            >
              {m.name}
            </div>
            {TAB_LIST.map((t) => (
              <div key={t.key} className="flex items-center justify-center">
                <Fab material={m.key} tab={t.key} size="md" />
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Glyphs — stroke style matching the deck icons ───────────────
function MicIcon() {
  return (
    <svg viewBox="0 0 20 20" className="h-full w-full" fill="none" aria-hidden>
      <rect x="7.25" y="2.25" width="5.5" height="9.5" rx="2.75" fill="currentColor" />
      <path
        d="M5 9.5a5 5 0 0 0 10 0M10 14.5V17M7 17h6"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function KeyboardIcon() {
  return (
    <svg viewBox="0 0 20 20" className="h-full w-full" fill="none" aria-hidden>
      <rect
        x="2.25"
        y="5.25"
        width="15.5"
        height="9.5"
        rx="2"
        stroke="currentColor"
        strokeWidth="1.5"
      />
      <path
        d="M5.5 8.5h.01M8.5 8.5h.01M11.5 8.5h.01M14.5 8.5h.01M7 11.5h6"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function ViewfinderIcon() {
  return (
    <svg viewBox="0 0 20 20" className="h-full w-full" fill="none" aria-hidden>
      <path
        d="M3 7V5a2 2 0 0 1 2-2h2M13 3h2a2 2 0 0 1 2 2v2M17 13v2a2 2 0 0 1-2 2h-2M7 17H5a2 2 0 0 1-2-2v-2"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="10" cy="10" r="2.4" fill="currentColor" />
    </svg>
  );
}

// ── Shared studio chrome (matches DeckPlayground) ────────────────
function SectionHeading({ label, hint }: { label: string; hint: string }) {
  return (
    <div className="flex items-baseline gap-3">
      <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em] text-stone-600">
        {label}
      </span>
      <span className="italic text-stone-400" style={{ fontSize: 12 }}>
        {hint}
      </span>
      <div className="ml-1 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
    </div>
  );
}

function Segmented({
  options,
  value,
  onChange,
}: {
  options: { value: string; label: string }[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="inline-flex rounded-lg border border-stone-200 bg-white p-1">
      {options.map((o) => {
        const on = o.value === value;
        return (
          <button
            key={o.value}
            onClick={() => onChange(o.value)}
            className={`rounded-md px-3 py-1.5 font-mono text-[11px] uppercase tracking-[0.12em] transition ${
              on ? "bg-stone-900 text-white" : "text-stone-500 hover:text-stone-800"
            }`}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
