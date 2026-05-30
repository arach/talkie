"use client";

/**
 * IOSDeck — cleanup pass on DeckMirrorNext.swift.
 *
 * Proportions: cockpit ≈ 40%, 16-tile grid ≈ 60% of body.
 *
 * The cockpit is ONE bounded chassis containing:
 *   1. Identity row    top-left "MAC MINI · MAC ⌄" (tap to change
 *                      computer / cycle deck) · top-right status pill
 *   2. Playback        trackpad + message-replay surface (success /
 *                      failure / live transcript all render here so
 *                      they don't pile up as separate banners)
 *   3. Key row         three groups, smaller buttons, generous gap
 *                      between groups so the bundling reads:
 *                        [esc ⌘C ⌘V]    [← ↑ ↓ →]    [⌘A ⌫ ↵]
 *
 * Top-left grid tile is the dictation slot. State-aware:
 *   • idle       → mic glyph, label "Dictate"      (tap to start)
 *   • dictating  → enter glyph, label "Finish"     (tap to commit)
 *     while dictating, the playback surface shows the live transcript.
 */

import { StatusBar } from "./primitives/StatusBar";

export type DeckState = "idle" | "dictating";

type Tile = { icon: keyof typeof TILE_ICONS; label: string };

// Slot 0 is the dictation slot — its icon + label morph by state.
// The remaining 15 slots are deck bindings (Mac/Safari sample here).
const TILES: (Tile | null)[] = [
  { icon: "mic", label: "Dictate" },
  { icon: "tab-x", label: "Close Tab" },
  { icon: "reload", label: "Reload" },
  null,
  { icon: "arrow-left", label: "Back" },
  { icon: "arrow-right", label: "Forward" },
  { icon: "find", label: "Find" },
  null,
  { icon: "bookmark", label: "Bookmark" },
  null,
  null,
  null,
  { icon: "window", label: "Window" },
  null,
  null,
  null,
];

const SAMPLE_TRANSCRIPT =
  "Open a new tab and search for the wireframe references Alex sent over yesterday afternoon — the ones about cockpit chassis depth.";

export function IOSDeck({ state = "idle" }: { state?: DeckState } = {}) {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />
      <Header />

      <div className="flex flex-1 flex-col px-4 pb-3">
        <div className="flex-[40] min-h-0">
          <Cockpit state={state} />
        </div>
        <div className="flex-[60] min-h-0 pt-3">
          <TileGrid state={state} />
        </div>
      </div>
    </div>
  );
}

// ── Header ──────────────────────────────────────────────────────

function Header() {
  return (
    <div className="flex items-center justify-between px-5 pb-2 pt-3">
      <div
        className="text-[10px] tracking-[0.22em]"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-mono)",
          opacity: 0.78,
        }}
      >
        TALKIE · DECK
      </div>
      <button
        className="grid h-7 w-7 place-items-center rounded-full"
        style={{ background: "var(--theme-edge-subtle)" }}
        aria-label="Close deck"
      >
        <CloseIcon />
      </button>
    </div>
  );
}

// ── Cockpit chassis ─────────────────────────────────────────────
// Everything inside lives in one bounded card so the cockpit reads
// as a single instrument — not three stacked strips.

function Cockpit({ state }: { state: DeckState }) {
  return (
    <div
      className="flex h-full flex-col gap-2 rounded-2xl p-2.5"
      style={{
        background: "var(--theme-canvas-alt)",
        boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
      }}
    >
      <CockpitIdentity state={state} />
      <PlaybackSurface state={state} />
      <KeyRow />
    </div>
  );
}

function CockpitIdentity({ state }: { state: DeckState }) {
  const status = state === "dictating"
    ? { label: "DICTATING", color: "var(--theme-amber)" }
    : { label: "LIVE", color: "#5CBD80" };

  return (
    <div className="flex items-center justify-between px-1">
      <button
        className="flex items-center gap-1.5 text-[10px] tracking-[0.14em]"
        style={{
          fontFamily: "var(--theme-font-mono)",
          color: "var(--theme-ink-dim)",
        }}
        aria-label="Change computer or deck"
      >
        <ComputerIcon />
        <span style={{ color: "var(--theme-ink)" }}>MAC MINI</span>
        <span style={{ color: "var(--theme-ink-faint)" }}>·</span>
        <span style={{ color: "var(--theme-ink-dim)" }}>MAC</span>
        <ChevronDownIcon />
      </button>

      <div
        className="flex items-center gap-1.5 rounded-full px-2 py-0.5"
        style={{
          background: `color-mix(in srgb, ${status.color} 12%, transparent)`,
          boxShadow: `inset 0 0 0 1px color-mix(in srgb, ${status.color} 36%, transparent)`,
        }}
      >
        <span
          className="inline-block h-1.5 w-1.5 rounded-full"
          style={{ background: status.color }}
          aria-hidden
        />
        <span
          className="text-[9px] tracking-[0.18em]"
          style={{
            color: status.color,
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {status.label}
        </span>
      </div>
    </div>
  );
}

// Trackpad / replay surface. The tape diagonals always render. In
// `dictating`, an elevated transcript card toggles in place over the
// surface — diagonals stay visible behind it as the "instrument".
function PlaybackSurface({ state }: { state: DeckState }) {
  const dictating = state === "dictating";
  return (
    <div
      className="relative flex-1 overflow-hidden rounded-xl"
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
        aria-hidden
      />
      {dictating ? (
        <TranscriptCard text={SAMPLE_TRANSCRIPT} />
      ) : (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-1 px-4 text-center">
          <span
            className="text-[9px] tracking-[0.22em]"
            style={{
              color: "var(--theme-ink-muted)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            DRAG TO MOVE
          </span>
          <span
            className="text-[10px] tracking-[0.04em]"
            style={{
              color: "var(--theme-amber)",
              fontFamily: "var(--theme-font-mono)",
              opacity: 0.85,
            }}
          >
            ↳ "close tab" sent · 0:00:24
          </span>
        </div>
      )}
    </div>
  );
}

// Elevated transcript card — sticky-note feel sitting on the tape
// surface. Paper fill + soft drop shadow + hairline border. 3 lines
// max, then ellipsis; older text scrolls off as new tokens land.
function TranscriptCard({ text }: { text: string }) {
  return (
    <div className="absolute inset-0 flex items-center justify-center px-2.5 py-2">
      <div
        className="flex w-full flex-col gap-1 rounded-lg px-2.5 py-2"
        style={{
          background: "var(--theme-paper)",
          boxShadow:
            "0 4px 10px -4px rgba(0,0,0,0.18), 0 1px 0 0 rgba(255,255,255,0.04) inset, 0 0 0 1px var(--theme-edge-faint)",
        }}
      >
        <span
          className="text-[8px] tracking-[0.22em]"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            opacity: 0.78,
          }}
        >
          TRANSCRIBING…
        </span>
        <span
          className="text-[11px] leading-snug"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-body)",
            display: "-webkit-box",
            WebkitLineClamp: 3,
            WebkitBoxOrient: "vertical",
            overflow: "hidden",
          }}
        >
          {text}
        </span>
      </div>
    </div>
  );
}

// Three groups, smaller buttons, wider inter-group gap so the
// bundling reads at a glance. Glyphs render via inline SVG (arrows,
// ⌫, ↵) or text+symbol combos (esc, ⌘C) so weight stays consistent
// with the donor's SF-Symbol-based DeckCommandButton.
type Key =
  | { kind: "text"; label: string; a11y: string }
  | { kind: "cmd"; letter: string; a11y: string }
  | { kind: "icon"; icon: KeyIconName; a11y: string };

type KeyIconName = "arrow-left" | "arrow-up" | "arrow-down" | "arrow-right" | "backspace" | "return";

function KeyRow() {
  const groups: Key[][] = [
    [
      { kind: "text", label: "esc", a11y: "Escape" },
      { kind: "cmd", letter: "C", a11y: "Copy" },
      { kind: "cmd", letter: "V", a11y: "Paste" },
    ],
    [
      { kind: "icon", icon: "arrow-left", a11y: "Left" },
      { kind: "icon", icon: "arrow-up", a11y: "Up" },
      { kind: "icon", icon: "arrow-down", a11y: "Down" },
      { kind: "icon", icon: "arrow-right", a11y: "Right" },
    ],
    [
      { kind: "cmd", letter: "A", a11y: "Select all" },
      { kind: "icon", icon: "backspace", a11y: "Backspace" },
      { kind: "icon", icon: "return", a11y: "Enter" },
    ],
  ];
  return (
    <div className="flex items-stretch gap-3">
      {groups.map((group, gi) => (
        <div key={gi} className="flex flex-1 gap-[2px]">
          {group.map((k, ki) => (
            <button
              key={ki}
              aria-label={k.a11y}
              className="grid flex-1 place-items-center rounded-md"
              style={{
                background: "var(--theme-paper)",
                color: "var(--theme-ink-dim)",
                fontFamily: "var(--theme-font-mono)",
                boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
                height: "24px",
              }}
            >
              <KeyGlyph k={k} />
            </button>
          ))}
        </div>
      ))}
    </div>
  );
}

function KeyGlyph({ k }: { k: Key }) {
  if (k.kind === "text") {
    return (
      <span
        className="text-[10px] font-medium leading-none tracking-wide"
        style={{ color: "var(--theme-ink-dim)" }}
      >
        {k.label}
      </span>
    );
  }
  if (k.kind === "cmd") {
    return (
      <span className="flex items-baseline gap-[1px] leading-none">
        <span
          className="text-[10px] font-medium"
          style={{ color: "var(--theme-ink-muted)" }}
        >
          ⌘
        </span>
        <span
          className="text-[10px] font-medium"
          style={{ color: "var(--theme-ink-dim)" }}
        >
          {k.letter}
        </span>
      </span>
    );
  }
  return <KeyIcon name={k.icon} />;
}

function KeyIcon({ name }: { name: KeyIconName }) {
  const stroke = "var(--theme-ink-dim)";
  const sw = 1.6;
  switch (name) {
    case "arrow-left":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path d="M9 3L4 7L9 11M4 7H12" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "arrow-up":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path d="M3 6L7 2L11 6M7 2V12" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "arrow-down":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path d="M3 8L7 12L11 8M7 12V2" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "arrow-right":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path d="M5 3L10 7L5 11M2 7H10" stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case "backspace":
      return (
        <svg viewBox="0 0 16 14" className="h-3 w-3.5" fill="none" aria-hidden>
          <path
            d="M5 2L1 7L5 12H14C14.5 12 15 11.5 15 11V3C15 2.5 14.5 2 14 2H5Z"
            stroke={stroke}
            strokeWidth={sw}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <path d="M7.5 5L11 9M11 5L7.5 9" stroke={stroke} strokeWidth={sw} strokeLinecap="round" />
        </svg>
      );
    case "return":
      return (
        <svg viewBox="0 0 14 14" className="h-3 w-3" fill="none" aria-hidden>
          <path
            d="M11 3V7C11 7.55 10.55 8 10 8H3M3 8L6 5M3 8L6 11"
            stroke={stroke}
            strokeWidth={sw}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      );
  }
}

// ── 16-tile grid ────────────────────────────────────────────────

function TileGrid({ state }: { state: DeckState }) {
  return (
    <div className="grid h-full grid-cols-4 grid-rows-4 gap-1.5">
      {TILES.map((tile, idx) => {
        if (idx === 0) {
          return <DictationTile key={idx} state={state} />;
        }
        return <TileCell key={idx} tile={tile} firing={false} />;
      })}
    </div>
  );
}

// Top-left tile is state-aware. Idle = "Dictate" mic. Dictating =
// "Finish" enter. Same physical position serves start AND commit.
function DictationTile({ state }: { state: DeckState }) {
  const dictating = state === "dictating";
  return (
    <button
      className="flex min-h-[72px] flex-col items-center justify-center gap-1.5 rounded-lg px-1"
      style={{
        background: "var(--theme-paper)",
        boxShadow: dictating
          ? "0 0 0 1px var(--theme-amber), 0 0 18px -2px var(--theme-amber-glow)"
          : "inset 0 0 0 1px var(--theme-edge-faint)",
        transform: dictating ? "scale(1.02)" : "scale(1)",
        transition: "transform 160ms ease, box-shadow 160ms ease",
      }}
      aria-label={dictating ? "Finish dictation" : "Start dictation"}
    >
      <span style={{ color: dictating ? "var(--theme-amber)" : "var(--theme-ink)" }}>
        {dictating ? TILE_ICONS["enter"] : TILE_ICONS["mic"]}
      </span>
      <span
        className="text-[11px] leading-none tracking-tight"
        style={{
          color: dictating ? "var(--theme-amber)" : "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {dictating ? "Finish" : "Dictate"}
      </span>
    </button>
  );
}

function TileCell({ tile, firing }: { tile: Tile | null; firing: boolean }) {
  if (!tile) {
    return (
      <div
        className="grid min-h-[72px] place-items-center rounded-lg"
        style={{
          background: "var(--theme-paper)",
          opacity: 0.45,
          color: "var(--theme-ink-faint)",
        }}
      >
        <PlusIcon />
      </div>
    );
  }
  return (
    <button
      className="flex min-h-[72px] flex-col items-center justify-center gap-1.5 rounded-lg px-1"
      style={{
        background: "var(--theme-paper)",
        boxShadow: firing
          ? "0 0 0 1px var(--theme-amber), 0 0 16px -2px var(--theme-amber-glow)"
          : "inset 0 0 0 1px var(--theme-edge-faint)",
        transform: firing ? "scale(1.02)" : "scale(1)",
        transition: "transform 160ms ease, box-shadow 160ms ease",
      }}
    >
      <span style={{ color: firing ? "var(--theme-amber)" : "var(--theme-ink)" }}>
        {TILE_ICONS[tile.icon]}
      </span>
      <span
        className="text-[11px] leading-none tracking-tight"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {tile.label}
      </span>
    </button>
  );
}

// ── Icons ───────────────────────────────────────────────────────

function CloseIcon() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none">
      <path
        d="M2 2L10 10M10 2L2 10"
        stroke="var(--theme-ink-muted)"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  );
}

function ComputerIcon() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none" aria-hidden>
      <rect
        x="1.5"
        y="2"
        width="9"
        height="6"
        rx="0.8"
        stroke="currentColor"
        strokeWidth="1"
      />
      <path d="M4 10H8" stroke="currentColor" strokeWidth="1" strokeLinecap="round" />
    </svg>
  );
}

function ChevronDownIcon() {
  return (
    <svg viewBox="0 0 10 10" className="h-2 w-2" fill="none" aria-hidden>
      <path
        d="M2 4L5 7L8 4"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function PlusIcon() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none">
      <path
        d="M6 2V10M2 6H10"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinecap="round"
      />
    </svg>
  );
}

const TILE_ICONS = {
  mic: (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <rect
        x="7.5"
        y="3"
        width="5"
        height="9"
        rx="2.5"
        stroke="currentColor"
        strokeWidth="1.4"
      />
      <path
        d="M5 10A5 5 0 0 0 15 10M10 15V17M7 17H13"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  ),
  enter: (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <path
        d="M16 5V10A2 2 0 0 1 14 12H5M5 12L9 8M5 12L9 16"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  "tab-plus": (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <rect x="3" y="6" width="14" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M10 9V13M8 11H12" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  ),
  "tab-x": (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <rect x="3" y="6" width="14" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M8 9L12 13M12 9L8 13" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  ),
  reload: (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <path
        d="M16 10A6 6 0 1 1 13.5 5.5M16 4V7H13"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  "arrow-left": (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <path
        d="M13 4L7 10L13 16"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  "arrow-right": (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <path
        d="M7 4L13 10L7 16"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  find: (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <circle cx="9" cy="9" r="4.5" stroke="currentColor" strokeWidth="1.3" />
      <path
        d="M12.5 12.5L15.5 15.5"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  ),
  bookmark: (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <path
        d="M6 3H14V17L10 14L6 17V3Z"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinejoin="round"
      />
    </svg>
  ),
  window: (
    <svg viewBox="0 0 20 20" className="h-5 w-5" fill="none">
      <rect x="3" y="4" width="14" height="12" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M3 8H17" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  ),
} as const;
