"use client";

/**
 * Mac Compose — full window composition.
 *
 * Shipping Swift: `apps/macos/Talkie/Views/Drafts/ScopeDraftsScreen.swift`.
 * Internally called "Drafts" but surfaced as "Compose" in the sidebar.
 * It is **not** a list — it's a single focused editor with:
 *
 *   1. Signal monitor — 78pt dark instrument panel up top, with a
 *      4-stage pipeline (CAPTURE → TRANSCRIPT → REVISE → SHIP).
 *   2. Editor bay — chrome bar (CH-IN label + model picker + word count
 *      + revising flag) over a cream textarea with a floating
 *      dictation pill at the bottom-center.
 *   3. Action bar — three smart-action chips, plus COMMAND voice
 *      prompt, plus SAVE / COPY on the right.
 *   4. Action rail — scrollable 4-col grid of all smart actions below
 *      the fold (Compose's "kitchen sink" of operations).
 *   5. Ownership strip — P1 (input device) → P2 (model) → P3 (output).
 *
 * Swift has no `GeometryReader` here, so the layout is whatever flex +
 * fixed paddings produce. Stamping at 820 surfaces the points where it
 * runs out of room: pipeline pin gaps collapse, the action chip row
 * truncates, the action grid drops from 4 columns to 2.
 */

import React from "react";

// ─── Stub content ────────────────────────────────────────────────────

const PIPELINE = [
  { key: "capture",    label: "Capture",    short: "S1", active: true,  done: true  },
  { key: "transcript", label: "Transcript", short: "S2", active: true,  done: true  },
  { key: "revise",     label: "Revise",     short: "S3", active: true,  done: false },
  { key: "ship",       label: "Ship",       short: "S4", active: false, done: false },
] as const;

const SMART_ACTIONS = [
  { key: "refine",    label: "Refine",      hint: "tighten, clarify, keep voice" },
  { key: "simplify",  label: "Simplify",    hint: "drop jargon, plain phrasing" },
  { key: "expand",    label: "Expand",      hint: "add context + examples" },
  { key: "bullets",   label: "To Bullets",  hint: "outline the structure" },
  { key: "summarize", label: "Summarize",   hint: "3-line TL;DR" },
  { key: "translate", label: "Translate",   hint: "to another language" },
  { key: "tone",      label: "Soften Tone", hint: "less direct, more diplomatic" },
  { key: "title",     label: "Title It",    hint: "derive a noun-phrase title" },
];

const DRAFT_TEXT = [
  "Okay, so the chiffon scheme is closer than I thought. The problem isn't the scheme, it's that I was reading the bay against the wrong floor. Once I dropped it onto the cream studio canvas instead of pure white, the brass amber stopped fighting and started reading like a real instrument bay. The bay wants to sit on warm paper. That's the whole insight.",
  "Next thing — the system status rail. Right now it follows the bay's scheme, which means when I'm in chiffon I get this very pale rail that reads as almost invisible. That might be correct, actually. The rail is health information, not feature surface. If it disappears into the page when everything's green, that's exactly what I want. We only need it loud when something's wrong.",
];

// ─── Composition root ────────────────────────────────────────────────

export function MacCompose({ width = 1180 }: { width?: number } = {}) {
  const compact = width < 880;
  const padX = compact ? 22 : width >= 1300 ? 40 : 32;

  return (
    <div style={{ width, background: "#FBFBFA" }} className="flex flex-col">
      <SignalMonitor padX={padX} compact={compact} />
      <div style={{ paddingLeft: padX, paddingRight: padX, paddingTop: 18, paddingBottom: 18 }}>
        <EditorBay compact={compact} />
        <ActionBar compact={compact} />
        <div className="h-9" />
        <ActionGrid compact={compact} />
        <div className="h-7" />
        <OwnershipStrip />
      </div>
    </div>
  );
}

// ─── Signal monitor (top dark panel) ─────────────────────────────────

function SignalMonitor({ padX, compact }: { padX: number; compact: boolean }) {
  return (
    <div
      style={{
        background: "#0E1518",
        borderBottom: "1px solid #1A2326",
        paddingLeft: padX,
        paddingRight: padX,
      }}
    >
      {/* Header row */}
      <div className="flex items-center gap-3 pt-3">
        <span aria-hidden className="h-1.5 w-1.5 rounded-full" style={{ background: "#5FE3C9", boxShadow: "0 0 6px #5FE3C988" }} />
        <span className="font-mono text-[9px] uppercase tracking-[0.26em]" style={{ color: "#5FE3C9" }}>
          · SIGNAL · TALKIE.COMPOSE
        </span>

        {!compact && (
          <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: "#5FE3C988" }}>
            · D-0024 · open since 9:31 AM
          </span>
        )}

        <div className="ml-auto flex items-center gap-3 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: "#5FE3C988" }}>
          <span style={{ color: "#5FE3C9" }}>✦ CLAUDE SONNET 4.6</span>
          <span className="opacity-50">|</span>
          <span>412 WORDS · 6:14 DICT</span>
        </div>
      </div>

      {/* Pipeline row */}
      <div className="flex items-center gap-3 pt-3 pb-3.5">
        {PIPELINE.map((stage, i) => (
          <React.Fragment key={stage.key}>
            <PipelinePin stage={stage} compact={compact} />
            {i < PIPELINE.length - 1 && <PipelineConnector active={!!PIPELINE[i + 1].active} compact={compact} />}
          </React.Fragment>
        ))}
        <span className="ml-auto font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: "#5FE3C988" }}>
          ⌃⇧⌘ R · revise
        </span>
      </div>
    </div>
  );
}

function PipelinePin({
  stage,
  compact,
}: {
  stage: (typeof PIPELINE)[number];
  compact: boolean;
}) {
  const amber = "#E89A3C";
  const teal = "#5FE3C9";
  const fillColor = stage.done ? teal : stage.active ? amber : "#3A4248";
  const labelColor = stage.done ? `${teal}` : stage.active ? `${amber}` : "#5A6066";
  return (
    <div className="flex items-center gap-1.5">
      <span
        className="font-mono text-[8px] uppercase tracking-[0.22em]"
        style={{ color: labelColor }}
      >
        {stage.short}
      </span>
      <span
        aria-hidden
        className="h-2 w-2 rounded-full"
        style={{
          background: fillColor,
          boxShadow: stage.active ? `0 0 8px ${fillColor}99` : "none",
        }}
      />
      {!compact && (
        <span
          className="font-mono text-[9px] uppercase tracking-[0.22em]"
          style={{ color: labelColor }}
        >
          {stage.label.toUpperCase()}
        </span>
      )}
    </div>
  );
}

function PipelineConnector({ active, compact }: { active: boolean; compact: boolean }) {
  const w = compact ? 28 : 56;
  return (
    <span
      aria-hidden
      className="h-px"
      style={{
        width: w,
        background: active ? "#E89A3C66" : "#3A4248",
      }}
    />
  );
}

// ─── Editor bay ──────────────────────────────────────────────────────

function EditorBay({ compact }: { compact: boolean }) {
  return (
    <div
      className="overflow-hidden rounded-md"
      style={{
        background: "#FDFAF1",
        border: "0.5px solid #E0DCD3",
        boxShadow: "0 1px 0 rgba(255,255,255,0.5) inset, 0 1px 2px rgba(0,0,0,0.04)",
      }}
    >
      <EditorChromeBar compact={compact} />
      <EditorSurface compact={compact} />
    </div>
  );
}

function EditorChromeBar({ compact }: { compact: boolean }) {
  return (
    <div
      className="flex items-center gap-3 px-4 py-2"
      style={{ background: "#F4F1EA", borderBottom: "0.5px solid #E0DCD3" }}
    >
      <span className="font-mono text-[9px] uppercase tracking-[0.22em] text-[#9A6A22]">
        · CH-IN
      </span>
      <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        D-0024
      </span>

      <button
        className="flex items-center gap-1.5 rounded-[3px] px-2 py-1 text-[10px] font-medium text-studio-ink"
        style={{ border: "0.5px solid #2A2620", background: "#FFFFFF" }}
      >
        <span className="text-[#9A6A22]">✦</span>
        <span>Claude Sonnet 4.6</span>
        <span className="text-studio-ink-faint">▾</span>
      </button>

      <div className="ml-auto flex items-center gap-3 font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        <span>412 words</span>
        {!compact && (
          <>
            <span className="opacity-50">|</span>
            <span className="flex items-center gap-1.5">
              <span aria-hidden className="h-1.5 w-1.5 rounded-full" style={{ background: "#E89A3C", boxShadow: "0 0 4px #E89A3C99" }} />
              <span className="text-[#9A6A22]">REVISING</span>
            </span>
          </>
        )}
        <span className="opacity-50">|</span>
        <button className="rounded-[2px] border border-studio-edge px-2 py-0.5 hover:border-studio-ink hover:text-studio-ink">
          NEW
        </button>
      </div>
    </div>
  );
}

function EditorSurface({ compact }: { compact: boolean }) {
  return (
    <div className="relative" style={{ minHeight: compact ? 360 : 440 }}>
      {/* Graticule underlay */}
      <GraticuleBackground />

      {/* Text content */}
      <div className="relative px-7 pt-6 pb-20">
        {DRAFT_TEXT.map((p, i) => (
          <p key={i} className="mb-4 text-[14px] leading-[1.7] text-studio-ink">
            {p}
          </p>
        ))}
      </div>

      {/* Dictation pill — floating bottom-center */}
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2">
        <DictationPill />
      </div>
    </div>
  );
}

function GraticuleBackground() {
  return (
    <svg
      aria-hidden
      className="absolute inset-0 h-full w-full"
      style={{ opacity: 0.05 }}
    >
      <defs>
        <pattern id="cgrid" width="24" height="24" patternUnits="userSpaceOnUse">
          <path d="M 24 0 L 0 0 0 24" fill="none" stroke="#9A6A22" strokeWidth="0.4" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill="url(#cgrid)" />
    </svg>
  );
}

function DictationPill() {
  return (
    <button
      className="flex items-center gap-2.5 rounded-full px-4 py-2"
      style={{
        background: "#FFFFFF",
        border: "0.5px solid #C47D1C",
        boxShadow: "0 4px 14px rgba(196,125,28,0.18), 0 0 0 4px rgba(196,125,28,0.06)",
      }}
    >
      <span aria-hidden className="flex h-6 w-6 items-center justify-center rounded-full" style={{ background: "#C47D1C" }}>
        <svg width="11" height="14" viewBox="0 0 11 14" aria-hidden>
          <rect x="3.5" y="0.5" width="4" height="8" rx="2" fill="#FFFFFF" />
          <path d="M 1 6.5 v 1 a 4.5 4.5 0 0 0 9 0 v -1" fill="none" stroke="#FFFFFF" strokeWidth="1" />
          <line x1="5.5" y1="11" x2="5.5" y2="13" stroke="#FFFFFF" strokeWidth="1" />
        </svg>
      </span>
      <span className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink">
        Dictate
      </span>
      <span className="font-mono text-[9px] tracking-[0.06em] text-studio-ink-faint">
        ⌃⇧⌘ D
      </span>
    </button>
  );
}

// ─── Action bar ──────────────────────────────────────────────────────

function ActionBar({ compact }: { compact: boolean }) {
  const visibleActions = compact ? SMART_ACTIONS.slice(0, 2) : SMART_ACTIONS.slice(0, 3);
  return (
    <div className="mt-4 flex items-center gap-2.5">
      {/* COMMAND voice button */}
      <button
        className="flex items-center gap-2 rounded-[4px] px-3 py-2"
        style={{
          background: "#FFFFFF",
          border: "0.5px solid #C47D1C",
          color: "#7A521A",
        }}
      >
        <span aria-hidden className="h-2 w-2 rounded-full" style={{ background: "#C47D1C", boxShadow: "0 0 6px #C47D1C99" }} />
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em]">
          COMMAND
        </span>
        <span className="font-mono text-[9px] tracking-[0.06em] opacity-60">
          ⌃⇧⌘ C
        </span>
      </button>

      <span className="h-5 w-px" style={{ background: "#E0DCD3" }} />

      {/* Smart action chips */}
      <div className="flex items-center gap-1.5">
        {visibleActions.map((a) => (
          <button
            key={a.key}
            className="rounded-[3px] px-2 py-1 font-mono text-[9px] font-semibold uppercase tracking-[0.18em]"
            style={{ border: "0.5px solid #E0DCD3", color: "#3F3A33" }}
          >
            {a.label.toUpperCase()}
          </button>
        ))}
        {compact && (
          <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
            +{SMART_ACTIONS.length - visibleActions.length} ↓
          </span>
        )}
      </div>

      <div className="ml-auto flex items-center gap-2">
        <button
          className="rounded-[3px] px-3 py-1.5 font-mono text-[9px] font-semibold uppercase tracking-[0.22em] text-studio-ink"
          style={{ border: "0.5px solid #E0DCD3" }}
        >
          COPY
        </button>
        <button
          className="rounded-[3px] px-3 py-1.5 font-mono text-[9px] font-semibold uppercase tracking-[0.22em]"
          style={{ background: "#2A2620", color: "#FBFBFA" }}
        >
          SAVE TO LIBRARY →
        </button>
      </div>
    </div>
  );
}

// ─── Action grid (below the fold) ────────────────────────────────────

function ActionGrid({ compact }: { compact: boolean }) {
  const cols = compact ? 2 : 4;
  return (
    <div>
      <div className="mb-3 flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em] text-studio-ink-faint">
          · Smart actions
        </span>
        <span className="flex-1 border-t border-studio-edge/60" />
        <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
          {SMART_ACTIONS.length} available · scroll for more ↓
        </span>
      </div>
      <div
        className="grid gap-2"
        style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}
      >
        {SMART_ACTIONS.map((a) => (
          <ActionCell key={a.key} action={a} />
        ))}
      </div>
    </div>
  );
}

function ActionCell({ action }: { action: (typeof SMART_ACTIONS)[number] }) {
  return (
    <button
      className="flex flex-col gap-1 rounded-md p-3 text-left"
      style={{
        background: "#FFFFFF",
        border: "0.5px solid #E0DCD3",
        boxShadow: "0 1px 0 rgba(255,255,255,0.5) inset",
      }}
    >
      <div className="flex items-baseline gap-2">
        <span className="font-display text-[14px] font-medium text-studio-ink">
          {action.label}
        </span>
        <span className="ml-auto font-mono text-[9px] uppercase tracking-[0.22em] text-[#9A6A22]">
          APPLY →
        </span>
      </div>
      <div className="text-[11px] text-studio-ink-faint">
        {action.hint}
      </div>
    </button>
  );
}

// ─── Ownership strip (footer) ───────────────────────────────────────

function OwnershipStrip() {
  return (
    <div
      className="grid grid-cols-3 gap-3 rounded-md px-4 py-3"
      style={{ background: "#F4F1EA", border: "0.5px solid #E0DCD3" }}
    >
      <OwnershipCol pin="P1" eyebrow="Input" value="MacBook Pro" detail="Parakeet v3 · local" />
      <OwnershipCol pin="P2" eyebrow="Model" value="Claude Sonnet 4.6" detail="Anthropic · API" />
      <OwnershipCol pin="P3" eyebrow="Output" value="Library · Memos" detail="Local · Cmd+S" />
    </div>
  );
}

function OwnershipCol({
  pin,
  eyebrow,
  value,
  detail,
}: {
  pin: string;
  eyebrow: string;
  value: string;
  detail: string;
}) {
  return (
    <div className="flex flex-col gap-0.5">
      <div className="flex items-baseline gap-2">
        <span className="font-mono text-[9px] uppercase tracking-[0.22em] text-[#9A6A22]">
          {pin}
        </span>
        <span className="font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
          · {eyebrow}
        </span>
      </div>
      <div className="font-display text-[13px] font-medium text-studio-ink">
        {value}
      </div>
      <div className="font-mono text-[9px] uppercase tracking-[0.18em] text-studio-ink-faint">
        {detail}
      </div>
    </div>
  );
}
