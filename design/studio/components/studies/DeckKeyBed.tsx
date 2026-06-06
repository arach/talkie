/**
 * iOS · Deck Key Bed — variant study.
 *
 * The deck's "mini keyboard" (DeckCockpitSurface.keyRow in
 * DeckMirrorNext.swift) currently reads as a bunch of floating chips:
 * six bare command caps + a 4-in-a-row arrow group, separated by empty
 * Spacers. This study commits the whole row to ONE recessed instrument
 * — a Key Bed — so it reads like a physical control deck rather than
 * scattered buttons. Direction chosen: "Unified Key Bed (subtle)".
 *
 * Three takes, differing only in the depth model:
 *   • V1 · Inset Bed     — bed routed INTO the chassis; caps raised.
 *   • V2 · Routed Channel — bed flush; groups split by routed grooves.
 *   • V3 · Sunk Keys     — bed a raised rail; caps sunk into wells.
 *
 * Named parts in <NamesMarginalia> at the bottom — one vocabulary for
 * studio · Swift · chat.
 */

import { IOS_THEMES } from "@/lib/themes";

type Variant = "inset" | "routed" | "sunk";

const VARIANTS: { key: Variant; name: string; blurb: string }[] = [
  { key: "inset", name: "V1 · Inset Bed", blurb: "Bed routed into the chassis (inner shadow). Caps gently raised — light from above, soft bottom shadow. The safe, quiet default." },
  { key: "routed", name: "V2 · Routed Channel", blurb: "Bed sits flush with the chassis; groups divided by routed grooves instead of gaps. Crisper cap relief. Reads most like milled aluminum." },
  { key: "sunk", name: "V3 · Sunk Keys", blurb: "Bed is a raised rail; keys sunk into wells. Inverse depth — caps look pressed-in, like a sealed membrane pad." },
];

// ── Study body ──────────────────────────────────────────────────────

export function DeckKeyBedStudy() {
  return (
    <div className="flex flex-col gap-12">
      <p
        className="max-w-[64ch] font-display italic"
        style={{ color: "#76767A", fontSize: 13, lineHeight: 1.5 }}
      >
        Same keys, same layout as the donor — the change is purely the
        housing. Each bed seats Command Keys + the Cursor Cluster in one
        plate, with Group Seams instead of empty space, and gives each
        cap a 1px depress on press. Compare the three depth models, then
        scan the bottom strip for token behaviour across themes.
      </p>

      {/* A/B/C — the three variants side by side on one dark chassis,
          shown at rest and with a key pressed. */}
      <Section
        label="Three takes — rest + pressed"
        hint="dark chassis · the ↓ cursor key and ⌘C shown depressed on the right"
      >
        <div className="flex flex-wrap gap-8">
          {VARIANTS.map((v) => (
            <div key={v.key} className="flex w-[340px] flex-col gap-3">
              <VariantLabel name={v.name} blurb={v.blurb} />
              <div data-theme="midnight">
                <Chassis>
                  <KeyBed variant={v.key} />
                </Chassis>
              </div>
              <div data-theme="midnight">
                <Chassis>
                  <KeyBed variant={v.key} pressed={["cursor-down", "cmd-C"]} />
                </Chassis>
              </div>
            </div>
          ))}
        </div>
      </Section>

      {/* In context — the recommended default (Inset Bed) inside a mini
          cockpit footer, across every iOS theme bundle. */}
      <Section
        label="In context — Inset Bed across themes"
        hint="identity + replay surface + bed, the way it sits in the cockpit"
      >
        <div className="flex flex-wrap gap-6">
          {IOS_THEMES.map((theme) => (
            <div key={theme.key} className="flex flex-col gap-2">
              <span
                className="font-mono text-[9px] uppercase tracking-[0.18em]"
                style={{ color: "#9A9A9E" }}
              >
                {theme.key}
              </span>
              <div data-theme={theme.key} className="w-[300px]">
                <MiniCockpit variant="inset" />
              </div>
            </div>
          ))}
        </div>
      </Section>

      <NamesMarginalia />
    </div>
  );
}

// ── Chassis + cockpit context ───────────────────────────────────────

// The trackpad/cockpit body the bed sits inside. Mirrors the Swift
// chassis: rounded card, canvas-alt fill, hairline inset edge.
function Chassis({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="rounded-2xl p-2.5"
      style={{
        background: "var(--theme-canvas-alt)",
        boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
      }}
    >
      {children}
    </div>
  );
}

function MiniCockpit({ variant }: { variant: Variant }) {
  return (
    <div
      className="flex flex-col gap-2 rounded-2xl p-2.5"
      style={{
        background: "var(--theme-canvas-alt)",
        boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
      }}
    >
      <div className="flex items-center justify-between px-1">
        <span
          className="font-mono text-[9px] tracking-[0.14em]"
          style={{ color: "var(--theme-ink-dim)" }}
        >
          MAC MINI · MAC
        </span>
        <span
          className="flex items-center gap-1 rounded-full px-1.5 py-0.5"
          style={{
            background: "color-mix(in srgb, #5CBD80 12%, transparent)",
            boxShadow: "inset 0 0 0 1px color-mix(in srgb, #5CBD80 36%, transparent)",
          }}
        >
          <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: "#5CBD80" }} />
          <span className="font-mono text-[8px] tracking-[0.18em]" style={{ color: "#5CBD80" }}>
            LIVE
          </span>
        </span>
      </div>
      <div
        className="relative h-16 overflow-hidden rounded-xl"
        style={{
          background: "var(--theme-screen-bg)",
          boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
        }}
      >
        <div
          className="absolute inset-0 opacity-60"
          style={{
            backgroundImage:
              "repeating-linear-gradient(135deg, transparent 0 14px, var(--theme-screen-trace) 14px 15px)",
          }}
        />
        <div className="absolute inset-0 grid place-items-center">
          <span
            className="font-mono text-[8px] tracking-[0.22em]"
            style={{ color: "var(--theme-ink-muted)" }}
          >
            DRAG TO MOVE
          </span>
        </div>
      </div>
      <KeyBed variant={variant} />
    </div>
  );
}

// ── The Key Bed ─────────────────────────────────────────────────────

type KeyId =
  | "esc" | "cmd-C" | "cmd-V"
  | "cursor-left" | "cursor-up" | "cursor-down" | "cursor-right"
  | "cmd-A" | "backspace" | "return";

const LEFT: KeyId[] = ["esc", "cmd-C", "cmd-V"];
const CURSOR: KeyId[] = ["cursor-left", "cursor-up", "cursor-down", "cursor-right"];
const RIGHT: KeyId[] = ["cmd-A", "backspace", "return"];

function KeyBed({ variant, pressed = [] }: { variant: Variant; pressed?: KeyId[] }) {
  return (
    <div className="flex items-stretch" style={bedStyle(variant)}>
      <Group ids={LEFT} variant={variant} pressed={pressed} />
      <Seam variant={variant} />
      <Group ids={CURSOR} variant={variant} pressed={pressed} grow={1.35} />
      <Seam variant={variant} />
      <Group ids={RIGHT} variant={variant} pressed={pressed} />
    </div>
  );
}

function Group({
  ids,
  variant,
  pressed,
  grow = 1,
}: {
  ids: KeyId[];
  variant: Variant;
  pressed: KeyId[];
  grow?: number;
}) {
  return (
    <div className="flex gap-[3px]" style={{ flex: grow }}>
      {ids.map((id) => (
        <Cap key={id} id={id} variant={variant} pressed={pressed.includes(id)} />
      ))}
    </div>
  );
}

function Cap({ id, variant, pressed }: { id: KeyId; variant: Variant; pressed: boolean }) {
  return (
    <button
      aria-label={A11Y[id]}
      className="grid flex-1 place-items-center"
      style={{ height: 28, borderRadius: 7, ...capStyle(variant, pressed) }}
    >
      <Glyph id={id} pressed={pressed} />
    </button>
  );
}

// Routed/sunk seams between functional groups. Replaces the donor's
// empty Spacer with a deliberate divider so the bed reads as one piece.
function Seam({ variant }: { variant: Variant }) {
  if (variant === "routed") {
    return (
      <div
        className="self-stretch"
        style={{
          width: 3,
          margin: "1px 4px",
          borderRadius: 2,
          background: "var(--theme-screen-bg)",
          boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.30)",
        }}
      />
    );
  }
  return (
    <div
      className="self-stretch"
      style={{ width: 1, margin: "3px 5px", background: "var(--theme-edge-faint)" }}
    />
  );
}

// ── Depth styling ───────────────────────────────────────────────────

function bedStyle(variant: Variant): React.CSSProperties {
  const base: React.CSSProperties = { padding: 5, borderRadius: 12, gap: 0 };
  switch (variant) {
    case "inset":
      return {
        ...base,
        background: "var(--theme-screen-bg)",
        boxShadow: "inset 0 1.5px 3px rgba(0,0,0,0.45), inset 0 0 0 1px var(--theme-edge-faint)",
      };
    case "routed":
      return {
        ...base,
        background: "var(--theme-canvas-alt)",
        boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
      };
    case "sunk":
      return {
        ...base,
        background: "var(--theme-paper)",
        boxShadow:
          "0 2px 5px -1px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.05), inset 0 0 0 1px var(--theme-edge-faint)",
      };
  }
}

function capStyle(variant: Variant, pressed: boolean): React.CSSProperties {
  if (pressed) {
    return {
      background: "color-mix(in srgb, var(--theme-amber) 16%, var(--theme-paper))",
      boxShadow:
        "inset 0 1.5px 3px rgba(0,0,0,0.5), inset 0 0 0 1px color-mix(in srgb, var(--theme-amber) 42%, transparent)",
      transform: "translateY(0.5px)",
    };
  }
  // Sunk variant = keys cut into the rail (inset). Others = raised caps.
  if (variant === "sunk") {
    return {
      background: "var(--theme-screen-bg)",
      boxShadow: "inset 0 1.5px 2.5px rgba(0,0,0,0.5), inset 0 0 0 1px var(--theme-edge-faint)",
    };
  }
  const highlight = variant === "routed" ? 0.11 : 0.07;
  return {
    background: "var(--theme-paper)",
    boxShadow: `0 1px 1.5px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,${highlight}), inset 0 0 0 1px var(--theme-edge-faint)`,
  };
}

// ── Glyphs ──────────────────────────────────────────────────────────

const A11Y: Record<KeyId, string> = {
  esc: "Escape",
  "cmd-C": "Copy",
  "cmd-V": "Paste",
  "cursor-left": "Left",
  "cursor-up": "Up",
  "cursor-down": "Down",
  "cursor-right": "Right",
  "cmd-A": "Select all",
  backspace: "Backspace",
  return: "Enter",
};

function Glyph({ id, pressed }: { id: KeyId; pressed: boolean }) {
  const color = pressed ? "var(--theme-amber)" : "var(--theme-ink-dim)";
  if (id === "esc") {
    return (
      <span className="font-mono text-[10px] font-medium leading-none" style={{ color }}>
        esc
      </span>
    );
  }
  if (id.startsWith("cmd-")) {
    return (
      <span className="flex items-baseline gap-[1px] font-mono leading-none">
        <span className="text-[10px]" style={{ color: pressed ? "var(--theme-amber)" : "var(--theme-ink-muted)" }}>⌘</span>
        <span className="text-[10px] font-medium" style={{ color }}>{id.slice(4)}</span>
      </span>
    );
  }
  return <KeyIcon id={id} color={color} />;
}

function KeyIcon({ id, color }: { id: KeyId; color: string }) {
  const sw = 1.6;
  const p: Record<string, string> = {
    "cursor-left": "M9 3L4 7L9 11M4 7H12",
    "cursor-up": "M3 6L7 2L11 6M7 2V12",
    "cursor-down": "M3 8L7 12L11 8M7 12V2",
    "cursor-right": "M5 3L10 7L5 11M2 7H10",
  };
  if (id in p) {
    return (
      <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
        <path d={p[id]} stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }
  if (id === "backspace") {
    return (
      <svg viewBox="0 0 16 14" className="h-3 w-3.5" fill="none" aria-hidden>
        <path d="M5 2L1 7L5 12H14C14.5 12 15 11.5 15 11V3C15 2.5 14.5 2 14 2H5Z" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        <path d="M7.5 5L11 9M11 5L7.5 9" stroke={color} strokeWidth={sw} strokeLinecap="round" />
      </svg>
    );
  }
  // return
  return (
    <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
      <path d="M11 3V7C11 7.55 10.55 8 10 8H3M3 8L6 5M3 8L6 11" stroke={color} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

// ── Layout helpers ──────────────────────────────────────────────────

function Section({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="flex flex-col gap-4">
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.18em] text-studio-ink">
          {label}
        </span>
        {hint && (
          <span className="font-display italic" style={{ color: "#9A9A9E", fontSize: 11.5 }}>
            {hint}
          </span>
        )}
        <div className="ml-1 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
      </div>
      {children}
    </section>
  );
}

function VariantLabel({ name, blurb }: { name: string; blurb: string }) {
  return (
    <div className="flex flex-col gap-1">
      <span className="font-mono text-[11px] font-semibold uppercase tracking-[0.14em]" style={{ color: "#2F6F4F" }}>
        {name}
      </span>
      <span className="font-display italic" style={{ color: "#5A5A5E", fontSize: 11.5, lineHeight: 1.4 }}>
        {blurb}
      </span>
    </div>
  );
}

function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Key Bed", "the single recessed plate the whole control row sits in — replaces the three floating chip groups"],
    ["Command Keys", "the six action caps (esc · ⌘C · ⌘V · ⌘A · ⌫ · ↵) seated in the bed"],
    ["Cursor Cluster", "the four arrow caps grouped between seams — kept as four keys in this 'subtle' direction (the rocker is a separate study)"],
    ["Group Seam", "the divider between functional groups — a hairline in Inset/Sunk, a routed groove in Routed Channel — instead of an empty gap"],
    ["Cap Relief", "the keycap depth: top highlight + bottom shadow when raised; inner shadow when sunk"],
    ["Depress", "the 1px translate + inset shadow + amber tint on press — the mechanical 'click', paired with a haptic in Swift"],
  ];
  return (
    <div>
      <div className="mb-3 flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.30em]" style={{ color: "#2F6F4F" }}>
          · names
        </span>
        <span className="font-display italic" style={{ color: "#76767A", fontSize: 12 }}>
          one vocabulary for studio · Swift · chat
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: "#DEDEDD" }} />
      </div>
      <div
        className="grid"
        style={{
          gridTemplateColumns: "150px 1fr",
          rowGap: 8,
          columnGap: 18,
          padding: "16px 20px",
          background: "#FFFFFF",
          border: "0.5px solid #DEDEDD",
          borderRadius: 8,
        }}
      >
        {rows.map(([name, def]) => (
          <div key={name} className="contents">
            <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em]" style={{ color: "#2F6F4F" }}>
              {name}
            </span>
            <span className="font-display italic" style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>
              {def}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
