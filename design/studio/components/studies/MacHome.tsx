"use client";

import { useState } from "react";
import { SCHEMES } from "@/lib/schemes";
import { Bay, type BayTreatments } from "./Bay";
import { RecordingHUD } from "./RecordingHUD";

// Hover treatment progression. Default state keeps the bay quiet —
// stat tiles + sparkline + faint graticule. On hover, the bay "wakes"
// and reveals the deeper material study: heatmap (last 7d), corner
// brackets (registration marks), and an inner bezel (subtle material
// highlight). Timeline stays off because it changes layout height;
// the rest are pure overlays.
const BAY_REST: BayTreatments = {
  sparkline: true,
  compact: true,
  heatmap: false,
  timeline: false,
  brackets: false,
  bezel: false,
  graticule: true,
};
const BAY_HOVER: BayTreatments = {
  ...BAY_REST,
  heatmap: true,
  brackets: true,
  bezel: true,
};

/**
 * Mac Home — the full macOS Home screen composition.
 *
 * v4: Bay leads. Hero + Capture Modes dropped.
 *
 * The capture-mode cards were replay-redundant with the Recent two-pane
 * below them (the "Last · 9:04 PM" line on each Mode card just restated
 * the top row of the corresponding sub-band). Folded together: Recent
 * sub-bands now carry the start-it CTA inline as their empty state, so
 * the "begin a memo" affordance lives next to the "your recent memos"
 * surface — one section, two states.
 *
 * Order now:
 *
 *   • Top band         — date strip
 *   • Agent bay        — the instrument-stats moment, leads the page
 *   • Recent · 2-pane  — Voice (Memos + Dictations) | Content (Captures + Notes)
 *   • Routines strip   — Workflows · Console
 *   • Discovery row    — Today · Shortcuts · Trending
 *   • System status    — instrument rail; matches bay scheme
 *   • Ownership strip
 *
 * Empty states in Recent sub-bands render a CTA row in the same row
 * anatomy as a real item (glyph + label + kbd hint) so the section
 * geometry doesn't shift between "you have memos" and "start a memo."
 *
 * Renders on the cream studio canvas, no SchemeCard wrapper — the
 * bay + system rail embed the AMBER scheme inline so the rest of the
 * page stays its natural cream + dark-ink editorial.
 */

// Bay schemes for this study, grouped by theme intent. Light-mode
// canonical bindings:
//   Modern → PEARL    (cool family, lightest)
//   Scope  → CHIFFON  (warm family, lightest)
// PEARL / ALUMINUM and VELLUM / PAPER are siblings within each family —
// available when the canonical pick feels off by one notch. AMBER is
// kept as a reference anchor for the original dark identity.
const BAY_GROUPS: { label: string; keys: string[] }[] = [
  // FROST sits at the cool extreme — even lighter than PEARL, almost
  // disappears into the cream canvas. Use when you want the bay to
  // recede further than the canonical PEARL.
  { label: "Modern",    keys: ["pearl", "frost", "porcelain", "aluminum"] },
  { label: "Scope",     keys: ["chiffon", "vellum", "paper"] },
  { label: "Reference", keys: ["amber"] },
];
const BAY_SCHEMES = BAY_GROUPS.flatMap((g) =>
  g.keys.map((key) => SCHEMES.find((s) => s.key === key)!)
);
// Which scheme is canonical for each theme. The picker marks these so
// it's clear which is the "default" within each group.
const CANONICAL: Record<string, string> = {
  Modern: "pearl",
  Scope:  "chiffon",
};

// Two-pane Recent data — left pane covers Voice (Memos + Dictations),
// right pane covers Content (Captures + Notes). Each row is a single
// glance: glyph + line + meta + time. Lines are intentionally long so
// truncation behavior is visible at the smaller stamp widths.

const RECENT_MEMOS = [
  { line: "Walking thoughts on scope reintegration vs simplification — keep the bay, drop instrument chrome elsewhere", meta: "0:42", when: "9:04 PM" },
  { line: "Quick voice memo about the chrome bar pill alignment — must stay centered or the strip drifts asymmetric", meta: "0:38", when: "Yesterday" },
];

const RECENT_DICTATIONS = [
  { line: "implement all of them and then give us toggles in the same screen using the designer shortcut", meta: "186 words", when: "9:34 AM" },
  { line: "Let's come up with a few treatments that make this look and feel better or at least make best", meta: "142 words", when: "9:28 AM" },
  { line: "Alright, so it's much nicer visually than it was. I think in general the rule of thumb is like", meta: "98 words", when: "8:37 PM" },
];

// Captures intentionally empty — demos the empty-state CTA pattern.
// Real data would look like:
//   { line: "Bay variant comparison — 9 schemes in studio", meta: "1280×757", when: "8:26 PM" }
const RECENT_CAPTURES: { line: string; meta: string; when: string }[] = [];

const RECENT_NOTES = [
  { title: "Studio → native handoff tooling", body: "Token export, Swift-hint annotations, spec overlay. Rejected: animation curve mapping. Start with token export.", attachments: 0, when: "Today" },
  { title: "Theme → scheme bindings (light mode)", body: "Modern → PORCELAIN. Scope → CHIFFON. Sibling ladders for each family.", attachments: 1, when: "Yesterday" },
  { title: "Talkie button — no-sidebar variant won", body: "Mac surfaces anchor the Talkie button in window chrome center, no icon rail.", attachments: 2, when: "Mon" },
];

const WORKFLOW_RUNS = [
  { name: "Summarize standup", at: "9:31 AM", status: "ok" as const },
  { name: "Dictation → Linear", at: "9:14 AM", status: "ok" as const },
  { name: "Compose draft",      at: "Yesterday", status: "stale" as const },
];

const SHORTCUTS = [
  { keys: ["⌃", "⇧", "⌘", "M"], label: "New Memo" },
  { keys: ["⌃", "⇧", "⌘", "D"], label: "Dictate" },
  { keys: ["⌃", "⇧", "⌘", "S"], label: "Capture screen" },
  { keys: ["⌃", "⇧", "⌘", "L"], label: "Library" },
];

const TRENDING_THEMES = [
  { tag: "Standups",       count: 8, max: 8 },
  { tag: "Compose drafts", count: 5, max: 8 },
  { tag: "Code review",    count: 3, max: 8 },
  { tag: "Design notes",   count: 2, max: 8 },
];

// Learn hooks for the Discovery row's Learn widget — small "did you
// know" snippets that surface Talkie features. Replaces the Today
// calendar (felt informational rather than delightful). Material vocab
// mirrors the RecapCard pattern in ScopeLearnScreen.swift.
const LEARN_HOOKS = [
  {
    eyebrow: "Voice edit",
    hook: "Talk back to a memo.",
    detail: "Hit ⌃⇧⌘ E during playback to dictate an edit in place.",
    action: "Try it",
  },
  {
    eyebrow: "Smart actions",
    hook: "Fix grammar with a chip.",
    detail: "Compose has one-tap chips for grammar, concise, and tone.",
    action: "See compose",
  },
  {
    eyebrow: "Tray",
    hook: "Hyper+S, anywhere.",
    detail: "Screenshots drain into your next memo unless you pin them.",
    action: "How it works",
  },
];

/**
 * MacHome accepts a `width` prop so the same composition can be stamped
 * inside `<MacWindowFrame>` at multiple widths (820 / 1180 / 1440).
 *
 * The outer card chrome (shadow, border, background) used to live here
 * but moved to MacWindowFrame so all mac studies share the same window
 * presentation. When MacHome is used standalone (no frame), the caller
 * should wrap it in its own frame — see app/mac-home/page.tsx.
 */
export function MacHome({ width = 1100 }: { width?: number } = {}) {
  const [bayKey, setBayKey] = useState<string>("chiffon");
  const bayScheme = BAY_SCHEMES.find((s) => s.key === bayKey) ?? BAY_SCHEMES[0];

  // Recording state — drives the RecordingHUD overlay (proximity-aware
  // wave that blooms ingredients as cursor approaches). Toggle lives
  // in TopBand. `hudScheme` lets us audition FROST vs PEARL as the
  // HUD's surface material.
  const [recording, setRecording] = useState(false);
  const [hudScheme, setHudScheme] = useState<string>("frost");

  // Inner horizontal padding scales subtly with width — 24px at the
  // compact 820 size (so the 3-col Capture / Discovery rows still
  // breathe), 32px at standard, 40px at wide.
  const padX = width < 900 ? 24 : width >= 1300 ? 40 : 32;

  return (
    <div style={{ width, position: "relative" }}>
      <TopBand
        recording={recording}
        onToggleRecord={() => setRecording((v) => !v)}
        hudScheme={hudScheme}
        onPickHudScheme={setHudScheme}
      />
      <div style={{ paddingLeft: padX, paddingRight: padX, paddingTop: 20, paddingBottom: 32 }}>
        <div
          className="flex flex-col gap-9 transition-opacity duration-500"
          style={{ opacity: recording ? 0.55 : 1 }}
        >
          <BayBlock scheme={bayScheme} bayKey={bayKey} onPick={setBayKey} />
          <RecentTwoPane />
          <RoutinesStrip />
          <DiscoveryRow />
          <SystemStatusRail scheme={bayScheme} />
          <OwnershipStrip />
        </div>
      </div>
      {recording ? <RecordingHUD schemeKey={hudScheme} /> : null}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Top band — universal "Today" identity rail. Also carries the record
// toggle + HUD scheme picker so the recording-state mock can be driven
// from the page without extra studio chrome.

function TopBand({
  recording,
  onToggleRecord,
  hudScheme,
  onPickHudScheme,
}: {
  recording: boolean;
  onToggleRecord: () => void;
  hudScheme: string;
  onPickHudScheme: (k: string) => void;
}) {
  return (
    <div className="flex items-center gap-3 border-b border-studio-edge px-8 py-3">
      <div className="font-display text-[15px] font-medium tracking-tight text-studio-ink">
        Today
      </div>
      <div className="ml-auto flex items-center gap-4">
        {recording ? (
          <div className="flex items-center gap-2">
            <span className="text-[8px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint">
              HUD
            </span>
            {["frost", "pearl"].map((k) => {
              const s = SCHEMES.find((x) => x.key === k)!;
              const active = hudScheme === k;
              return (
                <button
                  key={k}
                  onClick={() => onPickHudScheme(k)}
                  className="flex items-center gap-1.5 rounded-[3px] border px-2 py-1 text-[9px] font-semibold uppercase tracking-[0.18em] transition-colors"
                  style={{
                    borderColor: active ? "#2A2620" : "#E0DCD3",
                    color: active ? "#2A2620" : "#7A746C",
                    background: active ? "#F2F2F1" : "transparent",
                  }}
                >
                  <span
                    aria-hidden
                    className="h-2 w-2 rounded-full"
                    style={{ background: s.swatch }}
                  />
                  {s.name}
                </button>
              );
            })}
          </div>
        ) : (
          <div className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
            1K WORDS · 2-DAY STREAK
          </div>
        )}
        <button
          onClick={onToggleRecord}
          className="flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[9px] font-semibold uppercase tracking-eyebrow transition-colors"
          style={{
            borderColor: recording ? "#C43A1C" : "#E0DCD3",
            color: recording ? "#C43A1C" : "#2A2620",
            background: recording ? "rgba(196,58,28,0.06)" : "transparent",
          }}
        >
          <span
            aria-hidden
            className="inline-block h-1.5 w-1.5 rounded-full"
            style={{
              background: recording ? "#C43A1C" : "#9A6A22",
              boxShadow: recording ? "0 0 4px rgba(196,58,28,0.6)" : "none",
            }}
          />
          {recording ? "Stop" : "Start memo"}
        </button>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Agent bay — reuse the shared Bay artifact, scheme selectable per
// study. ALUMINUM is the current default; the picker lets us audition
// OXIDE / PAPER / AMBER in place without a code edit.

function BayBlock({
  scheme,
  bayKey,
  onPick,
}: {
  scheme: (typeof BAY_SCHEMES)[number];
  bayKey: string;
  onPick: (key: string) => void;
}) {
  const [hovered, setHovered] = useState(false);
  const treatments = hovered ? BAY_HOVER : BAY_REST;
  return (
    <SectionBlock
      eyebrow="Agent"
      trailingControls={
        <div className="flex items-center gap-3">
          {BAY_GROUPS.map((group, idx) => (
            <div key={group.label} className="flex items-center gap-1.5">
              <div className="text-[8px] font-mono uppercase tracking-[0.22em] text-studio-ink-faint mr-0.5">
                {group.label}
              </div>
              {group.keys.map((key) => {
                const s = BAY_SCHEMES.find((x) => x.key === key)!;
                const active = key === bayKey;
                const canonical = CANONICAL[group.label] === key;
                return (
                  <button
                    key={key}
                    onClick={() => onPick(key)}
                    title={canonical ? `${group.label} canonical` : undefined}
                    className="relative flex items-center gap-1.5 rounded-[3px] border px-2 py-1 text-[9px] font-semibold uppercase tracking-[0.18em] transition-colors"
                    style={{
                      borderColor: active ? "#2A2620" : "#E0DCD3",
                      color: active ? "#2A2620" : "#7A746C",
                      background: active ? "#F2F2F1" : "transparent",
                    }}
                  >
                    <span
                      aria-hidden
                      className="h-2 w-2 rounded-full"
                      style={{ background: s.swatch }}
                    />
                    {s.name}
                    {canonical ? (
                      <span
                        aria-hidden
                        className="absolute -top-1 -right-1 h-1.5 w-1.5 rounded-full"
                        style={{
                          background: "#2A2620",
                          boxShadow: "0 0 0 1.5px #FBFBFA",
                        }}
                      />
                    ) : null}
                  </button>
                );
              })}
              {idx < BAY_GROUPS.length - 1 ? (
                <span
                  aria-hidden
                  className="ml-1 h-3 w-px"
                  style={{ background: "#E0DCD3" }}
                />
              ) : null}
            </div>
          ))}
        </div>
      }
    >
      <div
        style={scheme.vars as React.CSSProperties}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        className="transition-[filter] duration-150"
      >
        <Bay treatments={treatments} />
      </div>
    </SectionBlock>
  );
}

// ────────────────────────────────────────────────────────────────────
// Routines strip — Workflows + Console as 2-col band.

function RoutinesStrip() {
  return (
    <SectionBlock eyebrow="Routines">
      <div className="grid grid-cols-2 gap-4">
        <Panel
          title="Workflows"
          trailing="3 ran today"
          rows={WORKFLOW_RUNS.map((r) => ({
            leading: r.status === "ok" ? "●" : "○",
            label: r.name,
            trailing: r.at,
          }))}
          footer={{ label: "MANAGE WORKFLOWS", href: "#" }}
        />
        <Panel
          title="Console"
          trailing="2 tabs · iTerm · Codex"
          rows={[
            { leading: "●", label: "iTerm2", trailing: "ACTIVE" },
            { leading: "●", label: "Codex",  trailing: "IDLE" },
            { leading: "○", label: "Claude", trailing: "OFF" },
          ]}
          footer={{ label: "OPEN CONSOLE", href: "#" }}
        />
      </div>
    </SectionBlock>
  );
}

function Panel({
  title,
  trailing,
  rows,
  footer,
}: {
  title: string;
  trailing: string;
  rows: { leading: string; label: string; trailing: string }[];
  footer: { label: string; href: string };
}) {
  return (
    <div className="flex flex-col rounded-md border border-studio-edge bg-white/40">
      <div className="flex items-baseline gap-3 border-b border-studio-edge px-4 py-2.5">
        <div className="font-display text-[14px] font-medium tracking-tight text-studio-ink">
          {title}
        </div>
        <div className="ml-auto text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          {trailing}
        </div>
      </div>
      <div className="flex flex-col">
        {rows.map((r, i) => (
          <div
            key={i}
            className="flex items-center gap-3 border-b border-studio-edge/60 px-4 py-2 last:border-b-0"
          >
            <span className="font-mono text-[10px] text-[#9A6A22]">{r.leading}</span>
            <span className="text-[12px] text-studio-ink">{r.label}</span>
            <span className="ml-auto text-[9px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
              {r.trailing}
            </span>
          </div>
        ))}
      </div>
      <a
        href={footer.href}
        className="flex items-center justify-end gap-1 px-4 py-2 text-[9px] font-semibold uppercase tracking-eyebrow text-[#9A6A22] hover:text-[#7A521A]"
      >
        {footer.label} <span className="text-[10px]">→</span>
      </a>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Recent · two-pane — Voice (Memos + Dictations) | Content (Captures + Notes).
//
// Replaces the single mixed activity table. Each pane is a card with
// two typed sub-bands separated by an interior hairline. Sub-bands
// share row anatomy (glyph + line + meta + time) so the panes scan as
// one consistent typography even though they cover four primitives.
//
// The pairing isn't arbitrary: Voice items recall by waveform/word
// count (transient, time-stamped), Content items recall by visual or
// excerpted thought (dimensions, title, attachments). Memos +
// Dictations both surface a transcript excerpt; Captures + Notes
// both surface a caption/title with a meta column.

const VOICE_TINT = "#9A6A22";   // brass
const CONTENT_TINT = "#6B7A75"; // slate

function RecentTwoPane() {
  return (
    <SectionBlock
      eyebrow="Recent"
      trailingLink={{ label: "LIBRARY", href: "#" }}
    >
      <div className="grid grid-cols-2 gap-4">
        <RecentPane
          label="Voice"
          tint={VOICE_TINT}
          sections={[
            {
              eyebrow: "Memos",
              count: countLabel(RECENT_MEMOS.length, "today"),
              libraryLink: { label: "ALL MEMOS", href: "#" },
              rows: RECENT_MEMOS.map((m) => ({
                glyph: "●",
                line: m.line,
                meta: m.meta,
                when: m.when,
              })),
              emptyCTA: {
                glyph: "●",
                label: "Start a memo",
                kbd: ["⌃", "⇧", "⌘", "M"],
              },
            },
            {
              eyebrow: "Dictations",
              count: countLabel(RECENT_DICTATIONS.length, "today"),
              libraryLink: { label: "ALL DICTATIONS", href: "#" },
              rows: RECENT_DICTATIONS.map((d) => ({
                glyph: "○",
                line: d.line,
                meta: d.meta,
                when: d.when,
              })),
              emptyCTA: {
                glyph: "○",
                label: "Dictate",
                kbd: ["⌃", "⇧", "⌘", "D"],
              },
            },
          ]}
        />
        <RecentPane
          label="Content"
          tint={CONTENT_TINT}
          sections={[
            {
              eyebrow: "Captures",
              count: countLabel(RECENT_CAPTURES.length, "today"),
              libraryLink: { label: "ALL CAPTURES", href: "#" },
              rows: RECENT_CAPTURES.map((c) => ({
                glyph: "▢",
                line: c.line,
                meta: c.meta,
                when: c.when,
              })),
              emptyCTA: {
                glyph: "▢",
                label: "Capture screen",
                kbd: ["⌃", "⇧", "⌘", "S"],
              },
            },
            {
              eyebrow: "Notes",
              count: countLabel(RECENT_NOTES.length, "this week"),
              libraryLink: { label: "ALL NOTES", href: "#" },
              rows: RECENT_NOTES.map((n) => ({
                glyph: "¶",
                line: n.title,
                body: n.body,
                meta: n.attachments > 0 ? `${n.attachments} attach.` : "",
                when: n.when,
              })),
              emptyCTA: {
                glyph: "¶",
                label: "Write a note",
                kbd: ["⌃", "⇧", "⌘", "N"],
              },
            },
          ]}
        />
      </div>
    </SectionBlock>
  );
}

function countLabel(n: number, suffix: string): string {
  return n === 0 ? `none ${suffix}` : `${n} ${suffix}`;
}

interface RecentRow {
  glyph: string;
  line: string;
  body?: string;
  meta: string;
  when: string;
}

interface RecentSection {
  eyebrow: string;
  count: string;
  libraryLink: { label: string; href: string };
  rows: RecentRow[];
  emptyCTA: { glyph: string; label: string; kbd: string[] };
}

function RecentPane({
  label,
  tint,
  sections,
}: {
  label: string;
  tint: string;
  sections: RecentSection[];
}) {
  return (
    <div className="flex flex-col rounded-md border border-studio-edge bg-white/40">
      <div className="flex items-baseline gap-3 border-b border-studio-edge px-4 py-2.5">
        <span
          aria-hidden
          className="h-1.5 w-1.5 rounded-full"
          style={{ background: tint }}
        />
        <div className="font-display text-[14px] font-medium tracking-tight text-studio-ink">
          {label}
        </div>
        <div className="ml-auto text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          {sections.reduce((sum, s) => sum + s.rows.length, 0)} items
        </div>
      </div>
      <div className="flex flex-col">
        {sections.map((s, idx) => (
          <RecentSubBand
            key={s.eyebrow}
            section={s}
            tint={tint}
            divided={idx > 0}
          />
        ))}
      </div>
    </div>
  );
}

function RecentSubBand({
  section,
  tint,
  divided,
}: {
  section: RecentSection;
  tint: string;
  divided: boolean;
}) {
  const isEmpty = section.rows.length === 0;
  return (
    <div className={divided ? "border-t-2 border-studio-edge/80" : ""}>
      <div className="flex items-baseline gap-3 px-4 pt-2.5 pb-1.5">
        <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
          · {section.eyebrow}
        </div>
        <div className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          {section.count}
        </div>
        <a
          href={section.libraryLink.href}
          className="ml-auto text-[8px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint hover:text-studio-ink"
        >
          {section.libraryLink.label} →
        </a>
      </div>
      <div className="flex flex-col">
        {isEmpty ? (
          <EmptyCTARow cta={section.emptyCTA} tint={tint} />
        ) : (
          section.rows.map((r, i) => (
            <RecentRowView key={i} row={r} tint={tint} />
          ))
        )}
      </div>
    </div>
  );
}

function EmptyCTARow({
  cta,
  tint,
}: {
  cta: { glyph: string; label: string; kbd: string[] };
  tint: string;
}) {
  return (
    <button className="group flex items-center gap-3 border-t border-studio-edge/40 px-4 py-2.5 text-left hover:bg-[#F2F2F1]/50 first:border-t-0">
      <span
        className="font-mono text-[11px] leading-none"
        style={{ color: tint }}
        aria-hidden
      >
        {cta.glyph}
      </span>
      <span className="text-[11px] font-semibold uppercase tracking-eyebrow text-studio-ink group-hover:text-[#7A521A]">
        {cta.label}
      </span>
      <span className="text-[10px] text-studio-ink-faint group-hover:text-studio-ink">→</span>
      <div className="ml-auto flex items-center gap-1">
        {cta.kbd.map((k, i) => (
          <kbd
            key={i}
            className="inline-flex h-4 min-w-[16px] items-center justify-center rounded-[2px] border border-studio-edge bg-white/70 px-1 font-mono text-[9px] text-studio-ink-faint"
          >
            {k}
          </kbd>
        ))}
      </div>
    </button>
  );
}

function RecentRowView({ row, tint }: { row: RecentRow; tint: string }) {
  return (
    <button className="group flex items-start gap-3 border-t border-studio-edge/40 px-4 py-2 text-left hover:bg-[#F2F2F1]/50 first:border-t-0">
      <span
        className="pt-0.5 font-mono text-[11px] leading-none"
        style={{ color: tint }}
        aria-hidden
      >
        {row.glyph}
      </span>
      <div className="min-w-0 flex-1">
        <div className="text-[12px] text-studio-ink line-clamp-1">{row.line}</div>
        {row.body ? (
          <div className="mt-0.5 text-[11px] text-studio-ink-faint line-clamp-1">
            {row.body}
          </div>
        ) : null}
      </div>
      <div className="flex shrink-0 flex-col items-end pt-0.5">
        {row.meta ? (
          <div className="text-[9px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
            {row.meta}
          </div>
        ) : null}
        <div className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint/80">
          {row.when}
        </div>
      </div>
    </button>
  );
}

// ────────────────────────────────────────────────────────────────────
// Discovery row — Today / Shortcuts / Trending, each with a tailored
// visual treatment so they read as distinct surfaces, not three flat
// lists.

function DiscoveryRow() {
  return (
    <SectionBlock eyebrow="Discovery">
      <div className="grid grid-cols-3 gap-4">
        <LearnWidget />
        <ShortcutsWidget />
        <TrendingWidget />
      </div>
    </SectionBlock>
  );
}

// Learn widget — replaced the Today calendar. Surfaces a rotating
// "did you know" hook from the Learn screen's RecapCard vocabulary:
// eyebrow + serif hook + body + action. Reads as editorial discovery
// (not a dashboard widget) so it lifts the midsection.
function LearnWidget() {
  const hook = LEARN_HOOKS[0];
  return (
    <WidgetCard title="Learn" eyebrow="Did you know">
      <button className="group flex flex-col gap-2 text-left">
        <div className="font-mono text-[8.5px] uppercase tracking-[0.22em]" style={{ color: "#9A6A22" }}>
          · {hook.eyebrow}
        </div>
        <div className="font-display text-[15px] font-medium leading-snug tracking-tight text-studio-ink">
          {hook.hook}
        </div>
        <div className="text-[11px] leading-snug text-studio-ink-faint">
          {hook.detail}
        </div>
        <div className="mt-auto pt-1.5 text-[9px] font-mono uppercase tracking-[0.22em] text-[#9A6A22] group-hover:text-[#7A521A]">
          {hook.action} →
        </div>
      </button>
    </WidgetCard>
  );
}

function ShortcutsWidget() {
  return (
    <WidgetCard title="Shortcuts" eyebrow="Keyboard">
      <div className="flex flex-col gap-2">
        {SHORTCUTS.map((s) => (
          <div key={s.keys.join("")} className="flex items-center gap-2.5 text-[11px]">
            <div className="flex items-center gap-1">
              {s.keys.map((k, i) => (
                <kbd
                  key={i}
                  className="inline-flex h-5 min-w-[20px] items-center justify-center rounded-[3px] border border-studio-edge bg-white/70 px-1 font-mono text-[10px] text-studio-ink shadow-[0_1px_0_rgba(0,0,0,0.04)]"
                >
                  {k}
                </kbd>
              ))}
            </div>
            <span className="ml-1 text-studio-ink-faint">{s.label}</span>
          </div>
        ))}
      </div>
    </WidgetCard>
  );
}

function TrendingWidget() {
  // Tag + horizontal bar + count. Reads as a mini histogram, not a list.
  return (
    <WidgetCard title="Trending" eyebrow="This week">
      <div className="flex flex-col gap-2.5">
        {TRENDING_THEMES.map((t) => {
          const pct = (t.count / t.max) * 100;
          return (
            <div key={t.tag} className="flex items-baseline gap-3 text-[11px]">
              <span className="w-[120px] truncate text-studio-ink">{t.tag}</span>
              <div className="relative h-1.5 flex-1 overflow-hidden rounded-[1px]" style={{ background: "#EAE6DC" }}>
                <div
                  className="absolute inset-y-0 left-0"
                  style={{ width: `${pct}%`, background: "#9A6A22" }}
                />
              </div>
              <span className="w-5 text-right font-mono text-[10px] text-studio-ink-faint">
                {t.count}
              </span>
            </div>
          );
        })}
      </div>
    </WidgetCard>
  );
}

function WidgetCard({
  title,
  eyebrow,
  children,
}: {
  title: string;
  eyebrow: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3 rounded-md border border-studio-edge bg-white/40 px-4 py-3">
      <div className="flex items-baseline gap-3 border-b border-studio-edge/70 pb-2">
        <div className="font-display text-[13px] font-medium tracking-tight text-studio-ink">
          {title}
        </div>
        <div className="ml-auto text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
          {eyebrow}
        </div>
      </div>
      {children}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// System status — RESTORED, scheme-aware. The footer rail wears the
// same scheme as the bay above it: on dark schemes (AMBER) it reads
// as a gunmetal recessed rail; on light schemes (PEARL / CHIFFON) it
// becomes a near-invisible chrome strip with subtle dotted indicators.
// The bay + rail share scheme so they read as the two ends of the
// same instrument body.

function SystemStatusRail({ scheme }: { scheme: (typeof BAY_SCHEMES)[number] }) {
  const isDark = scheme.key === "amber"; // could expand to other dark schemes later
  return (
    <div
      style={scheme.vars as React.CSSProperties}
      className="rounded-md border font-mono"
    >
      <div
        className="flex items-center gap-5 rounded-md px-4 py-2.5"
        style={{
          background: "var(--scheme-strip-bottom)",
          borderColor: "var(--scheme-edge)",
          boxShadow: isDark
            ? "inset 0 1px 0 rgba(255,255,255,0.04), 0 1px 0 rgba(0,0,0,0.20)"
            : "inset 0 1px 0 rgba(255,255,255,0.40), 0 1px 0 rgba(0,0,0,0.04)",
        }}
      >
        <PhosphorStatus label="AGENT" detail="AG-01 · RUNNING" ok dark={isDark} />
        <Divider />
        <PhosphorStatus label="BRIDGE" detail="LOCAL · CONNECTED" ok dark={isDark} />
        <Divider />
        <PhosphorStatus label="ICLOUD" detail="SYNCED" ok dark={isDark} />
        <Divider />
        <PhosphorStatus label="UPDATES" detail="V2.5.28 · CURRENT" muted dark={isDark} />
        <div
          className="ml-auto text-[8px] uppercase tracking-[0.22em]"
          style={{ color: "var(--scheme-ink-subtle)" }}
        >
          PID 50658 · UPTIME 4H 12M
        </div>
      </div>
    </div>
  );
}

function PhosphorStatus({
  label,
  detail,
  ok,
  muted,
  dark,
}: {
  label: string;
  detail: string;
  ok?: boolean;
  muted?: boolean;
  dark?: boolean;
}) {
  const dotColor = muted
    ? "var(--scheme-ink-subtle)"
    : ok
    ? "var(--scheme-accent)"
    : "var(--scheme-rec)";
  return (
    <div className="flex items-baseline gap-2">
      <span
        aria-hidden
        className="h-1.5 w-1.5 rounded-full"
        style={{
          background: dotColor,
          boxShadow: muted || !dark ? "none" : `0 0 4px var(--scheme-accent-glow)`,
        }}
      />
      <span
        className="text-[8px] font-semibold tracking-[0.22em]"
        style={{ color: "var(--scheme-ink-faint)" }}
      >
        {label}
      </span>
      <span
        className="text-[8px] tracking-[0.18em]"
        style={{ color: "var(--scheme-ink-subtle)" }}
      >
        {detail}
      </span>
    </div>
  );
}

function Divider() {
  return (
    <span
      aria-hidden
      className="h-3 w-px"
      style={{ background: "var(--scheme-edge)" }}
    />
  );
}

// ────────────────────────────────────────────────────────────────────
// Ownership strip — kept. Devices · iCloud · External models.

function OwnershipStrip() {
  return (
    <div className="grid grid-cols-3 gap-10 pt-2 text-[11px]">
      <OwnershipCol label="U1" title="Your devices" detail="LOCAL LIBRARY" />
      <OwnershipCol label="U2" title="Your iCloud" detail="PRIVATE SYNC" />
      <OwnershipCol label="U3" title="External models" detail="OPT-IN · YOUR KEYS" />
    </div>
  );
}

function OwnershipCol({
  label,
  title,
  detail,
}: {
  label: string;
  title: string;
  detail: string;
}) {
  return (
    <div className="flex items-baseline gap-3">
      <span className="font-mono text-[10px] text-studio-ink-faint">{label}</span>
      <div className="flex-1 border-t border-studio-edge pt-2">
        <div className="font-display text-[14px] font-medium tracking-tight text-studio-ink">
          {title}
        </div>
        <div className="mt-0.5 text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
          {detail}
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Section wrapper.

function SectionBlock({
  eyebrow,
  trailingLink,
  trailingControls,
  children,
}: {
  eyebrow: string;
  trailingLink?: { label: string; href: string };
  trailingControls?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section>
      <div className="mb-3 flex items-baseline gap-3">
        <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
          · {eyebrow}
        </div>
        {trailingLink ? (
          <a
            href={trailingLink.href}
            className="ml-auto flex items-center gap-1 text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint hover:text-studio-ink"
          >
            {trailingLink.label} <span className="text-[10px]">→</span>
          </a>
        ) : null}
        {trailingControls ? <div className="ml-auto">{trailingControls}</div> : null}
      </div>
      {children}
    </section>
  );
}
