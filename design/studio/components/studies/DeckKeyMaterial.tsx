"use client";

/**
 * iOS · Deck Key Material — resting lift + active/inactive grammar.
 *
 * Prompted by two live captures (2026-08-01):
 *   · Command deck: soft dual drop-shadows make every cap a floating card.
 *   · Codex deck: unavailable keys are the same raised face with ink faded
 *     to ~40%, so half the bed reads broken rather than intentional.
 *
 * This study freezes layout and compares only material. Three materials,
 * no fourth:
 *   Seated cap  — ready to press
 *   Socket      — unavailable / empty / blocked primary
 *   Armed       — actually on (dictating, listening, selected)
 *
 * Shadow recipes and inactive treatments are independent dials so you can
 * mix "contact-only lift" with "socket disabled" without committing to both.
 */

import { useMemo, useState, type CSSProperties, type ReactNode } from "react";

// ── Shadow recipes (resting lift) ────────────────────────────────────

type ShadowKey = "shipping" | "contact" | "contactEdge" | "milled" | "flush";

const SHADOWS: {
  key: ShadowKey;
  name: string;
  tag: string;
  blurb: string;
  well: boolean;
  face: CSSProperties;
  empty: CSSProperties;
}[] = [
  {
    key: "shipping",
    name: "S0 · Shipping",
    tag: "TODAY",
    blurb:
      "Dual soft shadow — ambient radius 7 / y 4 plus contact. Reads as iOS cards on a sheet, not caps on a deck. What both live captures use.",
    well: false,
    face: {
      background: "linear-gradient(180deg, #FFFFFF 0%, #F7F6F3 100%)",
      boxShadow:
        "0 5px 10px -3px rgba(20, 16, 12, 0.18), 0 2px 3px rgba(20, 16, 12, 0.12), inset 0 1px 0 rgba(255,255,255,0.9)",
    },
    empty: {
      background: "rgba(26, 22, 18, 0.04)",
      boxShadow: "inset 0 1px 2px rgba(20, 16, 12, 0.08)",
    },
  },
  {
    key: "contact",
    name: "S1 · Contact only",
    tag: "LEAN",
    blurb:
      "Kill the ambient bloom. One tight contact line (radius 1.5 / y 1) + a soft top light. Cap still seats; no sticker float.",
    well: false,
    face: {
      background: "linear-gradient(180deg, #FFFFFF 0%, #F4F2ED 100%)",
      boxShadow:
        "0 1px 1.5px rgba(20, 16, 12, 0.16), 0 0.5px 0 rgba(20, 16, 12, 0.08), inset 0 1px 0 rgba(255,255,255,0.95), inset 0 -1px 0 rgba(20, 16, 12, 0.06)",
    },
    empty: {
      background: "rgba(26, 22, 18, 0.05)",
      boxShadow: "inset 0 1.5px 3px rgba(20, 16, 12, 0.12)",
    },
  },
  {
    key: "contactEdge",
    name: "S2 · Contact + hairline",
    tag: "CRISP",
    blurb:
      "S1 plus a 0.5px edge so the cap silhouette holds on pure white chassis. Figure/ground without paying for a soft blur.",
    well: false,
    face: {
      background: "linear-gradient(180deg, #FFFFFF 0%, #F3F1EC 100%)",
      boxShadow:
        "0 1px 1.5px rgba(20, 16, 12, 0.14), inset 0 1px 0 rgba(255,255,255,0.95), inset 0 -1px 0 rgba(20, 16, 12, 0.07), inset 0 0 0 0.5px rgba(26, 22, 18, 0.10)",
    },
    empty: {
      background: "rgba(26, 22, 18, 0.05)",
      boxShadow:
        "inset 0 1.5px 3px rgba(20, 16, 12, 0.12), inset 0 0 0 0.5px rgba(26, 22, 18, 0.08)",
    },
  },
  {
    key: "milled",
    name: "S3 · Milled pocket",
    tag: "WELL",
    blurb:
      "Depth comes from the well, not the float. Recessed pocket; caps sit tight with contact only. Closest to a machined deck.",
    well: true,
    face: {
      background: "linear-gradient(180deg, #FFFFFF 0%, #F2F0EA 100%)",
      boxShadow:
        "0 1px 2px rgba(20, 16, 12, 0.18), inset 0 1px 0 rgba(255,255,255,0.9), inset 0 -1px 0 rgba(20, 16, 12, 0.08)",
    },
    empty: {
      background: "rgba(0, 0, 0, 0.10)",
      boxShadow: "inset 0 2px 4px rgba(0, 0, 0, 0.18), inset 0 0 0 0.5px rgba(255,255,255,0.04)",
    },
  },
  {
    key: "flush",
    name: "S4 · Flush chamfer",
    tag: "FLAT",
    blurb:
      "No drop shadow. Cap is paint and light: top highlight → bottom shade. Quietest; can go flat if the chassis is too close in value.",
    well: false,
    face: {
      background: "linear-gradient(180deg, #FFFFFF 0%, #EFECE6 100%)",
      boxShadow:
        "inset 0 1px 0 rgba(255,255,255,0.95), inset 0 -1.5px 0 rgba(20, 16, 12, 0.08), inset 0 0 0 0.5px rgba(26, 22, 18, 0.08)",
    },
    empty: {
      background: "rgba(26, 22, 18, 0.04)",
      boxShadow: "inset 0 1px 2px rgba(20, 16, 12, 0.10)",
    },
  },
];

// ── Inactive recipes (Codex unavailable keys) ────────────────────────

type InactiveKey = "ghost" | "muteLabel" | "socket" | "socketReason";

const INACTIVES: {
  key: InactiveKey;
  name: string;
  tag: string;
  blurb: string;
}[] = [
  {
    key: "ghost",
    name: "I0 · Shipping ghost",
    tag: "TODAY",
    blurb:
      "Same raised face; icon + label + face all fade (~0.42 ink). History/Read/Copy/Replay/Stop/Talk all look half-dead. Three jobs, one knob.",
  },
  {
    key: "muteLabel",
    name: "I1 · Full face · muted ink",
    tag: "SOFT",
    blurb:
      "Cap stays seated and lifted. Only icon and label mute. Still a key, just not currently useful — less 'broken button'.",
  },
  {
    key: "socket",
    name: "I2 · Socket",
    tag: "HARD",
    blurb:
      "Category change: recessed dimple, engraved index, no icon wash. Unavailable is empty, not faded. Matches the instrument grammar.",
  },
  {
    key: "socketReason",
    name: "I3 · Socket + reason",
    tag: "TALK",
    blurb:
      "For the primary (Talk) when blocked: socket face with a short silk reason (MAP A LANE). Never shares the ghost with History.",
  },
];

// ── Demo tiles ───────────────────────────────────────────────────────

type TileKind = "ready" | "unavailable" | "primary" | "primaryBlocked" | "armed" | "empty";

interface Tile {
  index: number;
  label: string;
  icon: string;
  kind: TileKind;
  /** Double-width (Talk spans 14–15). */
  span?: 2;
}

const COMMAND_TILES: Tile[] = [
  { index: 1, label: "Dictate", icon: "mic", kind: "ready" },
  { index: 2, label: "Memo", icon: "□", kind: "ready" },
  { index: 3, label: "Voice Cmd", icon: "≋", kind: "ready" },
  { index: 4, label: "Search", icon: "⌕", kind: "ready" },
  { index: 5, label: "Claude", icon: "✦", kind: "ready" },
  { index: 6, label: "Pi", icon: "◉", kind: "ready" },
  { index: 7, label: "Shell", icon: ">_", kind: "ready" },
  { index: 8, label: "Workflow", icon: "✧", kind: "ready" },
  { index: 9, label: "Desktop", icon: "▣", kind: "ready" },
  { index: 10, label: "Record", icon: "◎", kind: "ready" },
  { index: 11, label: "Memos", icon: "≋", kind: "ready" },
  { index: 12, label: "Command", icon: "⌘", kind: "ready" },
  { index: 13, label: "Pending", icon: "⌛", kind: "ready" },
  { index: 14, label: "Recent", icon: "↻", kind: "ready" },
  { index: 15, label: "Home", icon: "⌂", kind: "ready" },
  { index: 16, label: "Share", icon: "▦", kind: "ready" },
];

/** Codex bed as in the capture — no channel chosen, half the actions blocked. */
const CODEX_TILES: Tile[] = [
  { index: 1, label: "Audio", icon: "S", kind: "ready" },
  { index: 2, label: "Mapper", icon: "▦", kind: "ready" },
  { index: 3, label: "Spaces", icon: "⊞", kind: "ready" },
  { index: 4, label: "Details", icon: "OFF", kind: "ready" },
  { index: 5, label: "History", icon: "↻", kind: "unavailable" },
  { index: 6, label: "Read", icon: "☰", kind: "unavailable" },
  { index: 7, label: "Copy", icon: "⧉", kind: "unavailable" },
  { index: 8, label: "Refresh", icon: "⟳", kind: "ready" },
  { index: 9, label: "Lane 06", icon: "‹", kind: "ready" },
  { index: 10, label: "Replay", icon: "◁", kind: "unavailable" },
  { index: 11, label: "Stop", icon: "■", kind: "unavailable" },
  { index: 12, label: "Lane 01", icon: "›", kind: "ready" },
  { index: 13, label: "Task", icon: "+", kind: "ready" },
  { index: 14, label: "Talk", icon: "🎙", kind: "primaryBlocked", span: 2 },
  { index: 16, label: "Readout", icon: "≋", kind: "ready" },
];

// ── Study ────────────────────────────────────────────────────────────

export function DeckKeyMaterialStudy() {
  const [shadow, setShadow] = useState<ShadowKey>("contactEdge");
  const [inactive, setInactive] = useState<InactiveKey>("socket");
  const [armed, setArmed] = useState(false);

  const shadowSpec = SHADOWS.find((s) => s.key === shadow)!;
  const inactiveSpec = INACTIVES.find((i) => i.key === inactive)!;

  return (
    <div className="flex flex-col gap-12">
      <Thesis />

      <Section label="Diagnosis" hint="from the two live captures · 2026-08-01">
        <div className="grid gap-3 md:grid-cols-2">
          <DiagCard
            title="Command deck · lift"
            body="Every key is a white card with a soft ambient blur (radius ~6–8, y ~3–5). Elevation is doing all the figure/ground work on a flush chassis, so the grid reads as stickers — not seated caps."
          />
          <DiagCard
            title="Codex deck · inactive"
            body="History / Read / Copy / Replay / Stop / Talk are the same raised face with ink at ~40%. Opacity is doing three jobs: context-disabled, empty, and primary-blocked. The bottom half looks broken."
          />
        </div>
      </Section>

      <Section label="Resting lift" hint="shadow recipes · same 4×4 command bed">
        <div className="flex flex-wrap gap-2">
          {SHADOWS.map((s) => (
            <Seg
              key={s.key}
              on={shadow === s.key}
              tag={s.tag}
              onClick={() => setShadow(s.key)}
            >
              {s.name}
            </Seg>
          ))}
        </div>
        <p className="max-w-[72ch]" style={{ fontSize: 13, color: "#5A5A5E", lineHeight: 1.5, margin: 0 }}>
          <strong style={{ color: "#232423" }}>{shadowSpec.name}.</strong> {shadowSpec.blurb}
        </p>
        <div className="flex flex-wrap gap-8">
          {SHADOWS.map((s) => (
            <div key={s.key} className="flex flex-col gap-2" style={{ width: 280 }}>
              <VariantHead name={s.name} tag={s.tag} active={shadow === s.key} onPick={() => setShadow(s.key)} />
              <Chassis well={s.well}>
                <MiniGrid
                  tiles={COMMAND_TILES.slice(0, 8)}
                  shadow={s}
                  inactive="ghost"
                  armed={false}
                  compact
                />
              </Chassis>
            </div>
          ))}
        </div>
      </Section>

      <Section label="Inactive grammar" hint="Codex bed · no channel chosen · half the actions blocked">
        <div className="flex flex-wrap gap-2">
          {INACTIVES.map((i) => (
            <Seg
              key={i.key}
              on={inactive === i.key}
              tag={i.tag}
              onClick={() => setInactive(i.key)}
            >
              {i.name}
            </Seg>
          ))}
        </div>
        <p className="max-w-[72ch]" style={{ fontSize: 13, color: "#5A5A5E", lineHeight: 1.5, margin: 0 }}>
          <strong style={{ color: "#232423" }}>{inactiveSpec.name}.</strong> {inactiveSpec.blurb}
        </p>
        <div className="flex flex-wrap gap-8">
          {INACTIVES.map((i) => (
            <div key={i.key} className="flex flex-col gap-2" style={{ width: 300 }}>
              <VariantHead name={i.name} tag={i.tag} active={inactive === i.key} onPick={() => setInactive(i.key)} />
              <Chassis well={shadowSpec.well}>
                <MiniGrid
                  tiles={CODEX_TILES}
                  shadow={shadowSpec}
                  inactive={i.key}
                  armed={false}
                />
              </Chassis>
            </div>
          ))}
        </div>
      </Section>

      <Section
        label="Mix · full beds"
        hint="chosen lift + chosen inactive · Command and Codex side by side"
      >
        <div className="flex flex-wrap items-center gap-3">
          <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.18em] text-stone-400">
            lift · {shadowSpec.name}
          </span>
          <span className="text-stone-300">·</span>
          <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.18em] text-stone-400">
            inactive · {inactiveSpec.name}
          </span>
          <span className="text-stone-300">·</span>
          <button
            type="button"
            onClick={() => setArmed((v) => !v)}
            className="rounded-[4px] px-2 py-[3px] font-mono text-[9.5px] font-semibold uppercase tracking-[0.1em]"
            style={{
              color: armed ? "#FFFFFF" : "#5A5A5E",
              background: armed ? "#232423" : "#F2F1EE",
              border: `0.5px solid ${armed ? "#232423" : "#DEDEDD"}`,
            }}
          >
            {armed ? "Armed · dictate on" : "Resting"}
          </button>
        </div>

        <div className="flex flex-wrap gap-10">
          <div className="flex flex-col gap-2">
            <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.18em] text-stone-500">
              Command · 16 ready keys
            </span>
            <Chassis well={shadowSpec.well} wide>
              <MiniGrid
                tiles={COMMAND_TILES.map((t, i) =>
                  armed && i === 0 ? { ...t, kind: "armed" as const } : t
                )}
                shadow={shadowSpec}
                inactive={inactive}
                armed={armed}
              />
            </Chassis>
          </div>
          <div className="flex flex-col gap-2">
            <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.18em] text-stone-500">
              Codex · no channel · blocked primary
            </span>
            <Chassis well={shadowSpec.well} wide>
              <MiniGrid
                tiles={CODEX_TILES}
                shadow={shadowSpec}
                inactive={inactive}
                armed={armed}
              />
            </Chassis>
          </div>
        </div>
      </Section>

      <Section label="State strip" hint="one recipe applied to every state · no layout change">
        <StateStrip shadow={shadowSpec} inactive={inactive} />
      </Section>

      <Recommendation shadow={shadow} inactive={inactive} />
      <NamesMarginalia />
    </div>
  );
}

// ── Pieces ───────────────────────────────────────────────────────────

function Thesis() {
  return (
    <div className="flex flex-col gap-3">
      <p className="max-w-[78ch] font-display italic" style={{ color: "#5A5A5E", fontSize: 14, lineHeight: 1.55 }}>
        <strong style={{ fontStyle: "normal", color: "#232423" }}>
          Three materials, no fourth.
        </strong>{" "}
        A ready key is a seated cap. An unavailable key is a socket — a recessed dimple with an
        engraved index, not a faded twin of the same face. An armed key is the only place accent
        floods the surface. Opacity is not a material; soft ambient shadow is not a seat.
      </p>
      <p className="max-w-[78ch]" style={{ color: "#8A8A8E", fontSize: 12.5, lineHeight: 1.5, margin: 0 }}>
        Scope chassis (light, paper keys) matches the live captures. Mix the two dials below;
        the recommended default is S2 · Contact + hairline with I2 · Socket (I3 on Talk when blocked).
      </p>
    </div>
  );
}

function DiagCard({ title, body }: { title: string; body: string }) {
  return (
    <div
      className="rounded-[8px] bg-white px-4 py-3.5"
      style={{ border: "0.5px solid #DEDEDD" }}
    >
      <div className="mb-1.5 font-mono text-[9px] font-semibold uppercase tracking-[0.16em] text-stone-600">
        {title}
      </div>
      <p style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.5, margin: 0 }}>{body}</p>
    </div>
  );
}

function Section({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <section className="flex flex-col gap-3">
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.3em] text-stone-500">
          · {label}
        </span>
        {hint && (
          <span className="italic text-stone-400" style={{ fontSize: 12 }}>
            {hint}
          </span>
        )}
        <div className="ml-3 flex-1" style={{ height: 1, background: "#E4E4E3" }} />
      </div>
      {children}
    </section>
  );
}

function Seg({
  on,
  onClick,
  tag,
  children,
}: {
  on: boolean;
  onClick: () => void;
  tag?: string;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={on}
      className="inline-flex items-center gap-1.5 rounded-[4px] px-2.5 py-[4px] font-mono text-[9.5px] font-semibold uppercase tracking-[0.08em] transition-colors"
      style={{
        color: on ? "#FFFFFF" : "#5A5A5E",
        background: on ? "#232423" : "#F2F1EE",
        border: `0.5px solid ${on ? "#232423" : "#DEDEDD"}`,
      }}
    >
      {children}
      {tag && (
        <span
          className="rounded-[2px] px-1 py-px text-[7.5px] tracking-[0.1em]"
          style={{
            color: on ? "rgba(255,255,255,0.7)" : "#9A9A9E",
            border: `0.5px solid ${on ? "rgba(255,255,255,0.25)" : "#DEDEDD"}`,
          }}
        >
          {tag}
        </span>
      )}
    </button>
  );
}

function VariantHead({
  name,
  tag,
  active,
  onPick,
}: {
  name: string;
  tag: string;
  active: boolean;
  onPick: () => void;
}) {
  return (
    <button type="button" onClick={onPick} className="flex items-baseline gap-2 text-left">
      <span
        className="font-mono text-[10px] font-semibold uppercase tracking-[0.12em]"
        style={{ color: active ? "#232423" : "#7A7A7E" }}
      >
        {name}
      </span>
      <span
        className="rounded-[2px] px-1 py-px font-mono text-[7.5px] font-bold tracking-[0.12em]"
        style={{
          color: tag === "TODAY" ? "#B07A1F" : "#6A6A6E",
          border: `0.5px solid ${tag === "TODAY" ? "rgba(176,122,31,0.45)" : "#DEDEDD"}`,
        }}
      >
        {tag}
      </span>
    </button>
  );
}

function Chassis({
  children,
  well,
  wide,
}: {
  children: ReactNode;
  well?: boolean;
  wide?: boolean;
}) {
  return (
    <div
      data-theme="scope"
      className="rounded-[18px] p-2.5"
      style={{
        width: wide ? 340 : 280,
        background:
          "repeating-linear-gradient(100deg, rgba(255,255,255,0.4) 0 1px, transparent 1px 3px), linear-gradient(180deg, #F7F5F0, #EFECE6)",
        boxShadow: "inset 0 0 0 0.5px rgba(26,22,18,0.08), 0 8px 20px -12px rgba(20,16,12,0.18)",
      }}
    >
      <div
        className="rounded-[12px] p-2"
        style={
          well
            ? {
                background: "rgba(0,0,0,0.08)",
                boxShadow:
                  "inset 0 2px 6px rgba(0,0,0,0.14), inset 0 1px 0 rgba(0,0,0,0.06)",
              }
            : undefined
        }
      >
        {children}
      </div>
    </div>
  );
}

function MiniGrid({
  tiles,
  shadow,
  inactive,
  armed,
  compact,
}: {
  tiles: Tile[];
  shadow: (typeof SHADOWS)[number];
  inactive: InactiveKey;
  armed: boolean;
  compact?: boolean;
}) {
  // Build rows accounting for span-2 Talk key.
  const rows = useMemo(() => {
    const out: Tile[][] = [];
    let row: Tile[] = [];
    let cols = 0;
    for (const t of tiles) {
      const w = t.span ?? 1;
      if (cols + w > 4) {
        out.push(row);
        row = [];
        cols = 0;
      }
      row.push(t);
      cols += w;
      if (cols === 4) {
        out.push(row);
        row = [];
        cols = 0;
      }
    }
    if (row.length) out.push(row);
    return out;
  }, [tiles]);

  return (
    <div className="flex flex-col" style={{ gap: compact ? 6 : 8 }}>
      {rows.map((row, ri) => (
        <div key={ri} className="grid" style={{ gridTemplateColumns: "repeat(4, 1fr)", gap: compact ? 6 : 8 }}>
          {row.map((tile) => (
            <KeyCap
              key={tile.index}
              tile={tile}
              shadow={shadow}
              inactive={inactive}
              armed={armed}
              compact={compact}
            />
          ))}
        </div>
      ))}
    </div>
  );
}

function KeyCap({
  tile,
  shadow,
  inactive,
  armed,
  compact,
}: {
  tile: Tile;
  shadow: (typeof SHADOWS)[number];
  inactive: InactiveKey;
  armed: boolean;
  compact?: boolean;
}) {
  const kind = tile.kind === "armed" && !armed ? "ready" : tile.kind;
  const isSocket =
    kind === "empty" ||
    (kind === "unavailable" && (inactive === "socket" || inactive === "socketReason")) ||
    (kind === "primaryBlocked" && (inactive === "socket" || inactive === "socketReason"));
  const isGhost =
    (kind === "unavailable" || kind === "primaryBlocked") && inactive === "ghost";
  const isMute =
    (kind === "unavailable" || kind === "primaryBlocked") && inactive === "muteLabel";
  const isArmed = kind === "armed";
  const isPrimaryReady = kind === "primary";
  const showReason =
    kind === "primaryBlocked" && inactive === "socketReason";

  const h = compact ? 54 : 64;
  const spanStyle = tile.span === 2 ? { gridColumn: "span 2" } : undefined;

  if (isSocket) {
    return (
      <div
        className="relative flex flex-col items-center justify-center"
        style={{
          height: h,
          borderRadius: 11,
          ...shadow.empty,
          ...spanStyle,
        }}
      >
        <span
          className="absolute left-1.5 top-1.5 font-mono"
          style={{ fontSize: 8, color: "rgba(26,22,18,0.28)", letterSpacing: "0.06em" }}
        >
          {String(tile.index).padStart(2, "0")}
        </span>
        {showReason ? (
          <span
            className="px-1 text-center font-mono"
            style={{
              fontSize: 8,
              fontWeight: 600,
              letterSpacing: "0.12em",
              color: "rgba(26,22,18,0.38)",
            }}
          >
            MAP A LANE
          </span>
        ) : (
          <span style={{ fontSize: 11, color: "rgba(26,22,18,0.22)" }}>·</span>
        )}
      </div>
    );
  }

  const ink = isGhost
    ? "rgba(26,22,18,0.32)"
    : isMute
      ? "rgba(26,22,18,0.38)"
      : isArmed
        ? "var(--theme-amber, #B5823A)"
        : isPrimaryReady
          ? "#3B6AE0"
          : "#1A1612";

  const face: CSSProperties = isArmed
    ? {
        background: "color-mix(in srgb, #3B6AE0 16%, #FFFFFF)",
        boxShadow:
          "0 0 0 1px #3B6AE0, 0 0 12px -3px rgba(59,106,224,0.45), inset 0 1px 0 rgba(255,255,255,0.5)",
      }
    : isPrimaryReady
      ? {
          background: "color-mix(in srgb, #3B6AE0 12%, #FFFFFF)",
          boxShadow:
            "0 1px 1.5px rgba(20,16,12,0.14), inset 0 0 0 1px rgba(59,106,224,0.45), inset 0 1px 0 rgba(255,255,255,0.9)",
        }
      : isGhost
        ? {
            ...shadow.face,
            opacity: 0.55,
          }
        : shadow.face;

  return (
    <div
      className="relative flex flex-col items-center justify-center"
      style={{
        height: h,
        borderRadius: 11,
        ...face,
        ...spanStyle,
        gap: 4,
      }}
    >
      <span
        className="absolute left-1.5 top-1.5 font-mono"
        style={{ fontSize: 8, color: "rgba(26,22,18,0.32)", letterSpacing: "0.06em" }}
      >
        {String(tile.index).padStart(2, "0")}
      </span>
      {kind === "ready" && tile.index === 1 && (
        <span
          className="absolute right-1.5 top-1.5"
          style={{
            width: 4,
            height: 4,
            borderRadius: 2,
            background: "#3B6AE0",
          }}
        />
      )}
      <span
        style={{
          fontSize: tile.span === 2 ? 12 : 13,
          lineHeight: 1,
          color: ink,
          fontWeight: isArmed || isPrimaryReady ? 600 : 500,
        }}
      >
        {tile.icon}
      </span>
      <span
        className="px-1 text-center font-mono"
        style={{
          fontSize: compact ? 8 : 9,
          fontWeight: 600,
          letterSpacing: "0.08em",
          color: ink,
          opacity: isGhost ? 0.9 : 1,
        }}
      >
        {tile.label.toUpperCase()}
      </span>
    </div>
  );
}

function StateStrip({
  shadow,
  inactive,
}: {
  shadow: (typeof SHADOWS)[number];
  inactive: InactiveKey;
}) {
  const samples: Tile[] = [
    { index: 1, label: "Ready", icon: "⌁", kind: "ready" },
    { index: 2, label: "Unavailable", icon: "☰", kind: "unavailable" },
    { index: 3, label: "Empty", icon: "", kind: "empty" },
    { index: 4, label: "Armed", icon: "●", kind: "armed" },
    { index: 5, label: "Talk", icon: "🎙", kind: "primary", span: 2 },
    { index: 7, label: "Talk", icon: "🎙", kind: "primaryBlocked", span: 2 },
  ];

  return (
    <Chassis well={shadow.well} wide>
      <div className="grid" style={{ gridTemplateColumns: "repeat(4, 1fr)", gap: 8 }}>
        {samples.map((t) => (
          <KeyCap key={`${t.kind}-${t.index}`} tile={t} shadow={shadow} inactive={inactive} armed />
        ))}
      </div>
      <div
        className="mt-2.5 grid gap-x-3 gap-y-1 font-mono"
        style={{
          gridTemplateColumns: "72px 1fr",
          fontSize: 9,
          color: "rgba(26,22,18,0.45)",
          letterSpacing: "0.06em",
        }}
      >
        <span>READY</span>
        <span>seated cap · full ink</span>
        <span>UNAVAILABLE</span>
        <span>via inactive dial · ghost / mute / socket</span>
        <span>EMPTY</span>
        <span>always a socket · no icon</span>
        <span>ARMED</span>
        <span>accent ring + tint · only when actually on</span>
        <span>TALK</span>
        <span>primary ready · blue wash, not the same as armed</span>
        <span>TALK · BLOCKED</span>
        <span>never ghost · socket or socket+reason</span>
      </div>
    </Chassis>
  );
}

function Recommendation({
  shadow,
  inactive,
}: {
  shadow: ShadowKey;
  inactive: InactiveKey;
}) {
  const picks: [string, string][] = [
    [
      "Default lift",
      "S2 · Contact + hairline on light chassis. Ambient bloom goes; silhouette holds. S3 if you want a milled pocket under the whole bed.",
    ],
    [
      "Default inactive",
      "I2 · Socket for context-disabled utilities (History with no task, Replay with no turn). Category change, not alpha.",
    ],
    [
      "Talk blocked",
      "I3 · Socket + reason. Short silk (MAP A LANE / HOST OFFLINE). Never .opacity(0.48) on the primary.",
    ],
    [
      "Mute label (I1)",
      "Only if a key must stay obviously pressable while soft-disabled (rare). Prefer socket.",
    ],
    [
      "Armed",
      "Accent ring + tint only while something is on. Do not use armed material for 'selected utility'.",
    ],
    [
      "Swift touch points",
      "DeckMirrorNext.keycapSurface · CodexCommandDeckSurface.keycapSurface / actionKey / captureKey. Disabled must reach the surface recipe, not only .foregroundStyle.",
    ],
  ];

  return (
    <Section label="Recommendation" hint={`current pick · ${shadow} + ${inactive}`}>
      <div
        className="grid rounded-[8px] bg-white px-5 py-4"
        style={{
          gridTemplateColumns: "140px 1fr",
          rowGap: 10,
          columnGap: 18,
          border: "0.5px solid #DEDEDD",
        }}
      >
        {picks.map(([name, detail]) => (
          <div key={name} className="contents">
            <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-stone-700">
              {name}
            </span>
            <span style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>{detail}</span>
          </div>
        ))}
      </div>
    </Section>
  );
}

function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Seated cap", "A ready key. Contact lift (or milled seat), full ink, presses."],
    ["Socket", "Unavailable or empty. Recessed dimple, engraved index, no icon wash. Not a faded cap."],
    ["Armed", "Actually on — dictating, listening, fired. Accent ring + tint. Never the resting state of half the board."],
    ["Contact lift", "Tight shadow under the cap (radius ≤2, y ≤1). No ambient bloom."],
    ["Ambient bloom", "Soft large-radius drop shadow. Card language. What shipping uses today."],
    ["Ghost", "Same face + opacity fade. Shipping inactive. Three jobs, one wrong knob."],
    ["Mute label", "Full seated face; only icon/label muted. Soft-disabled without looking broken."],
    ["Primary", "Talk. May wear a quiet accent wash when ready. When blocked, becomes a socket with a reason — never a ghost."],
    ["Well", "Recessed pocket holding the whole bed (S3). Depth from the well so caps do not need to float."],
  ];
  return (
    <Section label="Names" hint="one vocabulary for studio · Swift · chat">
      <div
        className="grid rounded-[8px] bg-white px-5 py-4"
        style={{
          gridTemplateColumns: "130px 1fr",
          rowGap: 8,
          columnGap: 18,
          border: "0.5px solid #DEDEDD",
        }}
      >
        {rows.map(([name, def]) => (
          <div key={name} className="contents">
            <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em] text-stone-700">
              {name}
            </span>
            <span style={{ fontSize: 12.5, color: "#3A3A3A", lineHeight: 1.45 }}>{def}</span>
          </div>
        ))}
      </div>
    </Section>
  );
}
