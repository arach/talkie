"use client";

/**
 * Mac Dictation Detail — current vs proposed, rendered at wide width
 * where the problems are most visible.
 *
 * What today's surface (TalkieView in a dictation context) looks like
 * when the window is at 1680–1920px:
 *   - The body column stays narrow (~640pt) and gets centered, leaving
 *     a huge slab of dead cream on the right.
 *   - Metadata bits drift to the far right edge ("FILED · created
 *     22 Apr") as orphan labels, miles from the content they describe.
 *   - The action chips (COPY SHARE EXPORT ⋯) hang up at the top-left
 *     of the pane, isolated from both the body and the metadata.
 *   - MEDIA / READOUT / SCRATCHPAD sit as small utility tiles inside
 *     the narrow column, framed by all that empty space.
 *
 * Variant II keeps the same wide canvas and actually uses it: body
 * holds its measure cap, but the margin column anchors to the right
 * edge, the player rail spans full-bleed across the foot, and the
 * dead-space goes away.
 *
 * Palette: cool gray (2026-05-21 canon) — see lib/scope-tokens.ts.
 */

import React from "react";
import { SCOPE } from "@/lib/scope-tokens";

// Local alias — keeps the existing T.* call sites terse. Source of truth
// is lib/scope-tokens.ts. Mapping inkRule → SCOPE.rule, inkRuleS → SCOPE.ruleSubtle
// preserves the historical token names used in this file.
const T = {
  page:       SCOPE.canvas,
  pane:       SCOPE.pane,
  paneLifted: SCOPE.paneLifted,
  chrome:     SCOPE.chrome,
  rail:       SCOPE.rail,
  selection:  SCOPE.selection,
  ink:        SCOPE.ink,
  inkFaint:   SCOPE.inkFaint,
  inkFainter: SCOPE.inkFainter,
  inkRule:    SCOPE.rule,
  inkRuleS:   SCOPE.ruleSubtle,
  edge:       SCOPE.edge,
  ruleSoft:   SCOPE.ruleSoft,
  amber:      SCOPE.amber,
  brass:      SCOPE.brass,
  dictTint:   SCOPE.dictTint,
};

const PANE_WIDTH = 1680;
const GUTTER_WIDTH = 280; // compressed library list on the left

// ─── Stub dictation content ──────────────────────────────────────────

const DICT = {
  sequence: "M-0418",
  channel: "CH-02 · DICTATION",
  date: "Yesterday",
  time: "11:46 PM",
  timestampTitle: "Yesterday at 11:46 PM",
  derivedTitle: "No record to talk to — restore from agent",
  duration: "0:38",
  words: 47,
  provenance: "iTerm2",
  device: "MacBook Pro",
  model: "Parakeet v3",
  paragraphs: [
    "No record to talk to. As soon as you say what to do, that's what I'm able to do. The agent's still warm so the bridge should be honest about it. We can clean up a little bit the treatment for captures and I suppose also for notes let's see.",
    "No notes are c yeah, so notes detail or individual notes very ugly. The way we do it traditionally is we set it up in studio, clean it up, and then bring it back into the iOS. Sorry, the Mac OS side.",
  ],
};

// ──────────────────────────────────────────────────────────────────────
// Composition root

export function MacDictationDetail() {
  return (
    <div className="mx-auto flex flex-col items-center gap-14">
      <CurrentVariant />
      <ProposedVariant />
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Variant I — current state, at wide width (the dead-space problem)

function CurrentVariant() {
  return (
    <div className="flex flex-col gap-4" style={{ width: PANE_WIDTH }}>
      <VariantHeader
        eyebrow="· I · CURRENT @ 1680"
        title="Today's dictation detail — wide-display version"
        hint="body stays narrow · metadata orphaned at the edges · dead cream right"
      />
      <PaneFrame>
        <CurrentPane />
      </PaneFrame>
    </div>
  );
}

function CurrentPane() {
  return (
    <div className="flex" style={{ minHeight: 840 }}>
      <LibraryGutter />
      <div className="flex-1 relative" style={{ background: T.pane }}>
        {/* Top revision strip — full-width hairline-bordered band */}
        <div
          className="flex items-center gap-3 px-6 py-2.5"
          style={{ borderBottom: `0.5px solid ${T.inkRuleS}`, background: T.chrome }}
        >
          <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
            M-FWAP
          </span>
          <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
            · SELECTION
          </span>
          <div className="ml-auto flex items-center gap-2">
            <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFainter }}>
              COPY
            </span>
            <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFainter }}>
              SHARE
            </span>
            <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFainter }}>
              EXPORT
            </span>
            <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFainter }}>
              ⋯
            </span>
          </div>
        </div>

        {/* The body. Narrow column, intentionally centered to evoke the
            real surface. NOTE the huge right-side cream slab — that's the
            point of this study. */}
        <div className="flex">
          <div style={{ flex: "0 0 720px", paddingLeft: 56, paddingRight: 24, paddingTop: 28, paddingBottom: 24 }}>
            <div className="flex items-baseline gap-3 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
              <span>SELECTION</span>
            </div>
            <h2 className="mt-2 font-display font-medium" style={{ fontSize: 30, lineHeight: 1.15, color: T.ink }}>
              {DICT.timestampTitle}
            </h2>
            <div className="mt-1 font-mono text-[10px]" style={{ color: T.inkFaint }}>
              :88 · 1) Oenot - simple ou boord
            </div>

            {DICT.paragraphs.map((p, i) => (
              <p key={i} className="mt-4" style={{ fontSize: 13, lineHeight: 1.65, color: T.ink }}>
                {p}
              </p>
            ))}

            <div className="mt-5 flex items-center gap-2">
              <Chip label="Copy" />
              <Chip label="⚡ Workflows" />
            </div>

            {/* Stacked utility sections, each a small tile */}
            <div className="mt-6">
              <SectionLabel label="MEDIA · 1" />
              <div
                className="mt-2 inline-flex h-[60px] w-[120px] items-center justify-center"
                style={{
                  background: T.paneLifted,
                  border: `0.5px solid ${T.inkRuleS}`,
                  borderRadius: 2,
                }}
              >
                <span className="font-mono text-[9px]" style={{ color: T.inkFainter }}>
                  thumb
                </span>
              </div>
            </div>

            <div className="mt-5">
              <SectionLabel label="READOUT" />
              <div
                className="mt-2 flex items-center gap-3 px-3 py-2.5"
                style={{
                  background: T.paneLifted,
                  border: `0.5px solid ${T.inkRuleS}`,
                  borderRadius: 3,
                }}
              >
                <span
                  className="flex h-7 w-7 items-center justify-center rounded-full text-[10px]"
                  style={{ background: "#FFFFFF", border: `0.5px solid ${T.inkRule}`, color: T.ink }}
                >
                  ▶
                </span>
                <div className="flex flex-col gap-0.5">
                  <span style={{ fontSize: 11, color: T.ink }}>On-device voice</span>
                  <span className="font-mono text-[9px]" style={{ color: T.inkFaint }}>
                    Play to read aloud, or generate cloud audio
                  </span>
                </div>
                <div className="ml-auto rounded-[2px] px-2 py-1 font-mono text-[9px] uppercase tracking-[0.18em]" style={{ background: T.amber, color: "#F8F8F7" }}>
                  Generate
                </div>
              </div>
            </div>

            <div className="mt-5 mb-6">
              <SectionLabel label="SCRATCHPAD" />
              <div
                className="mt-2 h-[80px] w-full"
                style={{
                  background: T.paneLifted,
                  border: `0.5px solid ${T.inkRuleS}`,
                  borderRadius: 3,
                }}
              />
            </div>
          </div>

          {/* The dead slab. Body ends at ~720pt, the pane is ~1400 — so
              there's a ~680pt empty cream sweep with two orphan
              metadata labels floating at the top edge. */}
          <div className="flex-1 relative" style={{ minHeight: 600 }}>
            <div className="absolute right-12 top-7 flex flex-col gap-3">
              <DashRow label="FILED" rows={[["created", "22 Apr, 7:48 AM"]]} />
              <DashRow label="RUNTIME" rows={[["words", "40"]]} accent />
              <DashRow label="SOURCE" rows={[["device", "iPhone"]]} />
            </div>
            {/* The rest of this column is just empty cream. */}
          </div>
        </div>
      </div>
    </div>
  );
}

function Chip({ label }: { label: string }) {
  return (
    <span
      className="rounded-[3px] px-2 py-1 font-mono text-[10px]"
      style={{ background: T.chrome, border: `0.5px solid ${T.inkRule}`, color: T.inkFaint }}
    >
      {label}
    </span>
  );
}

function SectionLabel({ label }: { label: string }) {
  return (
    <span
      className="font-mono text-[9px] font-semibold uppercase tracking-[0.28em]"
      style={{ color: T.inkFaint }}
    >
      {label}
    </span>
  );
}

function DashRow({
  label,
  rows,
  accent,
}: {
  label: string;
  rows: [string, string][];
  accent?: boolean;
}) {
  return (
    <div className="min-w-[140px]">
      <div className="font-mono text-[8.5px] font-semibold uppercase tracking-[0.30em]" style={{ color: T.inkFaint }}>
        · {label}
      </div>
      <div className="mt-1.5 flex flex-col gap-1">
        {rows.map(([k, v]) => (
          <div key={k} className="flex items-baseline justify-between gap-3">
            <span className="font-mono text-[9px] uppercase tracking-[0.14em]" style={{ color: T.inkFaint }}>
              {k}
            </span>
            <span className="font-mono text-[10px]" style={{ color: accent ? T.brass : T.ink }}>
              {v}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Variant II — proposed, at the same wide width (uses the space)

function ProposedVariant() {
  return (
    <div className="flex flex-col gap-4" style={{ width: PANE_WIDTH }}>
      <VariantHeader
        eyebrow="· II · PROPOSED @ 1680"
        title="Editorial dictation that uses the wide canvas"
        hint="margin column anchors right · player rail spans full · no dead cream"
      />
      <PaneFrame>
        <ProposedPane />
      </PaneFrame>
    </div>
  );
}

function ProposedPane() {
  return (
    <div className="flex flex-col" style={{ minHeight: 840 }}>
      <div className="flex flex-1">
        <LibraryGutter />
        <div className="flex flex-1" style={{ background: T.pane }}>
          <BodyColumn />
          <MarginColumn />
        </div>
      </div>
      {/* Player rail spans the full width of the detail area
          (everything to the right of the library gutter). */}
      <div className="flex">
        <div style={{ width: GUTTER_WIDTH }} />
        <div className="flex-1">
          <PlayerRail />
        </div>
      </div>
    </div>
  );
}

function BodyColumn() {
  return (
    <div
      className="flex-1"
      style={{ paddingLeft: 80, paddingRight: 56, paddingTop: 48, paddingBottom: 32 }}
    >
      <div className="flex items-baseline gap-3 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.inkFaint }}>
        <span style={{ color: T.dictTint, fontWeight: 600 }}>{DICT.sequence}</span>
        <span>· {DICT.channel}</span>
        <span className="flex-1 border-t" style={{ borderColor: T.inkRuleS }} />
        <span>{DICT.date} · {DICT.time}</span>
      </div>

      <h2
        className="mt-3 font-display font-medium tracking-tight"
        style={{ fontSize: 32, lineHeight: 1.12, color: T.ink, maxWidth: 820 }}
      >
        {DICT.derivedTitle}
      </h2>

      <div className="mt-2 font-mono text-[10px] uppercase tracking-[0.16em]" style={{ color: T.inkFaint }}>
        {DICT.duration} · {DICT.words} words · {DICT.provenance} · {DICT.device} · {DICT.model}
      </div>

      {/* Inline action row — Copy / Share / Workflows / Export / Delete.
          Pulled off the top-right corner where COPY · SHARE · EXPORT · ⋯
          previously hung. Sits between the byline and the transcript so
          the user's hand finds them next to the content they act on.
          Primary action (Copy) carries amber; Delete stays visible but
          subdued at the trailing edge instead of buried in the overflow. */}
      <div className="mt-4 flex items-center gap-2" style={{ maxWidth: 720 }}>
        <InlineAction icon="⎘" label="Copy" isPrimary />
        <InlineAction icon="⚡" label="Workflows" />
        <InlineAction icon="↑" label="Share" />
        <InlineAction icon="↓" label="Export" />
        <span className="mx-1 h-3 w-px" style={{ background: T.inkRule, opacity: 0.4 }} />
        <InlineAction icon="✎" label="Edit" />
        <InlineAction icon="✕" label="Delete" tone="danger" />
        <div className="flex-1" />
        <InlineAction icon="⋯" label={null} compact />
      </div>

      {/* Transcript stays measure-capped even on a wide canvas — reading
          rhythm beats stretching the prose. */}
      <div className="relative mt-7" style={{ maxWidth: 720 }}>
        <span
          aria-hidden
          className="absolute top-0 bottom-0"
          style={{ left: -18, width: 1, background: T.dictTint, opacity: 0.32 }}
        />
        {DICT.paragraphs.map((p, i) => (
          <p
            key={i}
            className={i === 0 ? "mb-3 font-display" : "mb-3"}
            style={
              i === 0
                ? { fontSize: 16, lineHeight: 1.6, color: T.ink }
                : { fontSize: 14, lineHeight: 1.7, color: T.ink }
            }
          >
            {i === 0 && (
              <span className="mr-2 font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: T.brass }}>
                0:00 ·
              </span>
            )}
            {p}
          </p>
        ))}
      </div>
    </div>
  );
}

function MarginColumn() {
  return (
    <aside
      style={{
        flex: "0 0 320px",
        paddingLeft: 28,
        paddingRight: 48,
        paddingTop: 48,
        paddingBottom: 32,
        borderLeft: `0.5px solid ${T.inkRuleS}`,
      }}
    >
      {/* Actions migrated to the inline row beneath the byline. The
          rail now carries only metadata particulars — Provenance,
          Transcription, Timing, Context — properly aligned, no wraps. */}
      <div>
        <RailMeta
          label="Provenance"
          rows={[
            ["modified", "12m ago"],
            ["source", "iTerm2 · MacBook Pro"],
            ["origin", "headless agent"],
          ]}
        />
      </div>
      <div className="mt-6">
        <RailMeta
          label="Transcription"
          rows={[
            ["model", "Parakeet v3"],
            ["confidence", "94.2%"],
            ["end-to-end", "1.34 s"],
          ]}
          accentRow="model"
        />
      </div>
      <div className="mt-6">
        <RailMeta
          label="Stats"
          rows={[
            ["duration", DICT.duration],
            ["words", String(DICT.words)],
          ]}
        />
      </div>
    </aside>
  );
}

function ActionsBlock() {
  return (
    <div className="flex flex-col gap-1">
      <div className="font-mono text-[8.5px] font-semibold uppercase tracking-[0.30em]" style={{ color: T.inkFaint }}>
        · ACTIONS
      </div>
      <RailAction icon="✎" label="Edit" isPrimary />
      <RailAction icon="⎘" label="Copy" />
      <RailAction icon="★" label="Star" />
      <RailAction icon="↑" label="Share" />
      <RailAction icon="↓" label="Export" />
      <RailAction icon="⚡" label="Workflows" />
      <div className="my-1 h-px" style={{ background: T.inkRuleS }} />
      <RailAction icon="⋯" label="More" />
    </div>
  );
}

// Inline action chip used in the proposed body action row. Lives next
// to the byline so Copy / Share / Export / Delete are reachable in the
// document context, not floating in the top corner.
function InlineAction({
  icon,
  label,
  isPrimary,
  compact,
  tone,
}: {
  icon: string;
  label: string | null;
  isPrimary?: boolean;
  compact?: boolean;
  tone?: "danger";
}) {
  const fg =
    tone === "danger" ? SCOPE.alertSoft
    : isPrimary ? T.brass
    : T.inkFaint;
  const bg =
    isPrimary ? "rgba(196,125,28,0.08)" : "transparent";
  const border =
    isPrimary ? "rgba(196,125,28,0.32)" : T.inkRule;
  return (
    <div
      className="flex items-center gap-1.5 rounded-[3px] px-2"
      style={{
        height: 24,
        color: fg,
        background: bg,
        border: `0.5px solid ${border}`,
        paddingLeft: compact ? 6 : 8,
        paddingRight: compact ? 6 : 8,
      }}
    >
      <span style={{ fontSize: 11, lineHeight: 1, width: 12, textAlign: "center" }}>{icon}</span>
      {label && (
        <span
          className="font-mono uppercase"
          style={{
            fontSize: 9.5,
            letterSpacing: "0.14em",
            fontWeight: isPrimary ? 600 : 500,
          }}
        >
          {label}
        </span>
      )}
    </div>
  );
}

function RailAction({
  icon,
  label,
  isPrimary,
}: {
  icon: string;
  label: string;
  isPrimary?: boolean;
}) {
  return (
    <div
      className="flex items-center gap-2 rounded-[3px] px-2 py-1.5"
      style={{
        color: isPrimary ? T.brass : T.inkFaint,
        background: isPrimary ? "rgba(196,125,28,0.07)" : "transparent",
      }}
    >
      <span style={{ fontSize: 12, width: 14, textAlign: "center" }}>{icon}</span>
      <span style={{ fontSize: 12, fontWeight: isPrimary ? 500 : 400 }}>{label}</span>
    </div>
  );
}

function RailMeta({
  label,
  rows,
  accentRow,
}: {
  label: string;
  rows: [string, string][];
  accentRow?: string;
}) {
  return (
    <div>
      <div className="font-mono text-[8.5px] font-semibold uppercase tracking-[0.30em]" style={{ color: T.inkFaint }}>
        · {label}
      </div>
      <div className="mt-2 flex flex-col gap-1.5">
        {rows.map(([k, v]) => (
          <div key={k} className="flex items-baseline justify-between gap-3">
            <span className="font-mono text-[9px] uppercase tracking-[0.14em]" style={{ color: T.inkFaint }}>
              {k}
            </span>
            <span className="font-mono text-[10px]" style={{ color: accentRow === k ? T.brass : T.ink }}>
              {v}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function PlayerRail() {
  return (
    <div
      className="flex items-center gap-4 px-12 py-3"
      style={{
        background: T.rail,
        borderTop: `0.5px solid ${T.inkRuleS}`,
      }}
    >
      <button
        className="flex h-7 w-7 items-center justify-center rounded-full text-[12px]"
        style={{ background: T.amber, color: "#F8F8F7", boxShadow: "0 0 0 2px rgba(196,125,28,0.18)" }}
      >
        ▶
      </button>
      <div className="flex-1">
        <PlayerWave />
      </div>
      <span className="font-mono text-[10px]" style={{ color: T.ink }}>
        0:00 / {DICT.duration}
      </span>
    </div>
  );
}

function PlayerWave() {
  // Wide waveform — more bars to actually fill the breadth.
  const peaks = [
    4,6,9,12,8,14,11,7,5,9,13,16,12,10,15,18,14,11,8,6,10,13,9,7,11,14,17,13,
    10,8,12,15,11,9,6,8,11,14,10,7,5,9,12,15,11,8,6,4,7,10,13,9,6,8,11,7,5,
    9,12,15,11,8,6,4,7,10,13,9,6,8,11,7,5,9,12,15,11,8,6,4,7,10,13,9,6
  ];
  return (
    <svg width="100%" height="22" viewBox={`0 0 ${peaks.length * 4} 22`} preserveAspectRatio="none" aria-hidden>
      {peaks.map((p, i) => (
        <rect key={i} x={i * 4} y={(22 - p) / 2} width={2.5} height={p} fill={T.brass} opacity={0.55} />
      ))}
    </svg>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Shared shells

function LibraryGutter() {
  return (
    <div
      style={{ flex: `0 0 ${GUTTER_WIDTH}px`, background: T.page, borderRight: `0.5px solid ${T.inkRuleS}` }}
    >
      <div
        className="flex items-center gap-2 px-3 py-2.5"
        style={{ borderBottom: `0.5px solid ${T.inkRuleS}`, background: T.chrome }}
      >
        <span className="font-mono text-[8px] uppercase tracking-[0.28em]" style={{ color: T.inkFaint }}>
          · TODAY
        </span>
      </div>
      {Array.from({ length: 14 }).map((_, i) => (
        <div
          key={i}
          className="flex items-center gap-2 px-3 py-1.5"
          style={{
            borderBottom: `0.5px solid ${T.ruleSoft}`,
            background: i === 4 ? T.selection : "transparent",
          }}
        >
          <span
            className="flex h-4 w-4 items-center justify-center rounded-full font-mono text-[8px] font-bold"
            style={{
              color: T.dictTint,
              background: `${T.dictTint}14`,
              border: `0.5px solid ${T.dictTint}55`,
            }}
          >
            D
          </span>
          <span className="truncate text-[11px]" style={{ color: i === 4 ? T.ink : T.inkFaint }}>
            {i === 4 ? "Yesterday at 11:46 PM" : `Dictation ${50 - i}`}
          </span>
        </div>
      ))}
    </div>
  );
}

function VariantHeader({
  eyebrow,
  title,
  hint,
}: {
  eyebrow: string;
  title: string;
  hint?: string;
}) {
  return (
    <div className="flex items-baseline gap-4 border-b pb-3" style={{ borderColor: T.edge }}>
      <div>
        <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.30em]" style={{ color: T.inkFaint }}>
          {eyebrow}
        </div>
        <h3 className="m-0 font-display font-medium" style={{ fontSize: 19, lineHeight: 1, color: T.ink, letterSpacing: "-0.01em" }}>
          {title}
        </h3>
      </div>
      {hint && (
        <div className="ml-auto font-mono text-[10px] uppercase tracking-[0.18em]" style={{ color: T.inkFaint }}>
          {hint}
        </div>
      )}
    </div>
  );
}

function PaneFrame({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="rounded-md overflow-hidden"
      style={{
        background: T.page,
        boxShadow: "0 8px 30px rgba(0,0,0,0.06), 0 2px 6px rgba(0,0,0,0.04)",
        border: `0.5px solid ${T.edge}`,
      }}
    >
      <WindowChrome />
      {children}
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
      </div>
    </div>
  );
}
