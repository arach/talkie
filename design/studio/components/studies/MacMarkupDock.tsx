"use client";

/**
 * Mac Markup Dock · LEVEL UP
 * ==========================
 *
 * The floating tool cluster that rides at the bottom of the live overlay —
 * shared verbatim by two surfaces:
 *   · live screen-recording markup (LiveCaptureMarkupOverlayController)
 *   · the new desktop ink layer (DesktopInkController · "draw then snap")
 * Ships as the WKWebView chrome in
 *   apps/macos/TalkieAgent/TalkieAgent/Resources/CaptureMarkup/overlay.{html,css}
 *
 * Critique of the shipped dock (why it reads "ugly"):
 *   · TOOLS ARE UNICODE GLYPHS — ↖ ✎ ○ ↗ T. Mixed weights, mixed
 *     baselines, the pencil + capital-T look like fallback characters,
 *     not an icon set. This is the single biggest tell.
 *   · FLAT SLAB — one opaque charcoal rectangle, hairline border, 8px
 *     radius. Functional, but it sits on the desktop like a debug panel,
 *     not a floating instrument.
 *   · CRAMPED — 28px keys, 4px gaps; the segmented wells, the mode pair
 *     and the commit cluster all run together at one density.
 *
 * This study holds the LAYOUT + CONTENTS frozen (same parts, same order)
 * and varies only MATERIAL + SHAPE + ICONOGRAPHY, so the comparison is
 * about look-and-feel, not re-architecture. Real line-art icons (stroke =
 * currentColor) replace every glyph in all variants — that fix is shared.
 *
 * Names (so studio · Swift · chat share one vocabulary):
 *   · Dock          — the whole floating cluster
 *   · Tool Rail     — Select · Pen · Rect · Circle · Line · Arrow · Note (segmented)
 *   · Mode Pair     — Agent / Demo
 *   · Style Chip    — swatch + label; opens the Style Drawer
 *   · Style Drawer  — Note / Line / Arrow / Color / Stroke (expands above)
 *   · Window Chrome — Cancel at the top-left of the markup window
 *   · Surface Actions — Undo · Redo · Capture at the top-right
 *   · Commit Cluster— Done only
 *
 * Four directions to compare:
 *   · Slate      — today's dark slab, leveled up (icons + air + radius).
 *   · Onyx Glass — translucent frosted capsule, pill ends, floats.
 *   · Warm Deck  — amber-canon instrument; tactile keycap tools.
 *   · Paper Rail — light dock for drawing over dark content.
 */

import React from "react";

import { cn } from "@/lib/utils";

// ─── Icons ───────────────────────────────────────────────────────────
// One coherent set: 16-box, stroke = currentColor, round caps/joins.
// These replace the unicode glyphs (↖ ✎ ○ ↗ T ↶ ×) in every variant.

type IconProps = { className?: string };

function CursorIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="currentColor" aria-hidden>
      <path d="M3.2 2.4 L3.2 12.6 L6 9.9 L8 13.8 L9.7 13 L7.7 9.2 L11.6 9.2 Z" />
    </svg>
  );
}
function PenIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M2.6 13.4 L4.2 9.6 L10.8 3 L13 5.2 L6.4 11.8 Z" />
      <path d="M9.6 4.2 L11.8 6.4" />
    </svg>
  );
}
function RectangleIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinejoin="round" aria-hidden>
      <rect x="2.6" y="4" width="10.8" height="8" rx="0.6" />
    </svg>
  );
}
function CircleIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} aria-hidden>
      <circle cx="8" cy="8" r="5.3" />
    </svg>
  );
}
function LineIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" aria-hidden>
      <path d="M3.2 12.8 L12.8 3.2" />
    </svg>
  );
}
function ArrowIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M3.4 12.6 L12.4 3.6" />
      <path d="M12.4 7.6 L12.4 3.6 L8.4 3.6" />
    </svg>
  );
}
function NoteIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <rect x="3" y="3.4" width="10" height="9.2" rx="1.6" />
      <path d="M5.6 6.8 L10.4 6.8" />
      <path d="M5.6 9.3 L8.8 9.3" />
    </svg>
  );
}
function UndoIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M5 6 H9.6 a3.3 3.3 0 0 1 0 6.6 H6.4" />
      <path d="M6.9 3.4 L4 6 L6.9 8.6" />
    </svg>
  );
}
function RedoIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M11 6 H6.4 a3.3 3.3 0 0 0 0 6.6 H9.6" />
      <path d="M9.1 3.4 L12 6 L9.1 8.6" />
    </svg>
  );
}
function CheckIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M3.6 8.4 L6.6 11.4 L12.6 4.6" />
    </svg>
  );
}
function CloseIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" aria-hidden>
      <path d="M4.4 4.4 L11.6 11.6" />
      <path d="M11.6 4.4 L4.4 11.6" />
    </svg>
  );
}
function CameraIcon() {
  return (
    <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.4} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M2.4 6 a1.1 1.1 0 0 1 1.1 -1.1 H5 L5.9 3.5 h4.2 L11 4.9 h1.5 a1.1 1.1 0 0 1 1.1 1.1 v5.9 a1.1 1.1 0 0 1 -1.1 1.1 H3.5 a1.1 1.1 0 0 1 -1.1 -1.1 Z" />
      <circle cx="8" cy="8.9" r="2.2" />
    </svg>
  );
}

const TOOLS = [
  { key: "select", label: "Select", Icon: CursorIcon },
  { key: "ink", label: "Pen", Icon: PenIcon },
  { key: "rect", label: "Rect", Icon: RectangleIcon },
  { key: "ellipse", label: "Circle", Icon: CircleIcon },
  { key: "line", label: "Line", Icon: LineIcon },
  { key: "arrow", label: "Arrow", Icon: ArrowIcon },
  { key: "note", label: "Note", Icon: NoteIcon },
] as const;

type ToolKey = (typeof TOOLS)[number]["key"];

type ArrowStyleKey = "straight" | "curved" | "shaped";

const ARROW_STYLE_OPTIONS: { key: ArrowStyleKey; label: string }[] = [
  { key: "straight", label: "Straight" },
  { key: "curved", label: "Curve" },
  { key: "shaped", label: "Block" },
];

const TOOL_LABELS: Record<ToolKey, string> = {
  select: "Select",
  ink: "Pen",
  rect: "Rectangle",
  ellipse: "Circle",
  line: "Line",
  arrow: "Arrow",
  note: "Note",
};

function toolOptionsLabel(tool: ToolKey) {
  return tool === "select" ? "Select" : `${TOOL_LABELS[tool]} options`;
}

function toolSummary(tool: ToolKey, arrowStyle: ArrowStyleKey) {
  const arrowStyleLabel = ARROW_STYLE_OPTIONS.find((option) => option.key === arrowStyle)?.label ?? "Straight";
  if (tool === "note") return "Sticky · 4px";
  if (tool === "arrow") return `${arrowStyleLabel} · Solid · 4px`;
  if (tool === "select") return "Move and reshape";
  return "Solid · 4px";
}

// ─── Variant themes ──────────────────────────────────────────────────
// Each block is one "material" — read top to bottom to compare. Layout
// is shared; only these tokens change.

interface DockTheme {
  key: string;
  name: string;
  blurb: string;
  /** prefers a light or dark backdrop to be judged against */
  bias: "dark" | "light";
  surface: React.CSSProperties;
  /** radius applied to keys + clusters */
  radius: number;
  /** the segmented well behind Tool Rail / Mode Pair */
  well: React.CSSProperties;
  divider: string;
  text: string;
  textActive: string;
  /** fill behind an active tool/mode key */
  active: React.CSSProperties;
  labelColor: string;
  chip: React.CSSProperties;
  done: React.CSSProperties;
  doneText: string;
  cancel: string;
  keyHover: string;
}

const AMBER = "#DFA13A";
const AMBER_BRIGHT = "#F5C96D";
const PAPER_AMBER = "#C47D1C";

// Shared active treatment — flat accent tint + crisp 1px square inset
// border. No rounded bottom rule, no gradient. This is the fix the user
// asked for ("never like that bottom rounded highlight").
const activeDark: React.CSSProperties = {
  background: "rgba(223,161,58,0.15)",
  boxShadow: "inset 0 0 0 1px rgba(223,161,58,0.62)",
};
const activeLight: React.CSSProperties = {
  background: "rgba(196,125,28,0.13)",
  boxShadow: "inset 0 0 0 1px rgba(196,125,28,0.58)",
};

const VARIANTS: DockTheme[] = [
  {
    key: "slate",
    name: "Slate",
    blurb: "Flat cool charcoal, hairline, squared. The neutral baseline.",
    bias: "dark",
    radius: 3,
    surface: {
      background: "#16181D",
      border: "1px solid rgba(255,255,255,0.11)",
      borderRadius: 6,
      boxShadow: "0 6px 20px rgba(0,0,0,0.45)",
    },
    well: {
      background: "rgba(0,0,0,0.22)",
      borderRadius: 4,
      boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)",
    },
    divider: "rgba(255,255,255,0.13)",
    text: "rgba(255,255,255,0.82)",
    textActive: AMBER_BRIGHT,
    active: activeDark,
    labelColor: "rgba(223,161,58,0.70)",
    chip: { background: "rgba(255,255,255,0.05)", boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.10)" },
    done: { background: AMBER, boxShadow: "none" },
    doneText: "#0E0F12",
    cancel: "rgba(255,255,255,0.5)",
    keyHover: "rgba(255,255,255,0.07)",
  },
  {
    key: "graphite",
    name: "Graphite",
    blurb: "Near-black, ultra-restrained. The most precise — hairline only, nothing extra.",
    bias: "dark",
    radius: 3,
    surface: {
      background: "#0F1012",
      border: "1px solid rgba(255,255,255,0.08)",
      borderRadius: 6,
      boxShadow: "0 6px 20px rgba(0,0,0,0.55)",
    },
    well: {
      background: "rgba(255,255,255,0.03)",
      borderRadius: 4,
      boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.06)",
    },
    divider: "rgba(255,255,255,0.10)",
    text: "rgba(255,255,255,0.78)",
    textActive: AMBER_BRIGHT,
    active: activeDark,
    labelColor: "rgba(223,161,58,0.65)",
    chip: { background: "rgba(255,255,255,0.04)", boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)" },
    done: { background: AMBER, boxShadow: "none" },
    doneText: "#0E0F12",
    cancel: "rgba(255,255,255,0.46)",
    keyHover: "rgba(255,255,255,0.06)",
  },
  {
    key: "warm",
    name: "Warm Deck",
    blurb: "Flat warm charcoal, amber canon. Talkie's instrument identity — no bevels.",
    bias: "dark",
    radius: 3,
    surface: {
      background: "#1E1B16",
      border: "1px solid rgba(223,161,58,0.24)",
      borderRadius: 6,
      boxShadow: "0 6px 20px rgba(0,0,0,0.50)",
    },
    well: {
      background: "rgba(0,0,0,0.26)",
      borderRadius: 4,
      boxShadow: "inset 0 0 0 1px rgba(223,161,58,0.12)",
    },
    divider: "rgba(223,161,58,0.26)",
    text: "rgba(244,231,210,0.80)",
    textActive: AMBER_BRIGHT,
    active: activeDark,
    labelColor: "rgba(223,161,58,0.78)",
    chip: { background: "rgba(223,161,58,0.07)", boxShadow: "inset 0 0 0 1px rgba(223,161,58,0.18)" },
    done: { background: AMBER, boxShadow: "none" },
    doneText: "#2A1B06",
    cancel: "rgba(244,231,210,0.5)",
    keyHover: "rgba(223,161,58,0.10)",
  },
  {
    key: "paper",
    name: "Paper Rail",
    blurb: "Flat warm off-white for drawing over dark content. Ink icons, amber active.",
    bias: "light",
    radius: 3,
    surface: {
      background: "#F6F1E7",
      border: "1px solid rgba(40,33,20,0.16)",
      borderRadius: 6,
      boxShadow: "0 6px 18px rgba(0,0,0,0.22)",
    },
    well: {
      background: "rgba(40,33,20,0.05)",
      borderRadius: 4,
      boxShadow: "inset 0 0 0 1px rgba(40,33,20,0.09)",
    },
    divider: "rgba(40,33,20,0.16)",
    text: "rgba(40,33,20,0.74)",
    textActive: "#8A5A12",
    active: activeLight,
    labelColor: "rgba(138,90,18,0.85)",
    chip: { background: "rgba(40,33,20,0.05)", boxShadow: "inset 0 0 0 1px rgba(40,33,20,0.11)" },
    done: { background: PAPER_AMBER, boxShadow: "none" },
    doneText: "#FFF7E8",
    cancel: "rgba(40,33,20,0.45)",
    keyHover: "rgba(40,33,20,0.06)",
  },
];

// ─── Backdrops ───────────────────────────────────────────────────────
// The dock floats over arbitrary desktop content. Judge legibility on
// each. Faux "windows" give the dock something to overlap.

interface Backdrop {
  key: string;
  label: string;
  style: React.CSSProperties;
  windows: React.CSSProperties[];
}

const BACKDROPS: Record<string, Backdrop> = {
  dark: {
    key: "dark",
    label: "Dark desktop",
    style: { background: "radial-gradient(120% 120% at 30% 10%, #2A2E36 0%, #15171C 60%, #0C0D10 100%)" },
    windows: [
      { left: "8%", top: "14%", width: "44%", height: "58%", background: "#1E2229", boxShadow: "0 20px 60px rgba(0,0,0,0.5)" },
      { right: "9%", top: "22%", width: "34%", height: "44%", background: "#232831", boxShadow: "0 20px 60px rgba(0,0,0,0.5)" },
    ],
  },
  light: {
    key: "light",
    label: "Light desktop",
    style: { background: "radial-gradient(120% 120% at 70% 0%, #FBFAF7 0%, #E9E6DF 55%, #D6D2C8 100%)" },
    windows: [
      { left: "8%", top: "14%", width: "44%", height: "58%", background: "#FFFFFF", boxShadow: "0 20px 50px rgba(0,0,0,0.16)" },
      { right: "9%", top: "22%", width: "34%", height: "44%", background: "#F4F2EC", boxShadow: "0 20px 50px rgba(0,0,0,0.16)" },
    ],
  },
  photo: {
    key: "photo",
    label: "Photo wallpaper",
    style: { background: "linear-gradient(135deg, #3E5C76 0%, #748CAB 30%, #C98B6B 70%, #E0A458 100%)" },
    windows: [
      { left: "10%", top: "16%", width: "40%", height: "54%", background: "rgba(20,22,28,0.55)", boxShadow: "0 20px 60px rgba(0,0,0,0.4)" },
    ],
  },
};

// ─── Dock ────────────────────────────────────────────────────────────

function Key({
  theme,
  active,
  children,
  width,
  title,
}: {
  theme: DockTheme;
  active?: boolean;
  children: React.ReactNode;
  width?: number;
  title?: string;
}) {
  const [hover, setHover] = React.useState(false);
  return (
    <button
      type="button"
      title={title}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      className="grid place-items-center font-semibold transition-colors"
      style={{
        height: 30,
        width: width ?? 30,
        borderRadius: theme.radius,
        color: active ? theme.textActive : theme.text,
        fontSize: 11,
        border: "none",
        cursor: "pointer",
        ...(active ? theme.active : hover ? { background: theme.keyHover } : { background: "transparent" }),
      }}
    >
      {children}
    </button>
  );
}

function Divider({ color }: { color: string }) {
  return <span aria-hidden style={{ width: 1, height: 20, background: color, display: "block", margin: "0 3px" }} />;
}

function Dock({
  theme,
  activeTool,
  arrowStyle,
  drawerOpen,
  scale = 1,
}: {
  theme: DockTheme;
  activeTool: string;
  arrowStyle: ArrowStyleKey;
  drawerOpen: boolean;
  scale?: number;
}) {
  const toolKey = activeTool as ToolKey;
  const styleChipLabel = toolOptionsLabel(toolKey);
  const styleChipDetail = toolSummary(toolKey, arrowStyle);

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 7,
        transform: `scale(${scale})`,
        transformOrigin: "bottom center",
      }}
    >
      {drawerOpen ? <StyleDrawer theme={theme} activeTool={toolKey} arrowStyle={arrowStyle} /> : null}

      {/* Toolbar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 6,
          padding: 5,
          ...theme.surface,
        }}
      >
        {/* Tool Rail */}
        <div style={{ display: "flex", alignItems: "center", gap: 1, padding: 2, ...theme.well }}>
          {TOOLS.map((t) => (
            <Key key={t.key} theme={theme} active={activeTool === t.key} title={t.label}>
              <t.Icon />
            </Key>
          ))}
        </div>

        {/* Mode Pair */}
        <div style={{ display: "flex", alignItems: "center", gap: 1, padding: 2, ...theme.well }}>
          <Key theme={theme} active width={48} title="Agent instruction markup">
            <span style={{ fontSize: 11 }}>Agent</span>
          </Key>
          <Key theme={theme} width={48} title="Presentation markup">
            <span style={{ fontSize: 11 }}>Demo</span>
          </Key>
        </div>

        <Divider color={theme.divider} />

        {/* Tool Options */}
        <button
          type="button"
          className="flex items-center gap-1.5 transition-colors"
          style={{
            height: 30,
            minWidth: 152,
            padding: "0 9px",
            borderRadius: theme.radius,
            border: "none",
            color: theme.text,
            fontSize: 11,
            fontWeight: 600,
            cursor: "pointer",
            ...theme.chip,
          }}
          title={`Show ${styleChipLabel}`}
        >
          <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" aria-hidden>
            <path d="M3 4.5 H13" />
            <path d="M3 11.5 H13" />
            <circle cx="6" cy="4.5" r="1.5" fill="currentColor" stroke="none" />
            <circle cx="10.5" cy="11.5" r="1.5" fill="currentColor" stroke="none" />
          </svg>
          <span style={{ width: 11, height: 11, borderRadius: 3, background: "#D03A1C", boxShadow: "inset 0 0 0 1px rgba(0,0,0,0.25)" }} />
          <span style={{ display: "flex", minWidth: 0, flexDirection: "column", alignItems: "flex-start", gap: 2 }}>
            <span style={{ maxWidth: 102, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{styleChipLabel}</span>
            <span style={{ maxWidth: 102, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: theme.cancel, fontSize: 9 }}>{styleChipDetail}</span>
          </span>
        </button>

        <Divider color={theme.divider} />

        {/* Commit Cluster */}
        <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <button
            type="button"
            className="grid place-items-center font-bold transition-colors"
            style={{
              height: 30,
              padding: "0 14px",
              borderRadius: theme.radius,
              border: "none",
              color: theme.doneText,
              fontSize: 11.5,
              cursor: "pointer",
              ...theme.done,
            }}
            title="Done"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
}

function StyleDrawer({ theme, activeTool, arrowStyle }: { theme: DockTheme; activeTool: ToolKey; arrowStyle: ArrowStyleKey }) {
  const swatches = ["#D03A1C", "#4F7DFF", "#12A594", "#FFFFFF"];
  const showNote = activeTool === "note";
  const showLine = activeTool === "ink" || activeTool === "rect" || activeTool === "ellipse" || activeTool === "line" || activeTool === "arrow";
  const showArrow = activeTool === "arrow";
  const Group = ({ label, children }: { label: string; children: React.ReactNode }) => (
    <div style={{ display: "flex", alignItems: "center", gap: 5 }}>
      <span style={{ fontSize: 10, fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.2, color: theme.labelColor }}>{label}</span>
      {children}
    </div>
  );
  const Pill = ({ children, active }: { children: React.ReactNode; active?: boolean }) => (
    <span
      style={{
        height: 22,
        padding: "0 8px",
        display: "grid",
        placeItems: "center",
        borderRadius: Math.min(theme.radius, 6),
        fontSize: 10.5,
        fontWeight: 600,
        color: active ? theme.textActive : theme.text,
        ...(active ? theme.active : {}),
      }}
    >
      {children}
    </span>
  );
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 14, padding: "8px 12px", ...theme.surface }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 6 }}>
        <span style={{ fontSize: 10, fontWeight: 600, textTransform: "uppercase", color: theme.labelColor }}>Tool</span>
        <span style={{ fontSize: 11, fontWeight: 700, color: theme.text }}>{toolOptionsLabel(activeTool)}</span>
      </div>
      {showNote ? (
        <>
          <Divider color={theme.divider} />
          <Group label="Note">
            <Pill active>Sticky</Pill>
            <Pill>Bubble</Pill>
            <Pill>Glass</Pill>
          </Group>
        </>
      ) : null}
      {showLine ? (
        <>
          <Divider color={theme.divider} />
          <Group label="Line">
            <Pill active>Solid</Pill>
            <Pill>Dash</Pill>
            <Pill>Glow</Pill>
          </Group>
        </>
      ) : null}
      {showArrow ? (
        <>
          <Divider color={theme.divider} />
          <Group label="Arrow">
            {ARROW_STYLE_OPTIONS.map((style) => (
              <Pill key={style.key} active={arrowStyle === style.key}>
                {style.label}
              </Pill>
            ))}
          </Group>
        </>
      ) : null}
      <Divider color={theme.divider} />
      <Group label="Color">
        {swatches.map((c, i) => (
          <span
            key={c}
            style={{
              width: 16,
              height: 16,
              borderRadius: 4,
              background: c,
              boxShadow: i === 0 ? `inset 0 0 0 1.5px ${theme.textActive}` : "inset 0 0 0 1px rgba(0,0,0,0.25)",
            }}
          />
        ))}
      </Group>
      <Divider color={theme.divider} />
      <Group label="Stroke">
        <Pill active>M</Pill>
        <Pill>H</Pill>
      </Group>
    </div>
  );
}

function BehaviorCard({
  title,
  caption,
  children,
}: {
  title: string;
  caption: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-[6px] border border-studio-edge bg-white p-3">
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h3 className="m-0 font-mono text-[10px] font-semibold uppercase tracking-[0.1em] text-studio-ink">{title}</h3>
        <span className="text-[10px] text-studio-ink-faint">{caption}</span>
      </div>
      {children}
    </div>
  );
}

function HandleDot({
  left,
  top,
  square,
  theme,
}: {
  left: string;
  top: string;
  square?: boolean;
  theme: DockTheme;
}) {
  return (
    <span
      className="absolute"
      style={{
        left,
        top,
        width: 14,
        height: 14,
        transform: "translate(-50%, -50%)",
        borderRadius: square ? 3 : 999,
        background: theme.doneText,
        boxShadow: `0 0 0 2px ${theme.textActive}, 0 0 0 9px rgba(223,161,58,0.16)`,
      }}
    />
  );
}

function MarkupBehaviorStrip({ theme, arrowStyle }: { theme: DockTheme; arrowStyle: ArrowStyleKey }) {
  const arrowStyleLabel = ARROW_STYLE_OPTIONS.find((option) => option.key === arrowStyle)?.label ?? "Straight";

  return (
    <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
      <BehaviorCard title="Frame Handles" caption="18 px grab area">
        <div className="relative h-[132px] rounded-[5px] border border-studio-edge bg-[#F7F4EE]">
          <div
            className="absolute"
            style={{
              left: "22%",
              top: "24%",
              width: "56%",
              height: "52%",
              border: `2px solid ${theme.textActive}`,
              background: "rgba(223,161,58,0.08)",
            }}
          />
          {[
            ["22%", "24%"],
            ["50%", "24%"],
            ["78%", "24%"],
            ["22%", "50%"],
            ["78%", "50%"],
            ["22%", "76%"],
            ["50%", "76%"],
            ["78%", "76%"],
          ].map(([left, top]) => (
            <HandleDot key={`${left}-${top}`} left={left} top={top} square theme={theme} />
          ))}
        </div>
      </BehaviorCard>

      <BehaviorCard title="Arrow Handles" caption="free drag, Shift = 15 deg">
        <div className="relative h-[132px] rounded-[5px] border border-studio-edge bg-[#15171C]">
          <svg className="absolute inset-0 h-full w-full" viewBox="0 0 260 132" aria-hidden>
            <path d="M54 92 Q132 18 208 64" fill="none" stroke={theme.textActive} strokeWidth="4" strokeLinecap="round" />
            <path d="M195 52 L208 64 L190 70" fill="none" stroke={theme.textActive} strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M44 100 L216 36" fill="none" stroke="rgba(255,255,255,0.14)" strokeWidth="1" strokeDasharray="4 5" />
          </svg>
          <HandleDot left="21%" top="70%" theme={theme} />
          <HandleDot left="80%" top="49%" theme={theme} />
          <span className="absolute right-3 top-3 rounded-[3px] bg-white/10 px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-[0.1em] text-white/70">
            15 deg
          </span>
        </div>
      </BehaviorCard>

      <BehaviorCard title="Arrow Styles" caption={arrowStyleLabel}>
        <div className="grid h-[132px] grid-cols-3 gap-2">
          {ARROW_STYLE_OPTIONS.map((style) => (
            <div
              key={style.key}
              className={cn(
                "relative rounded-[5px] border bg-[#F7F4EE]",
                arrowStyle === style.key ? "border-studio-ink" : "border-studio-edge"
              )}
            >
              <svg className="absolute inset-0 h-full w-full" viewBox="0 0 100 96" aria-hidden>
                {style.key === "straight" ? (
                  <>
                    <path d="M22 72 L76 24" fill="none" stroke="#2B2520" strokeWidth="6" strokeLinecap="round" />
                    <path d="M74 44 L76 24 L55 27" fill="none" stroke="#2B2520" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" />
                  </>
                ) : null}
                {style.key === "curved" ? (
                  <>
                    <path d="M22 72 Q44 20 76 44" fill="none" stroke="#2B2520" strokeWidth="6" strokeLinecap="round" />
                    <path d="M58 49 L76 44 L69 27" fill="none" stroke="#2B2520" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" />
                  </>
                ) : null}
                {style.key === "shaped" ? (
                  <path d="M20 62 L60 32 L56 18 L84 30 L73 58 L67 45 L29 75 Z" fill="#2B2520" />
                ) : null}
              </svg>
              <span className="absolute inset-x-0 bottom-2 text-center font-mono text-[9px] font-semibold uppercase tracking-[0.08em] text-studio-ink-faint">
                {style.label}
              </span>
            </div>
          ))}
        </div>
      </BehaviorCard>
    </div>
  );
}

// ─── Stage ───────────────────────────────────────────────────────────

type RealMarkupAPI = {
  setTool: (tool: string) => void;
  setArrowStyle: (style: string) => void;
  setStyleOpen: (open: boolean) => void;
  setContext: (context: string) => void;
  clear: () => void;
};

type RealMarkupWindow = Window & {
  talkieLiveMarkup?: RealMarkupAPI;
};

function RealMarkupSurface({
  themeKey,
  activeTool,
  arrowStyle,
  drawerOpen,
  clearSignal,
}: {
  themeKey: string;
  activeTool: ToolKey;
  arrowStyle: ArrowStyleKey;
  drawerOpen: boolean;
  clearSignal: number;
}) {
  const frameRef = React.useRef<HTMLIFrameElement>(null);
  const src = `/real-capture-markup/overlay.html?theme=${encodeURIComponent(themeKey)}&context=desktopInk`;

  const syncFrame = React.useCallback(() => {
    const frameWindow = frameRef.current?.contentWindow as RealMarkupWindow | null | undefined;
    const api = frameWindow?.talkieLiveMarkup;
    if (!api) return;
    api.setContext("desktopInk");
    api.setTool(activeTool);
    api.setArrowStyle(arrowStyle);
    api.setStyleOpen(drawerOpen && activeTool !== "select");
  }, [activeTool, arrowStyle, drawerOpen]);

  React.useEffect(() => {
    syncFrame();
  }, [syncFrame]);

  React.useEffect(() => {
    const api = (frameRef.current?.contentWindow as RealMarkupWindow | null | undefined)?.talkieLiveMarkup;
    if (api && clearSignal > 0) api.clear();
  }, [clearSignal]);

  return (
    <iframe
      ref={frameRef}
      title="Live Talkie markup overlay"
      src={src}
      onLoad={() => {
        window.setTimeout(syncFrame, 0);
      }}
      className="absolute inset-0 h-full w-full border-0"
      style={{ background: "transparent", colorScheme: themeKey === "paper" ? "light" : "dark" }}
    />
  );
}

function ChromeKey({
  theme,
  children,
  title,
  accent = false,
}: {
  theme: DockTheme;
  children: React.ReactNode;
  title: string;
  accent?: boolean;
}) {
  const [hover, setHover] = React.useState(false);
  return (
    <button
      type="button"
      title={title}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      className="grid place-items-center transition-colors"
      style={{
        width: 30,
        height: 30,
        border: "none",
        borderRadius: theme.radius,
        color: accent ? theme.doneText : theme.text,
        cursor: "pointer",
        ...(accent ? theme.done : hover ? { background: theme.keyHover } : { background: "transparent" }),
      }}
    >
      {children}
    </button>
  );
}

function MarkupWindowChrome({ theme }: { theme: DockTheme }) {
  return (
    <>
      <div className="absolute left-4 top-4 z-20" style={{ padding: 4, ...theme.surface }}>
        <ChromeKey theme={theme} title="Cancel markup">
          <span style={{ color: theme.cancel, display: "grid", placeItems: "center" }}>
            <CloseIcon />
          </span>
        </ChromeKey>
      </div>
      <div className="absolute right-4 top-4 z-20 flex items-center gap-[5px]" style={{ padding: 4, ...theme.surface }}>
        <ChromeKey theme={theme} title="Undo">
          <UndoIcon />
        </ChromeKey>
        <ChromeKey theme={theme} title="Redo">
          <RedoIcon />
        </ChromeKey>
        <ChromeKey theme={theme} title="Take screenshot" accent>
          <CameraIcon />
        </ChromeKey>
      </div>
    </>
  );
}

function Stage({
  backdrop,
  children,
  height = 360,
  fill = false,
  chromeTheme,
}: {
  backdrop: Backdrop;
  children: React.ReactNode;
  height?: number;
  fill?: boolean;
  chromeTheme?: DockTheme;
}) {
  return (
    <div
      className="relative overflow-hidden rounded-[10px] border border-studio-edge"
      style={{ height, ...backdrop.style }}
    >
      {backdrop.windows.map((w, i) => (
        <div key={i} className="absolute rounded-[10px]" style={{ position: "absolute", borderRadius: 10, ...w }} />
      ))}
      {chromeTheme ? <MarkupWindowChrome theme={chromeTheme} /> : null}
      {fill ? children : <div className="absolute inset-x-0 bottom-6 flex justify-center">{children}</div>}
    </div>
  );
}

// ─── Picker ──────────────────────────────────────────────────────────

function SegPicker<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T;
  options: { key: T; label: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="mr-1 text-[9px] font-semibold uppercase tracking-ch text-studio-ink-faint">{label}</span>
      <div className="flex items-center gap-1 rounded-[5px] border border-studio-edge bg-white p-0.5">
        {options.map((o) => (
          <button
            key={o.key}
            onClick={() => onChange(o.key)}
            className={cn(
              "rounded-[3px] px-2.5 py-1 font-mono text-[9px] font-semibold uppercase tracking-[0.10em] transition-colors",
              value === o.key
                ? "bg-studio-ink text-studio-canvas"
                : "text-studio-ink-faint hover:text-studio-ink"
            )}
          >
            {o.label}
          </button>
        ))}
      </div>
    </div>
  );
}

// ─── Study ───────────────────────────────────────────────────────────

export function MacMarkupDock() {
  const [variant, setVariant] = React.useState<string>("warm");
  const [backdropKey, setBackdropKey] = React.useState<string>("dark");
  const [drawerOpen, setDrawerOpen] = React.useState(true);
  const [activeTool, setActiveTool] = React.useState<ToolKey>("arrow");
  const [arrowStyle, setArrowStyle] = React.useState<ArrowStyleKey>("curved");
  const [clearSignal, setClearSignal] = React.useState(0);

  const theme = VARIANTS.find((v) => v.key === variant) ?? VARIANTS[0];
  const backdrop = BACKDROPS[backdropKey];

  return (
    <div className="flex flex-col gap-6">
      {/* Controls */}
      <div className="flex flex-wrap items-center gap-x-6 gap-y-3 rounded-[6px] border border-studio-edge bg-white px-4 py-3">
        <SegPicker
          label="Variant"
          value={variant}
          onChange={setVariant}
          options={VARIANTS.map((v) => ({ key: v.key, label: v.name }))}
        />
        <SegPicker
          label="Backdrop"
          value={backdropKey}
          onChange={setBackdropKey}
          options={Object.values(BACKDROPS).map((b) => ({ key: b.key, label: b.label }))}
        />
        <SegPicker
          label="Tool"
          value={activeTool}
          onChange={setActiveTool}
          options={TOOLS.map((t) => ({ key: t.key, label: t.label }))}
        />
        <SegPicker
          label="Arrow"
          value={arrowStyle}
          onChange={setArrowStyle}
          options={ARROW_STYLE_OPTIONS}
        />
        <button
          onClick={() => setDrawerOpen((o) => !o)}
          className={cn(
            "rounded-[4px] border px-3 py-1.5 font-mono text-[9px] font-semibold uppercase tracking-[0.12em] transition-colors",
            drawerOpen ? "border-studio-ink bg-studio-ink text-studio-canvas" : "border-studio-edge text-studio-ink-faint hover:text-studio-ink"
          )}
        >
          {drawerOpen ? "Drawer open" : "Drawer closed"}
        </button>
        <button
          onClick={() => setClearSignal((value) => value + 1)}
          className="rounded-[4px] border border-studio-edge px-3 py-1.5 font-mono text-[9px] font-semibold uppercase tracking-[0.12em] text-studio-ink-faint transition-colors hover:text-studio-ink"
        >
          Clear
        </button>
      </div>

      {/* Featured */}
      <div>
        <div className="mb-2 flex items-baseline gap-3">
          <h2 className="m-0 font-display text-[19px] font-medium text-studio-ink">{theme.name}</h2>
          <p className="m-0 text-[12px] text-studio-ink-faint">{theme.blurb}</p>
        </div>
        <Stage backdrop={backdrop} height={drawerOpen ? 420 : 360} fill>
          <RealMarkupSurface
            themeKey={theme.key}
            activeTool={activeTool}
            arrowStyle={arrowStyle}
            drawerOpen={drawerOpen}
            clearSignal={clearSignal}
          />
        </Stage>
      </div>

      <MarkupBehaviorStrip theme={theme} arrowStyle={arrowStyle} />

      {/* Board — all four, same backdrop, for side-by-side */}
      <div>
        <div className="mb-2 text-[9px] font-semibold uppercase tracking-ch text-studio-ink-faint">
          All four · {backdrop.label}
        </div>
        <div className="grid grid-cols-2 gap-4">
          {VARIANTS.map((v) => (
            <div
              key={v.key}
              role="button"
              tabIndex={0}
              onClick={() => setVariant(v.key)}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  setVariant(v.key);
                }
              }}
              className={cn(
                "group block cursor-pointer text-left",
                v.key === variant ? "ring-2 ring-studio-ink rounded-[12px]" : ""
              )}
            >
              <Stage
                backdrop={v.bias === "light" && backdrop.key === "dark" ? BACKDROPS.dark : v.bias === "dark" && backdrop.key === "light" ? BACKDROPS.light : backdrop}
                height={210}
                chromeTheme={v}
              >
                <Dock theme={v} activeTool={activeTool} arrowStyle={arrowStyle} drawerOpen={false} scale={0.82} />
              </Stage>
              <div className="mt-1.5 flex items-center gap-2 px-1">
                <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.1em] text-studio-ink">{v.name}</span>
                <span className="truncate text-[11px] text-studio-ink-faint">{v.blurb}</span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Names marginalia */}
      <aside className="rounded-[6px] border border-studio-edge bg-white px-4 py-3 text-[11px] leading-relaxed text-studio-ink-faint">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-ch text-studio-ink">Names</span>
        <span className="mx-2 text-studio-edge">·</span>
        <b className="text-studio-ink">Dock</b> the whole cluster ·{" "}
        <b className="text-studio-ink">Tool Rail</b> Select/Pen/Rect/Circle/Line/Arrow/Note ·{" "}
        <b className="text-studio-ink">Mode Pair</b> Agent/Demo ·{" "}
        <b className="text-studio-ink">Tool Options</b> sliders + swatch + summary ·{" "}
        <b className="text-studio-ink">Options Drawer</b> contextual tool controls ·{" "}
        <b className="text-studio-ink">Window Chrome</b> cancel ·{" "}
        <b className="text-studio-ink">Surface Actions</b> undo/redo/capture ·{" "}
        <b className="text-studio-ink">Commit Cluster</b> Done.
        <span className="mt-1.5 block">
          Ports to <code className="text-studio-ink">overlay.css</code> ·{" "}
          <code className="text-studio-ink">overlay.html</code> (shared by live-recording markup + desktop ink).
          Every variant swaps the unicode glyphs for the shared line-art icon set.
        </span>
      </aside>
    </div>
  );
}
