"use client";

import { useState } from "react";
import { SCHEMES } from "@/lib/schemes";
import { Bay, type BayTreatments } from "./Bay";

/**
 * Mac Home — the full macOS Home screen composition.
 *
 * v2: tightened identity on each section.
 *
 *   • Top band         (kept)
 *   • Hero             (subhead added — contextual cadence)
 *   • Capture Modes    (per-card identity — distinct amber treatment + primary verb)
 *   • Agent bay        (kept) — the polished instrument bay
 *   • Routines strip   (RESTORED) — Workflows runs · Agent Console
 *   • Activity table   (row type differentiation — D/M/S badges + per-type meta)
 *   • Discovery row    (RESTORED + textured) — Today / Shortcuts / Trending
 *   • System status    (RESTORED — now a dark recessed rail, mirrors bay)
 *   • Ownership strip  (kept)
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
  { label: "Modern",    keys: ["pearl", "porcelain", "aluminum"] },
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

const BAY_TREATMENTS: BayTreatments = {
  sparkline: true,
  compact: true,
  heatmap: false,
  timeline: false,
  brackets: false,
  bezel: false,
  graticule: true,
};

type CaptureKind = "dictation" | "memo" | "screenshot";

const CAPTURES: { kind: CaptureKind; src: string; line: string; meta: string; when: string }[] = [
  { kind: "dictation", src: "iTerm2", line: "implement all of them and then give us toggles in the same screen using the designer shortcut and to", meta: "186 words", when: "9:34 AM" },
  { kind: "dictation", src: "iTerm2", line: "Let's come up with a few treatments that make this look and feel better or at least like make best u", meta: "142 words", when: "9:28 AM" },
  { kind: "memo",      src: "Voice",  line: "Alright, you gotta be able to see the scroll performance through the instrument lens. If you need to", meta: "0:42",     when: "9:04 PM" },
  { kind: "dictation", src: "iTerm2", line: "Alright, so it's much nicer visually than it was. I think in general the rule of thumb is like thinn", meta: "98 words",  when: "8:37 PM" },
  { kind: "screenshot",src: "Hyper+S",line: "Bay variant comparison — 9 schemes in studio. Captured at 1280×757.",                                  meta: "1280×757", when: "8:26 PM" },
  { kind: "dictation", src: "iTerm2", line: "Yeah, that sounds good. Can you chair pick that? The bridge off stuff seems pretty good. I think I t", meta: "73 words",  when: "8:09 PM" },
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

// 24h event ticks for the Today widget — hour positions on the day
// where something is scheduled.
const TODAY_EVENTS = [
  { hour: 9.5,  label: "09:30 · Design review" },
  { hour: 11,   label: "11:00 · Standup" },
  { hour: 14,   label: "14:00 · Bay polish merge" },
];

export function MacHome() {
  const [bayKey, setBayKey] = useState<string>("chiffon");
  const bayScheme = BAY_SCHEMES.find((s) => s.key === bayKey) ?? BAY_SCHEMES[0];

  return (
    <div
      className="mx-auto rounded-md"
      style={{
        width: "1100px",
        background: "#FBFBFA",
        boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
        border: "0.5px solid #E0DCD3",
      }}
    >
      <TopBand />
      <div className="px-8 pt-4 pb-8">
        <div className="flex flex-col gap-9">
          <Hero />
          <CaptureModes />
          <BayBlock scheme={bayScheme} bayKey={bayKey} onPick={setBayKey} />
          <RoutinesStrip />
          <ActivitySignalTable />
          <DiscoveryRow />
          <SystemStatusRail scheme={bayScheme} />
          <OwnershipStrip />
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Top band — universal "Today" identity rail with chrome trailing.

function TopBand() {
  return (
    <div className="flex items-center gap-3 border-b border-studio-edge px-8 py-3">
      <div className="font-display text-[15px] font-medium tracking-tight text-studio-ink">
        Today
      </div>
      <div className="ml-auto text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
        1K WORDS · 2-DAY STREAK
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Hero — editorial count + contextual cadence subhead.

function Hero() {
  return (
    <div className="flex flex-col gap-1.5">
      <h1 className="m-0 font-display text-[44px] font-medium leading-none tracking-tight text-studio-ink">
        2 captures
      </h1>
      <div className="text-[10px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint">
        Most active <span className="text-studio-ink">09–10</span> · 4 from iTerm2
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────────────
// Capture modes — per-card identity. Each card gets a distinct amber
// glyph (dot · ring · crosshair) and a primary-verb action label. The
// amber-family stays consistent (no rainbow accents); each card varies
// in *how* the amber lives on the surface.

function CaptureModes() {
  return (
    <SectionBlock eyebrow="Capture modes">
      <div className="grid grid-cols-3 gap-4">
        <CaptureCard
          glyph={<DotGlyph />}
          eyebrow="Memo"
          channel="CH-01"
          state="Last · 9:04 PM"
          action="START RECORDING"
          hint="·"
        />
        <CaptureCard
          glyph={<RingGlyph />}
          eyebrow="Dictation"
          channel="CH-02"
          state="5 today · last 9:34 AM"
          action="DICTATE"
          hint="⌃⇧⌘ D"
        />
        <CaptureCard
          glyph={<CrosshairGlyph />}
          eyebrow="Capture"
          channel="CH-03"
          state="1 today · last 8:26 PM"
          action="CAPTURE"
          hint="⌃⇧⌘ S"
        />
      </div>
    </SectionBlock>
  );
}

function DotGlyph() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden>
      <circle cx="11" cy="11" r="4.5" fill="#E89A3C" />
      <circle cx="11" cy="11" r="9" fill="none" stroke="#E89A3C" strokeOpacity="0.18" strokeWidth="1" />
    </svg>
  );
}

function RingGlyph() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden>
      <circle cx="11" cy="11" r="7" fill="none" stroke="#E89A3C" strokeWidth="1.5" />
      <circle cx="11" cy="11" r="1.8" fill="#E89A3C" />
    </svg>
  );
}

function CrosshairGlyph() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" aria-hidden>
      <path d="M 2 4 L 2 2 L 4 2" fill="none" stroke="#E89A3C" strokeWidth="1.2" />
      <path d="M 18 2 L 20 2 L 20 4" fill="none" stroke="#E89A3C" strokeWidth="1.2" />
      <path d="M 2 18 L 2 20 L 4 20" fill="none" stroke="#E89A3C" strokeWidth="1.2" />
      <path d="M 18 20 L 20 20 L 20 18" fill="none" stroke="#E89A3C" strokeWidth="1.2" />
      <circle cx="11" cy="11" r="2.5" fill="#E89A3C" />
    </svg>
  );
}

function CaptureCard({
  glyph,
  eyebrow,
  channel,
  state,
  action,
  hint,
}: {
  glyph: React.ReactNode;
  eyebrow: string;
  channel: string;
  state: string;
  action: string;
  hint: string;
}) {
  return (
    <button className="group flex flex-col rounded-md border border-studio-edge bg-white/40 text-left transition-colors hover:border-studio-ink">
      {/* Identity row */}
      <div className="flex items-center gap-3 px-4 pt-3.5 pb-2.5">
        <span>{glyph}</span>
        <span className="text-[10px] font-semibold uppercase tracking-eyebrow text-studio-ink">
          {eyebrow}
        </span>
        <span className="ml-auto text-[9px] font-mono uppercase tracking-[0.20em] text-studio-ink-faint">
          {channel}
        </span>
      </div>
      {/* State row — single factual line */}
      <div className="border-t border-studio-edge/70 px-4 py-2">
        <div className="text-[10px] font-mono uppercase tracking-[0.16em] text-studio-ink-faint">
          {state}
        </div>
      </div>
      {/* Action row */}
      <div className="flex items-center gap-3 border-t border-studio-edge/70 px-4 py-2.5">
        <div className="text-[9px] font-mono uppercase tracking-[0.20em] text-[#9A6A22] group-hover:text-[#7A521A] transition-colors">
          {action} →
        </div>
        <div className="ml-auto font-mono text-[10px] text-studio-ink-faint">
          {hint}
        </div>
      </div>
    </button>
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
      <div style={scheme.vars as React.CSSProperties}>
        <Bay treatments={BAY_TREATMENTS} />
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
// Activity — captures table with row-type differentiation.

const KIND_BADGE: Record<CaptureKind, { letter: string; label: string }> = {
  dictation:  { letter: "D", label: "Dictation" },
  memo:       { letter: "M", label: "Memo" },
  screenshot: { letter: "S", label: "Screenshot" },
};

function ActivitySignalTable() {
  return (
    <SectionBlock
      eyebrow="Captures"
      trailingLink={{ label: "LIBRARY", href: "#" }}
    >
      <div className="rounded-md border border-studio-edge">
        {CAPTURES.map((c, i) => {
          const badge = KIND_BADGE[c.kind];
          const tint =
            c.kind === "dictation" ? "#E89A3C" :
            c.kind === "memo"      ? "#9A6A22" :
                                     "#6B7A75";
          return (
            <button
              key={i}
              className="group flex w-full items-start gap-4 border-b border-studio-edge/70 px-4 py-3 text-left last:border-b-0 hover:bg-[#F2F2F1]/50"
            >
              <div
                className="flex h-7 w-7 items-center justify-center rounded border font-mono text-[9px] font-bold uppercase tracking-[0.06em]"
                style={{
                  borderColor: `${tint}55`,
                  background: `${tint}10`,
                  color: tint,
                }}
                title={badge.label}
              >
                {badge.letter}
              </div>
              <div className="flex-1 min-w-0">
                <div className="text-[13px] font-medium text-studio-ink">{c.src}</div>
                <div className="text-[12px] text-studio-ink-faint line-clamp-1">{c.line}</div>
              </div>
              <div className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint pt-0.5 w-24 text-right">
                {c.meta}
              </div>
              <div className="text-[9px] font-mono uppercase tracking-[0.18em] text-studio-ink-faint pt-0.5 w-16 text-right">
                {c.when}
              </div>
            </button>
          );
        })}
      </div>
    </SectionBlock>
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
        <TodayWidget />
        <ShortcutsWidget />
        <TrendingWidget />
      </div>
    </SectionBlock>
  );
}

function TodayWidget() {
  // Mini 24h timeline ribbon — ticks every 2 hours, event dots at
  // their hour position. Reads as a day-at-a-glance map.
  return (
    <WidgetCard title="Today" eyebrow="Calendar">
      <div className="flex flex-col gap-3">
        <div className="relative h-7 select-none">
          {/* 24h baseline */}
          <div
            className="absolute left-0 right-0 top-3 h-px"
            style={{ background: "#E0DCD3" }}
          />
          {/* hour ticks every 4h */}
          {[0, 4, 8, 12, 16, 20, 24].map((h) => {
            const left = `${(h / 24) * 100}%`;
            return (
              <div key={h} className="absolute top-2.5 -translate-x-1/2" style={{ left }}>
                <div className="h-1 w-px bg-studio-edge" />
                <div className="mt-1 font-mono text-[7px] tracking-[0.06em] text-studio-ink-faint">
                  {h.toString().padStart(2, "0")}
                </div>
              </div>
            );
          })}
          {/* event dots */}
          {TODAY_EVENTS.map((e, i) => {
            const left = `${(e.hour / 24) * 100}%`;
            return (
              <div
                key={i}
                className="absolute top-1.5 -translate-x-1/2"
                style={{ left }}
                title={e.label}
              >
                <span
                  aria-hidden
                  className="block h-3 w-3 rounded-full"
                  style={{
                    background: "#9A6A22",
                    boxShadow: "0 0 0 2px #FBFBFA",
                  }}
                />
              </div>
            );
          })}
        </div>
        <div className="flex flex-col gap-1 text-[11px]">
          {TODAY_EVENTS.map((e, i) => (
            <div key={i} className="flex justify-between text-studio-ink-faint">
              <span className="font-mono text-[10px] text-studio-ink tracking-[0.02em]">
                {e.label.split(" · ")[0]}
              </span>
              <span>{e.label.split(" · ")[1]}</span>
            </div>
          ))}
        </div>
      </div>
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
