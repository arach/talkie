"use client";

/**
 * Mac Note Detail — the right-hand pane when a Note is selected in the
 * Library, or the standalone surface when you open a Note directly.
 *
 * Notes are intentional written content. The surface reads like an
 * opened page in a notebook — eyebrow / serif title / comfortable body
 * measure / attachment rail at the foot. NO audio readout, NO player
 * rail — those belong to Memos.
 *
 * Palette: PEARL (#F5F8FA pane) on FROST (#F9FBFC canvas). Cool, ghost-
 * paler than the warm cream family. Amber stays as the single accent
 * touch so it still reads as Talkie.
 *
 * Width-aware. At 1180 the layout is the studio default. At 1440+ the
 * pane breathes — wider gutter, wider margin column, body prose still
 * capped at a comfortable measure so reading rhythm doesn't break.
 */

import React from "react";

// Scope canon — source of truth at lib/scope-tokens.ts.
import { SCOPE } from "@/lib/scope-tokens";

const T = {
  page:        SCOPE.canvas,
  pane:        SCOPE.pane,
  chrome:      SCOPE.chrome,
  rail:        SCOPE.rail,
  ink:         SCOPE.ink,
  inkFaint:    SCOPE.inkFaint,
  inkFainter:  SCOPE.inkFainter,
  inkRule:     SCOPE.rule,
  inkRuleS:    SCOPE.ruleSubtle,
  edge:        SCOPE.edge,
  ruleSoft:    SCOPE.ruleSoft,
  amber:       SCOPE.amber,
  brass:       SCOPE.brass,
  noteTint:    SCOPE.noteTint,
  captureTint: SCOPE.captureTint,
  dictTint:    SCOPE.dictTint,
  memoTint:    SCOPE.memoTint,
};

// ─── Stub content ────────────────────────────────────────────────────

const NOTE = {
  sequence: "N-0042",
  channel: "CH-04 · NOTE",
  date: "Today",
  time: "3:42 PM",
  title: "Chrome bar consolidation — pill stays centered",
  byline: {
    words: 188,
    attachments: 3,
    edits: 4,
    created: "today · 3:42 PM",
  },
  paragraphs: [
    "Move the chrome bar Talkie pill to permanent center, add a hover-revealed nav strip, and surface Settings as a gear in the toolbar trailing slot. The pill must stay centered — that's the geometric anchor. Strip chips split 3+3 around it.",
    "The Talkie button anchors the chrome bar's geometric center. Any asymmetric split (3+4 / 4+3) drifts the pill off-center and breaks the feel. Symmetric only: 3+3, 4+4.",
    "Tap pill → voice command mode. Hover → reveal compose strip. Long-press → open Skills. Three gestures, one anchor.",
  ],
  attachments: [
    { kind: "screenshot", label: "scope-pill-hover.png", meta: "1280×412" },
    { kind: "screenshot", label: "chrome-strip-split.png", meta: "1280×412" },
    { kind: "voice", label: "design pass · pill anchoring", meta: "0:42" },
  ] as Attachment[],
  meta: [
    {
      title: "Provenance",
      rows: [
        { label: "created", value: "Today · 3:42 PM" },
        { label: "via", value: "Skills · /capture-thought" },
      ],
    },
    {
      title: "Tags",
      rows: [
        { label: "topic", value: "chrome-bar", accent: true },
        { label: "related", value: "Skills · NavRail" },
      ],
    },
  ] as MetaBlock[],
};

type Attachment =
  | { kind: "screenshot"; label: string; meta: string }
  | { kind: "voice"; label: string; meta: string }
  | { kind: "clip"; label: string; meta: string };

type MetaBlock = {
  title: string;
  rows: { label: string; value: string; accent?: boolean }[];
};

// ──────────────────────────────────────────────────────────────────────
// Composition root — width-aware.

export function MacNoteDetail({ width = 1180 }: { width?: number } = {}) {
  // Responsive proportions
  const gutter   = width < 1300 ? 200 : Math.min(260, Math.round(width * 0.16));
  const margin   = width < 1300 ? 220 : Math.min(300, Math.round(width * 0.18));
  const bodyPad  = width < 1300 ? 56  : Math.round(width * 0.06);
  // Comfortable prose measure — never let it exceed ~70ch / 720px.
  const proseMax = Math.min(720, width - gutter - margin - bodyPad * 2);

  return (
    <div className="flex flex-col items-center gap-3" style={{ width }}>
      <WidthEyebrow width={width} />
      <PaneFrame width={width}>
        <NoteDetailPane
          gutterWidth={gutter}
          marginWidth={margin}
          bodyPad={bodyPad}
          proseMax={proseMax}
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
      <span>{label === "External" ? "near-fullscreen · stress-test fills" : "PEARL on FROST · cool"}</span>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Pane frame — window chrome + library gutter + detail body.

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

// ──────────────────────────────────────────────────────────────────────
// Library list gutter — compressed hint of the list pane.

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
        { id: "N-0042", kind: "note", title: "Chrome bar consolidation", sel: true },
        { id: "M-0419", kind: "memo", title: "Hey, anything?", sel: false },
        { id: "C-0017", kind: "capture", title: "Bay variant compare — 9", sel: false },
        { id: "M-0418", kind: "dictation", title: "Status rail rethink", sel: false },
        { id: "N-0041", kind: "note", title: "Skills runner wrapper plan", sel: false },
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

function NoteDetailPane({
  gutterWidth,
  marginWidth,
  bodyPad,
  proseMax,
}: {
  gutterWidth: number;
  marginWidth: number;
  bodyPad: number;
  proseMax: number;
}) {
  return (
    <>
      <LibraryListGutter width={gutterWidth} />
      <div className="flex flex-1 flex-col" style={{ background: T.pane }}>
        <Toolbar bodyPad={bodyPad} />
        <div className="flex flex-1">
          <BodyColumn bodyPad={bodyPad} proseMax={proseMax} />
          <MarginColumn width={marginWidth} />
        </div>
        <AttachmentRail bodyPad={bodyPad} />
      </div>
    </>
  );
}

function Toolbar({ bodyPad }: { bodyPad: number }) {
  return (
    <div
      className="flex items-center gap-3 py-3"
      style={{
        borderBottom: `0.5px solid ${T.inkRuleS}`,
        paddingLeft: bodyPad,
        paddingRight: bodyPad,
        background: T.pane,
      }}
    >
      <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em]" style={{ color: T.noteTint }}>
        {NOTE.sequence}
      </span>
      <span className="font-mono text-[9px] uppercase tracking-[0.18em]" style={{ color: T.inkFaint }}>
        · {NOTE.channel}
      </span>
      <div className="ml-auto flex items-center gap-1.5 text-[9px] font-mono uppercase tracking-[0.16em]" style={{ color: T.inkFaint }}>
        <ToolButton label="Edit" />
        <ToolButton label="Star" />
        <ToolButton label="Pin" />
        <ToolButton label="Share" />
        <ToolButton label="Export" />
        <span className="mx-1 h-3 w-px" style={{ background: T.inkRule }} />
        <ToolButton label="⋯" />
      </div>
    </div>
  );
}

function ToolButton({ label }: { label: string }) {
  return (
    <button
      className="rounded-[2px] px-1.5 py-0.5"
      style={{ color: T.inkFainter }}
    >
      {label}
    </button>
  );
}

function BodyColumn({ bodyPad, proseMax }: { bodyPad: number; proseMax: number }) {
  return (
    <div className="flex-1" style={{ paddingLeft: bodyPad, paddingRight: bodyPad, paddingTop: 36, paddingBottom: 32 }}>
      {/* Eyebrow */}
      <div className="flex items-baseline gap-3 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
        <span>· {NOTE.channel}</span>
        <span className="flex-1 border-t" style={{ borderColor: T.inkRuleS }} />
        <span>{NOTE.date} · {NOTE.time}</span>
      </div>

      {/* Title — serif, sized for a note (smaller than memo titles) */}
      <h2 className="mt-3 font-display font-medium tracking-tight" style={{ fontSize: 26, lineHeight: 1.15, color: T.ink }}>
        {NOTE.title}
      </h2>

      {/* Byline */}
      <div className="mt-2 font-mono text-[10px] uppercase tracking-[0.16em]" style={{ color: T.inkFaint }}>
        {NOTE.byline.words} words · {NOTE.byline.attachments} attachments · {NOTE.byline.edits} edits · {NOTE.byline.created}
      </div>

      {/* Body — measure-capped */}
      <div className="relative mt-7" style={{ maxWidth: proseMax }}>
        <span
          aria-hidden
          className="absolute top-0 bottom-0"
          style={{ left: -18, width: 1, background: T.noteTint, opacity: 0.28 }}
        />
        {NOTE.paragraphs.map((p, i) => (
          <p
            key={i}
            className={
              i === 0
                ? "mb-3 font-display"
                : "mb-3"
            }
            style={
              i === 0
                ? { fontSize: 15.5, lineHeight: 1.6, color: T.ink }
                : { fontSize: 13.5, lineHeight: 1.7, color: T.ink }
            }
          >
            {p}
          </p>
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
        paddingLeft: 20,
        paddingRight: 32,
        paddingTop: 36,
        paddingBottom: 32,
        borderLeft: `0.5px solid ${T.inkRuleS}`,
        background: T.pane,
      }}
    >
      {NOTE.meta.map((block, i) => (
        <div key={block.title} className={i === 0 ? "" : "mt-6"}>
          <div className="font-mono text-[8.5px] font-semibold uppercase tracking-[0.28em]" style={{ color: T.inkFaint }}>
            · {block.title}
          </div>
          <div className="mt-2 flex flex-col gap-1.5">
            {block.rows.map((row) => (
              <div key={row.label} className="flex items-baseline justify-between gap-3">
                <span className="font-mono text-[9px] uppercase tracking-[0.14em]" style={{ color: T.inkFaint }}>
                  {row.label}
                </span>
                <span
                  className="font-mono text-[10px] tracking-[0.06em]"
                  style={{ color: row.accent ? T.brass : T.ink }}
                >
                  {row.value}
                </span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </aside>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Attachment rail — foot of the page. Replaces the memo's player rail.

function AttachmentRail({ bodyPad }: { bodyPad: number }) {
  return (
    <div
      className="flex items-stretch gap-3 py-4"
      style={{
        background: T.rail,
        borderTop: `0.5px solid ${T.inkRuleS}`,
        paddingLeft: bodyPad,
        paddingRight: bodyPad,
      }}
    >
      <div className="flex items-center gap-2">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.28em]" style={{ color: T.inkFaint }}>
          · ATTACHMENTS
        </span>
        <span className="font-mono text-[9px] tracking-[0.06em]" style={{ color: T.inkFaint }}>
          {NOTE.attachments.length}
        </span>
      </div>
      <div className="flex flex-1 items-center gap-2">
        {NOTE.attachments.map((a, i) => (
          <AttachmentChip key={i} attachment={a} />
        ))}
      </div>
      <button
        className="rounded-[2px] border px-2 py-1 font-mono text-[9px] font-semibold uppercase tracking-[0.22em]"
        style={{
          borderColor: T.inkRule,
          color: T.noteTint,
          background: "rgba(255,255,255,0.5)",
        }}
      >
        + ADD
      </button>
    </div>
  );
}

function AttachmentChip({ attachment }: { attachment: Attachment }) {
  const tint =
    attachment.kind === "screenshot" ? T.captureTint
    : attachment.kind === "voice" ? T.brass
    : "#7A7E84";
  const glyph =
    attachment.kind === "screenshot" ? "▢"
    : attachment.kind === "voice" ? "◉"
    : "▶";
  return (
    <div
      className="flex items-center gap-2 rounded-[3px] px-2 py-1.5"
      style={{
        border: `0.5px solid ${tint}44`,
        background: `${tint}11`,
        minWidth: 168,
      }}
    >
      <span className="font-mono text-[11px]" style={{ color: tint }}>
        {glyph}
      </span>
      <div className="flex flex-1 flex-col gap-0.5">
        <span className="truncate text-[11px]" style={{ color: T.ink }}>
          {attachment.label}
        </span>
        <span className="font-mono text-[8.5px] uppercase tracking-[0.16em]" style={{ color: T.inkFaint }}>
          {attachment.meta}
        </span>
      </div>
    </div>
  );
}

function Footnote() {
  return (
    <div
      className="font-mono text-[9px] uppercase tracking-[0.22em]"
      style={{ color: T.inkFaint, textAlign: "left", width: "100%" }}
    >
      · Note detail · text-first · attachments rail replaces player rail · PEARL on FROST
    </div>
  );
}
