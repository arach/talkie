"use client";

/**
 * Library mock — recreated from 02-library-memos-scope-view.png +
 * 03-capture-list-items.png. Incorporates mira's critique:
 *  - variant leading icons by source (kills the all-mic column)
 *  - inline transcript preview line (doubles row info density)
 *  - hairline anchor above the search bar (un-maroons it)
 *
 * Pure theme component — reads --theme-* vars. Drop into a
 * <PhoneFrame> and it inherits the theme.
 */

import { StatusBar } from "./primitives/StatusBar";
import { NavBar, NavPill } from "./primitives/NavBar";
import { ChannelLabel } from "./primitives/ChannelLabel";
import { Chip } from "./primitives/Chip";
import { ListRow, type ListRowSource } from "./primitives/ListRow";

const ITEMS: Array<{
  source: ListRowSource;
  title: string;
  preview: string;
  meta: string;
}> = [
  {
    source: "dictation",
    title: "Meeting notes — product roadmap Q1",
    preview: "alex pushed back on the migration window, we settled on staging…",
    meta: "7:34 AM · 4:12 · 232 KB",
  },
  {
    source: "dictation",
    title: "Idea: offline-first sync architecture",
    preview: "what if the bridge cached the last 48h locally and reconciled on…",
    meta: "5:34 AM · 2:08 · 132 KB",
  },
  {
    source: "typed",
    title: "Quick thought on keyboard shortcuts",
    preview: "swap cmd-shift-3 to be the global capture, cmd-shift-4 stays scr…",
    meta: "3:34 AM · TEXT · 12 words",
  },
];

export function Library() {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />

      <NavBar
        left={<NavPill>Done</NavPill>}
        title="Library"
        right={
          <span
            className="inline-flex items-center justify-center rounded-full px-3 py-1 text-[12px] font-medium tabular-nums"
            style={{
              background: "var(--theme-paper)",
              color: "var(--theme-ink-faint)",
              boxShadow: "inset 0 0 0 0.5px var(--theme-edge-faint)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            3 / 3
          </span>
        }
      />

      {/* tab row */}
      <div
        className="flex items-center justify-center gap-1 px-4 py-2"
        style={{ background: "var(--theme-canvas)" }}
      >
        <Chip variant="tab" active glyph={<TabGlyph kind="wave" />}>
          Memos
        </Chip>
        <Chip variant="tab" glyph={<TabGlyph kind="key" />}>
          Dictations
        </Chip>
        <Chip variant="tab" glyph={<TabGlyph kind="tray" />}>
          Items
        </Chip>
      </div>

      {/* list */}
      <div
        className="mx-3 mt-1 flex-1 rounded-[10px] overflow-hidden"
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

        {/* fill the void with a section divider + empty-state hint
            (mira's #1) — replaces the previous huge white space. */}
        <div
          className="px-3 pt-4 pb-2"
          style={{ borderTop: "0.5px solid var(--theme-edge-subtle)" }}
        >
          <ChannelLabel tier="status">Earlier · this week</ChannelLabel>
        </div>
        <div className="flex flex-1 items-end justify-center px-3 pb-5">
          <span
            className="text-[10px]"
            style={{
              color: "var(--theme-ink-subtle)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            ·  ·  ·   nothing else clipped today
          </span>
        </div>
      </div>

      {/* anchored search */}
      <div
        className="px-3 pt-3 pb-4"
        style={{
          background: "var(--theme-canvas)",
          borderTop: "0.5px solid var(--theme-edge-faint)",
        }}
      >
        <div
          className="flex items-center gap-2 rounded-full px-3 py-2"
          style={{
            background: "var(--theme-paper)",
            border: "0.5px solid var(--theme-edge-faint)",
          }}
        >
          <SearchGlyph />
          <span
            className="text-[13px]"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-body)",
            }}
          >
            Search memos
          </span>
        </div>
      </div>
    </div>
  );
}

function TabGlyph({ kind }: { kind: "wave" | "key" | "tray" }) {
  if (kind === "wave") {
    return (
      <svg viewBox="0 0 16 16" fill="none" className="h-3 w-3">
        <g stroke="currentColor" strokeWidth={1} strokeLinecap="round">
          <line x1={3} y1={6} x2={3} y2={10} />
          <line x1={6} y1={3} x2={6} y2={13} />
          <line x1={9} y1={5} x2={9} y2={11} />
          <line x1={12} y1={2} x2={12} y2={14} />
        </g>
      </svg>
    );
  }
  if (kind === "key") {
    return (
      <svg viewBox="0 0 16 16" fill="none" className="h-3 w-3">
        <rect x={2} y={5} width={12} height={6} rx={1} stroke="currentColor" strokeWidth={0.9} />
      </svg>
    );
  }
  // tray
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-3 w-3">
      <path d="M 3 6 L 3 12 L 13 12 L 13 6 M 6 4 L 10 4" stroke="currentColor" strokeWidth={0.9} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function SearchGlyph() {
  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-3.5 w-3.5" style={{ color: "var(--theme-ink-faint)" }}>
      <circle cx={7} cy={7} r={4} stroke="currentColor" strokeWidth={1.1} />
      <line x1={10} y1={10} x2={13} y2={13} stroke="currentColor" strokeWidth={1.1} strokeLinecap="round" />
    </svg>
  );
}
