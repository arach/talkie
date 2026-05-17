"use client";

/**
 * Home — Talkie's canonical home screen. Recreated from
 * `14-recording-capture-sheet.png` (the home behind the recording
 * sheet) but isolated as its own study.
 *
 * Composition (top → bottom):
 *  1. Status bar
 *  2. TALKIE wordmark header (subtle, centered)
 *  3. STATION card — eyebrow, headline ("5 signals on deck."),
 *     meta, LIVE · ACTION BUS dark inset tile (3 numerals)
 *  4. RECENT list — channel-label divider + 3 list rows + "ALL"
 *  5. Voice-pivot button bottom-left (the universal Talkie button —
 *     resting state by default; this study just demonstrates how
 *     Home looks at rest with the new chrome pattern)
 *
 * Reads --theme-* vars; drop into <PhoneFrame>.
 */

import { StatusBar } from "./primitives/StatusBar";
import { ChannelLabel } from "./primitives/ChannelLabel";
import { ListRow, type ListRowSource } from "./primitives/ListRow";

const ITEMS: Array<{
  source: ListRowSource;
  title: string;
  preview: string;
  meta: string;
}> = [
  {
    source: "dictation",
    title: "Scope dashboard design notes",
    preview: "the trace band should anchor to the bottom of the sheet…",
    meta: "9:34 AM · 1:08",
  },
  {
    source: "dictation",
    title: "Meeting notes — product roadmap",
    preview: "alex pushed back on the migration window, we settled on st…",
    meta: "7:34 AM · 4:12",
  },
  {
    source: "link",
    title: "Keyboard configurator reference",
    preview: "iOS custom keyboard extension — entitlement scoping notes…",
    meta: "6:34 AM · LINK",
  },
];

export function Home() {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />

      <HomeHeader />

      {/* STATION card */}
      <div className="px-3 pt-1">
        <StationCard />
      </div>

      {/* RECENT */}
      <div className="mx-3 mt-3 flex-1 overflow-hidden">
        <div className="flex items-center gap-2 pb-2">
          <ChannelLabel tier="eyebrow">Recent</ChannelLabel>
          <span
            className="rounded-full px-1.5 text-[10px] font-semibold"
            style={{
              color: "var(--theme-amber)",
              background: "var(--theme-amber-faint)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            5
          </span>
          <span
            className="ml-auto text-[10px] font-semibold uppercase tracking-[0.18em]"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            All
          </span>
        </div>
        <div
          className="overflow-hidden rounded-[10px]"
          style={{
            background: "var(--theme-paper)",
            border: "0.5px solid var(--theme-edge-faint)",
            boxShadow:
              "var(--theme-card-shadow-strong, inset 0 0.5px 0 rgba(255,255,255,0.20))",
          }}
        >
          {ITEMS.map((row, i) => (
            <ListRow
              key={row.title}
              source={row.source}
              title={row.title}
              preview={row.preview}
              meta={row.meta}
              divider={i > 0}
            />
          ))}
        </div>
      </div>

      {/* Ambient voice button (resting state — the universal Talkie
       *  button per /complications). Bottom-left, low-key. */}
      <AmbientVoiceButton />
    </div>
  );
}

function HomeHeader() {
  // Wordmark is MONO, not display — closer to the channel-label
  // vocabulary. Reads as an instrument label / brand tag rather
  // than a magazine title.
  return (
    <div className="flex items-center justify-between px-4 py-2">
      <span className="w-7" aria-hidden />
      <span
        className="text-[10px] font-semibold leading-none"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.32em",
        }}
      >
        TALKIE
      </span>
      <button
        aria-label="Settings"
        className="flex h-7 w-7 items-center justify-center rounded-full"
        style={{
          background: "var(--theme-paper)",
          color: "var(--theme-ink-faint)",
          border: "0.5px solid var(--theme-edge-faint)",
        }}
      >
        <svg viewBox="0 0 16 16" fill="none" className="h-3.5 w-3.5">
          <circle cx={8} cy={8} r={2} stroke="currentColor" strokeWidth={1} />
          <path
            d="M 8 1.5 L 8 3.5 M 8 12.5 L 8 14.5 M 1.5 8 L 3.5 8 M 12.5 8 L 14.5 8
               M 3.05 3.05 L 4.4 4.4 M 11.6 11.6 L 12.95 12.95
               M 3.05 12.95 L 4.4 11.6 M 11.6 4.4 L 12.95 3.05"
            stroke="currentColor"
            strokeWidth={1}
            strokeLinecap="round"
          />
        </svg>
      </button>
    </div>
  );
}

function StationCard() {
  // STATION is now a meaningful surface: "PICK UP" — the
  // document/capture the user was last in, with one-tap continue.
  // The Action Bus stays at the bottom as today's at-a-glance tally.
  // No repeated "5" anywhere; each number means something different.
  return (
    <div
      className="rounded-[12px]"
      style={{
        background: "var(--theme-paper)",
        border: "0.5px solid var(--theme-edge-faint)",
        boxShadow:
          "var(--theme-card-shadow-strong, inset 0 0.5px 0 rgba(255,255,255,0.45))",
        overflow: "hidden",
      }}
    >
      <div className="flex items-start gap-3 px-4 pt-3.5 pb-3.5">
        <div className="min-w-0 flex-1">
          <ChannelLabel tier="eyebrow">Pick up</ChannelLabel>
          <h2
            className="m-0 mt-1.5 truncate leading-tight"
            style={{
              color: "var(--theme-ink)",
              fontFamily: "var(--theme-font-display)",
              fontWeight: "var(--theme-display-weight, 500)",
              letterSpacing: "var(--theme-display-tracking, -0.018em)",
              fontSize: 22,
            }}
          >
            Conference Bio
          </h2>
          <p
            className="m-0 mt-1.5 text-[10px] font-semibold uppercase"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.18em",
            }}
          >
            Compose · 31 words · 4m ago
          </p>
        </div>
        <button
          aria-label="Continue"
          className="flex-none rounded-full px-3 py-1.5 text-[11px] font-semibold"
          style={{
            background: "var(--theme-amber)",
            color: "var(--theme-paper)",
            fontFamily: "var(--theme-font-body)",
            letterSpacing: "-0.005em",
          }}
        >
          Continue ›
        </button>
      </div>

      <ActionBus />
    </div>
  );
}

function ActionBus() {
  // Smart period — adapts based on signal. The mock shows "Last 24h"
  // because today might still be hour 1 with all zeros; the bus
  // auto-rolls to whichever window has activity (24h → 7d → 30d).
  // Background uses --theme-canvas-alt instead of --theme-screen-bg
  // so light themes get a light bus (no dark inset fighting cream/white)
  // and dark themes still feel instrument-y.
  return (
    <div
      className="relative overflow-hidden px-3 py-2.5"
      style={{
        background: "var(--theme-canvas-alt)",
        borderTop: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      <div
        className="flex items-center gap-1.5 pb-2 text-[8px] font-semibold uppercase"
        style={{
          color: "var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        <span
          aria-hidden
          className="h-[5px] w-[5px] rounded-full"
          style={{
            background: "var(--theme-amber)",
            animation: "bus-pulse 1.6s ease-in-out infinite",
          }}
        />
        Last 24h · 9 captures
        <span
          className="ml-auto inline-flex items-center gap-0.5"
          style={{ color: "var(--theme-ink-faint)" }}
        >
          Week ›
        </span>
      </div>
      <div className="grid grid-cols-3">
        {[
          { num: "6", lbl: "Memos" },
          { num: "1", lbl: "Type" },
          { num: "2", lbl: "Grab" },
        ].map((cell, i) => (
          <div
            key={cell.lbl}
            className="flex flex-col items-center justify-center gap-1 px-2"
            style={
              i < 2
                ? { borderRight: "0.5px solid var(--theme-edge-faint)" }
                : undefined
            }
          >
            <span
              className="leading-none tabular-nums"
              style={{
                color: "var(--theme-amber)",
                fontFamily: "var(--theme-font-display)",
                fontWeight: 500,
                fontSize: 24,
                letterSpacing: "-0.02em",
              }}
            >
              {cell.num}
            </span>
            <span
              className="text-[7.5px] font-semibold uppercase"
              style={{
                color: "var(--theme-ink-faint)",
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.24em",
              }}
            >
              {cell.lbl}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function AmbientVoiceButton() {
  return (
    <button
      aria-label="Summon chrome"
      style={{
        position: "absolute",
        bottom: 22,
        left: 20,
        width: 48,
        height: 48,
        borderRadius: "50%",
        background: "var(--theme-paper)",
        color: "var(--theme-ink-dim)",
        border: "0.5px solid var(--theme-edge-faint)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        boxShadow:
          "var(--theme-card-shadow-strong, 0 2px 6px rgba(0,0,0,0.10))",
        zIndex: 12,
      }}
    >
      <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
        <g stroke="currentColor" strokeWidth={1.1} strokeLinecap="round" fill="none">
          <path d="M 4 4 a 5 5 0 0 0 0 8" />
          <path d="M 12 4 a 5 5 0 0 1 0 8" />
          <path d="M 6 6 a 2.5 2.5 0 0 0 0 4" />
          <path d="M 10 6 a 2.5 2.5 0 0 1 0 4" />
        </g>
        <circle cx={8} cy={8} r={1.3} fill="currentColor" />
      </svg>
    </button>
  );
}
