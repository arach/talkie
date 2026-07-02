"use client";

import { PhoneFrame } from "./PhoneFrame";
import { StatusBar } from "./primitives/StatusBar";
import { IOS_THEMES } from "@/lib/themes";

const midnight = IOS_THEMES.find((theme) => theme.key === "midnight")!;

type RecentSource = "dictation" | "typed";
type RowMode = "stretched" | "fixed";

const RECENT_ROWS: Array<{
  source: RecentSource;
  title: string;
  date: string;
}> = [
  { source: "dictation", title: "Memo Jun 15 · 1:26 PM", date: "Jun 15" },
  { source: "dictation", title: "Memo Jun 15 · 1:21 PM", date: "Jun 15" },
  { source: "dictation", title: "Memo Jun 7 · 12:06 PM", date: "Jun 7" },
  { source: "typed", title: "Untitled note", date: "Jun 4" },
  { source: "typed", title: "Memo May 30 · 6:39 PM...", date: "Jun 4" },
  { source: "dictation", title: "Memo Jun 4 · 11:05 AM", date: "Jun 4" },
  { source: "dictation", title: "Memo Jun 4 · 10:53 AM", date: "Jun 4" },
  { source: "dictation", title: "Memo May 30 · 6:39 PM", date: "May 30" },
  { source: "typed", title: "Go 5/30/26, 12:06 AM...", date: "May 30" },
  { source: "dictation", title: "Go 5/30/26, 12:06 AM", date: "May 30" },
];

export function HomeRecentsStudy() {
  return (
    <div className="flex flex-col gap-10">
      <div className="flex flex-wrap items-start gap-8">
        <Labeled
          label="Failure"
          caption="embedded disabled List stretches row 10"
          tone="muted"
        >
          <PhoneFrame theme={midnight}>
            <HomeRecentsScreen mode="stretched" />
          </PhoneFrame>
        </Labeled>

        <Labeled
          label="Fixed"
          caption="plain stack, 44pt rows, footer follows content"
          tone="accent"
        >
          <PhoneFrame theme={midnight}>
            <HomeRecentsScreen mode="fixed" />
          </PhoneFrame>
        </Labeled>
      </div>

      <ReviewNotes />
    </div>
  );
}

function Labeled({
  label,
  caption,
  tone,
  children,
}: {
  label: string;
  caption: string;
  tone: "accent" | "muted";
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-baseline gap-2 pl-1">
        <span
          className={`text-[11px] font-semibold uppercase tracking-eyebrow ${
            tone === "accent" ? "text-studio-amber" : "text-studio-ink"
          }`}
        >
          {label}
        </span>
        <span className="text-[11px] text-studio-ink-faint">{caption}</span>
      </div>
      {children}
    </div>
  );
}

function HomeRecentsScreen({ mode }: { mode: RowMode }) {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar time="2:11" />

      <main className="flex min-h-0 flex-1 flex-col px-3 pb-5 pt-1">
        <RecentCard mode={mode} />
        <ExploreStrip />
        <HomeControls />
      </main>
    </div>
  );
}

function RecentCard({ mode }: { mode: RowMode }) {
  return (
    <section className="min-h-0">
      <div className="flex items-center gap-2 px-1 pb-2">
        <span
          className="text-[10px] font-semibold uppercase"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.20em",
          }}
        >
          · Recent · 42
        </span>
        <span
          className="ml-auto text-[10px] font-semibold uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.18em",
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
            "var(--theme-card-shadow-strong, inset 0 0.5px 0 rgba(255,255,255,0.16))",
        }}
      >
        <div role="list">
          {RECENT_ROWS.map((row, index) => (
            <RecentStressRow
              key={`${row.title}-${index}`}
              row={row}
              divider={index > 0}
              mode={mode}
              isLast={index === RECENT_ROWS.length - 1}
            />
          ))}
        </div>
        <LoadMoreFooter />
      </div>
    </section>
  );
}

function RecentStressRow({
  row,
  divider,
  mode,
  isLast,
}: {
  row: (typeof RECENT_ROWS)[number];
  divider: boolean;
  mode: RowMode;
  isLast: boolean;
}) {
  const height = mode === "stretched" && isLast ? 146 : 44;

  return (
    <div
      role="listitem"
      className="relative flex items-start gap-2 px-3.5"
      style={{ height }}
    >
      {divider ? (
        <span
          aria-hidden
          className="absolute left-12 right-0 top-0 h-px"
          style={{ background: "var(--theme-edge-subtle)" }}
        />
      ) : null}

      <span
        aria-hidden
        className="mt-[14px] flex h-4 w-4 flex-none items-center justify-center"
        style={{ color: "var(--theme-ink-faint)" }}
      >
        <RecentGlyph source={row.source} />
      </span>

      <div className="mt-[11px] flex min-w-0 flex-1 items-baseline gap-2">
        <span
          className="min-w-0 flex-1 truncate text-[17px] leading-none"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-body)",
            fontWeight: 400,
          }}
        >
          {row.title}
        </span>
        <span
          className="flex-none text-[12px] tabular-nums"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {row.date}
        </span>
      </div>
    </div>
  );
}

function LoadMoreFooter() {
  return (
    <div
      className="relative flex h-[52px] items-center justify-center gap-2 text-[15px]"
      style={{
        color: "var(--theme-ink-muted)",
        fontFamily: "var(--theme-font-body)",
      }}
    >
      <span
        aria-hidden
        className="absolute left-12 right-0 top-0 h-px"
        style={{ background: "var(--theme-edge-subtle)" }}
      />
      <span
        aria-hidden
        className="text-[18px] leading-none"
        style={{ fontFamily: "var(--theme-font-mono)" }}
      >
        ↓
      </span>
      <span>Load 10 more</span>
    </div>
  );
}

function ExploreStrip() {
  const chips = [
    ["▦", "Deck"],
    ["▥", "Library"],
    ["⌘", "Workflows"],
    [">_", "Terminal"],
  ];

  return (
    <section className="mt-3">
      <div
        className="px-1 pb-2 text-[10px] font-semibold uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.30em",
        }}
      >
        · Explore
      </div>
      <div className="flex gap-2 overflow-hidden">
        {chips.map(([icon, label]) => (
          <div
            key={label}
            className="flex flex-none items-center gap-2 rounded-full px-3 py-2"
            style={{
              background: "var(--theme-paper)",
              border: "0.5px solid var(--theme-edge-faint)",
              color: "var(--theme-ink-muted)",
              boxShadow:
                "var(--theme-card-shadow-soft, inset 0 0.5px 0 rgba(255,255,255,0.10))",
            }}
          >
            <span
              className="text-[13px] leading-none"
              style={{ color: "var(--theme-ink)" }}
            >
              {icon}
            </span>
            <span
              className="text-[15px] leading-none"
              style={{ fontFamily: "var(--theme-font-body)" }}
            >
              {label}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

function HomeControls() {
  return (
    <div className="relative mt-auto flex items-end justify-center px-5 pt-6">
      <div
        className="absolute left-8 flex h-[54px] w-[54px] items-center justify-center rounded-full"
        style={{
          background: "var(--theme-paper)",
          border: "0.5px solid var(--theme-edge-faint)",
          color: "var(--theme-ink)",
        }}
      >
        <VoicePivotGlyph />
      </div>
      <div
        className="flex h-[76px] w-[76px] items-center justify-center rounded-full"
        style={{
          background: "var(--theme-ink)",
          color: "var(--theme-canvas)",
        }}
      >
        <MicGlyph />
      </div>
    </div>
  );
}

function ReviewNotes() {
  const notes: [string, string][] = [
    [
      "Root cause",
      "The tall row is layout slack from a disabled nested List, not a row-content problem.",
    ],
    [
      "Rule",
      "Home owns the scroll. The recent card should be a plain stack of fixed-height rows.",
    ],
    [
      "Acceptance",
      "Ten rows produce exactly ten 44pt row slots, then the load-more footer. No row absorbs leftover height.",
    ],
  ];

  return (
    <section className="max-w-3xl">
      <h2 className="mb-3 text-[11px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
        · Review
      </h2>
      <dl className="grid grid-cols-1 gap-x-8 gap-y-3 sm:grid-cols-3">
        {notes.map(([name, desc]) => (
          <div key={name} className="flex flex-col gap-1">
            <dt className="text-[12px] font-medium text-studio-ink">{name}</dt>
            <dd className="text-[12px] leading-snug text-studio-ink-muted">
              {desc}
            </dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function RecentGlyph({ source }: { source: RecentSource }) {
  if (source === "typed") {
    return (
      <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
        <rect
          x={1.7}
          y={4.2}
          width={12.6}
          height={7.6}
          rx={1.2}
          stroke="currentColor"
          strokeWidth={1}
        />
        <g stroke="currentColor" strokeLinecap="round" strokeWidth={0.8}>
          <line x1={4} y1={7} x2={4.2} y2={7} />
          <line x1={6.7} y1={7} x2={6.9} y2={7} />
          <line x1={9.4} y1={7} x2={9.6} y2={7} />
          <line x1={12} y1={7} x2={12.2} y2={7} />
          <line x1={4.5} y1={9.6} x2={11.5} y2={9.6} />
        </g>
      </svg>
    );
  }

  return (
    <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
      <g stroke="currentColor" strokeLinecap="round" strokeWidth={1.15}>
        <line x1={1.5} y1={8} x2={1.5} y2={8} />
        <line x1={3.5} y1={5.8} x2={3.5} y2={10.2} />
        <line x1={5.5} y1={2.8} x2={5.5} y2={13.2} />
        <line x1={7.5} y1={5} x2={7.5} y2={11} />
        <line x1={9.5} y1={2} x2={9.5} y2={14} />
        <line x1={11.5} y1={5.8} x2={11.5} y2={10.2} />
        <line x1={14.5} y1={8} x2={14.5} y2={8} />
      </g>
    </svg>
  );
}

function VoicePivotGlyph() {
  return (
    <svg viewBox="0 0 28 28" fill="none" className="h-7 w-7">
      <g stroke="currentColor" strokeLinecap="round" strokeWidth={1.8}>
        <path d="M 8 18.5 a 8 8 0 0 1 0 -9" />
        <path d="M 20 9.5 a 8 8 0 0 1 0 9" />
        <path d="M 11 16.5 a 4 4 0 0 1 0 -5" />
        <path d="M 17 11.5 a 4 4 0 0 1 0 5" />
        <circle cx={14} cy={14} r={1.9} />
      </g>
    </svg>
  );
}

function MicGlyph() {
  return (
    <svg viewBox="0 0 32 32" fill="none" className="h-10 w-10">
      <g stroke="currentColor" strokeLinecap="round" strokeWidth={2.2}>
        <rect x={11} y={4} width={10} height={17} rx={5} />
        <path d="M 7 15 a 9 9 0 0 0 18 0" />
        <path d="M 16 24 L 16 28" />
        <path d="M 11 28 L 21 28" />
      </g>
    </svg>
  );
}
