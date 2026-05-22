"use client";

import React from "react";
import { StudioPage } from "@/components/StudioPage";

/**
 * Mac Talkie — Notes as a distinct surface.
 *
 * Today Notes is just a Library filter (`ScopeLibraryView(initialTypeFilter:
 * .notes)`). The question this study asks: does Notes deserve its own
 * composition, distinct from Memos (audio-first) and Dictations (text-
 * first via voice)?
 *
 * Notes per project memory:
 *   - Content-first. Screenshots, typed text, voice snippets.
 *   - Audio is optional / attachment.
 *   - Tray items (Hyper+S captures) can become Notes when promoted.
 *
 * Two compositions for comparison:
 *
 *   I.  Commonplace book — single-column editorial entries grouped by
 *       day. Each entry gets its own full-width composition: eyebrow
 *       (date / time / attachments) → title in serif → body excerpt →
 *       attachment row → meta footer. Reads as pages from a journal.
 *
 *   II. Sheaf — two-column grid of compact note cards. Each card has
 *       the same elements but in tighter form. Reads as a wall of
 *       scraps. Denser, faster to scan.
 */

const CREAM       = "#F8F8F7";
const PAPER       = "#E7E7E6";
const INK         = "#232423";
const INK_FAINT   = "rgba(35,36,35,0.55)";
const INK_FAINTER = "rgba(35,36,35,0.32)";
const INK_RULE    = "rgba(35,36,35,0.16)";
const INK_RULE_S  = "rgba(35,36,35,0.10)";
const AMBER       = "#C47D1C";
const BRASS       = "#9A6A22";

// ─── Stub notes ──────────────────────────────────────────────────────

type Attachment =
  | { kind: "voice"; duration: string }
  | { kind: "screenshot"; label: string }
  | { kind: "clip"; duration: string };

type Note = {
  id: string;
  date: string;       // group bucket — "Mon 19 May"
  time: string;       // "3:42 PM"
  title: string;
  body: string;
  attachments?: Attachment[];
  wordCount?: number;
};

const NOTES: Note[] = [
  {
    id: "n1",
    date: "Mon 19 May",
    time: "3:42 PM",
    title: "Chrome bar consolidation",
    body: "Move the chrome bar Talkie pill to permanent center, add a hover-revealed nav strip, and surface Settings as a gear in the toolbar trailing slot. The pill must stay centered — that's the geometric anchor. Strip chips split 3+3 around it.",
    attachments: [
      { kind: "voice", duration: "0:42" },
      { kind: "screenshot", label: "scope-pill-hover.png" },
    ],
    wordCount: 88,
  },
  {
    id: "n2",
    date: "Mon 19 May",
    time: "11:58 AM",
    title: "Notch flicker — sequence counter",
    body: "After transcription completes, notch briefly flickers back into processing state before settling to idle. Root cause: notification-polling race between DistributedNotifications and 60Hz mmap polling. Fix options: dedup via sequence counter, or guard handlers to skip if state already past notification's phase.",
    attachments: [{ kind: "screenshot", label: "notch-flicker-trace.png" }],
    wordCount: 168,
  },
  {
    id: "n3",
    date: "Mon 19 May",
    time: "10:22 AM",
    title: "Mast tooling diff plan",
    body: "Token export → swift-hints annotations → spec overlay. Three pieces of plumbing that let studio mocks carry forward into Swift without losing fidelity. The token export goes first — names match SwiftUI without translation.",
    wordCount: 184,
  },
  {
    id: "n4",
    date: "Fri 16 May",
    time: "2:10 PM",
    title: "Memo as document, not dashboard",
    body: "Content-detail surfaces should default to editorial \"document on a desk\" framing — eyebrow + serif headline + mono byline — not dashboard chrome with KPI tiles. The memo IS the document; chrome around it should serve the document, not the other way around.",
    attachments: [
      { kind: "voice", duration: "1:53" },
      { kind: "screenshot", label: "memo-detail-doc.png" },
      { kind: "screenshot", label: "memo-detail-dash.png" },
    ],
    wordCount: 312,
  },
  {
    id: "n5",
    date: "Fri 16 May",
    time: "9:15 AM",
    title: "Tray drag pattern — onDrag wins",
    body: ".onDrag { NSItemProvider } is the canonical SwiftUI drag-out. NSDraggingSource doesn't work inside NSHostingController panels. Confirmed via TrayDrawer.swift.",
    wordCount: 24,
  },
  {
    id: "n6",
    date: "Thu 15 May",
    time: "4:48 PM",
    title: "Studio → native handoff",
    body: "Greenlit: token export, swift-hint annotations, spec overlay. Rejected: animation curve mapping. Start with token export — names should match SwiftUI exactly so the port is a copy-paste, not a translation.",
    attachments: [{ kind: "clip", duration: "0:12" }],
    wordCount: 38,
  },
];

// Group notes by date for the commonplace variant.
function groupByDate(notes: Note[]): { date: string; items: Note[] }[] {
  const map = new Map<string, Note[]>();
  for (const n of notes) {
    const arr = map.get(n.date) ?? [];
    arr.push(n);
    map.set(n.date, arr);
  }
  return Array.from(map.entries()).map(([date, items]) => ({ date, items }));
}

// ─── Page ────────────────────────────────────────────────────────────

export default function MacNotesStudy() {
  return (
    <StudioPage
      eyebrow="Notes · macOS · distinct surface study"
      title="Notes as their own thing"
      help="Today Notes is a Library filter; this asks whether it earns its own composition"
    >
      <div className="flex flex-col gap-14 py-6">
        <Variant
          eyebrow="· I · Commonplace book"
          title="Single-column editorial entries, grouped by day"
          hint="slow read · most narrative · invites lingering"
        >
          <CanvasGap>
            <CommonplaceSurface />
          </CanvasGap>
          <Note>
            One entry per day-block. Each note becomes a small editorial
            composition: eyebrow with date / time / attachment chips,
            serif headline, body excerpt at comfortable measure, optional
            attachment row, mono caps meta footer (word count, audio
            duration). Day buckets separated by hairline + small day
            stamp. Reads as pages from a commonplace book — the kind
            of surface you scroll through deliberately, not scan.
          </Note>
        </Variant>

        <Variant
          eyebrow="· II · Sheaf"
          title="Two-column card grid · scraps on a board"
          hint="fast scan · denser · most utilitarian"
        >
          <CanvasGap>
            <SheafSurface />
          </CanvasGap>
          <Note>
            Same data, tighter shells. Two-column grid of compact note
            cards. Each card has: eyebrow (date · time · attachments
            inline), serif title, 2-3 line body truncation, attachment
            thumbnails as a row of small chips at the bottom. Hover
            lifts the card with an amber tint. Reads as a wall of
            scraps — useful when you have lots of notes and want to
            find one fast.
          </Note>
        </Variant>
      </div>
    </StudioPage>
  );
}

// ─── Scaffolding ─────────────────────────────────────────────────────

function Variant({
  eyebrow,
  title,
  hint,
  children,
}: {
  eyebrow: string;
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section>
      <div className="mb-4 flex items-baseline gap-4 border-b border-studio-edge pb-3">
        <div>
          <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
            {eyebrow}
          </div>
          <h2 className="m-0 font-display text-[19px] font-medium leading-none tracking-tight text-studio-ink">
            {title}
          </h2>
        </div>
        {hint && (
          <div className="ml-auto font-mono text-[10px] uppercase tracking-[0.18em] text-studio-ink-faint">
            {hint}
          </div>
        )}
      </div>
      <div className="flex flex-col gap-3">{children}</div>
    </section>
  );
}

function Note({ children }: { children: React.ReactNode }) {
  return (
    <p className="m-0 max-w-[820px] text-[12.5px] leading-[1.65] text-studio-ink">
      {children}
    </p>
  );
}

function CanvasGap({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="flex items-stretch rounded-md"
      style={{
        background: CREAM,
        border: `0.5px dashed rgba(26,22,18,0.10)`,
        minHeight: 560,
        padding: 0,
      }}
    >
      <div className="flex w-full">{children}</div>
    </div>
  );
}

// ─── I — Commonplace book ────────────────────────────────────────────

function CommonplaceSurface() {
  const buckets = groupByDate(NOTES);

  return (
    <div className="flex w-full flex-col" style={{ padding: "44px 64px" }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
          style={{ color: INK_FAINT }}
        >
          · NOTES · COMMONPLACE BOOK ·
        </span>
        <span style={{ flex: 1, height: 0.5, background: INK_RULE }} />
        <span className="font-display italic" style={{ color: INK_FAINT, fontSize: 13 }}>
          {NOTES.length} entries · this week
        </span>
      </div>

      <div className="mt-8 flex flex-col gap-12">
        {buckets.map((bucket) => (
          <DayBlock key={bucket.date} date={bucket.date} items={bucket.items} />
        ))}
      </div>
    </div>
  );
}

function DayBlock({ date, items }: { date: string; items: Note[] }) {
  return (
    <section>
      <div className="flex items-baseline gap-4">
        <span
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.32em]"
          style={{ color: BRASS }}
        >
          · {date.toUpperCase()} ·
        </span>
        <span style={{ flex: 1, height: 0.5, background: INK_RULE_S }} />
        <span className="font-display italic" style={{ color: INK_FAINTER, fontSize: 12 }}>
          {items.length} entr{items.length === 1 ? "y" : "ies"}
        </span>
      </div>

      <div className="mt-5 flex flex-col gap-9">
        {items.map((n) => (
          <CommonplaceEntry key={n.id} note={n} />
        ))}
      </div>
    </section>
  );
}

function CommonplaceEntry({ note }: { note: Note }) {
  return (
    <article>
      {/* Eyebrow */}
      <div className="flex items-baseline gap-3 font-mono text-[9.5px] uppercase tracking-[0.22em]" style={{ color: INK_FAINT }}>
        <span className="tabular-nums">{note.time}</span>
        {note.attachments && note.attachments.length > 0 && (
          <>
            <span style={{ color: INK_FAINTER }}>·</span>
            <AttachmentInline attachments={note.attachments} />
          </>
        )}
      </div>

      {/* Title */}
      <h3
        className="m-0 mt-3 font-display"
        style={{
          color: INK,
          fontSize: 22,
          lineHeight: 1.25,
          letterSpacing: "-0.012em",
          fontWeight: 500,
        }}
      >
        {note.title}
      </h3>

      {/* Body */}
      <p
        className="m-0 mt-3"
        style={{
          color: INK,
          fontSize: 14,
          lineHeight: 1.7,
          maxWidth: 680,
        }}
      >
        {note.body}
      </p>

      {/* Attachment row */}
      {note.attachments && note.attachments.length > 0 && (
        <div className="mt-4 flex flex-wrap gap-2">
          {note.attachments.map((a, i) => (
            <AttachmentChip key={i} attachment={a} />
          ))}
        </div>
      )}

      {/* Footer */}
      <div
        className="mt-4 flex items-baseline gap-3 font-mono text-[9px] uppercase tracking-[0.22em]"
        style={{ color: INK_FAINTER }}
      >
        {note.wordCount && <span>{note.wordCount} words</span>}
        <span>·</span>
        <span>filed to Library · Notes</span>
      </div>
    </article>
  );
}

function AttachmentInline({ attachments }: { attachments: Attachment[] }) {
  const parts: string[] = [];
  const voices = attachments.filter((a) => a.kind === "voice");
  const screens = attachments.filter((a) => a.kind === "screenshot");
  const clips = attachments.filter((a) => a.kind === "clip");
  if (voices.length) parts.push(`${voices.length} voice`);
  if (clips.length) parts.push(`${clips.length} clip`);
  if (screens.length) parts.push(`${screens.length} screenshot${screens.length > 1 ? "s" : ""}`);
  return (
    <span style={{ color: BRASS }}>{parts.join(" · ")}</span>
  );
}

function AttachmentChip({ attachment }: { attachment: Attachment }) {
  if (attachment.kind === "voice") {
    return (
      <span
        className="inline-flex items-baseline gap-1.5 rounded-[2px] border px-2 py-1"
        style={{ borderColor: INK_RULE_S, background: PAPER }}
      >
        <span style={{ color: AMBER, fontSize: 10 }}>♪</span>
        <span
          className="font-mono text-[9.5px] uppercase tracking-[0.16em] tabular-nums"
          style={{ color: INK_FAINT }}
        >
          VOICE · {attachment.duration}
        </span>
      </span>
    );
  }
  if (attachment.kind === "clip") {
    return (
      <span
        className="inline-flex items-baseline gap-1.5 rounded-[2px] border px-2 py-1"
        style={{ borderColor: INK_RULE_S, background: PAPER }}
      >
        <span style={{ color: AMBER, fontSize: 10 }}>▶</span>
        <span
          className="font-mono text-[9.5px] uppercase tracking-[0.16em] tabular-nums"
          style={{ color: INK_FAINT }}
        >
          CLIP · {attachment.duration}
        </span>
      </span>
    );
  }
  return (
    <span
      className="inline-flex items-baseline gap-1.5 rounded-[2px] border px-2 py-1"
      style={{ borderColor: INK_RULE_S, background: PAPER }}
    >
      <span style={{ color: BRASS, fontSize: 10 }}>▢</span>
      <span
        className="font-mono text-[9.5px] uppercase tracking-[0.16em]"
        style={{ color: INK_FAINT }}
      >
        {attachment.label}
      </span>
    </span>
  );
}

// ─── II — Sheaf ──────────────────────────────────────────────────────

function SheafSurface() {
  return (
    <div className="flex w-full flex-col" style={{ padding: "44px 56px" }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
          style={{ color: INK_FAINT }}
        >
          · NOTES · SHEAF ·
        </span>
        <span style={{ flex: 1, height: 0.5, background: INK_RULE }} />
        <span className="font-display italic" style={{ color: INK_FAINT, fontSize: 13 }}>
          {NOTES.length} entries · this week
        </span>
      </div>

      <div
        className="mt-6 grid"
        style={{
          gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
          columnGap: 28,
          rowGap: 22,
        }}
      >
        {NOTES.map((n) => (
          <SheafCard key={n.id} note={n} />
        ))}
      </div>
    </div>
  );
}

function SheafCard({ note }: { note: Note }) {
  return (
    <article
      className="group flex flex-col gap-3 rounded-[3px] p-4 transition-colors hover:bg-[rgba(196,125,28,0.04)]"
      style={{ border: `0.5px solid ${INK_RULE_S}` }}
    >
      {/* Eyebrow */}
      <div className="flex items-baseline gap-2 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: INK_FAINTER }}>
        <span>{note.date.split(" ").slice(0, 2).join(" ")}</span>
        <span>·</span>
        <span className="tabular-nums">{note.time}</span>
        {note.attachments && note.attachments.length > 0 && (
          <>
            <span style={{ color: INK_FAINTER }}>·</span>
            <span style={{ color: BRASS }}>
              {note.attachments.length} attached
            </span>
          </>
        )}
      </div>

      {/* Title */}
      <h3
        className="m-0 font-display"
        style={{
          color: INK,
          fontSize: 17,
          lineHeight: 1.3,
          letterSpacing: "-0.005em",
          fontWeight: 500,
        }}
      >
        {note.title}
      </h3>

      {/* Body excerpt — 2 lines max */}
      <p
        className="m-0"
        style={{
          color: INK_FAINT,
          fontSize: 12.5,
          lineHeight: 1.55,
          display: "-webkit-box",
          WebkitLineClamp: 2,
          WebkitBoxOrient: "vertical" as const,
          overflow: "hidden",
        }}
      >
        {note.body}
      </p>

      {/* Attachment thumbnails */}
      {note.attachments && note.attachments.length > 0 && (
        <div className="mt-auto flex flex-wrap gap-1.5">
          {note.attachments.slice(0, 3).map((a, i) => (
            <AttachmentMini key={i} attachment={a} />
          ))}
          {note.attachments.length > 3 && (
            <span
              className="font-mono text-[9px] uppercase tracking-[0.18em]"
              style={{ color: INK_FAINTER }}
            >
              + {note.attachments.length - 3}
            </span>
          )}
        </div>
      )}
    </article>
  );
}

function AttachmentMini({ attachment }: { attachment: Attachment }) {
  if (attachment.kind === "voice" || attachment.kind === "clip") {
    return (
      <span
        className="inline-flex items-baseline gap-1 rounded-[2px] border px-1.5 py-0.5"
        style={{ borderColor: INK_RULE_S, background: CREAM }}
      >
        <span style={{ color: AMBER, fontSize: 8 }}>
          {attachment.kind === "voice" ? "♪" : "▶"}
        </span>
        <span
          className="font-mono text-[8.5px] uppercase tracking-[0.14em] tabular-nums"
          style={{ color: INK_FAINTER }}
        >
          {attachment.duration}
        </span>
      </span>
    );
  }
  return (
    <span
      className="inline-flex items-baseline rounded-[2px] border px-1.5 py-0.5"
      style={{ borderColor: INK_RULE_S, background: CREAM }}
    >
      <span
        className="font-mono text-[8.5px] uppercase tracking-[0.14em]"
        style={{ color: INK_FAINTER }}
      >
        IMG
      </span>
    </span>
  );
}
