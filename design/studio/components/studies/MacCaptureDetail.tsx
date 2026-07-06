"use client";

/**
 * Mac Capture Detail — image-first surface for a standalone screenshot.
 *
 * Captures are the low-ceremony bucket. "Capture = anything I grabbed
 * in passing. Note = intentional." A standalone screenshot with no
 * text lives here; the moment a caption, dictation, or typed
 * annotation lands, it promotes to a Note.
 *
 * Palette: PEARL (#F5F8FA pane) on FROST (#F9FBFC canvas), matching
 * MacNoteDetail. Cool tones — a screenshot reads better on a cool
 * neutral mat than warm cream.
 *
 * Composition:
 *   - Hero column: channel/date eyebrow, filename, derived caption, and screenshot,
 *     filling the available width up to a reasonable cap.
 *   - Margin column: actions, workflows, capture metadata, and Tray status.
 *   - Foot rail: dimensions + filesize + Reveal-in-Finder / Delete.
 *
 * Width-aware. At 1180 the image fills the body column; at 1440+ the
 * image gets significantly more real estate while metadata stays the
 * same size — that's the whole point of a wider canvas for an image.
 */

import React from "react";

// Scope canon — source of truth at lib/scope-tokens.ts.
import { SCOPE, SCOPE_MATS } from "@/lib/scope-tokens";

const T = {
  page:        SCOPE.canvas,
  pane:        SCOPE.pane,
  chrome:      SCOPE.chrome,
  rail:        SCOPE.rail,
  mat:         SCOPE.rail, // image mat — neutral photographic gray
  ink:         SCOPE.ink,
  inkFaint:    SCOPE.inkFaint,
  inkFainter:  SCOPE.inkFainter,
  inkRule:     SCOPE.rule,
  inkRuleS:    SCOPE.ruleSubtle,
  edge:        SCOPE.edge,
  ruleSoft:    SCOPE.ruleSoft,
  amber:       SCOPE.amber,
  brass:       SCOPE.brass,
  captureTint: SCOPE.captureTint,
  noteTint:    SCOPE.noteTint,
  dictTint:    SCOPE.dictTint,
  memoTint:    SCOPE.memoTint,
};

const CAPTURE = {
  sequence: "C-0017",
  channel: "CH-05 · CAPTURE",
  date: "Today",
  time: "9:51 AM",
  source: "Hyper+S · region",
  filename: "bay-scheme-compare-9up.png",
  dimensions: "1840 × 1124",
  fileSize: "284 KB",
  derived: "Bay variant comparison · 9 schemes ladder · chiffon → porcelain",
  actions: [
    { label: "Copy", icon: "⧉", primary: true },
    { label: "Export", icon: "⇩" },
    { label: "Markup", icon: "✎" },
    { label: "Open", icon: "↗" },
    { label: "Pin", icon: "⌖" },
    { label: "Share", icon: "⇧" },
  ],
  workflows: [
    { label: "Describe UI", icon: "▣", color: "#5B5BFF" },
  ],
  meta: [
    {
      title: "Capture",
      rows: [
        { label: "source", value: "Hyper+S\nregion", accent: true },
        { label: "captured", value: "Today\n9:51 AM" },
        { label: "size", value: "284 KB\n1840×1124" },
      ],
    },
    {
      title: "Tray",
      rows: [
        { label: "pinned", value: "no" },
        { label: "draining", value: "next\nrecording" },
      ],
    },
  ] as { title: string; rows: { label: string; value: string; accent?: boolean }[] }[],
};

// ──────────────────────────────────────────────────────────────────────
// Composition root — width-aware.

export function MacCaptureDetail({ width = 1180 }: { width?: number } = {}) {
  const gutter   = width < 1300 ? 200 : Math.min(260, Math.round(width * 0.16));
  const margin   = width < 1300 ? 220 : Math.min(300, Math.round(width * 0.18));
  const bodyPad  = width < 1300 ? 56  : Math.round(width * 0.06);

  return (
    <div className="flex flex-col items-center gap-3" style={{ width }}>
      <WidthEyebrow width={width} />
      <PaneFrame width={width}>
        <CaptureDetailPane
          gutterWidth={gutter}
          marginWidth={margin}
          bodyPad={bodyPad}
        />
      </PaneFrame>
      <Footnote />
    </div>
  );
}

function WidthEyebrow({ width }: { width: number }) {
  const label =
    width <= 900  ? "Compact"  :
    width <= 1200 ? "Default"  :
    width <= 1500 ? "Wide"     :
    "External";
  return (
    <div
      className="flex w-full items-baseline justify-between font-mono text-[9px] uppercase tracking-[0.22em]"
      style={{ color: T.inkFaint }}
    >
      <span>· {width} · {label}</span>
      <span>{label === "External" ? "image stretches · metadata stays fixed" : "PEARL on FROST · cool"}</span>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Pane frame

function PaneFrame({
  width,
  children,
}: {
  width: number;
  children: React.ReactNode;
}) {
  return (
    <div
      className="rounded-md overflow-hidden"
      style={{
        width,
        background: T.page,
        boxShadow: "0 10px 38px rgba(46,68,82,0.10), 0 2px 8px rgba(46,68,82,0.06)",
        border: `0.5px solid ${T.edge}`,
      }}
    >
      <WindowChrome />
      <div className="flex" style={{ minHeight: 780 }}>
        {children}
      </div>
    </div>
  );
}

function WindowChrome() {
  return (
    <div
      className="flex items-center gap-2 border-b px-4 py-2.5"
      style={{ borderColor: T.edge, background: T.chrome }}
    >
      <div className="flex gap-1.5">
        <span className="h-3 w-3 rounded-full" style={{ background: T.edge }} />
        <span className="h-3 w-3 rounded-full" style={{ background: T.edge }} />
        <span className="h-3 w-3 rounded-full" style={{ background: T.edge }} />
      </div>
      <div className="mx-auto font-mono text-[9px] uppercase tracking-[0.20em]" style={{ color: T.inkFaint }}>
        Talkie · Library
      </div>
      <div className="invisible flex gap-1.5">
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
      </div>
    </div>
  );
}

function LibraryListGutter({ width }: { width: number }) {
  return (
    <div
      style={{ width, background: T.page, borderRight: `0.5px solid ${T.ruleSoft}` }}
      className="flex flex-col"
    >
      <div
        className="flex items-center gap-2 px-3 py-2"
        style={{ borderBottom: `0.5px solid ${T.ruleSoft}`, background: T.chrome }}
      >
        <span className="font-mono text-[8px] uppercase tracking-[0.28em]" style={{ color: T.inkFaint }}>
          · TODAY
        </span>
        <span className="ml-auto font-mono text-[8px] tracking-[0.12em]" style={{ color: T.inkFaint }}>
          7
        </span>
      </div>
      {[
        { id: "M-0421", kind: "dictation", title: "Re-grounding the bay", sel: false },
        { id: "N-0042", kind: "note", title: "Chrome bar consolidation", sel: false },
        { id: "M-0419", kind: "memo", title: "Hey, anything?", sel: false },
        { id: "C-0017", kind: "capture", title: "Bay variant compare — 9", sel: true },
        { id: "M-0418", kind: "dictation", title: "Status rail rethink", sel: false },
        { id: "C-0016", kind: "capture", title: "Notch flicker trace", sel: false },
      ].map((r) => (
        <div
          key={r.id}
          className="flex items-center gap-2 px-3 py-1.5"
          style={{
            borderBottom: `0.5px solid ${T.ruleSoft}`,
            background: r.sel ? "#DCDCDB" : "transparent",
          }}
        >
          <span
            className="flex h-4 w-4 items-center justify-center rounded-full font-mono text-[8px] font-bold"
            style={{
              color: KIND_TINT[r.kind],
              background: `${KIND_TINT[r.kind]}1A`,
              border: `0.5px solid ${KIND_TINT[r.kind]}55`,
            }}
          >
            {KIND_LETTER[r.kind]}
          </span>
          <span
            className="truncate text-[11px]"
            style={{
              color: r.sel ? T.ink : T.inkFaint,
              fontWeight: r.sel ? 500 : 400,
            }}
          >
            {r.title}
          </span>
        </div>
      ))}
    </div>
  );
}

const KIND_LETTER: Record<string, string> = {
  dictation: "D", memo: "M", note: "N", capture: "C",
};
const KIND_TINT: Record<string, string> = {
  dictation: T.dictTint, memo: T.memoTint, note: T.noteTint, capture: T.captureTint,
};

// ──────────────────────────────────────────────────────────────────────
// Detail pane

function CaptureDetailPane({
  gutterWidth,
  marginWidth,
  bodyPad,
}: {
  gutterWidth: number;
  marginWidth: number;
  bodyPad: number;
}) {
  return (
    <>
      <LibraryListGutter width={gutterWidth} />
      <div className="flex flex-1 flex-col" style={{ background: T.pane }}>
        <div className="flex flex-1">
          <HeroColumn bodyPad={bodyPad} />
          <MarginColumn width={marginWidth} />
        </div>
        <CaptureFootRail bodyPad={bodyPad} />
      </div>
    </>
  );
}

function HeroColumn({ bodyPad }: { bodyPad: number }) {
  return (
    <div className="flex-1 flex flex-col" style={{ paddingLeft: bodyPad, paddingRight: bodyPad, paddingTop: 32, paddingBottom: 28 }}>
      {/* Eyebrow */}
      <div className="flex items-baseline gap-3 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
        <span>· {CAPTURE.channel}</span>
        <span className="flex-1 border-t" style={{ borderColor: T.inkRuleS }} />
        <span>{CAPTURE.date} · {CAPTURE.time}</span>
      </div>

      {/* Filename — mono, since it's a file artifact, not a written title */}
      <div className="mt-3 flex items-baseline gap-3">
        <span className="font-mono font-medium tracking-tight" style={{ fontSize: 18, color: T.ink }}>
          {CAPTURE.filename}
        </span>
        <span className="font-mono text-[10px] uppercase tracking-[0.16em]" style={{ color: T.inkFaint }}>
          {CAPTURE.dimensions} · {CAPTURE.fileSize}
        </span>
      </div>

      {/* Derived caption — italic, greyed, marked as synthesized */}
      <div className="mt-1.5 flex items-baseline gap-2">
        <span className="font-mono text-[8.5px] uppercase tracking-[0.28em]" style={{ color: T.inkFaint }}>
          · DERIVED
        </span>
        <span className="font-display italic" style={{ fontSize: 12.5, color: T.inkFaint }}>
          {CAPTURE.derived}
        </span>
      </div>

      {/* Hero — the image. Fills the body column. */}
      <div className="mt-5 flex-1 flex items-center justify-center">
        <CaptureHero />
      </div>

      {/* Promote-to-Note affordance — the most important action */}
      <div className="mt-5 flex items-center gap-3">
        <button
          className="flex items-center gap-2 rounded-[3px] px-3 py-1.5"
          style={{
            border: `0.5px solid ${T.amber}66`,
            background: "rgba(196,125,28,0.10)",
            color: T.brass,
          }}
        >
          <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em]">
            ＋ ADD CAPTION
          </span>
          <span className="font-display italic" style={{ fontSize: 11, color: "rgba(154,106,34,0.65)" }}>
            promotes to a note
          </span>
        </button>
        <span className="font-mono text-[9px] uppercase tracking-[0.18em]" style={{ color: T.inkFaint }}>
          ⌘N
        </span>
      </div>
    </div>
  );
}

// Static screenshot placeholder — cool checker mat with a 3×3 swatch
// grid on top to evoke "screenshot of bay variant comparison."
function CaptureHero() {
  return (
    <div
      className="relative flex items-center justify-center w-full"
      style={{
        aspectRatio: "1840 / 1124",
        background:
          `repeating-conic-gradient(${T.mat} 0deg 25%, #E8DFC8 25% 50%) 0 0 / 24px 24px`,
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 4,
        boxShadow: "0 12px 38px rgba(46,68,82,0.10), 0 2px 8px rgba(46,68,82,0.06)",
      }}
    >
      <div
        className="grid"
        style={{
          width: "92%",
          height: "86%",
          gridTemplateColumns: "repeat(3, 1fr)",
          gridTemplateRows: "repeat(3, 1fr)",
          gap: 14,
          padding: 20,
          background: T.page,
          border: `0.5px solid ${T.inkRuleS}`,
          borderRadius: 3,
        }}
      >
        {Object.values(SCOPE_MATS).map(({ hex: bg, name }, i) => (
          <div
            key={i}
            className="flex flex-col items-start justify-between"
            style={{
              background: bg,
              border: `0.5px solid ${T.inkRuleS}`,
              borderRadius: 2,
              padding: 12,
            }}
          >
            <span className="font-mono text-[8px] uppercase tracking-[0.20em]" style={{ color: T.inkFaint }}>
              SCHEME · {String(i + 1).padStart(2, "0")}
            </span>
            <span className="font-display" style={{ fontSize: 11, color: T.ink }}>
              {name}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function MarginColumn({ width }: { width: number }) {
  return (
    <aside
      style={{
        width,
        paddingLeft: 18,
        paddingRight: 24,
        paddingTop: 36,
        paddingBottom: 32,
        borderLeft: `0.5px solid ${T.inkRuleS}`,
        background: T.pane,
      }}
      className="flex flex-col gap-[22px]"
    >
      <RailSection title="Actions">
        {CAPTURE.actions.map((action) => (
          <RailActionRow key={action.label} action={action} />
        ))}
        <div className="my-1 h-px w-full" style={{ background: T.inkRuleS }} />
        <RailMoreRow label="More" />
      </RailSection>

      <RailSection title="Workflows">
        {CAPTURE.workflows.map((workflow) => (
          <WorkflowRow key={workflow.label} workflow={workflow} />
        ))}
      </RailSection>

      {CAPTURE.meta.map((block) => (
        <MetaBlock key={block.title} block={block} />
      ))}
    </aside>
  );
}

function RailSection({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-[5px]">
      <RailTitle>{title}</RailTitle>
      {children}
    </div>
  );
}

function RailTitle({ children }: { children: React.ReactNode }) {
  return (
    <div className="pb-[3px] font-mono text-[8.5px] font-semibold uppercase tracking-[0.28em]" style={{ color: T.inkFaint }}>
      · {children}
    </div>
  );
}

function RailActionRow({ action }: { action: (typeof CAPTURE.actions)[number] }) {
  return (
    <button
      className="flex min-h-7 w-full items-center gap-[9px] rounded px-2 py-[5px] text-left"
      style={{
        color: action.primary ? T.brass : T.inkFaint,
        background: action.primary ? "rgba(196,125,28,0.07)" : "transparent",
      }}
    >
      <span className="w-4 text-center text-[12px]">{action.icon}</span>
      <span className="truncate text-[12px]" style={{ fontWeight: action.primary ? 500 : 400 }}>
        {action.label}
      </span>
    </button>
  );
}

function RailMoreRow({ label }: { label: string }) {
  return (
    <button className="flex min-h-7 w-full items-center gap-[9px] rounded px-2 py-[5px] text-left" style={{ color: T.inkFaint }}>
      <span className="w-4 text-center text-[12px]">…</span>
      <span className="truncate text-[12px]">{label}</span>
    </button>
  );
}

function WorkflowRow({ workflow }: { workflow: (typeof CAPTURE.workflows)[number] }) {
  return (
    <button className="flex min-h-7 w-full items-center gap-[9px] rounded px-2 py-[5px] text-left" style={{ color: T.inkFaint }}>
      <span className="w-4 text-center text-[12px]" style={{ color: workflow.color }}>{workflow.icon}</span>
      <span className="truncate text-[12px] font-medium">{workflow.label}</span>
    </button>
  );
}

function MetaBlock({ block }: { block: (typeof CAPTURE.meta)[number] }) {
  return (
    <div>
      <RailTitle>{block.title}</RailTitle>
      <div className="mt-1 flex flex-col gap-2">
        {block.rows.map((row) => (
          <div key={row.label} className="grid items-start gap-2" style={{ gridTemplateColumns: "58px minmax(0, 1fr)" }}>
            <span className="font-mono text-[9px] uppercase tracking-[0.14em]" style={{ color: T.inkFaint }}>
              {row.label}
            </span>
            <span
              className="whitespace-pre-line text-right font-mono text-[10px] tracking-[0.06em]"
              style={{ color: row.accent ? T.captureTint : T.ink }}
            >
              {row.value}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function CaptureFootRail({ bodyPad }: { bodyPad: number }) {
  return (
    <div
      className="flex items-center gap-4 py-3"
      style={{
        background: T.rail,
        borderTop: `0.5px solid ${T.inkRuleS}`,
        paddingLeft: bodyPad,
        paddingRight: bodyPad,
      }}
    >
      <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
        · {CAPTURE.dimensions} · {CAPTURE.fileSize} · {CAPTURE.source}
      </span>
      <div className="ml-auto flex items-center gap-1.5 text-[9px] font-mono uppercase tracking-[0.22em]">
        <FootAction label="Reveal in Finder" tone={T.ink} />
        <span className="mx-1 h-3 w-px" style={{ background: T.inkRule }} />
        <FootAction label="Delete" tone={SCOPE.alertSoft} />
      </div>
    </div>
  );
}

function FootAction({ label, tone }: { label: string; tone: string }) {
  return (
    <button className="rounded-[2px] px-1.5 py-0.5 font-semibold" style={{ color: tone, opacity: 0.75 }}>
      {label}
    </button>
  );
}

function Footnote() {
  return (
    <div
      className="font-mono text-[9px] uppercase tracking-[0.22em]"
      style={{ color: T.inkFaint, textAlign: "left", width: "100%" }}
    >
      · Capture detail · image-first · derived caption promotes to Note · PEARL on FROST
    </div>
  );
}
