"use client";

/**
 * Mac Talkie Button — single anchor replaces the sidebar.
 *
 * Today the macOS app has a global sidebar (AppNavigation.swift, three
 * display states: Hidden / Icon-rail / Expanded) plus three voice/text
 * affordances spread across the surface:
 *
 *   - Cmd+Shift+V → VoiceCommandOverlay (particle blob, intent recognition)
 *   - Cmd+K       → CommandPaletteView  (Raycast-style 560×420 sheet)
 *   - In Compose  → ScopeDraftsScreen's inline COMMAND button (scoped voice edit)
 *
 * This study consolidates all three into ONE button — the Talkie Button —
 * with a tap path (palette), a hold path (voice command), and a
 * right-click path (sectioned nav popover). The notch is the natural
 * anchor since NotchComposer already owns that space and already has
 * tap gestures during recording.
 *
 * The study has three sections, stacked:
 *
 *   1. STATES GALLERY — the 8 lifecycle moments side-by-side.
 *   2. SUMMONED OVERLAYS — palette + sectioned nav popover, each
 *      anchored from a button.
 *   3. VARIANTS A & B in context — MacHome reframed two ways:
 *      A) No sidebar at all. Button floats top-leading.
 *      B) Minimized icon-rail sidebar with the Talkie button at its
 *         top and icon-only nav stacked below.
 *      Both at 820 / 1180 / 1440 so the responsive behavior is honest.
 *
 * Reuses MacHome's existing composition (we just wrap it differently).
 */

import React from "react";
import { MacHome } from "./MacHome";
import { IconRail } from "./primitives/IconRail";

// ─── Tokens ──────────────────────────────────────────────────────────

const AMBER = "#C47D1C";
const AMBER_GLOW = "#E89A3C";
const INK = "#232423";
const INK_FAINT = "rgba(26,22,18,0.45)";
const EDGE = "#DEDEDD";
const CREAM = "#F8F8F7";
const PAPER = "#E7E7E6";

// ─── Composition root ────────────────────────────────────────────────

export function MacTalkieButton() {
  return (
    <div className="flex flex-col gap-16">
      <StatesGallery />
      <SummonedOverlays />
      <HoverRevealStrip />
      <VariantA />
      <VariantB />
    </div>
  );
}

// ─── Studio section header ───────────────────────────────────────────

function SectionHeader({
  eyebrow,
  title,
  hint,
}: {
  eyebrow: string;
  title: string;
  hint?: string;
}) {
  return (
    <div className="mb-5 flex items-baseline gap-4 border-b border-studio-edge pb-3">
      <div>
        <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
          {eyebrow}
        </div>
        <h2 className="m-0 font-display text-[20px] font-medium leading-none tracking-tight text-studio-ink">
          {title}
        </h2>
      </div>
      {hint && (
        <div className="ml-auto font-mono text-[10px] uppercase tracking-[0.18em] text-studio-ink-faint">
          {hint}
        </div>
      )}
    </div>
  );
}

// ─── 1. States gallery ───────────────────────────────────────────────

const STATES = [
  { key: "idle",        label: "Idle",        hint: "default rest state" },
  { key: "hover",       label: "Hover",       hint: "tooltip · pre-summon" },
  { key: "paletteOpen", label: "Palette",     hint: "tap · text search" },
  { key: "navOpen",     label: "Nav",         hint: "right-click · sections" },
  { key: "listening",   label: "Listening",   hint: "hold ≥250ms · capture" },
  { key: "processing",  label: "Processing",  hint: "recognizing intent" },
  { key: "recording",   label: "Recording",   hint: "memo in progress" },
  { key: "error",       label: "Error",       hint: "low confidence · revert" },
] as const;

type ButtonState = (typeof STATES)[number]["key"];

function StatesGallery() {
  return (
    <section>
      <SectionHeader
        eyebrow="· One"
        title="Button states"
        hint="lifecycle moments — read left to right"
      />
      <div className="grid gap-4" style={{ gridTemplateColumns: "repeat(4, minmax(0, 1fr))" }}>
        {STATES.map((s) => (
          <StateCell key={s.key} state={s.key} label={s.label} hint={s.hint} />
        ))}
      </div>
    </section>
  );
}

function StateCell({
  state,
  label,
  hint,
}: {
  state: ButtonState;
  label: string;
  hint: string;
}) {
  return (
    <div
      className="flex flex-col items-center gap-3 rounded-md py-6"
      style={{ background: CREAM, border: `0.5px solid ${EDGE}` }}
    >
      <TalkieButton state={state} />
      <div className="flex flex-col items-center gap-0.5">
        <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em] text-studio-ink">
          · {label}
        </div>
        <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          {hint}
        </div>
      </div>
    </div>
  );
}

// ─── The Talkie Button itself ────────────────────────────────────────
// A notch-shaped pill with a mark inside. Reads as the menu-bar
// neighbor when anchored to the screen top. Width varies by state.

function TalkieButton({
  state = "idle",
  large = false,
}: {
  state?: ButtonState;
  large?: boolean;
}) {
  // State-driven dimensions. The pill grows when listening / recording
  // to make room for either the particle blob or the elapsed timer.
  const h = large ? 32 : 26;
  const baseWidth = large ? 140 : 110;
  const dimensions = {
    idle:        { w: baseWidth, expanded: false },
    hover:       { w: baseWidth, expanded: false },
    paletteOpen: { w: baseWidth + 20, expanded: true },
    navOpen:     { w: baseWidth + 20, expanded: true },
    listening:   { w: baseWidth + 80, expanded: true },
    processing:  { w: baseWidth + 20, expanded: true },
    recording:   { w: baseWidth + 60, expanded: true },
    error:       { w: baseWidth, expanded: false },
  }[state];

  return (
    <div className="flex flex-col items-center gap-2">
      <div
        className="relative flex items-center justify-center gap-2 px-3"
        style={{
          height: h,
          minWidth: dimensions.w,
          borderRadius: h / 2,
          background:
            state === "recording" ? "#2A1614" :
            state === "error"     ? "#3A1010" :
            state === "navOpen"   ? "#1A1614" :
            state === "paletteOpen" ? "#1A1614" :
                                    INK,
          boxShadow:
            state === "hover" || state === "listening"
              ? `0 0 0 3px ${AMBER}22, 0 4px 14px rgba(0,0,0,0.18)`
              : state === "recording"
              ? `0 0 0 3px rgba(220,40,40,0.22), 0 4px 14px rgba(0,0,0,0.22)`
              : state === "error"
              ? `0 0 0 3px rgba(220,40,40,0.28)`
              : "0 2px 8px rgba(0,0,0,0.14)",
          transition: "all 200ms ease",
        }}
      >
        <ButtonInner state={state} />
      </div>

      {/* Tooltip — only on hover */}
      {state === "hover" && (
        <div
          className="rounded-[3px] px-2 py-1 font-mono text-[8.5px] uppercase tracking-[0.20em]"
          style={{
            background: INK,
            color: CREAM,
            boxShadow: "0 2px 6px rgba(0,0,0,0.18)",
          }}
        >
          Tap to search · Hold to speak
        </div>
      )}
    </div>
  );
}

// What renders INSIDE the pill, per state. The mark on the left is
// constant; what changes is what sits to the right of it.
function ButtonInner({ state }: { state: ButtonState }) {
  // Recording variant gets a red dot + timer
  if (state === "recording") {
    return (
      <>
        <RedPulse />
        <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.14em]" style={{ color: "#FBE2DC" }}>
          REC
        </span>
        <span className="font-mono text-[10px] tracking-[0.06em]" style={{ color: "#FBE2DC" }}>
          0:24
        </span>
      </>
    );
  }

  if (state === "error") {
    return (
      <>
        <span className="font-mono text-[10px] font-bold" style={{ color: "#FBE2DC" }}>!</span>
        <span className="font-mono text-[10px] uppercase tracking-[0.18em]" style={{ color: "#FBE2DC" }}>
          Low confidence
        </span>
      </>
    );
  }

  if (state === "listening") {
    return (
      <>
        <TalkieMark glow />
        <ParticleBlob />
        <span className="font-mono text-[10px] uppercase tracking-[0.18em]" style={{ color: AMBER_GLOW }}>
          Listening
        </span>
      </>
    );
  }

  if (state === "processing") {
    return (
      <>
        <Spinner />
        <span className="font-mono text-[10px] uppercase tracking-[0.18em]" style={{ color: AMBER_GLOW }}>
          Thinking…
        </span>
      </>
    );
  }

  if (state === "paletteOpen") {
    return (
      <>
        <TalkieMark />
        <span className="font-mono text-[10px] uppercase tracking-[0.18em]" style={{ color: CREAM }}>
          Search
        </span>
        <span className="font-mono text-[10px] tracking-[0.06em]" style={{ color: "rgba(251,251,250,0.5)" }}>
          ⌘K
        </span>
      </>
    );
  }

  if (state === "navOpen") {
    return (
      <>
        <TalkieMark />
        <span className="font-mono text-[10px] uppercase tracking-[0.18em]" style={{ color: CREAM }}>
          Navigate
        </span>
        <Caret />
      </>
    );
  }

  // idle, hover — same shape, hover just adds tooltip outside
  return (
    <>
      <TalkieMark glow={state === "hover"} />
      <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.20em]" style={{ color: CREAM }}>
        Talkie
      </span>
      <span className="font-mono text-[9px] tracking-[0.06em]" style={{ color: "rgba(251,251,250,0.45)" }}>
        ⌘K
      </span>
    </>
  );
}

function TalkieMark({ glow = false }: { glow?: boolean }) {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden>
      <circle
        cx="7"
        cy="7"
        r="3"
        fill={AMBER_GLOW}
        style={glow ? { filter: `drop-shadow(0 0 4px ${AMBER_GLOW})` } : undefined}
      />
      <circle cx="7" cy="7" r="5.5" fill="none" stroke={AMBER_GLOW} strokeOpacity="0.4" strokeWidth="1" />
    </svg>
  );
}

function RedPulse() {
  return (
    <span
      aria-hidden
      className="h-2 w-2 rounded-full"
      style={{
        background: "#E53E3E",
        boxShadow: "0 0 0 3px rgba(229,62,62,0.28), 0 0 6px rgba(229,62,62,0.6)",
      }}
    />
  );
}

function Spinner() {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
      <circle cx="6" cy="6" r="4.5" fill="none" stroke={AMBER_GLOW} strokeOpacity="0.25" strokeWidth="1.4" />
      <path d="M 6 1.5 A 4.5 4.5 0 0 1 10.5 6" fill="none" stroke={AMBER_GLOW} strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}

function ParticleBlob() {
  // Five tiny dots in a wave pattern — static for the study; the
  // shipping version ports VoiceCommandOverlay's ParticleSystemView.
  const dots = [
    { x: 0,  y: 0,  r: 1.6 },
    { x: 5,  y: -2, r: 1.4 },
    { x: 10, y: 1,  r: 1.8 },
    { x: 15, y: -1, r: 1.4 },
    { x: 20, y: 2,  r: 1.6 },
  ];
  return (
    <svg width="24" height="10" viewBox="-2 -5 26 10" aria-hidden>
      {dots.map((d, i) => (
        <circle
          key={i}
          cx={d.x}
          cy={d.y}
          r={d.r}
          fill={AMBER_GLOW}
          opacity={0.85}
        />
      ))}
    </svg>
  );
}

function Caret() {
  return (
    <svg width="8" height="6" viewBox="0 0 8 6" aria-hidden>
      <path d="M 1 1 L 4 4 L 7 1" fill="none" stroke={CREAM} strokeOpacity="0.6" strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  );
}

// ─── 2. Summoned overlays ────────────────────────────────────────────

function SummonedOverlays() {
  return (
    <section>
      <SectionHeader
        eyebrow="· Two"
        title="What it summons"
        hint="palette · sectioned nav popover"
      />
      <div className="grid gap-6" style={{ gridTemplateColumns: "minmax(0, 1.4fr) minmax(0, 1fr)" }}>
        <PaletteAnchored />
        <NavPopoverAnchored />
      </div>
    </section>
  );
}

// Palette anchored under the button. The palette itself reuses the
// existing CommandPaletteView shape (~560×420). Here it sits on a
// faint stage with a connecting bracket so the anchor point reads.
function PaletteAnchored() {
  return (
    <div
      className="relative flex flex-col items-center gap-3 rounded-md py-7"
      style={{ background: CREAM, border: `0.5px solid ${EDGE}` }}
    >
      <TalkieButton state="paletteOpen" />
      <ConnectingBracket />
      <PaletteSheet />
      <div className="mt-2 font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
        · TAP · open palette · ⌘K
      </div>
    </div>
  );
}

const PALETTE_ROWS = [
  { glyph: "↗", section: "Go to",     label: "Home",                  hint: "" },
  { glyph: "↗", section: "Go to",     label: "Library",               hint: "" },
  { glyph: "↗", section: "Go to",     label: "Compose",               hint: "" },
  { glyph: "✦", section: "Action",    label: "Start a memo",          hint: "⌃⇧⌘ M" },
  { glyph: "✦", section: "Action",    label: "Dictate",               hint: "⌃⇧⌘ D" },
  { glyph: "✦", section: "Action",    label: "Capture screen",        hint: "⌃⇧⌘ S" },
  { glyph: "✺", section: "Workflows", label: "Summarize standup",     hint: "" },
  { glyph: "✺", section: "Workflows", label: "Dictation → Linear",    hint: "" },
];

function PaletteSheet() {
  return (
    <div
      className="overflow-hidden rounded-md"
      style={{
        width: 560,
        background: CREAM,
        border: `0.5px solid ${EDGE}`,
        boxShadow: "0 12px 40px rgba(0,0,0,0.16), 0 4px 12px rgba(0,0,0,0.06)",
      }}
    >
      {/* Search input */}
      <div
        className="flex items-center gap-2 px-4 py-3"
        style={{ borderBottom: `0.5px solid ${EDGE}`, background: PAPER }}
      >
        <span className="font-mono text-[12px] text-studio-ink-faint">⌕</span>
        <span className="font-display text-[14px] text-studio-ink-faint">
          Search anything — type, or hold the button to speak…
        </span>
        <div className="ml-auto flex items-center gap-1">
          <KeyCap>⌘</KeyCap>
          <KeyCap>K</KeyCap>
        </div>
      </div>

      {/* Rows */}
      <div className="flex flex-col">
        {PALETTE_ROWS.map((r, i) => {
          const sectionBreak =
            i === 0 || PALETTE_ROWS[i - 1].section !== r.section;
          const selected = i === 0;
          return (
            <React.Fragment key={i}>
              {sectionBreak && (
                <div
                  className="px-4 pt-2 pb-1 font-mono text-[8px] uppercase tracking-[0.28em]"
                  style={{ color: INK_FAINT }}
                >
                  · {r.section}
                </div>
              )}
              <div
                className="flex items-center gap-3 px-4 py-2"
                style={{
                  background: selected ? "#EAEAE9" : "transparent",
                  borderLeft: selected ? `2px solid ${AMBER}` : "2px solid transparent",
                }}
              >
                <span className="font-mono text-[12px]" style={{ color: AMBER }}>
                  {r.glyph}
                </span>
                <span
                  className="flex-1 text-[12px]"
                  style={{ color: selected ? INK : "#3A3A38", fontWeight: selected ? 500 : 400 }}
                >
                  {r.label}
                </span>
                {r.hint && (
                  <span className="font-mono text-[9px] tracking-[0.06em] text-studio-ink-faint">
                    {r.hint}
                  </span>
                )}
              </div>
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
}

function KeyCap({ children }: { children: React.ReactNode }) {
  return (
    <span
      className="flex h-4 min-w-[16px] items-center justify-center rounded-[2px] px-1 font-mono text-[9px]"
      style={{
        background: CREAM,
        border: `0.5px solid ${EDGE}`,
        color: INK,
      }}
    >
      {children}
    </span>
  );
}

// Right-click → sectioned popover that mirrors AppNavigation.sidebarEntries.
function NavPopoverAnchored() {
  return (
    <div
      className="relative flex flex-col items-center gap-3 rounded-md py-7"
      style={{ background: CREAM, border: `0.5px solid ${EDGE}` }}
    >
      <TalkieButton state="navOpen" />
      <ConnectingBracket />
      <NavPopover />
      <div className="mt-2 font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
        · RIGHT-CLICK · sectioned nav
      </div>
    </div>
  );
}

const NAV_SECTIONS: { label: string; rows: { icon: string; label: string; badge?: string }[] }[] = [
  {
    label: "Primary",
    rows: [
      { icon: "⌂", label: "Home" },
      { icon: "▤", label: "Library", badge: "436" },
      { icon: "✎", label: "Compose" },
    ],
  },
  {
    label: "Activity",
    rows: [
      { icon: "◔", label: "Actions" },
      { icon: "◌", label: "Pending", badge: "3" },
    ],
  },
  {
    label: "Tools",
    rows: [
      { icon: "✦", label: "Learn" },
      { icon: "⚙︎", label: "Models" },
      { icon: "✺", label: "Workflows" },
      { icon: "▢", label: "Screenshots" },
      { icon: "⎘", label: "Console" },
    ],
  },
  {
    label: "Settings",
    rows: [
      { icon: "⚙︎", label: "Settings", badge: "⌘," },
    ],
  },
];

function NavPopover() {
  return (
    <div
      className="overflow-hidden rounded-md"
      style={{
        width: 260,
        background: CREAM,
        border: `0.5px solid ${EDGE}`,
        boxShadow: "0 12px 40px rgba(0,0,0,0.16), 0 4px 12px rgba(0,0,0,0.06)",
      }}
    >
      {NAV_SECTIONS.map((sec, si) => (
        <div key={si} className={si > 0 ? "border-t" : ""} style={{ borderColor: EDGE }}>
          <div
            className="px-3 pt-2 pb-1 font-mono text-[8px] uppercase tracking-[0.28em]"
            style={{ color: INK_FAINT }}
          >
            · {sec.label}
          </div>
          {sec.rows.map((r, ri) => (
            <div key={ri} className="flex items-center gap-2.5 px-3 py-1.5">
              <span className="font-mono text-[12px]" style={{ color: AMBER, width: 14, textAlign: "center" }}>
                {r.icon}
              </span>
              <span className="flex-1 text-[12px]" style={{ color: INK }}>
                {r.label}
              </span>
              {r.badge && (
                <span className="font-mono text-[9px] tracking-[0.06em] text-studio-ink-faint">
                  {r.badge}
                </span>
              )}
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

function ConnectingBracket() {
  return (
    <svg width="40" height="14" viewBox="0 0 40 14" aria-hidden>
      <path
        d="M 20 0 L 20 6 L 4 6 L 4 14 M 20 6 L 36 6 L 36 14"
        fill="none"
        stroke={EDGE}
        strokeWidth="0.5"
      />
      <circle cx="20" cy="0.5" r="1.5" fill={AMBER} />
    </svg>
  );
}

// ─── 3. Hover-reveal nav strip — INTERACTIVE ─────────────────────────
// Discoverability scaffolding: when the cursor enters the chrome row
// (button + strip area), a thin horizontal nav strip slides in below
// the window chrome showing the available sections. Move the cursor
// away → it retracts. Tap the button → palette still opens normally;
// the strip is parallel to (not a replacement for) the palette flow.
//
// This is intentionally NOT a state viewer. The whole point of the
// hover-reveal is the *moment* — the latency, the easing, the
// threshold at which the strip commits. Static frames hide all three.
// One live frame so the behavior is felt, not narrated.
//
// Hover region wraps the chrome row AND the strip itself so you can
// move the cursor down onto a section item without the strip dismissing.

// All sections — equal slots, equal treatment. Settings sits at the
// end of the row but doesn't get distinguished chrome (no divider, no
// trailing-edge anchoring). In a rhythmic horizontal grid, any visual
// special-casing breaks the cadence. Settings is just another slot.
const STRIP_SECTIONS: { icon: string; label: string; selected?: boolean }[] = [
  { icon: "⌂", label: "Home", selected: true },
  { icon: "▤", label: "Library" },
  { icon: "✎", label: "Compose" },
  { icon: "◔", label: "Actions" },
  { icon: "✦", label: "Learn" },
  { icon: "✺", label: "Workflows" },
  { icon: "⚙︎", label: "Settings" },
];

function HoverRevealStrip() {
  const [revealed, setRevealed] = React.useState(false);
  const [hoveredLabel, setHoveredLabel] = React.useState<string | null>(null);
  const width = 1100;

  return (
    <section>
      <SectionHeader
        eyebrow="· Three · Shape A"
        title="Hover-reveal nav strip — live"
        hint="hover the chrome row to reveal · move cursor onto a section to keep it open"
      />

      <div className="flex flex-col items-center gap-3" style={{ width }}>
        <div className="flex w-full items-baseline justify-between font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
          <span>· try it · cursor into the chrome row triggers reveal</span>
          <span>1100 · shape a · interactive</span>
        </div>

        <div
          className="overflow-hidden rounded-md"
          style={{
            width,
            background: CREAM,
            boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
            border: `0.5px solid ${EDGE}`,
          }}
        >
          {/* Hover region wraps chrome + strip together so the cursor
              can travel from the button down to a section item. */}
          <div
            onMouseEnter={() => setRevealed(true)}
            onMouseLeave={() => {
              setRevealed(false);
              setHoveredLabel(null);
            }}
          >
            <InteractiveChrome />
            <InteractiveStrip
              revealed={revealed}
              hoveredLabel={hoveredLabel}
              onHoverLabel={setHoveredLabel}
            />
          </div>

          <div style={{ width }}>
            <MacHome width={width} />
          </div>
        </div>

        <div className="mt-3 flex w-full items-baseline justify-between font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">
          <span>state · {revealed ? "revealed" : "idle"}{hoveredLabel ? ` · → ${hoveredLabel.toLowerCase()}` : ""}</span>
          <span>easing · 180ms · ease-out · 6pt rise · 0→1 opacity</span>
        </div>
      </div>
    </section>
  );
}

function InteractiveChrome() {
  return (
    <div
      className="relative flex cursor-pointer items-center gap-2 border-b px-4 py-2"
      style={{ borderColor: EDGE, background: PAPER }}
    >
      <div className="flex gap-1.5">
        <span className="h-3 w-3 rounded-full" style={{ background: EDGE }} />
        <span className="h-3 w-3 rounded-full" style={{ background: EDGE }} />
        <span className="h-3 w-3 rounded-full" style={{ background: EDGE }} />
      </div>

      <div className="mx-auto">
        <TalkieButton state="idle" />
      </div>

      <div className="invisible flex gap-1.5">
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
      </div>
    </div>
  );
}

// The strip lives in a height-collapsing container so the body content
// underneath shifts down when revealed (rather than the strip floating
// over content). 180ms transition on height + opacity + translateY for
// a single coherent reveal motion.
function InteractiveStrip({
  revealed,
  hoveredLabel,
  onHoverLabel,
}: {
  revealed: boolean;
  hoveredLabel: string | null;
  onHoverLabel: (label: string | null) => void;
}) {
  return (
    <div
      style={{
        background: "#F1F1F0",
        maxHeight: revealed ? 44 : 0,
        borderBottom: revealed ? `0.5px solid ${EDGE}` : "0.5px solid transparent",
        overflow: "hidden",
        transition: "max-height 180ms ease-out, border-color 180ms ease-out",
      }}
    >
      <div
        className="flex items-center justify-center gap-1 px-6 py-2"
        style={{
          opacity: revealed ? 1 : 0,
          transform: `translateY(${revealed ? 0 : -6}px)`,
          transition: "opacity 180ms ease-out, transform 180ms ease-out",
        }}
      >
        {STRIP_SECTIONS.map((s) => (
          <InteractiveStripItem
            key={s.label}
            item={s}
            hovered={hoveredLabel === s.label}
            onEnter={() => onHoverLabel(s.label)}
            onLeave={() => onHoverLabel(null)}
          />
        ))}
      </div>
    </div>
  );
}

// Each slot is a fixed 112px wide so the row reads as a rhythmic
// horizontal grid rather than a content-sized button cluster. Workflows
// is the widest label, so the slot is sized for it; shorter labels
// (Home, Learn) breathe inside the slot rather than huddle.
const STRIP_SLOT_WIDTH = 112;

function InteractiveStripItem({
  item,
  hovered,
  onEnter,
  onLeave,
}: {
  item: { icon: string; label: string; selected?: boolean };
  hovered: boolean;
  onEnter: () => void;
  onLeave: () => void;
}) {
  const active = item.selected || hovered;
  return (
    <button
      onMouseEnter={onEnter}
      onMouseLeave={onLeave}
      className="flex items-center justify-center gap-1.5 rounded-[3px] py-1"
      style={{
        width: STRIP_SLOT_WIDTH,
        background: hovered ? "#EAEAE9" : "transparent",
        color: active ? INK : "#5A554C",
        borderBottom: item.selected ? `1.5px solid ${AMBER}` : "1.5px solid transparent",
        transition: "background 120ms ease, color 120ms ease",
      }}
    >
      <span className="font-mono text-[11px]" style={{ color: active ? AMBER : "#A4A4A6" }}>
        {item.icon}
      </span>
      <span className="font-mono text-[9.5px] font-semibold uppercase tracking-[0.18em]">
        {item.label}
      </span>
    </button>
  );
}

// ─── 4. Variant A — No sidebar, button floats ────────────────────────

function VariantA() {
  return (
    <section>
      <SectionHeader
        eyebrow="· Four · A"
        title="Variant A — No sidebar"
        hint="full canvas reclaim · button floats top-leading"
      />
      <div className="flex flex-col items-center gap-12">
        {[820, 1180, 1440].map((w) => (
          <ReframedHomeFrame key={w} width={w} variant="floating" />
        ))}
      </div>
    </section>
  );
}

// ─── 5. Variant B — Minimized icon-rail + button ─────────────────────

function VariantB() {
  return (
    <section>
      <SectionHeader
        eyebrow="· Four · B"
        title="Variant B — Icon-rail sidebar"
        hint="button anchors a thin 52pt rail · keeps navigation context for surfaces that need it"
      />
      <div className="flex flex-col items-center gap-12">
        {[820, 1180, 1440].map((w) => (
          <ReframedHomeFrame key={w} width={w} variant="rail" />
        ))}
      </div>
    </section>
  );
}

// ─── Reframed Home frame ─────────────────────────────────────────────

function ReframedHomeFrame({
  width,
  variant,
}: {
  width: number;
  variant: "floating" | "rail";
}) {
  return (
    <div className="flex w-full flex-col items-center gap-3" style={{ width }}>
      {/* Width annotation */}
      <div className="flex w-full items-baseline justify-between font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
        <span>· {width} · {variant === "floating" ? "FLOATING" : "ICON-RAIL"}</span>
        <span>{variant === "floating" ? "no global nav · button is the entry point" : "52pt rail · button + icon nav"}</span>
      </div>

      {/* Window */}
      <div
        className="overflow-hidden rounded-md"
        style={{
          width,
          background: CREAM,
          boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
          border: `0.5px solid ${EDGE}`,
        }}
      >
        <WindowChrome variant={variant} />
        {variant === "floating" ? (
          <FloatingLayout width={width} />
        ) : (
          <RailLayout width={width} />
        )}
      </div>
    </div>
  );
}

// macOS chrome row. In Variant A the button lives in the chrome center
// (where the title would be), making the chrome itself the home of the
// button. In Variant B the button is at the top of the icon rail, so
// the chrome center is empty.
function WindowChrome({ variant }: { variant: "floating" | "rail" }) {
  return (
    <div
      className="flex items-center gap-2 border-b px-4 py-2"
      style={{ borderColor: EDGE, background: PAPER }}
    >
      <div className="flex gap-1.5">
        <span className="h-3 w-3 rounded-full" style={{ background: EDGE }} />
        <span className="h-3 w-3 rounded-full" style={{ background: EDGE }} />
        <span className="h-3 w-3 rounded-full" style={{ background: EDGE }} />
      </div>

      {variant === "floating" ? (
        <div className="mx-auto">
          <TalkieButton state="idle" />
        </div>
      ) : (
        <div className="mx-auto font-mono text-[9px] uppercase tracking-[0.20em] text-studio-ink-faint">
          Talkie · Home
        </div>
      )}

      <div className="invisible flex gap-1.5">
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
      </div>
    </div>
  );
}

function FloatingLayout({ width }: { width: number }) {
  return (
    <div style={{ width }}>
      <MacHome width={width} />
    </div>
  );
}

function RailLayout({ width }: { width: number }) {
  const RAIL = 52;
  return (
    <div className="flex" style={{ width }}>
      <IconRail selected="home" />
      <div style={{ width: width - RAIL, borderLeft: `0.5px solid ${EDGE}` }}>
        <MacHome width={width - RAIL} />
      </div>
    </div>
  );
}

