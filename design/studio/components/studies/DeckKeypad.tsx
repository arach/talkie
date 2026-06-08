"use client";

/**
 * iOS · Deck Keypad — variant study.
 *
 * The deck's bottom 4×4 grid (TileGrid in DeckMirrorNext.swift) renders
 * 16 flat `paper` cards with a hairline border, floating on the canvas
 * with gaps — it reads as "a bunch of floating buttons." This study
 * commits the grid to ONE physical keypad: a recessed Faceplate with
 * the keys seated in it, so it reads like a Stream-Deck / macro pad /
 * MPC bank rather than scattered cards.
 *
 * Three takes, differing in the key↔plate depth model:
 *   • V1 · Faceplate    — keys are raised keycaps seated in a recessed plate.
 *   • V2 · Sunk Pads    — keys are sunk into routed sockets; gutters are ribs.
 *   • V3 · Backlit Keys — raised keys that read as illuminated (powered device).
 *
 * Real tiles (Dictate · Memo · Voice · … · Share) so it matches the
 * shipping deck, not the Safari sample in IOSDeck.tsx. Named parts in
 * <NamesMarginalia>.
 */

import { IOS_THEMES } from "@/lib/themes";

type Variant = "faceplate" | "sunk" | "backlit";

const VARIANTS: { key: Variant; name: string; blurb: string }[] = [
  { key: "faceplate", name: "V1 · Faceplate", blurb: "Keys are raised keycaps seated in a recessed plate — light from above, soft bottom shadow. Stream-Deck body. The quiet default." },
  { key: "sunk", name: "V2 · Sunk Pads", blurb: "Keys sunk into routed sockets; the gutters become raised ribs between them. Inverse depth — an MPC / sealed membrane pad." },
  { key: "backlit", name: "V3 · Backlit Keys", blurb: "Raised keys that read as illuminated — brighter glyphs, a faint top glow, the active key fully lit amber. A powered device." },
];

// ── Real deck tiles (mirrors DeckLegacyDisplayInfo in
//    DeckBoardSnapshot.swift). Slot 0 = dictation. `mac` = the MAC hint. ──
type Tile = { id: IconName; label: string; mac?: boolean };

const DECK_TILES: Tile[] = [
  { id: "mic", label: "Dictate" },
  { id: "memo", label: "Memo" },
  { id: "voice", label: "Voice" },
  { id: "search", label: "Search" },
  { id: "claude", label: "Claude", mac: true },
  { id: "pi", label: "Pi" },
  { id: "shell", label: "Shell" },
  { id: "workflow", label: "Workflow", mac: true },
  { id: "desktop", label: "Desktop", mac: true },
  { id: "screen", label: "Screen" },
  { id: "memos", label: "Memos" },
  { id: "command", label: "Command" },
  { id: "pending", label: "Pending" },
  { id: "recent", label: "Recent" },
  { id: "home", label: "Home" },
  { id: "share", label: "Share", mac: true },
];

// ── Study body ──────────────────────────────────────────────────────

export function DeckKeypadStudy() {
  return (
    <div className="flex flex-col gap-12">
      <p className="max-w-[66ch] font-display italic" style={{ color: "#76767A", fontSize: 13, lineHeight: 1.5 }}>
        Same 16 tiles, same labels — the change is the housing and the key
        material. Each keypad seats the tiles in one recessed Faceplate
        with even gutters and gives every key real depth, so the grid
        reads as a physical macro deck instead of floating cards. The
        Dictate key is shown lit in each, to preview the active/press state.
      </p>

      {/* A/B/C — the three keypads side by side on one dark chassis. */}
      <Section label="Three takes" hint="dark chassis · Dictate key lit to show the active state">
        <div className="flex flex-wrap gap-8">
          {VARIANTS.map((v) => (
            <div key={v.key} className="flex w-[330px] flex-col gap-3">
              <VariantLabel name={v.name} blurb={v.blurb} />
              <div data-theme="midnight">
                <Chassis>
                  <Keypad variant={v.key} activeId="mic" />
                </Chassis>
              </div>
            </div>
          ))}
        </div>
      </Section>

      {/* In context — the recommended default (Faceplate) across themes. */}
      <Section label="Faceplate across themes" hint="token behaviour on every iOS bundle">
        <div className="flex flex-wrap gap-6">
          {IOS_THEMES.map((theme) => (
            <div key={theme.key} className="flex flex-col gap-2">
              <span className="font-mono text-[9px] uppercase tracking-[0.18em]" style={{ color: "#9A9A9E" }}>
                {theme.key}
              </span>
              <div data-theme={theme.key} className="w-[300px]">
                <Chassis>
                  <Keypad variant="faceplate" activeId={null} />
                </Chassis>
              </div>
            </div>
          ))}
        </div>
      </Section>

      <NamesMarginalia />
    </div>
  );
}

// ── Chassis ─────────────────────────────────────────────────────────

function Chassis({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="rounded-2xl p-2.5"
      style={{ background: "var(--theme-canvas)", boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)" }}
    >
      {children}
    </div>
  );
}

// ── The Keypad ──────────────────────────────────────────────────────

function Keypad({ variant, activeId }: { variant: Variant; activeId: IconName | null }) {
  return (
    <div className="grid grid-cols-4" style={faceplateStyle(variant)}>
      {DECK_TILES.map((tile) => (
        <Key key={tile.id} tile={tile} variant={variant} active={tile.id === activeId} />
      ))}
    </div>
  );
}

function Key({ tile, variant, active }: { tile: Tile; variant: Variant; active: boolean }) {
  const glyph = active ? "var(--theme-amber)" : variant === "backlit" ? "var(--theme-ink)" : "var(--theme-ink-dim)";
  const label = active ? "var(--theme-amber)" : "var(--theme-ink-dim)";
  return (
    <button
      aria-label={tile.label}
      className="relative flex min-h-[64px] flex-col items-center justify-center gap-1 px-1"
      style={{ borderRadius: 9, ...keyStyle(variant, active) }}
    >
      <TileIcon name={tile.id} color={glyph} />
      <span className="font-mono text-[10px] leading-none tracking-tight" style={{ color: label }}>
        {tile.label}
      </span>
      {tile.mac && (
        <span
          className="absolute right-1.5 top-1.5 font-mono text-[7px] tracking-[0.16em]"
          style={{ color: "var(--theme-ink-faint)" }}
        >
          MAC
        </span>
      )}
    </button>
  );
}

// ── Depth styling ───────────────────────────────────────────────────

function faceplateStyle(variant: Variant): React.CSSProperties {
  const base: React.CSSProperties = { borderRadius: 16, padding: 8, gap: 8 };
  switch (variant) {
    case "faceplate":
      return {
        ...base,
        background: "var(--theme-screen-bg)",
        // recess + anodised bevel: top edge catches light, bottom falls to shadow
        boxShadow: [
          "inset 0 2px 6px rgba(0,0,0,0.5)",
          "inset 0 1px 0 rgba(255,255,255,0.12)",
          "inset 0 -1px 0 rgba(0,0,0,0.40)",
          "inset 0 0 0 1px var(--theme-edge-faint)",
        ].join(", "),
      };
    case "sunk":
      // Lighter plate so the sunk sockets + rib gutters read as ridges.
      return {
        ...base,
        gap: 7,
        background: "var(--theme-paper)",
        boxShadow:
          "0 2px 6px -1px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,0.05), inset 0 0 0 1px var(--theme-edge-faint)",
      };
    case "backlit":
      return {
        ...base,
        background: "#070709",
        boxShadow: "inset 0 2px 6px rgba(0,0,0,0.6), inset 0 0 0 1px rgba(255,255,255,0.04)",
      };
  }
}

function keyStyle(variant: Variant, active: boolean): React.CSSProperties {
  if (active) {
    return {
      background: "color-mix(in srgb, var(--theme-amber) 18%, var(--theme-paper))",
      boxShadow:
        "0 0 0 1px var(--theme-amber), 0 0 16px -3px var(--theme-amber-glow), inset 0 1px 0 rgba(255,255,255,0.10)",
      transform: "translateY(-0.5px)",
    };
  }
  switch (variant) {
    case "faceplate":
      return {
        // domed cap: top highlight, bottom inner shadow, seated drop shadow
        background: "var(--theme-paper)",
        boxShadow: [
          "0 1px 1.5px rgba(0,0,0,0.4)",
          "inset 0 1px 0 rgba(255,255,255,0.10)",
          "inset 0 -3px 5px -3px rgba(0,0,0,0.20)",
          "inset 0 0 0 1px var(--theme-edge-faint)",
        ].join(", "),
      };
    case "sunk":
      return {
        background: "var(--theme-screen-bg)",
        boxShadow: "inset 0 2px 4px rgba(0,0,0,0.5), inset 0 0 0 1px var(--theme-edge-faint)",
      };
    case "backlit":
      return {
        background: "color-mix(in srgb, var(--theme-paper) 88%, #000)",
        boxShadow:
          "inset 0 1px 0 rgba(255,255,255,0.10), inset 0 -6px 10px -8px var(--theme-amber-glow), inset 0 0 0 1px rgba(255,255,255,0.05)",
      };
  }
}

// ── Tile icons (line SVGs, currentColor via the `color` prop) ────────

type IconName =
  | "mic" | "memo" | "voice" | "search" | "claude" | "pi" | "shell" | "workflow"
  | "desktop" | "screen" | "memos" | "command" | "pending" | "recent" | "home" | "share";

function TileIcon({ name, color }: { name: IconName; color: string }) {
  const s = 1.5;
  const c = { stroke: color, strokeWidth: s, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, fill: "none" as const };
  const wrap = (children: React.ReactNode) => (
    <svg viewBox="0 0 20 20" className="h-[19px] w-[19px]" aria-hidden>
      {children}
    </svg>
  );
  switch (name) {
    case "mic":
      return wrap(<><rect x="7.5" y="2.5" width="5" height="9" rx="2.5" {...c} /><path d="M4.5 9.5a5.5 5.5 0 0 0 11 0M10 15v3" {...c} /></>);
    case "memo":
      return wrap(<><path d="M4 16l1-3 8-8 2 2-8 8-3 1z" {...c} /><path d="M12 5l3 3" {...c} /></>);
    case "voice":
      return wrap(<><path d="M4 10h0M7 7v6M10 4.5v11M13 7v6M16 10h0" {...c} /></>);
    case "search":
      return wrap(<><circle cx="9" cy="9" r="5" {...c} /><path d="M13 13l4 4" {...c} /></>);
    case "claude":
      return wrap(<><path d="M10 3l1.6 4.4L16 9l-4.4 1.6L10 15l-1.6-4.4L4 9l4.4-1.6z" {...c} /></>);
    case "pi":
      return wrap(<><circle cx="10" cy="5.5" r="1.6" {...c} /><circle cx="5.5" cy="11" r="1.6" {...c} /><circle cx="14.5" cy="11" r="1.6" {...c} /><circle cx="10" cy="15" r="1.6" {...c} /></>);
    case "shell":
      return wrap(<><rect x="3" y="4" width="14" height="12" rx="2" {...c} /><path d="M6 8l2.5 2L6 12M10.5 12.5h3.5" {...c} /></>);
    case "workflow":
      return wrap(<><path d="M5 15l7-7 2 2-7 7-3 1z" {...c} /><path d="M14 3l.7 1.8L16.5 5.5l-1.8.7L14 8l-.7-1.8L11.5 5.5l1.8-.7z" {...c} /></>);
    case "desktop":
      return wrap(<><rect x="3" y="4" width="14" height="9" rx="1.5" {...c} /><path d="M7 16h6M10 13v3" {...c} /></>);
    case "screen":
      return wrap(<><circle cx="10" cy="10" r="6.5" {...c} /><circle cx="10" cy="10" r="2.5" {...c} fill={color} /></>);
    case "memos":
      return wrap(<><path d="M5 6h10M5 10h10M5 14h6" {...c} /></>);
    case "command":
      return wrap(<><path d="M7.5 4a1.5 1.5 0 1 0 1.5 1.5V14.5A1.5 1.5 0 1 0 7.5 16h5A1.5 1.5 0 1 0 11 14.5V5.5A1.5 1.5 0 1 0 12.5 4z" {...c} /></>);
    case "pending":
      return wrap(<><path d="M6 3h8M6 17h8M7 3c0 4 6 4 6 7s-6 3-6 7M13 3c0 4-6 4-6 7" {...c} /></>);
    case "recent":
      return wrap(<><circle cx="10" cy="10" r="6.5" {...c} /><path d="M10 6.5V10l2.5 1.5" {...c} /></>);
    case "home":
      return wrap(<><path d="M4 9l6-5 6 5M6 8v8h8V8" {...c} /></>);
    case "share":
      return wrap(<><rect x="3.5" y="6" width="10" height="8" rx="1.5" {...c} /><path d="M7 6V4.5h9.5V13" {...c} /></>);
  }
}

// ── Layout helpers ──────────────────────────────────────────────────

function Section({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-4">
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-studio-ink">{label}</span>
        {hint && <span className="font-display italic" style={{ color: "#9A9A9E", fontSize: 11.5 }}>{hint}</span>}
        <div className="ml-1 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
      </div>
      {children}
    </section>
  );
}

function VariantLabel({ name, blurb }: { name: string; blurb: string }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="font-mono text-[11px] font-semibold uppercase tracking-[0.14em]" style={{ color: "#2F6F4F" }}>{name}</span>
      <span className="font-display italic" style={{ color: "#5A5A5E", fontSize: 11.5, lineHeight: 1.4 }}>{blurb}</span>
    </div>
  );
}

function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Faceplate", "the single recessed plate all 16 keys are seated in — replaces 16 cards floating on the canvas"],
    ["Keycap", "one raised key (V1/V3): top highlight + bottom shadow so it reads as pressable"],
    ["Pad Socket", "a key sunk into the plate (V2): inner shadow well, like an MPC/membrane pad"],
    ["Gutter Rib", "the raised channel between sunk pads (V2) — the plate showing through, not empty space"],
    ["Backlight", "the illuminated read (V3): brighter glyph + faint top glow + amber bleed from the active key"],
    ["Active Key", "fired/selected state — amber ring + glow + lift; the Dictate key shown lit in the takes above"],
    ["MAC tag", "the corner legend on Mac-routed keys (Claude · Workflow · Desktop · Share)"],
  ];
  return (
    <div>
      <div className="mb-3 flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.30em]" style={{ color: "#2F6F4F" }}>· names</span>
        <span className="font-display italic" style={{ color: "#76767A", fontSize: 12 }}>one vocabulary for studio · Swift · chat</span>
        <div className="ml-3 flex-1" style={{ height: 1, background: "#DEDEDD" }} />
      </div>
      <div className="grid" style={{ gridTemplateColumns: "150px 1fr", rowGap: 8, columnGap: 18, padding: "16px 20px", background: "#FFFFFF", border: "0.5px solid #DEDEDD", borderRadius: 8 }}>
        {rows.map(([name, def]) => (
          <div key={name} className="contents">
            <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em]" style={{ color: "#2F6F4F" }}>{name}</span>
            <span className="font-display italic" style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>{def}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
