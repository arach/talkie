"use client";

/**
 * IOSMemo — memo detail cleanup pass.
 *
 * Three changes vs the donor (VoiceMemoDetailNext.swift):
 *
 *   1. Body is the page, not a sub-section.
 *      Donor wraps the memo text in a card titled `· TRANSCRIPT`. The
 *      card frames it as "one of many sections". Here the body has no
 *      eyebrow, no surrounding card — just a wider editorial column
 *      sitting on the canvas at higher type weight. Word count moves
 *      to a single quiet meta line under the title.
 *
 *   2. Playback comes AFTER the body.
 *      Donor renders the playback card before the body, which makes
 *      the user wait to read. New order: title → body → playback.
 *      The standalone "Listen" tile is dropped (it duplicated the
 *      playback control we already render right above it).
 *
 *   3. Actions collapse to one composite affordance.
 *      Donor: 2×2 grid of Listen · Ask Agent · Run CLI · Attach.
 *      Now: full-width Share, then a single "Attach" — tap opens a
 *      sheet with the sub-options (Add file · Ask Agent · Run CLI).
 *      All three are forms of "attach external context to this memo",
 *      so they share one verb.
 */

import { StatusBar } from "./primitives/StatusBar";

const TITLE = "Notes on cockpit chassis depth";
const META = "MAY 26 · 1:24 PM · 0:48";
const WORD_COUNT = 84;

const MEMO_BODY = `The cockpit should feel like one instrument, not three stacked strips. Identity on the left, status on the right, trackpad in the middle, key row beneath — all inside the same bounded chassis. The transcript card should toggle in place on top of the trackpad, not occupy its own row. We keep the diagonals at full opacity behind it so the instrument is still readable; the elevated card just floats on top while dictation is active. Three lines max, then ellipsis — older tokens scroll off as new ones land.`;

export function IOSMemo() {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />
      <Header />

      <div className="flex-1 overflow-y-auto px-5 pb-24 pt-2">
        <TitleBlock />
        <Body />
        <Playback />
        <Actions />
      </div>
    </div>
  );
}

// ── Header ──────────────────────────────────────────────────────

function Header() {
  return (
    <div className="flex items-center justify-between px-4 pb-2 pt-3">
      <button
        className="flex items-center gap-1.5 px-1 text-[12px]"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-mono)",
        }}
        aria-label="Back"
      >
        <ChevronIcon dir="left" />
        Home
      </button>
      <span
        className="text-[10px] tracking-[0.22em]"
        style={{
          color: "var(--theme-ink-muted)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        MEMO
      </span>
      <div className="flex items-center gap-2">
        <button
          className="rounded-full px-2.5 py-0.5 text-[10px] tracking-[0.14em]"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
          }}
        >
          EDIT
        </button>
        <button
          className="grid h-6 w-6 place-items-center rounded-full"
          style={{
            color: "var(--theme-ink-muted)",
            boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
          }}
          aria-label="More"
        >
          ⋯
        </button>
      </div>
    </div>
  );
}

// ── Title + meta ────────────────────────────────────────────────

function TitleBlock() {
  return (
    <div className="flex flex-col gap-1.5 pt-3 pb-5">
      <h1
        className="text-[22px] leading-[1.18] tracking-[-0.01em]"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-display)",
          fontWeight: 500,
        }}
      >
        {TITLE}
      </h1>
      <div
        className="flex items-center gap-2 text-[10px] tracking-[0.14em]"
        style={{
          color: "var(--theme-ink-muted)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        <span>{META}</span>
        <span style={{ color: "var(--theme-ink-faint)" }}>·</span>
        <span>{WORD_COUNT} WORDS</span>
      </div>
    </div>
  );
}

// ── Body ────────────────────────────────────────────────────────
// No eyebrow, no surrounding card, no border. The memo IS the page.
// Wider line-length, larger type, generous line-height. Refine-in-
// Compose stays as a quiet tap target inside the column.

function Body() {
  return (
    <div className="flex flex-col gap-4 pb-7">
      <p
        className="text-[15px] leading-[1.55]"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-body)",
        }}
      >
        {MEMO_BODY}
      </p>
      <button
        className="flex items-center gap-2 self-start text-[11px] tracking-[0.06em]"
        style={{
          color: "var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        <PencilIcon />
        Refine in Compose
        <ChevronIcon dir="right" />
      </button>
    </div>
  );
}

// ── Playback (moved BELOW the body) ─────────────────────────────

function Playback() {
  return (
    <div
      className="mb-5 flex items-center gap-3 rounded-xl px-3 py-3"
      style={{
        background: "var(--theme-paper)",
        boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
      }}
    >
      <button
        className="grid h-9 w-9 place-items-center rounded-full"
        style={{
          background: "var(--theme-amber)",
          color: "var(--theme-canvas)",
        }}
        aria-label="Play"
      >
        <PlayIcon />
      </button>
      <Waveform />
      <div
        className="flex flex-col items-end text-[10px] leading-tight tracking-[0.04em]"
        style={{
          color: "var(--theme-ink-muted)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        <span style={{ color: "var(--theme-ink)" }}>0:00</span>
        <span>0:48</span>
      </div>
    </div>
  );
}

function Waveform() {
  // Static bar bargraph — 32 bars at varying heights.
  const heights = [
    4, 6, 9, 5, 11, 14, 8, 17, 12, 9, 6, 18, 22, 15, 10, 6,
    8, 13, 19, 14, 9, 6, 11, 7, 5, 12, 16, 9, 6, 4, 5, 3,
  ];
  return (
    <div className="flex flex-1 items-center gap-[2px]">
      {heights.map((h, i) => (
        <span
          key={i}
          style={{
            display: "inline-block",
            width: 2,
            height: `${h}px`,
            background: "var(--theme-ink-muted)",
            opacity: i < 4 ? 1 : 0.55,
            borderRadius: 1,
          }}
        />
      ))}
    </div>
  );
}

// ── Actions ─────────────────────────────────────────────────────
// Share = full-width primary. Attach = single composite affordance
// (Ask Agent + Run CLI + Add file all live behind it as sheet options).
// Standalone Listen is gone — playback above already does that.

function Actions() {
  return (
    <div className="flex flex-col gap-2">
      <ActionRow icon={<ShareIcon />} label="Share Memo" tint="amber" />
      <ActionRow
        icon={<PaperclipIcon />}
        label="Attach"
        sublabel="Ask Agent · Run CLI · Add file"
      />
    </div>
  );
}

function ActionRow({
  icon,
  label,
  sublabel,
  tint,
}: {
  icon: React.ReactNode;
  label: string;
  sublabel?: string;
  tint?: "amber";
}) {
  return (
    <button
      className="flex items-center gap-3 rounded-xl px-3 py-3"
      style={{
        background: "var(--theme-paper)",
        boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
      }}
    >
      <span
        className="grid h-8 w-8 place-items-center rounded-md"
        style={{
          background: "var(--theme-amber-faint)",
          color: tint === "amber" ? "var(--theme-amber)" : "var(--theme-ink-dim)",
        }}
      >
        {icon}
      </span>
      <span className="flex flex-1 flex-col items-start">
        <span
          className="text-[13px]"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-body)",
          }}
        >
          {label}
        </span>
        {sublabel && (
          <span
            className="text-[10px] tracking-[0.08em]"
            style={{
              color: "var(--theme-ink-muted)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            {sublabel}
          </span>
        )}
      </span>
      <span style={{ color: "var(--theme-ink-muted)" }}>
        <ChevronIcon dir="right" />
      </span>
    </button>
  );
}

// ── Icons ───────────────────────────────────────────────────────

function ChevronIcon({ dir }: { dir: "left" | "right" }) {
  return (
    <svg viewBox="0 0 10 10" className="h-2.5 w-2.5" fill="none">
      <path
        d={dir === "left" ? "M6.5 1.5L3 5L6.5 8.5" : "M3.5 1.5L7 5L3.5 8.5"}
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function PencilIcon() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none" aria-hidden>
      <path
        d="M1.5 10.5L1.5 8.5L8 2L10 4L3.5 10.5L1.5 10.5Z"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg viewBox="0 0 14 14" className="h-3.5 w-3.5" fill="currentColor" aria-hidden>
      <path d="M4 3L11 7L4 11Z" />
    </svg>
  );
}

function ShareIcon() {
  return (
    <svg viewBox="0 0 16 16" className="h-4 w-4" fill="none" aria-hidden>
      <path
        d="M8 2V10M8 2L5 5M8 2L11 5M3 9V12.5C3 13.05 3.45 13.5 4 13.5H12C12.55 13.5 13 13.05 13 12.5V9"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function PaperclipIcon() {
  return (
    <svg viewBox="0 0 16 16" className="h-4 w-4" fill="none" aria-hidden>
      <path
        d="M11 6L6.5 10.5C5.7 11.3 5.7 12.6 6.5 13.4C7.3 14.2 8.6 14.2 9.4 13.4L13.5 9.3C14.9 7.9 14.9 5.6 13.5 4.2C12.1 2.8 9.8 2.8 8.4 4.2L4.3 8.3C2.2 10.4 2.2 13.8 4.3 15.9"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
