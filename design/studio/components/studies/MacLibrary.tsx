"use client";

/**
 * Mac Library — full window composition.
 *
 * The shipping Swift screen is `ScopeLibraryView.swift`. Layout:
 *   - Header band: title + count, filter pills, search.
 *   - Body: GeometryReader branches at 880px.
 *       - Compact (<880): list column only.
 *       - Split (≥880):  resizable list (default 520) + inspector pane.
 *   - Inspector pane: 200pt dark instrument "readout" bay on top, then
 *     the memo-detail body below, then a memo-specific footer rail.
 *   - Footer bar: total count + selection count.
 *
 * Studio responsibility: visualize the same composition at three widths
 * so the responsive transition is legible at a glance. The 820 stamp
 * sits below the 880 breakpoint and falls back to list-only. The 1180
 * and 1440 stamps stay in split mode but show the inspector breathing
 * differently — at 1440 there's enough room for an editorial transcript;
 * at 1180 it's compact.
 *
 * Fonts / colors mirror the Scope ladder used in MacMemoDetail and
 * MacHome — Newsreader display for editorial fall-lines, Inter for body,
 * JetBrains Mono for chrome. Brass amber `#9A6A22` is the single accent.
 */

import React from "react";

// ─── Stub content ────────────────────────────────────────────────────
// The list shows a mix of dictations, memos, notes, captures so the
// channel-letter and meta-line variation is visible.

type LibKind = "dictation" | "memo" | "note" | "capture";

const ROWS: {
  id: string;
  kind: LibKind;
  bucket: "TODAY" | "YESTERDAY" | "THIS WEEK";
  title: string;
  meta: string;
  time: string;
  selected?: boolean;
}[] = [
  { id: "M-0421", kind: "dictation",  bucket: "TODAY",     title: "Re-grounding the bay against the chiffon canvas",       meta: "iTerm2 · 6:14 · 412 words",        time: "10:58", selected: true },
  { id: "M-0420", kind: "dictation",  bucket: "TODAY",     title: "Okay, do you want to switch?",                          meta: "iTerm2 · 0:38 · 47 words",         time: "10:42" },
  { id: "M-0419", kind: "memo",       bucket: "TODAY",     title: "Hey, anything?",                                        meta: "Voice · 0:12 · 9 words",           time: "10:38" },
  { id: "M-0418", kind: "dictation",  bucket: "TODAY",     title: "And then maybe separately, the system status rail",     meta: "iTerm2 · 2:04 · 184 words",        time: "10:14" },
  { id: "M-0417", kind: "capture",    bucket: "TODAY",     title: "Bay variant comparison — 9 schemes",                    meta: "Hyper+S · 1280×757",               time: "9:51" },
  { id: "M-0416", kind: "dictation",  bucket: "TODAY",     title: "That sounds good. Let's do it.",                        meta: "iTerm2 · 0:24 · 31 words",         time: "9:34" },
  { id: "M-0415", kind: "note",       bucket: "YESTERDAY", title: "Shipped chiffon canonical for Scope theme",             meta: "Markdown · 142 words",             time: "Yesterday" },
  { id: "M-0414", kind: "dictation",  bucket: "YESTERDAY", title: "Awesome, any results?",                                 meta: "iTerm2 · 0:18 · 24 words",         time: "Yesterday" },
  { id: "M-0413", kind: "memo",       bucket: "THIS WEEK", title: "Walking through the bay before review",                 meta: "Voice · 4:32 · 287 words",         time: "Wed" },
  { id: "M-0412", kind: "dictation",  bucket: "THIS WEEK", title: "The compose surface still feels heavy",                 meta: "iTerm2 · 1:48 · 142 words",        time: "Wed" },
  { id: "M-0411", kind: "capture",    bucket: "THIS WEEK", title: "Dictation pipeline diagram",                            meta: "Hyper+S · 1840×1124",              time: "Tue" },
];

const FILTERS: { key: LibKind | "all"; label: string; count: number }[] = [
  { key: "all",        label: "All",        count: 436 },
  { key: "memo",       label: "Memos",      count: 18  },
  { key: "dictation",  label: "Dictations", count: 287 },
  { key: "note",       label: "Notes",      count: 86  },
  { key: "capture",    label: "Captures",   count: 45  },
];

// Mock transcript paragraphs for the inspector — reuses the same memo
// the row marked `selected` points to. Two paragraphs is enough to
// show rhythm without dominating the page.
const SELECTED_MEMO = {
  channel: "CH-02 · DICTATION",
  date: "Today",
  time: "10:58 AM",
  sequence: "M-0421",
  title: "Re-grounding the bay against the chiffon canvas",
  byline: "iTerm2 · 6:14 duration · 412 words · MacBook Pro · Parakeet v3",
  paragraphs: [
    "Okay, so the chiffon scheme is closer than I thought. The problem isn't the scheme, it's that I was reading the bay against the wrong floor. Once I dropped it onto the cream studio canvas instead of pure white, the brass amber stopped fighting and started reading like a real instrument bay.",
    "Next thing — the system status rail. Right now it follows the bay's scheme, which means when I'm in chiffon I get this very pale rail that reads as almost invisible. That might be correct, actually.",
  ],
};

// ─── Composition root ────────────────────────────────────────────────

export function MacLibrary({ width = 1180 }: { width?: number } = {}) {
  const compact = width < 880;
  // Mirror Swift's listColumnWidth AppStorage default (520) but clamp
  // to leave the inspector ≥ 360 at the studio's minimum split width.
  const listWidth = compact ? width : Math.max(440, Math.min(560, width - 720));

  return (
    <div style={{ width, background: "#FBFBFA" }}>
      <HeaderBand width={width} />
      <div className="flex" style={{ minHeight: compact ? 540 : 720 }}>
        <ListColumn width={compact ? width : listWidth} />
        {!compact && (
          <>
            <DividerHandle />
            <Inspector width={width - listWidth - 6} />
          </>
        )}
      </div>
      <FooterBar compact={compact} />
    </div>
  );
}

// ─── Header band ─────────────────────────────────────────────────────

function HeaderBand({ width }: { width: number }) {
  const padX = width < 900 ? 18 : width >= 1300 ? 28 : 22;
  return (
    <div style={{ borderBottom: "0.5px solid #E0DCD3", background: "#F4F1EA" }}>
      <div style={{ paddingLeft: padX, paddingRight: padX, paddingTop: 14, paddingBottom: 10 }}>
        {/* Title row */}
        <div className="flex items-baseline gap-3">
          <div className="font-display text-[20px] font-medium tracking-tight text-studio-ink">
            Library
          </div>
          <div className="text-[9px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
            · 436 captures · 7 days
          </div>
          <div className="ml-auto flex items-center gap-2 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
            <span>· NEWEST FIRST</span>
            <span className="opacity-50">|</span>
            <span className="text-[#9A6A22]">REC</span>
          </div>
        </div>

        {/* Filter pills */}
        <div className="mt-3 flex items-center gap-1.5">
          {FILTERS.map((f, i) => (
            <FilterPill key={f.key} filter={f} active={i === 0} />
          ))}
        </div>

        {/* Search */}
        <div className="mt-2.5">
          <div
            className="flex items-center gap-2 rounded-[3px] px-2.5 py-1.5"
            style={{ border: "0.5px solid #E0DCD3", background: "#FFFFFF" }}
          >
            <span className="font-mono text-[10px] text-studio-ink-faint">⌕</span>
            <span className="text-[11px] text-studio-ink-faint">Search title, transcript, or channel…</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function FilterPill({
  filter,
  active,
}: {
  filter: (typeof FILTERS)[number];
  active: boolean;
}) {
  return (
    <button
      className="flex items-baseline gap-1.5 rounded-[3px] px-2 py-1"
      style={{
        border: `0.5px solid ${active ? "#2A2620" : "transparent"}`,
        background: active ? "#FFFFFF" : "transparent",
        color: active ? "#2A2620" : "#7A746C",
      }}
    >
      <span className="text-[10px] font-semibold uppercase tracking-[0.18em]">
        {filter.label}
      </span>
      <span
        className="font-mono text-[9px] tracking-[0.06em]"
        style={{ color: active ? "#9A6A22" : "#A8A29E" }}
      >
        {filter.count}
      </span>
      {active && (
        <span
          aria-hidden
          className="ml-0.5 h-1.5 w-1.5 rounded-full"
          style={{ background: "#E89A3C" }}
        />
      )}
    </button>
  );
}

// ─── List column ─────────────────────────────────────────────────────

function ListColumn({ width }: { width: number }) {
  // Group rows by bucket so date headers can be inserted in flow.
  const buckets = Array.from(new Set(ROWS.map((r) => r.bucket)));
  return (
    <div
      style={{ width, background: "#FBFBFA", borderRight: "0.5px solid #E0DCD3" }}
      className="flex flex-col"
    >
      {buckets.map((b) => (
        <React.Fragment key={b}>
          <BucketHeader label={b} count={ROWS.filter((r) => r.bucket === b).length} />
          {ROWS.filter((r) => r.bucket === b).map((r) => (
            <LibraryRow key={r.id} row={r} />
          ))}
        </React.Fragment>
      ))}
    </div>
  );
}

function BucketHeader({ label, count }: { label: string; count: number }) {
  return (
    <div
      className="flex items-center gap-2 px-4 py-2"
      style={{ borderBottom: "0.5px solid #E0DCD3", background: "#F8F5EC" }}
    >
      <span className="font-mono text-[8px] uppercase tracking-[0.28em] text-studio-ink-faint">
        · {label}
      </span>
      <span className="ml-auto font-mono text-[8px] tracking-[0.12em] text-studio-ink-faint">
        {count}
      </span>
    </div>
  );
}

const KIND_GLYPH: Record<LibKind, { letter: string; tint: string }> = {
  dictation: { letter: "D", tint: "#E89A3C" },
  memo:      { letter: "M", tint: "#9A6A22" },
  note:      { letter: "N", tint: "#6B7A75" },
  capture:   { letter: "C", tint: "#5A7A86" },
};

function LibraryRow({ row }: { row: (typeof ROWS)[number] }) {
  const glyph = KIND_GLYPH[row.kind];
  return (
    <div
      className="flex items-center gap-3 px-4 py-2.5"
      style={{
        borderBottom: "0.5px solid #ECE7DD",
        background: row.selected ? "#F2EFE6" : "transparent",
      }}
    >
      {/* Channel letter */}
      <div
        className="flex h-6 w-6 items-center justify-center rounded-full font-mono text-[9px] font-bold"
        style={{
          color: glyph.tint,
          background: `${glyph.tint}14`,
          border: `0.5px solid ${glyph.tint}55`,
        }}
        title={row.kind}
      >
        {glyph.letter}
      </div>

      {/* Title + meta */}
      <div className="flex flex-1 min-w-0 flex-col gap-0.5">
        <div
          className="truncate text-[12.5px]"
          style={{
            color: row.selected ? "#2A2620" : "#3F3A33",
            fontWeight: row.selected ? 500 : 400,
          }}
        >
          {row.title}
        </div>
        <div className="truncate font-mono text-[9px] uppercase tracking-[0.14em] text-studio-ink-faint">
          {row.meta}
        </div>
      </div>

      {/* Trailing meta */}
      <div className="flex w-[72px] flex-col items-end gap-1">
        <span className="font-mono text-[9px] tracking-[0.06em] text-studio-ink-faint">
          {row.time}
        </span>
        {row.kind === "memo" || row.kind === "dictation" ? (
          <MiniWave selected={!!row.selected} />
        ) : (
          <span className="h-[10px] w-[56px]" />
        )}
      </div>
    </div>
  );
}

// Tiny static sparkline — three-bar amplitude strip. The selected row
// gets the amber stroke; everyone else gets the faded ink.
function MiniWave({ selected }: { selected: boolean }) {
  const peaks = [3, 6, 9, 5, 8, 4, 7, 3, 6, 8, 5, 7, 4, 6, 3, 5];
  const stroke = selected ? "#9A6A22" : "#A8A29E";
  return (
    <svg width="56" height="10" viewBox="0 0 56 10" aria-hidden>
      {peaks.map((p, i) => (
        <rect
          key={i}
          x={i * 3.5}
          y={(10 - p) / 2}
          width={2}
          height={p}
          fill={stroke}
          opacity={selected ? 0.8 : 0.5}
        />
      ))}
    </svg>
  );
}

// ─── Divider ────────────────────────────────────────────────────────

function DividerHandle() {
  return (
    <div
      className="relative flex items-stretch"
      style={{ width: 6, background: "#FBFBFA" }}
    >
      <span
        aria-hidden
        className="my-auto block h-8 w-px"
        style={{ background: "#E0DCD3" }}
      />
    </div>
  );
}

// ─── Inspector ──────────────────────────────────────────────────────

function Inspector({ width }: { width: number }) {
  const padX = width < 600 ? 22 : 32;
  return (
    <div
      style={{
        width,
        background: "linear-gradient(180deg, #FAF7EF 0%, #FAF6EB 60%, #F7F2E5 100%)",
      }}
      className="flex flex-col"
    >
      <ReadoutPanel />
      <InspectorMasthead padX={padX} />
      <InspectorBody padX={padX} />
      <InspectorPlayerRail padX={padX} />
    </div>
  );
}

// 200pt dark instrument bay — top of the inspector. Picks the
// "phasePlot" variant from the Swift readoutBodyVariant choices since
// it's the most visually distinctive of the three.
function ReadoutPanel() {
  return (
    <div className="m-4 mb-3 overflow-hidden rounded-[8px]" style={{
      background: "#0E1518",
      border: "1px solid #1A2326",
      boxShadow: "0 6px 22px rgba(0,0,0,0.22)",
    }}>
      {/* Top chrome strip */}
      <div
        className="flex items-center gap-2 px-3 py-1.5"
        style={{ background: "#15191E", borderBottom: "1px solid #1A2326" }}
      >
        <span aria-hidden className="h-1.5 w-1.5 rounded-full" style={{ background: "#5FE3C9", boxShadow: "0 0 6px #5FE3C988" }} />
        <span className="font-mono text-[8px] uppercase tracking-[0.28em]" style={{ color: "#5FE3C9" }}>
          · READOUT · PHASE
        </span>
        <span className="ml-auto font-mono text-[8px] uppercase tracking-[0.22em]" style={{ color: "#5FE3C988" }}>
          M-0421 · LIVE
        </span>
      </div>

      {/* Body — static Lissajous mock */}
      <div className="relative flex h-[140px] items-center justify-center">
        <svg width="100%" height="100%" viewBox="0 0 400 140" preserveAspectRatio="none" aria-hidden>
          {/* graticule */}
          {[1, 2, 3].map((i) => (
            <line key={`gh-${i}`} x1={0} x2={400} y1={(140 / 4) * i} y2={(140 / 4) * i} stroke="#5FE3C9" strokeOpacity="0.08" />
          ))}
          {[1, 2, 3, 4, 5, 6, 7].map((i) => (
            <line key={`gv-${i}`} x1={(400 / 8) * i} x2={(400 / 8) * i} y1={0} y2={140} stroke="#5FE3C9" strokeOpacity="0.08" />
          ))}
          {/* phase trace */}
          <path
            d="M 40 70 C 80 20, 160 120, 200 70 S 320 20, 360 70"
            stroke="#5FE3C9"
            strokeWidth="1.4"
            fill="none"
            opacity="0.85"
          />
          <path
            d="M 40 70 C 80 120, 160 20, 200 70 S 320 120, 360 70"
            stroke="#5FE3C9"
            strokeWidth="1.4"
            fill="none"
            opacity="0.55"
          />
        </svg>
        {/* corner readout */}
        <div className="absolute left-3 top-2 font-mono text-[8px] uppercase tracking-[0.20em]" style={{ color: "#5FE3C988" }}>
          PEAK 0.74 · AVG 0.31
        </div>
        <div className="absolute right-3 bottom-2 font-mono text-[8px] uppercase tracking-[0.20em]" style={{ color: "#5FE3C988" }}>
          6:14 · 412W
        </div>
      </div>

      {/* Bottom chrome strip */}
      <div
        className="flex items-center gap-2 px-3 py-1.5"
        style={{ background: "#15191E", borderTop: "1px solid #1A2326" }}
      >
        <span className="font-mono text-[8px] uppercase tracking-[0.28em]" style={{ color: "#5FE3C988" }}>
          · CH-02 · INSTRUMENT
        </span>
        <span className="ml-auto font-mono text-[8px] uppercase tracking-[0.22em]" style={{ color: "#5FE3C988" }}>
          10:58 · TODAY
        </span>
      </div>
    </div>
  );
}

function InspectorMasthead({ padX }: { padX: number }) {
  return (
    <div style={{ paddingLeft: padX, paddingRight: padX, paddingTop: 8, paddingBottom: 12 }}>
      {/* Toolbar slug — sequence + tools */}
      <div className="flex items-center gap-3 pb-3" style={{ borderBottom: "0.5px solid rgba(26,22,18,0.10)" }}>
        <span className="font-mono text-[9px] uppercase tracking-[0.22em] text-[#9A6A22]">
          {SELECTED_MEMO.sequence}
        </span>
        <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          · {SELECTED_MEMO.channel}
        </span>
        <div className="ml-auto flex items-center gap-1.5 text-[9px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
          <ToolButton label="Star" />
          <ToolButton label="Pin" />
          <ToolButton label="Share" />
          <ToolButton label="Export" />
          <span className="mx-1 h-3 w-px" style={{ background: "rgba(26,22,18,0.16)" }} />
          <ToolButton label="⋯" />
        </div>
      </div>

      {/* Eyebrow line */}
      <div className="mt-4 flex items-baseline gap-3 font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
        <span>· {SELECTED_MEMO.channel}</span>
        <span className="flex-1 border-t border-studio-edge/60" />
        <span>{SELECTED_MEMO.date} · {SELECTED_MEMO.time}</span>
      </div>

      {/* Serif headline */}
      <h2 className="mt-2 font-display text-[24px] font-medium leading-[1.15] tracking-tight text-studio-ink">
        {SELECTED_MEMO.title}
      </h2>

      {/* Byline */}
      <div className="mt-2 font-mono text-[10px] uppercase tracking-[0.16em] text-studio-ink-faint">
        {SELECTED_MEMO.byline}
      </div>
    </div>
  );
}

function ToolButton({ label }: { label: string }) {
  return (
    <button className="rounded-[2px] px-1.5 py-0.5 hover:text-studio-ink" style={{ color: "rgba(26,22,18,0.45)" }}>
      {label}
    </button>
  );
}

function InspectorBody({ padX }: { padX: number }) {
  return (
    <div className="relative flex-1" style={{ paddingLeft: padX, paddingRight: padX, paddingTop: 4, paddingBottom: 20 }}>
      {/* Marginal rule */}
      <span
        aria-hidden
        className="absolute top-0 bottom-0"
        style={{ left: padX - 10, width: 1, background: "#C47D1C", opacity: 0.32 }}
      />
      {SELECTED_MEMO.paragraphs.map((p, i) => (
        <p
          key={i}
          className={
            i === 0
              ? "mb-3 font-display text-[15px] leading-[1.55] text-studio-ink"
              : "mb-2.5 text-[13px] leading-[1.7] text-studio-ink"
          }
        >
          {i === 0 && (
            <span className="mr-2 font-mono text-[9px] uppercase tracking-[0.22em] text-[#9A6A22]">
              0:00 ·
            </span>
          )}
          {p}
        </p>
      ))}
    </div>
  );
}

function InspectorPlayerRail({ padX }: { padX: number }) {
  return (
    <div
      style={{
        paddingLeft: padX,
        paddingRight: padX,
        paddingTop: 10,
        paddingBottom: 12,
        background: "#F2EDDE",
        borderTop: "0.5px solid rgba(26,22,18,0.10)",
      }}
      className="flex items-center gap-3"
    >
      <button
        className="flex h-7 w-7 items-center justify-center rounded-full text-[12px]"
        style={{ background: "#C47D1C", color: "#FBFBFA", boxShadow: "0 0 0 2px rgba(196,125,28,0.18)" }}
      >
        ▶
      </button>
      <div className="flex-1">
        <PlayerWave />
      </div>
      <span className="font-mono text-[10px] tracking-[0.06em] text-studio-ink">
        2:14 / 6:14
      </span>
    </div>
  );
}

function PlayerWave() {
  const peaks = [4, 6, 9, 12, 8, 14, 11, 7, 5, 9, 13, 16, 12, 10, 15, 18, 14, 11, 8, 6, 10, 13, 9, 7, 11, 14, 17, 13, 10, 8, 12, 15, 11, 9, 6, 8, 11, 14, 10, 7];
  const PLAYED = 14;
  return (
    <svg width="100%" height="22" viewBox={`0 0 ${peaks.length * 4} 22`} preserveAspectRatio="none" aria-hidden>
      {peaks.map((p, i) => (
        <rect
          key={i}
          x={i * 4}
          y={(22 - p) / 2}
          width={2.5}
          height={p}
          fill={i < PLAYED ? "#C47D1C" : "#C8C2B6"}
          opacity={i < PLAYED ? 0.9 : 0.55}
        />
      ))}
    </svg>
  );
}

// ─── Footer bar ─────────────────────────────────────────────────────

function FooterBar({ compact }: { compact: boolean }) {
  return (
    <div
      className="flex items-center gap-3 px-4 py-2"
      style={{ borderTop: "0.5px solid #E0DCD3", background: "#F4F1EA" }}
    >
      <span className="font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
        · 436 captures · 11 visible
      </span>
      <span className="ml-auto font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
        {compact ? "· LIST · LIST-ONLY MODE" : "· SPLIT · INSPECTOR LIVE"}
      </span>
    </div>
  );
}
