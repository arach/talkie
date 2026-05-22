"use client";

import React from "react";
import { StudioPage } from "@/components/StudioPage";

/**
 * Mac Talkie — Library "no selection" empty state.
 *
 * When the user lands on Library but hasn't picked a memo, the detail
 * pane today shows a generic placeholder. On a big canvas that's a
 * wasted slab. These three variants honor the same space in different
 * editorial registers — all on the cream paper, all quiet, none of
 * them lean on marketing copy.
 *
 *   I.   Daybook — today as a frontispiece. Date in monumental serif,
 *                  today's tally, today's memos as a typeset index.
 *   II.  Contents — week-long typeset table of contents. Most utilitarian.
 *   III. Pullquote — a single excerpt from recent activity, surfaced
 *                    as a monumental pullquote with byline. Most poetic.
 */

const TALKIE_INK = "#232423";
const TALKIE_INK_FAINT = "rgba(35,36,35,0.55)";
const TALKIE_INK_FAINTER = "rgba(35,36,35,0.32)";
const TALKIE_CREAM = "#F8F8F7";
const TALKIE_PAPER = "#E7E7E6";
const SCOPE_AMBER = "#C47D1C";

// Mock memo data — used across all three variants.
const TODAY_MEMOS = [
  { time: "9:14 AM", title: "Mast tooling diff plan", duration: "1:02", words: 184 },
  { time: "11:38 AM", title: "Chrome bar consolidation", duration: "0:42", words: 88 },
  { time: "1:05 PM", title: "Notch flicker — sequence counter", duration: "2:11", words: 312 },
  { time: "3:42 PM", title: "Recording → memo transition", duration: "0:14", words: 32 },
];

const WEEK_MEMOS = [
  { date: "Mon 13", time: "10:22 AM", title: "Sidebar replacement scope", duration: "3:48", scope: "Library" },
  { date: "Mon 13", time: "4:15 PM", title: "Engine fallback for Parakeet keyboard path", duration: "1:22", scope: "Dictations" },
  { date: "Tue 14", time: "9:01 AM", title: "Studio ↔ native handoff tooling", duration: "2:35", scope: "Compose" },
  { date: "Wed 15", time: "11:48 AM", title: "Tray drag pattern — onDrag wins", duration: "0:48", scope: "Library" },
  { date: "Thu 16", time: "2:10 PM", title: "Memo as document, not dashboard", duration: "1:53", scope: "Compose" },
  { date: "Fri 17", time: "10:00 AM", title: "Codex delegation — wiring only", duration: "0:32", scope: "Library" },
  { date: "Mon 19", time: "3:42 PM", title: "Chrome bar consolidation", duration: "0:42", scope: "Library" },
];

const FEATURED_PULL = {
  excerpt:
    "The pill is the constant — chrome bars built around it should be symmetric in chip count so the geometric center never drifts, because the brand identity is anchored at that pivot, not at the page corners.",
  title: "Chrome bar consolidation",
  date: "Mon 19 May · 3:42 PM",
  duration: "0:42",
};

export default function MacLibraryEmptyStudy() {
  return (
    <StudioPage
      eyebrow="Library · no-selection empty state"
      title="Three takes on the empty detail pane"
      help="Each variant fills the same canvas slot — pick by register, not by feature list"
    >
      <div className="flex flex-col gap-14 py-6">
        <Variant
          eyebrow="· ★ · Combined — Daybook + Contents"
          title="Today on top · earlier this week below"
          hint="vertical stack · recommended direction"
        >
          <CanvasGap>
            <CombinedSurface />
          </CanvasGap>
          <Note>
            Two full-width sections stacked vertically. Top is the
            Daybook — eyebrow <code>· LIBRARY · TODAY · MONDAY ·</code>,
            "19 May" serif headline + italic tally byline, hairline,
            today's memos as a 3-column index (time / title / duration).
            Bottom is the week Contents — eyebrow <code>· EARLIER THIS
            WEEK ·</code> with an italic byline pinned right, hairline,
            5-column rows (date / time / scope / title / duration).
            Today's rows are <em>excluded</em> from the week section so
            there's no duplication. Reads as two stacked pages sharing
            a single bottom rule + footer.
          </Note>
        </Variant>

        <Variant
          eyebrow="· I · Daybook"
          title="Today as a frontispiece"
          hint="single-day focus · most ceremonial · narrow-canvas fallback"
        >
          <CanvasGap>
            <DaybookSurface />
          </CanvasGap>
          <Note>
            Today's date dominates the canvas in monumental Newsreader
            serif. Beneath it, a small italic byline (day name + week
            tally). Beneath that, a typeset index of today's memos —
            time / title / duration, hairline-divided rows. The pattern
            mirrors the recording-state Frontispiece variant so the
            user moves from "I just recorded" → "here's the day" with
            the same typographic register.
          </Note>
        </Variant>

        <Variant
          eyebrow="· II · Contents"
          title="Week-long table of contents"
          hint="utilitarian · highest information density"
        >
          <CanvasGap>
            <ContentsSurface />
          </CanvasGap>
          <Note>
            Reads as a book's contents page. Eyebrow{" "}
            <code>· LIBRARY · THIS WEEK ·</code>, then rows of:
            day-stamp / time / scope tag / serif title / duration /
            leader-dots. Hover lifts a row to ink-full opacity; click
            opens the memo. Right margin holds a small Today / This week
            tally so the page reads as both index and digest.
          </Note>
        </Variant>

        <Variant
          eyebrow="· III · Pullquote"
          title="Featured excerpt as a monumental pullquote"
          hint="single beat · most poetic · least utilitarian"
        >
          <CanvasGap>
            <PullquoteSurface />
          </CanvasGap>
          <Note>
            A single transcript excerpt from a recent memo, rendered as
            a monumental serif pullquote. Source line below: title,
            date, duration. The choice of excerpt could be: (a) most
            recent memo's strongest sentence, (b) memo with the highest
            transcription confidence, or (c) something model-curated.
            Rotates daily so opening Library is never the same page
            twice — gives the empty state a sense of unfolding.
          </Note>
        </Variant>
      </div>
    </StudioPage>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Studio scaffolding

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
        background: TALKIE_CREAM,
        border: `0.5px dashed rgba(26,22,18,0.10)`,
        minHeight: 540,
        padding: 0,
      }}
    >
      <div className="flex w-full">{children}</div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// ★ — Combined (Daybook on top · Contents below · vertical stack)

function CombinedSurface() {
  // The week section excludes today's rows — today lives in its own
  // section above so there's no duplication.
  const earlierThisWeek = WEEK_MEMOS.filter((m) => m.date !== "Mon 19");

  return (
    <div className="flex w-full flex-col" style={{ padding: "44px 64px" }}>
      {/* ── Today section ───────────────────────────────────────── */}
      <CombinedTodaySection />

      {/* mid rule — divides the two stacked pages */}
      <div
        className="mt-10"
        style={{ height: 0.5, background: "rgba(35,36,35,0.18)" }}
      />

      {/* ── Week section ────────────────────────────────────────── */}
      <CombinedWeekSection memos={earlierThisWeek} />

      {/* footer */}
      <div className="mt-auto pt-9">
        <div style={{ height: 0.5, background: "rgba(35,36,35,0.18)" }} />
        <div
          className="flex items-baseline justify-between pt-3 font-mono text-[10px] uppercase tracking-[0.28em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          <span>tap a memo · ⌘N to record</span>
          <span>1,738 words this week · 11:00 elapsed</span>
        </div>
      </div>
    </div>
  );
}

function CombinedTodaySection() {
  return (
    <section>
      {/* eyebrow */}
      <div
        className="font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
        style={{ color: TALKIE_INK_FAINT }}
      >
        · LIBRARY · TODAY · MONDAY ·
      </div>

      {/* headline row — date as inline serif headline + byline */}
      <div className="mt-4 flex items-baseline gap-6">
        <h2
          className="m-0 font-display"
          style={{
            color: TALKIE_INK,
            fontSize: 56,
            lineHeight: 1,
            letterSpacing: "-0.02em",
            fontWeight: 400,
          }}
        >
          19 May
        </h2>
        <span
          className="font-display italic"
          style={{
            color: TALKIE_INK_FAINT,
            fontSize: 17,
            letterSpacing: "0.005em",
          }}
        >
          Monday · 4 memos · 4:09 elapsed · 616 words
        </span>
      </div>

      {/* hairline */}
      <div
        className="mt-6"
        style={{ height: 0.5, background: "rgba(35,36,35,0.14)" }}
      />

      {/* today's memos — full width, 3-column */}
      <div className="mt-1 flex flex-col">
        {TODAY_MEMOS.map((m, i) => (
          <div
            key={i}
            className="group grid items-baseline border-b py-3 transition-colors hover:bg-[rgba(196,125,28,0.04)]"
            style={{
              gridTemplateColumns: "92px 1fr 56px",
              borderColor: "rgba(35,36,35,0.06)",
              columnGap: 20,
            }}
          >
            <span
              className="font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
              style={{ color: TALKIE_INK_FAINTER }}
            >
              {m.time}
            </span>
            <span
              className="font-display"
              style={{
                color: TALKIE_INK,
                fontSize: 17,
                letterSpacing: "-0.002em",
                lineHeight: 1.3,
              }}
            >
              {m.title}
            </span>
            <span
              className="text-right font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
              style={{ color: TALKIE_INK_FAINT }}
            >
              {m.duration}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

function CombinedWeekSection({
  memos,
}: {
  memos: typeof WEEK_MEMOS;
}) {
  return (
    <section className="pt-9">
      {/* eyebrow + italic byline */}
      <div className="flex items-baseline justify-between">
        <span
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          · EARLIER THIS WEEK ·
        </span>
        <span
          className="font-display italic"
          style={{
            color: TALKIE_INK_FAINT,
            fontSize: 14,
            letterSpacing: "0.005em",
          }}
        >
          {memos.length} memos · 1,122 words · 6:51
        </span>
      </div>

      {/* hairline */}
      <div
        className="mt-4"
        style={{ height: 0.5, background: "rgba(35,36,35,0.14)" }}
      />

      {/* week rows — full width, 5-column */}
      <div className="mt-1 flex flex-col">
        {memos.map((m, i) => (
          <div
            key={i}
            className="group grid items-baseline border-b py-3 transition-colors hover:bg-[rgba(196,125,28,0.04)]"
            style={{
              gridTemplateColumns: "92px 80px 110px 1fr 56px",
              borderColor: "rgba(35,36,35,0.06)",
              columnGap: 20,
            }}
          >
            <span
              className="font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
              style={{ color: TALKIE_INK_FAINTER }}
            >
              {m.date}
            </span>
            <span
              className="font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
              style={{ color: TALKIE_INK_FAINTER }}
            >
              {m.time}
            </span>
            <span
              className="font-mono text-[10px] uppercase tracking-[0.12em]"
              style={{ color: SCOPE_AMBER }}
            >
              {m.scope}
            </span>
            <span
              className="font-display"
              style={{
                color: TALKIE_INK,
                fontSize: 17,
                letterSpacing: "-0.002em",
                lineHeight: 1.3,
              }}
            >
              {m.title}
            </span>
            <span
              className="text-right font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
              style={{ color: TALKIE_INK_FAINT }}
            >
              {m.duration}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

// ──────────────────────────────────────────────────────────────────────
// I — Daybook

function DaybookSurface() {
  return (
    <div className="flex w-full flex-col" style={{ padding: "56px 72px" }}>
      {/* eyebrow */}
      <div
        className="flex items-center gap-3 font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
        style={{ color: TALKIE_INK_FAINT }}
      >
        <span>· LIBRARY · TODAY ·</span>
      </div>

      {/* monumental date */}
      <div className="mt-7 flex items-baseline gap-6">
        <span
          className="font-display"
          style={{
            color: TALKIE_INK,
            fontSize: 152,
            lineHeight: 0.88,
            letterSpacing: "-0.045em",
            fontWeight: 400,
          }}
        >
          19
        </span>
        <div className="flex flex-col gap-1">
          <span
            className="font-display"
            style={{
              color: TALKIE_INK,
              fontSize: 38,
              lineHeight: 0.95,
              letterSpacing: "-0.012em",
              fontWeight: 400,
            }}
          >
            May
          </span>
          <span
            className="font-display italic"
            style={{
              color: TALKIE_INK_FAINT,
              fontSize: 16,
              letterSpacing: "0.005em",
            }}
          >
            Monday · 4 memos · 4:09 elapsed
          </span>
        </div>
      </div>

      {/* hairline */}
      <div
        className="mt-9"
        style={{ height: 0.5, background: "rgba(35,36,35,0.18)" }}
      />

      {/* today index */}
      <div className="mt-5 flex flex-col">
        {TODAY_MEMOS.map((m, i) => (
          <div
            key={i}
            className="grid items-baseline border-b py-3"
            style={{
              gridTemplateColumns: "72px 1fr 72px",
              borderColor: "rgba(35,36,35,0.08)",
            }}
          >
            <span
              className="font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
              style={{ color: TALKIE_INK_FAINTER }}
            >
              {m.time}
            </span>
            <span
              className="font-display"
              style={{
                color: TALKIE_INK,
                fontSize: 17,
                letterSpacing: "-0.002em",
                lineHeight: 1.3,
              }}
            >
              {m.title}
            </span>
            <span
              className="text-right font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
              style={{ color: TALKIE_INK_FAINT }}
            >
              {m.duration}
            </span>
          </div>
        ))}
      </div>

      {/* bottom rule */}
      <div className="mt-auto pt-9">
        <div style={{ height: 0.5, background: "rgba(35,36,35,0.18)" }} />
        <div
          className="flex items-baseline justify-between pt-3 font-mono text-[10px] uppercase tracking-[0.28em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          <span>tap a memo · or ⌘N to record</span>
          <span>616 words today</span>
        </div>
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// II — Contents

function ContentsSurface() {
  return (
    <div className="flex w-full" style={{ padding: "56px 72px" }}>
      <div className="flex flex-1 flex-col">
        {/* eyebrow */}
        <div
          className="flex items-center gap-3 font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          <span>· LIBRARY · THIS WEEK ·</span>
        </div>

        {/* page title */}
        <h2
          className="m-0 mt-4 font-display"
          style={{
            color: TALKIE_INK,
            fontSize: 36,
            lineHeight: 1.1,
            letterSpacing: "-0.014em",
            fontWeight: 400,
          }}
        >
          Contents
        </h2>

        <div
          className="mt-2 font-display italic"
          style={{
            color: TALKIE_INK_FAINT,
            fontSize: 14,
            letterSpacing: "0.005em",
          }}
        >
          7 memos · 11:00 elapsed · 1,738 words
        </div>

        {/* hairline */}
        <div
          className="mt-7"
          style={{ height: 0.5, background: "rgba(35,36,35,0.20)" }}
        />

        {/* rows */}
        <div className="mt-2 flex flex-col">
          {WEEK_MEMOS.map((m, i) => (
            <ContentsRow key={i} {...m} />
          ))}
        </div>
      </div>

      {/* right margin — tally */}
      <aside
        className="flex flex-col gap-7"
        style={{ width: 180, marginLeft: 48, paddingTop: 16 }}
      >
        <MetaGroup
          label="Today"
          rows={[
            ["memos", "4"],
            ["runtime", "4:09"],
            ["words", "616"],
          ]}
        />
        <MetaGroup
          label="This week"
          rows={[
            ["memos", "7"],
            ["runtime", "11:00"],
            ["words", "1,738"],
          ]}
        />
        <MetaGroup
          label="Scopes"
          rows={[
            ["Library", "4"],
            ["Compose", "2"],
            ["Dictations", "1"],
          ]}
        />
      </aside>
    </div>
  );
}

function ContentsRow({
  date,
  time,
  title,
  duration,
  scope,
}: {
  date: string;
  time: string;
  title: string;
  duration: string;
  scope: string;
}) {
  return (
    <div
      className="group grid items-baseline border-b py-3 transition-colors hover:bg-[rgba(196,125,28,0.04)]"
      style={{
        gridTemplateColumns: "92px 76px 110px 1fr 56px",
        borderColor: "rgba(35,36,35,0.08)",
        columnGap: 20,
      }}
    >
      <span
        className="font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
        style={{ color: TALKIE_INK_FAINTER }}
      >
        {date}
      </span>
      <span
        className="font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
        style={{ color: TALKIE_INK_FAINTER }}
      >
        {time}
      </span>
      <span
        className="font-mono text-[10px] uppercase tracking-[0.12em]"
        style={{ color: SCOPE_AMBER }}
      >
        {scope}
      </span>
      <span
        className="font-display"
        style={{
          color: TALKIE_INK,
          fontSize: 17,
          letterSpacing: "-0.002em",
          lineHeight: 1.3,
        }}
      >
        {title}
      </span>
      <span
        className="text-right font-mono text-[10px] uppercase tracking-[0.06em] tabular-nums"
        style={{ color: TALKIE_INK_FAINT }}
      >
        {duration}
      </span>
    </div>
  );
}

function MetaGroup({
  label,
  rows,
}: {
  label: string;
  rows: [string, string][];
}) {
  return (
    <div>
      <div
        className="mb-2 font-mono text-[9px] font-semibold uppercase tracking-[0.32em]"
        style={{ color: TALKIE_INK_FAINTER }}
      >
        {label}
      </div>
      <div className="flex flex-col gap-1">
        {rows.map(([k, v]) => (
          <div
            key={k}
            className="flex items-baseline justify-between font-mono text-[10px] uppercase tracking-[0.06em]"
          >
            <span style={{ color: TALKIE_INK_FAINT }}>{k}</span>
            <span style={{ color: TALKIE_INK }} className="tabular-nums">
              {v}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// III — Pullquote

function PullquoteSurface() {
  return (
    <div
      className="flex w-full flex-col items-stretch"
      style={{ padding: "72px 92px" }}
    >
      {/* eyebrow */}
      <div
        className="flex items-center gap-3 font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
        style={{ color: TALKIE_INK_FAINT }}
      >
        <span>· LIBRARY · FEATURED ·</span>
      </div>

      {/* hairline */}
      <div
        className="mt-9"
        style={{ height: 0.5, background: "rgba(35,36,35,0.18)" }}
      />

      {/* monumental opening quote glyph + pullquote */}
      <div className="mt-9 flex flex-col items-center gap-6">
        <div
          className="font-display"
          style={{
            color: SCOPE_AMBER,
            fontSize: 132,
            lineHeight: 0.6,
            letterSpacing: "-0.04em",
            fontWeight: 400,
          }}
        >
          “
        </div>
        <blockquote
          className="m-0 font-display"
          style={{
            color: TALKIE_INK,
            fontSize: 30,
            lineHeight: 1.4,
            letterSpacing: "-0.01em",
            fontWeight: 400,
            maxWidth: 740,
            textAlign: "center",
          }}
        >
          {FEATURED_PULL.excerpt}
        </blockquote>
      </div>

      {/* source byline */}
      <div className="mt-8 flex flex-col items-center gap-1">
        <div
          className="font-display italic"
          style={{
            color: TALKIE_INK,
            fontSize: 16,
            letterSpacing: "0.005em",
          }}
        >
          — {FEATURED_PULL.title}
        </div>
        <div
          className="font-mono text-[10px] uppercase tracking-[0.28em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          {FEATURED_PULL.date} · {FEATURED_PULL.duration}
        </div>
      </div>

      {/* bottom hairline + nav */}
      <div className="mt-auto pt-9">
        <div style={{ height: 0.5, background: "rgba(35,36,35,0.18)" }} />
        <div
          className="flex items-baseline justify-between pt-3 font-mono text-[10px] uppercase tracking-[0.28em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          <span>open the memo · ↵</span>
          <span>next feature · →</span>
        </div>
      </div>
    </div>
  );
}
