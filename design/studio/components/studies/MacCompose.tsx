"use client";

/**
 * Mac Compose — full window composition (V2).
 *
 * Shipping Swift: `apps/macos/Talkie/Views/Drafts/ScopeDraftsScreen.swift`.
 * Internally called "Drafts" but surfaced as "Compose" in the sidebar.
 *
 * V1 had a dark gunmetal SignalMonitor (`#0E1518` panel, teal `#5FE3C9`
 * pipeline pins, instrument-bay chrome). That was the same instrument-
 * cosplay direction the recording state's V1 wore — it doesn't speak
 * Scope's cream paper editorial language. V2 recasts the whole surface:
 *
 *   A. Signal monitor → typeset header on cream. Pipeline becomes a
 *      quiet typeset row (filled / half / empty discs with mono labels),
 *      not a phosphor readout.
 *   B. Two-pill conflict resolved. The chrome bar's TALKIE pill is the
 *      only recording anchor; the editor's "Dictate" pill is gone.
 *   C. Editor bay → page. Hairlines top/bottom, brass marginal rule on
 *      the left, no card chrome, no graticule underlay. Writing on
 *      paper, not into a textarea widget.
 *   D. Action grid → typeset list. Two-column editorial list, each row
 *      label + hint + amber APPLY caret; whole row lifts on hover.
 *   E. Ownership strip → byline. Single italic Newsreader sentence:
 *      "Recorded on MacBook Pro via Parakeet v3, polished with Claude
 *      Sonnet 4.6, filed to Library."
 */

import React from "react";

// ─── Tokens ──────────────────────────────────────────────────────────

const CREAM       = "#FBFBFA";
const PAPER       = "#F4F1EA";
const INK         = "#2A2620";
const INK_FAINT   = "rgba(42,38,32,0.55)";
const INK_FAINTER = "rgba(42,38,32,0.32)";
const INK_RULE    = "rgba(42,38,32,0.18)";
const INK_RULE_S  = "rgba(42,38,32,0.10)";
const AMBER       = "#C47D1C";
const BRASS       = "#9A6A22";
const EDGE        = "#E0DCD3";

// ─── Stub content ────────────────────────────────────────────────────

type Stage = {
  key: string;
  label: string;
  short: string;
  state: "done" | "active" | "pending";
};

const PIPELINE: Stage[] = [
  { key: "capture",    label: "Capture",    short: "S1", state: "done"    },
  { key: "transcript", label: "Transcript", short: "S2", state: "done"    },
  { key: "revise",     label: "Revise",     short: "S3", state: "active"  },
  { key: "ship",       label: "Ship",       short: "S4", state: "pending" },
];

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
    <div style={{ width, background: CREAM }} className="flex flex-col">
      <SignalHeader padX={padX} compact={compact} />
      <div style={{ paddingLeft: padX, paddingRight: padX, paddingTop: 24, paddingBottom: 24 }}>
        <EditorPage compact={compact} />
        <ActionBar compact={compact} />
        <div className="h-9" />
        <ActionList compact={compact} />
        <div className="h-7" />
        <OwnershipByline />
      </div>
    </div>
  );
}

// ─── A. Signal header (typeset, cream paper) ─────────────────────────

function SignalHeader({ padX, compact }: { padX: number; compact: boolean }) {
  return (
    <div
      style={{
        paddingLeft: padX,
        paddingRight: padX,
        paddingTop: 18,
        paddingBottom: 18,
        background: CREAM,
      }}
    >
      {/* Top row — eyebrow + metadata */}
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: INK_FAINT }}>
          · COMPOSE · D-0024 ·
        </span>
        {!compact && (
          <span className="font-display italic" style={{ color: INK_FAINT, fontSize: 13 }}>
            open since 9:31 AM · 6:14 dictation
          </span>
        )}

        <div className="ml-auto flex items-baseline gap-3">
          <button
            className="flex items-baseline gap-1.5 rounded-[2px] px-2 py-0.5 hover:bg-[rgba(196,125,28,0.05)]"
            style={{ border: `0.5px solid ${EDGE}` }}
          >
            <span style={{ color: BRASS, fontSize: 10 }}>✦</span>
            <span className="font-mono text-[10px] font-medium" style={{ color: INK }}>
              Claude Sonnet 4.6
            </span>
            <span className="font-mono text-[9px]" style={{ color: INK_FAINTER }}>
              ▾
            </span>
          </button>
          <span className="font-mono text-[10px] uppercase tracking-[0.22em] tabular-nums" style={{ color: INK_FAINT }}>
            412 words
          </span>
        </div>
      </div>

      {/* Top hairline */}
      <div className="mt-3.5" style={{ height: 0.5, background: INK_RULE }} />

      {/* Pipeline row */}
      <div className="mt-4 flex items-center gap-3">
        {PIPELINE.map((stage, i) => (
          <React.Fragment key={stage.key}>
            <PipelineStage stage={stage} compact={compact} />
            {i < PIPELINE.length - 1 && (
              <PipelineRule done={PIPELINE[i + 1].state !== "pending"} compact={compact} />
            )}
          </React.Fragment>
        ))}

        <span
          className="ml-auto font-mono text-[9px] uppercase tracking-[0.22em]"
          style={{ color: INK_FAINTER }}
        >
          ⌃⇧⌘R · revise
        </span>
      </div>
    </div>
  );
}

function PipelineStage({ stage, compact }: { stage: Stage; compact: boolean }) {
  const labelColor =
    stage.state === "done"
      ? INK
      : stage.state === "active"
      ? AMBER
      : INK_FAINTER;

  return (
    <div className="flex items-center gap-2">
      <StageDisc state={stage.state} />
      <span
        className="font-mono text-[10px] uppercase tracking-[0.22em]"
        style={{ color: labelColor, fontWeight: stage.state === "active" ? 600 : 400 }}
      >
        {compact ? stage.short : stage.label}
      </span>
    </div>
  );
}

function StageDisc({ state }: { state: Stage["state"] }) {
  const size = 9;
  if (state === "done") {
    return (
      <span
        aria-hidden
        className="inline-block rounded-full"
        style={{ width: size, height: size, background: AMBER }}
      />
    );
  }
  if (state === "active") {
    // Ring + half-fill: outline ring with amber, inner half via clip-path
    return (
      <svg width={size} height={size} viewBox="0 0 9 9" aria-hidden>
        <circle cx="4.5" cy="4.5" r="3.6" fill="none" stroke={AMBER} strokeWidth="1.2" />
        <path d="M 4.5 0.9 A 3.6 3.6 0 0 1 4.5 8.1 Z" fill={AMBER} />
      </svg>
    );
  }
  return (
    <span
      aria-hidden
      className="inline-block rounded-full"
      style={{
        width: size,
        height: size,
        border: `1px solid ${INK_FAINTER}`,
        background: "transparent",
      }}
    />
  );
}

function PipelineRule({ done, compact }: { done: boolean; compact: boolean }) {
  const w = compact ? 22 : 48;
  return (
    <span
      aria-hidden
      style={{
        width: w,
        height: 0.5,
        background: done ? AMBER : INK_FAINTER,
        opacity: done ? 0.5 : 0.5,
      }}
    />
  );
}

// ─── C. Editor page (hairlines + marginal rule, no card chrome) ─────

function EditorPage({ compact }: { compact: boolean }) {
  return (
    <div>
      {/* Editor chrome row — sits ABOVE the page rules, no card frame */}
      <EditorChromeRow compact={compact} />

      {/* Top page rule */}
      <div className="mt-3" style={{ height: 0.5, background: INK_RULE }} />

      {/* Page body — text with marginal rule, no container */}
      <div className="relative pt-7 pb-9">
        <div className="flex">
          {/* Left marginal rule — brass amber, 30% (matches memo detail) */}
          <span
            aria-hidden
            className="self-stretch"
            style={{ width: 0.5, background: `${BRASS}55`, marginRight: 20 }}
          />

          {/* Text column */}
          <div className="flex-1" style={{ paddingRight: compact ? 0 : 24 }}>
            {DRAFT_TEXT.map((p, i) => (
              <p
                key={i}
                className="m-0 mb-4 font-display"
                style={{
                  color: INK,
                  fontSize: 15,
                  lineHeight: 1.7,
                  letterSpacing: "-0.001em",
                }}
              >
                {p}
              </p>
            ))}

            {/* Active cursor hint — typeset, not a floating pill */}
            <div
              className="mt-5 inline-flex items-baseline gap-2 font-mono text-[10px] uppercase tracking-[0.22em]"
              style={{ color: INK_FAINTER }}
            >
              <span style={{ color: AMBER }}>▍</span>
              <span>cursor</span>
              <span style={{ color: INK_FAINTER }}>·</span>
              <span>hold</span>
              <span style={{ color: INK_FAINT, fontWeight: 600 }}>⌃⇧⌘ D</span>
              <span>to dictate inline</span>
            </div>
          </div>
        </div>
      </div>

      {/* Bottom page rule */}
      <div style={{ height: 0.5, background: INK_RULE }} />
    </div>
  );
}

function EditorChromeRow({ compact }: { compact: boolean }) {
  return (
    <div className="flex items-baseline gap-3">
      <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: BRASS }}>
        · DRAFT
      </span>
      <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: INK_FAINTER }}>
        chiffon scheme & system status rail
      </span>

      <div className="ml-auto flex items-baseline gap-3 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: INK_FAINT }}>
        {!compact && (
          <>
            <span className="flex items-center gap-1.5">
              <span aria-hidden className="h-1.5 w-1.5 rounded-full" style={{ background: AMBER }} />
              <span style={{ color: BRASS }}>REVISING</span>
            </span>
            <span style={{ color: INK_FAINTER }}>·</span>
          </>
        )}
        <button className="hover:text-studio-ink" style={{ color: INK_FAINT }}>
          NEW DRAFT
        </button>
      </div>
    </div>
  );
}

// ─── D. Action bar (above the list) ──────────────────────────────────

function ActionBar({ compact }: { compact: boolean }) {
  const visibleActions = compact ? SMART_ACTIONS.slice(0, 2) : SMART_ACTIONS.slice(0, 3);

  return (
    <div className="mt-5 flex items-baseline gap-3">
      {/* Inline COMMAND affordance — text + hotkey, no pill */}
      <button
        className="flex items-baseline gap-2 rounded-[2px] px-2 py-1 hover:bg-[rgba(196,125,28,0.06)]"
        style={{ border: `0.5px solid ${INK_RULE}` }}
      >
        <span className="font-mono text-[10px] font-semibold uppercase tracking-[0.24em]" style={{ color: BRASS }}>
          ⌘ COMMAND
        </span>
        <span className="font-mono text-[9px]" style={{ color: INK_FAINTER }}>
          ⌃⇧⌘C
        </span>
      </button>

      <span style={{ width: 0.5, height: 14, background: INK_RULE }} />

      <div className="flex items-baseline gap-1.5">
        {visibleActions.map((a) => (
          <button
            key={a.key}
            className="rounded-[2px] px-2 py-1 hover:bg-[rgba(196,125,28,0.06)]"
          >
            <span className="font-mono text-[9.5px] font-semibold uppercase tracking-[0.20em]" style={{ color: INK }}>
              {a.label.toUpperCase()}
            </span>
          </button>
        ))}
        {compact && (
          <span className="font-mono text-[9px] uppercase tracking-[0.18em]" style={{ color: INK_FAINTER }}>
            + {SMART_ACTIONS.length - visibleActions.length} more ↓
          </span>
        )}
      </div>

      <div className="ml-auto flex items-baseline gap-3">
        <button
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em] hover:text-studio-ink"
          style={{ color: INK_FAINT }}
        >
          COPY
        </button>
        <button
          className="rounded-[3px] px-3 py-1.5 font-mono text-[10px] font-semibold uppercase tracking-[0.22em]"
          style={{ background: INK, color: CREAM }}
        >
          SAVE TO LIBRARY →
        </button>
      </div>
    </div>
  );
}

// ─── D. Action list (typeset, two-column, no cards) ──────────────────

function ActionList({ compact }: { compact: boolean }) {
  const half = Math.ceil(SMART_ACTIONS.length / 2);
  const leftCol = SMART_ACTIONS.slice(0, half);
  const rightCol = SMART_ACTIONS.slice(half);

  return (
    <section>
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: INK_FAINT }}>
          · SMART ACTIONS
        </span>
        <span style={{ flex: 1, height: 0.5, background: INK_RULE }} />
        <span className="font-display italic" style={{ color: INK_FAINT, fontSize: 13 }}>
          {SMART_ACTIONS.length} operations · pick one to apply
        </span>
      </div>

      <div
        className="mt-3 grid"
        style={{
          gridTemplateColumns: compact ? "1fr" : "1fr 1fr",
          columnGap: 36,
        }}
      >
        <div>
          {leftCol.map((a) => (
            <ActionRow key={a.key} action={a} />
          ))}
        </div>
        {!compact && (
          <div>
            {rightCol.map((a) => (
              <ActionRow key={a.key} action={a} />
            ))}
          </div>
        )}
        {compact && (
          <div className="hidden">
            {/* hidden — list is single column on compact */}
          </div>
        )}
        {compact && rightCol.length > 0 && (
          <div>
            {rightCol.map((a) => (
              <ActionRow key={a.key} action={a} />
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function ActionRow({ action }: { action: (typeof SMART_ACTIONS)[number] }) {
  return (
    <button
      className="group grid w-full items-baseline border-b py-2.5 transition-colors hover:bg-[rgba(196,125,28,0.04)]"
      style={{
        gridTemplateColumns: "120px 1fr 56px",
        columnGap: 14,
        borderColor: INK_RULE_S,
      }}
    >
      <span className="text-left font-display" style={{ color: INK, fontSize: 15, letterSpacing: "-0.002em" }}>
        {action.label}
      </span>
      <span className="text-left" style={{ color: INK_FAINT, fontSize: 12.5 }}>
        {action.hint}
      </span>
      <span
        className="text-right font-mono text-[9.5px] uppercase tracking-[0.22em] opacity-0 transition-opacity group-hover:opacity-100"
        style={{ color: AMBER }}
      >
        APPLY →
      </span>
    </button>
  );
}

// ─── E. Ownership byline (single italic line, no boxes) ──────────────

function OwnershipByline() {
  return (
    <div className="border-t pt-3" style={{ borderColor: INK_RULE_S }}>
      <p
        className="m-0 font-display italic"
        style={{
          color: INK_FAINT,
          fontSize: 14,
          lineHeight: 1.5,
          letterSpacing: "0.005em",
        }}
      >
        Recorded on <strong style={{ fontStyle: "normal", color: INK }}>MacBook Pro</strong>{" "}
        via <span style={{ color: BRASS, fontStyle: "normal" }}>Parakeet v3</span>, polished with{" "}
        <span style={{ color: BRASS, fontStyle: "normal" }}>Claude Sonnet 4.6</span>, filed to{" "}
        <strong style={{ fontStyle: "normal", color: INK }}>Library</strong>.
      </p>
    </div>
  );
}
