"use client";

/**
 * Mac Skills — one tab, one surface, the whole loop.
 *
 * The first session is a complete loop and it all happens on one page.
 * The user lands here, picks a starter card, customizes via chat in
 * the editor bay above, runs it, and watches it land under "your
 * skills." No tabs, no modal, no extra screens.
 *
 * The composition top-to-bottom:
 *
 *   1. Header        — Skills + state line
 *   2. Editor bay    — chat + markup of the active skill (top of fold)
 *   3. Console strip — last run, ✓ marks
 *   4. Starters row  — 3 cards, the one being edited shows active border
 *   5. Your skills   — empty state on day one, populated after first save
 *
 * Shown here mid-iteration: the user picked Daily Standup, dropped a
 * line in chat ("post to #engineering"), the markup updated, they ran
 * it. The starter card carries an `EDITING` badge. Saving lands the
 * card under "your skills."
 *
 * Pre-Swift. Same palette as MacSkillForge (Scope cream/amber). The
 * older mac-skill-forge study stays as a framing-comparison record.
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
const AMBER_SOFT  = "rgba(196,125,28,0.08)";
const AMBER_LINE  = "rgba(196,125,28,0.45)";

// ─── Content ─────────────────────────────────────────────────────────

type Starter = {
  code: string;
  category: string;
  name: string;
  byline: string;
  pipeline: { kw: string; tag: string }[];
  status: "READY" | "DRAFT" | "EDITING" | "WORKFLOW";
};

const STARTERS: Starter[] = [
  {
    code: "S-0024",
    category: "Productivity",
    name: "Log Bug",
    byline: 'You see the bug, you say "log bug." A region, your last sentence, a GitHub issue — done.',
    pipeline: [
      { kw: "WHEN", tag: "voice" }, { kw: "WITH", tag: "region" },
      { kw: "DO", tag: "github" },  { kw: "THEN", tag: "ack" },
    ],
    status: "READY",
  },
  {
    code: "S-0011",
    category: "Comms",
    name: "Daily Standup",
    byline: "Three bullets, Claude tightens the language, posted to #standup before you stand up.",
    pipeline: [
      { kw: "WHEN", tag: "voice" }, { kw: "WITH", tag: "dictation" },
      { kw: "DO", tag: "#engineering" }, { kw: "THEN", tag: "ack" },
    ],
    status: "EDITING",
  },
  {
    code: "S-0007",
    category: "Personal",
    name: "Capture Thought",
    byline: "For the half-formed ideas — a quick voice memo, auto-tagged, filed to your library.",
    pipeline: [
      { kw: "WHEN", tag: "voice" }, { kw: "WITH", tag: "dictation" },
      { kw: "DO", tag: "library" }, { kw: "THEN", tag: "tag" },
    ],
    status: "DRAFT",
  },
];

const YOUR_SKILLS: Starter[] = [
  {
    code: "Y-0001",
    category: "Personal · atomic",
    name: "Pull Calendar",
    byline: "First thing in the morning — pull today's calendar into a compact agenda for the next skill to use.",
    pipeline: [
      { kw: "WHEN", tag: "voice" }, { kw: "WITH", tag: "—" },
      { kw: "DO", tag: "calendar.today" }, { kw: "THEN", tag: "stash" },
    ],
    status: "READY",
  },
  {
    code: "Y-0002",
    category: "Routine · composed",
    name: "Morning Routine",
    byline: "Pull the calendar, run standup, fire the weekly digest if it's Monday. Three skills, one trigger.",
    pipeline: [
      { kw: "WHEN", tag: "schedule" }, { kw: "WITH", tag: "—" },
      { kw: "DO", tag: "sequence(3)" }, { kw: "THEN", tag: "notify" },
    ],
    status: "READY",
  },
  {
    code: "Y-0003",
    category: "Capture · workflow",
    name: "Brain Dump Processor",
    byline: "Transcribe the dump, extract ideas, branch on length, save + remind. Lives in the Workflow Editor.",
    pipeline: [
      { kw: "WHEN", tag: "transcribe" }, { kw: "WITH", tag: "10 steps" },
      { kw: "DO", tag: "branch" }, { kw: "THEN", tag: "save + remind" },
    ],
    status: "WORKFLOW",
  },
];

type Line =
  | { kind: "kw"; word: "WHEN" | "WITH" | "DO" | "THEN"; rest: string; changed?: boolean }
  | { kind: "sub"; text: string; changed?: boolean }
  | { kind: "blank" };

const ACTIVE_LINES: Line[] = [
  { kind: "kw",  word: "WHEN", rest: 'voice "standup"' },
  { kind: "blank" },
  { kind: "kw",  word: "WITH", rest: "dictation" },
  { kind: "sub", text: "three bullets" },
  { kind: "blank" },
  { kind: "kw",  word: "DO",   rest: "slack.post" },
  { kind: "sub", text: "channel: #engineering", changed: true },
  { kind: "sub", text: "polish: claude.tighten" },
  { kind: "blank" },
  { kind: "kw",  word: "THEN", rest: "voice ack" },
];

const CHAT: { who: "you" | "agent"; text: string }[] = [
  { who: "agent", text: "Daily Standup loaded. It dictates three bullets, Claude tightens the language, posts to #standup, and acks. Change anything?" },
  { who: "you",   text: "post to #engineering instead." },
  { who: "agent", text: "Done — updated channel to #engineering." },
  { who: "you",   text: "run it." },
];

const RUN_LINES = [
  { ok: true, text: "dictation captured · 3 bullets · 18s" },
  { ok: true, text: "claude.tighten · sentence merge + bullet pass" },
  { ok: true, text: "slack.post · #engineering · message 47291" },
  { ok: true, text: "voice ack · 0.8s" },
];

// ─── Composition root ────────────────────────────────────────────────

export function MacSkills() {
  return (
    <div style={{ width: 1180, background: CREAM }} className="flex flex-col">
      <Header />
      <EditorBay />
      <ConsoleStrip />
      <SectionLine label="starters" hint="shipped with Talkie · ready to run, fork, or ignore" />
      <StartersRow />
      <SectionLine label="your skills" hint="three modes shown — atomic, composed, and workflow" />
      <YourSkillsRow />
      <SectionLine label="where it fires" hint="saved skills show up in these surfaces" />
      <WhereItFires />
      <Footer />
    </div>
  );
}

// ─── Header ──────────────────────────────────────────────────────────

function Header() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 20, paddingBottom: 12 }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono font-semibold uppercase tracking-[0.32em]"
          style={{ color: INK_FAINT, fontSize: 9 }}
        >
          · SKILLS
        </span>
        <span className="font-display italic" style={{ color: INK_FAINT, fontSize: 13 }}>
          one surface · pick a starter, iterate, save
        </span>
        <div className="ml-auto flex items-center gap-2">
          <Chip label="DAILY STANDUP · EDITING" tone="amber" />
        </div>
      </div>
      <h2
        className="font-display tracking-tight"
        style={{ color: INK, fontSize: 30, fontWeight: 500, lineHeight: 1, marginTop: 8 }}
      >
        Skills
      </h2>
    </div>
  );
}

// ─── Editor bay (chat + markup) ──────────────────────────────────────

function EditorBay() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 4 }}>
      <div className="flex gap-5">
        <div style={{ flex: "1.1 1 0%" }}>
          <PaneHeader title="agent" sub="claude sonnet 4.6" />
          <ChatPane thread={CHAT} />
        </div>
        <div style={{ flex: "1 1 0%" }}>
          <div className="flex items-baseline justify-between" style={{ marginBottom: 8 }}>
            <span
              className="font-mono font-semibold uppercase tracking-[0.24em]"
              style={{ color: INK_FAINT, fontSize: 9 }}
            >
              · markup · daily-standup.skill.md
            </span>
            <div className="flex items-center gap-2">
              <Chip label="⌘↵ RUN" tone="ink" />
              <Chip label="⌘S SAVE" tone="amber" />
            </div>
          </div>
          <MarkupEditor lines={ACTIVE_LINES} height={240} />
        </div>
      </div>
    </div>
  );
}

// ─── Console strip ───────────────────────────────────────────────────

function ConsoleStrip() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 14 }}>
      <div
        style={{
          background: PAPER,
          border: `1px solid ${INK_RULE_S}`,
          borderRadius: 4,
          padding: "12px 14px",
        }}
      >
        <div className="flex items-baseline justify-between" style={{ marginBottom: 6 }}>
          <span
            className="font-mono font-semibold uppercase tracking-[0.24em]"
            style={{ color: INK_FAINT, fontSize: 9 }}
          >
            · console · just ran
          </span>
          <span
            className="font-mono uppercase tracking-[0.18em]"
            style={{ color: INK_FAINTER, fontSize: 9 }}
          >
            12:14:08 · 2.4s
          </span>
        </div>
        <div className="font-mono" style={{ fontSize: 11.5, lineHeight: "20px", color: INK }}>
          <div style={{ color: AMBER }}>{"> run skill daily-standup"}</div>
          {RUN_LINES.map((l, i) => (
            <div key={i}>
              <span style={{ color: BRASS, marginRight: 8 }}>✓</span>
              {l.text}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─── Section line ────────────────────────────────────────────────────

function SectionLine({ label, hint }: { label: string; hint: string }) {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 22, paddingBottom: 8 }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono font-semibold uppercase tracking-[0.28em]"
          style={{ color: INK_FAINT, fontSize: 9 }}
        >
          · {label}
        </span>
        <span className="font-display italic" style={{ color: INK_FAINT, fontSize: 12 }}>
          {hint}
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: INK_RULE_S }} />
      </div>
    </div>
  );
}

// ─── Starters row ────────────────────────────────────────────────────

function StartersRow() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 4 }}>
      <div className="grid gap-4" style={{ gridTemplateColumns: "repeat(3, 1fr)" }}>
        {STARTERS.map((s) => (
          <StarterCard key={s.code} starter={s} />
        ))}
      </div>
    </div>
  );
}

function StarterCard({ starter }: { starter: Starter }) {
  const isActive = starter.status === "EDITING";
  const ready = starter.status === "READY";
  const isWorkflow = starter.status === "WORKFLOW";
  const eyebrowColor = isActive ? AMBER : isWorkflow ? BRASS : INK_FAINT;
  const chipTone: "amber" | "brass" | "ink" = isWorkflow
    ? "brass"
    : isActive || ready
    ? "amber"
    : "ink";
  const ctaLabel = isActive
    ? "OPEN ABOVE ↑"
    : isWorkflow
    ? "OPEN IN EDITOR →"
    : ready
    ? "USE →"
    : "OPEN →";
  const ctaColor = isWorkflow ? BRASS : AMBER;
  return (
    <div
      style={{
        background: PAPER,
        border: isActive
          ? `1px solid ${AMBER_LINE}`
          : isWorkflow
          ? `1px solid rgba(154,106,34,0.30)`
          : `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        padding: "14px 16px 12px 16px",
        display: "flex",
        flexDirection: "column",
        minHeight: 184,
        position: "relative",
      }}
    >
      {isActive && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: AMBER_SOFT,
            borderRadius: 4,
            pointerEvents: "none",
          }}
        />
      )}
      <div style={{ position: "relative" }}>
        <div className="flex items-baseline gap-2" style={{ marginBottom: 4 }}>
          <span
            className="font-mono font-semibold uppercase tracking-[0.26em]"
            style={{ fontSize: 9, color: eyebrowColor }}
          >
            · {starter.category}
          </span>
          <span
            className="font-mono uppercase tracking-[0.18em]"
            style={{ fontSize: 9, color: INK_FAINTER }}
          >
            {starter.code}
          </span>
        </div>
        <div
          className="font-display tracking-tight"
          style={{ color: INK, fontSize: 19, fontWeight: 500, lineHeight: 1.1, marginBottom: 4 }}
        >
          {starter.name}
        </div>
        <p
          className="font-display italic"
          style={{ color: INK_FAINT, fontSize: 11.5, lineHeight: 1.45, margin: 0 }}
        >
          {starter.byline}
        </p>
        <div style={{ marginTop: 10, marginBottom: 10 }}>
          <div style={{ height: 1, background: INK_RULE_S, marginBottom: 8 }} />
          <div className="flex items-baseline gap-2 flex-wrap">
            {starter.pipeline.map((p, i) => (
              <React.Fragment key={i}>
                <span className="font-mono" style={{ fontSize: 10, lineHeight: "14px" }}>
                  <span style={{ color: isWorkflow ? BRASS : AMBER, fontWeight: 600 }}>
                    {p.kw}
                  </span>
                  <span style={{ color: INK, marginLeft: 4 }}>{p.tag}</span>
                </span>
                {i < starter.pipeline.length - 1 && (
                  <span className="font-mono" style={{ fontSize: 10, color: INK_FAINTER }}>
                    ·
                  </span>
                )}
              </React.Fragment>
            ))}
          </div>
        </div>
        <div className="mt-auto flex items-center justify-between">
          <Chip label={isActive ? "EDITING" : starter.status} tone={chipTone} />
          <span
            className="font-mono uppercase tracking-[0.22em]"
            style={{
              fontSize: 9,
              fontWeight: 600,
              color: ctaColor,
              borderBottom: `1px solid ${ctaColor}`,
              paddingBottom: 1,
            }}
          >
            {ctaLabel}
          </span>
        </div>
      </div>
    </div>
  );
}

function YourSkillsRow() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 4 }}>
      <div className="grid gap-4" style={{ gridTemplateColumns: "repeat(3, 1fr)" }}>
        {YOUR_SKILLS.map((s) => (
          <StarterCard key={s.code} starter={s} />
        ))}
      </div>
    </div>
  );
}

// ─── Where it fires (invocation surface previews) ────────────────────

function WhereItFires() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 4 }}>
      <div className="grid gap-4" style={{ gridTemplateColumns: "repeat(3, 1fr)" }}>
        <ComposePreview />
        <VoicePreview />
        <LibraryPreview />
      </div>
    </div>
  );
}

function PreviewShell({
  surface,
  caption,
  children,
}: {
  surface: string;
  caption: string;
  children: React.ReactNode;
}) {
  return (
    <div
      style={{
        background: PAPER,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        padding: "12px 14px 14px 14px",
        display: "flex",
        flexDirection: "column",
        minHeight: 196,
      }}
    >
      <div className="flex items-baseline gap-2" style={{ marginBottom: 8 }}>
        <span
          className="font-mono font-semibold uppercase tracking-[0.26em]"
          style={{ fontSize: 9, color: INK_FAINT }}
        >
          · {surface}
        </span>
      </div>
      <div style={{ flex: 1 }}>{children}</div>
      <p
        className="font-display italic"
        style={{ color: INK_FAINT, fontSize: 11.5, lineHeight: 1.4, margin: 0, marginTop: 10 }}
      >
        {caption}
      </p>
    </div>
  );
}

function ComposePreview() {
  return (
    <PreviewShell
      surface="Compose · action chip"
      caption="Daily Standup joins the smart-action row. Select text, tap the chip, the skill fires on your selection."
    >
      <div
        style={{
          background: CREAM,
          border: `1px solid ${INK_RULE_S}`,
          borderRadius: 3,
          padding: 10,
        }}
      >
        {/* Editor body mock */}
        <div
          className="font-display italic"
          style={{ fontSize: 11, lineHeight: 1.5, color: INK, marginBottom: 10 }}
        >
          “We made real progress on the worker layer today. The pool
          contention is gone — switching to a single-writer model cleared
          the last batch of stalls...”
        </div>
        <div style={{ height: 1, background: INK_RULE_S, marginBottom: 8 }} />
        {/* Action chip row */}
        <div className="flex items-center gap-1.5 flex-wrap">
          <MiniChip label="Refine" />
          <MiniChip label="Simplify" />
          <MiniChip label="Daily Standup" active />
          <MiniChip label="…" muted />
        </div>
      </div>
    </PreviewShell>
  );
}

function VoicePreview() {
  return (
    <PreviewShell
      surface="Voice · trigger anywhere"
      caption='The WHEN line registers. Say "standup" from any app, the skill fires headless.'
    >
      <div
        style={{
          background: "#0E1518",
          borderRadius: 6,
          padding: "14px 14px 16px 14px",
          color: "#E8E4D8",
          position: "relative",
          overflow: "hidden",
        }}
      >
        <div className="flex items-center gap-2" style={{ marginBottom: 10 }}>
          <span
            style={{
              width: 6,
              height: 6,
              borderRadius: 999,
              background: AMBER,
              boxShadow: `0 0 8px ${AMBER}`,
            }}
          />
          <span
            className="font-mono font-semibold uppercase tracking-[0.28em]"
            style={{ fontSize: 9, color: "rgba(232,228,216,0.6)" }}
          >
            · LISTENING
          </span>
        </div>
        <div
          className="font-display"
          style={{ fontSize: 14, lineHeight: 1.3, color: "#F4F1EA", marginBottom: 6 }}
        >
          say <span style={{ color: AMBER, fontWeight: 500 }}>“standup”</span>
        </div>
        <div className="flex items-baseline gap-1.5 flex-wrap">
          <span
            className="font-mono"
            style={{ fontSize: 9, color: "rgba(232,228,216,0.45)", letterSpacing: "0.12em" }}
          >
            then dictate · 3 bullets · auto-stops
          </span>
        </div>
        {/* Faint waveform suggestion */}
        <div
          className="flex items-end gap-0.5"
          style={{ height: 14, marginTop: 12 }}
        >
          {[3, 6, 4, 9, 5, 11, 7, 4, 8, 12, 6, 9, 5, 7, 3, 10, 6, 4].map((h, i) => (
            <span
              key={i}
              style={{
                width: 2,
                height: h,
                background: "rgba(196,125,28,0.5)",
                borderRadius: 1,
              }}
            />
          ))}
        </div>
      </div>
    </PreviewShell>
  );
}

function LibraryPreview() {
  return (
    <PreviewShell
      surface="Library · apply to memo"
      caption="Recorded something already? Apply a skill post-hoc — it runs over the existing transcript."
    >
      <div
        style={{
          background: CREAM,
          border: `1px solid ${INK_RULE_S}`,
          borderRadius: 3,
          overflow: "hidden",
        }}
      >
        {/* Memo row */}
        <div className="flex items-baseline gap-3" style={{ padding: "10px 12px" }}>
          <span
            className="font-mono uppercase tracking-[0.18em]"
            style={{ fontSize: 9, color: INK_FAINTER }}
          >
            08:42
          </span>
          <div style={{ flex: 1 }}>
            <div
              className="font-display"
              style={{ fontSize: 12.5, color: INK, lineHeight: 1.2 }}
            >
              Worker layer notes
            </div>
            <div
              className="font-display italic"
              style={{ fontSize: 10.5, color: INK_FAINT, marginTop: 1 }}
            >
              4:12 · today
            </div>
          </div>
          <span
            className="font-mono uppercase tracking-[0.22em]"
            style={{ fontSize: 9, color: INK_FAINTER }}
          >
            ▷ apply ↓
          </span>
        </div>
        <div style={{ height: 1, background: INK_RULE_S }} />
        {/* Dropdown showing skills */}
        <div style={{ background: PAPER, padding: "8px 12px" }}>
          <div
            className="font-mono font-semibold uppercase tracking-[0.24em]"
            style={{ fontSize: 9, color: INK_FAINT, marginBottom: 6 }}
          >
            · your skills
          </div>
          <div
            className="flex items-center justify-between"
            style={{
              background: AMBER_SOFT,
              borderRadius: 2,
              padding: "5px 8px",
              border: `1px solid ${AMBER_LINE}`,
              marginBottom: 4,
            }}
          >
            <span
              className="font-display"
              style={{ fontSize: 11.5, color: INK }}
            >
              Daily Standup
            </span>
            <span
              className="font-mono uppercase tracking-[0.22em]"
              style={{ fontSize: 9, fontWeight: 600, color: AMBER }}
            >
              APPLY →
            </span>
          </div>
          <div
            className="flex items-center justify-between"
            style={{ padding: "4px 8px" }}
          >
            <span
              className="font-display"
              style={{ fontSize: 11.5, color: INK_FAINT }}
            >
              Log Bug
            </span>
            <span
              className="font-mono uppercase tracking-[0.22em]"
              style={{ fontSize: 9, color: INK_FAINTER }}
            >
              READY
            </span>
          </div>
        </div>
      </div>
    </PreviewShell>
  );
}

function MiniChip({ label, active, muted }: { label: string; active?: boolean; muted?: boolean }) {
  return (
    <span
      className="font-mono uppercase tracking-[0.18em]"
      style={{
        fontSize: 9,
        fontWeight: active ? 600 : 500,
        color: active ? AMBER : muted ? INK_FAINTER : INK_FAINT,
        border: `1px solid ${active ? AMBER : INK_RULE_S}`,
        padding: "3px 7px",
        borderRadius: 2,
        background: active ? AMBER_SOFT : "transparent",
      }}
    >
      {label}
      {active && (
        <span style={{ marginLeft: 4, color: AMBER }}>→</span>
      )}
    </span>
  );
}

// ─── Footer (closing byline) ─────────────────────────────────────────

function Footer() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 4, paddingBottom: 22 }}>
      <div style={{ height: 1, background: INK_RULE_S, marginBottom: 12 }} />
      <p
        className="font-display italic"
        style={{ color: INK_FAINT, fontSize: 12.5, lineHeight: 1.6, margin: 0 }}
      >
        One tab. The user reads the page top to bottom — pick a starter,
        watch it open above, talk to the agent, run, save. Three skill
        modes coexist in your collection — atomic (single action),
        composed (DO sequence/route over other skills), and workflow
        (graduated into the legacy editor). The foot of the page shows
        where they manifest — Compose, voice trigger, Library. Workshop,
        catalog, and promise on the same surface.
      </p>
    </div>
  );
}

// ─── Shared primitives ───────────────────────────────────────────────

function PaneHeader({ title, sub }: { title: string; sub?: string }) {
  return (
    <div className="flex items-baseline justify-between" style={{ marginBottom: 8 }}>
      <span
        className="font-mono font-semibold uppercase tracking-[0.24em]"
        style={{ color: INK_FAINT, fontSize: 9 }}
      >
        · {title}
      </span>
      {sub && (
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ color: INK_FAINTER, fontSize: 9 }}
        >
          {sub}
        </span>
      )}
    </div>
  );
}

function Chip({ label, tone }: { label: string; tone: "amber" | "brass" | "ink" }) {
  const color =
    tone === "amber" ? AMBER : tone === "brass" ? BRASS : INK_FAINT;
  const border =
    tone === "amber" ? AMBER : tone === "brass" ? BRASS : INK_RULE;
  const background =
    tone === "amber"
      ? AMBER_SOFT
      : tone === "brass"
      ? "rgba(154,106,34,0.08)"
      : "transparent";
  return (
    <span
      className="font-mono uppercase tracking-[0.22em]"
      style={{
        fontSize: 9,
        fontWeight: 600,
        color,
        border: `1px solid ${border}`,
        padding: "3px 8px",
        borderRadius: 2,
        background,
      }}
    >
      {label}
    </span>
  );
}

function ChatPane({ thread }: { thread: { who: "you" | "agent"; text: string }[] }) {
  return (
    <div
      style={{
        background: CREAM,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        height: 240,
        padding: "12px 14px",
        display: "flex",
        flexDirection: "column",
        gap: 10,
        overflow: "hidden",
      }}
    >
      {thread.map((m, i) => (
        <div key={i}>
          <div
            className="font-mono font-semibold uppercase tracking-[0.22em]"
            style={{ fontSize: 9, color: m.who === "agent" ? AMBER : INK_FAINT, marginBottom: 2 }}
          >
            · {m.who}
          </div>
          <div
            className="font-display"
            style={{
              fontSize: 12.5,
              lineHeight: 1.5,
              color: INK,
              fontStyle: m.who === "agent" ? "italic" : "normal",
            }}
          >
            {m.text}
          </div>
        </div>
      ))}
      <div style={{ flex: 1 }} />
      <div
        className="flex items-center gap-2"
        style={{ borderTop: `1px solid ${INK_RULE_S}`, paddingTop: 8 }}
      >
        <span className="font-mono" style={{ fontSize: 11, color: INK_FAINT }}>
          ▌
        </span>
        <span className="font-display italic" style={{ fontSize: 12, color: INK_FAINTER }}>
          ask the agent · or dictate
        </span>
        <div className="ml-auto">
          <Chip label="VOICE" tone="amber" />
        </div>
      </div>
    </div>
  );
}

function MarkupEditor({ lines, height }: { lines: Line[]; height: number }) {
  return (
    <div
      style={{
        background: PAPER,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        height,
        position: "relative",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 0,
          bottom: 0,
          left: 0,
          width: 32,
          borderRight: `1px solid ${INK_RULE_S}`,
          background: "rgba(42,38,32,0.02)",
          paddingTop: 14,
        }}
      >
        {lines.map((_, i) => (
          <div
            key={i}
            className="font-mono"
            style={{
              fontSize: 10,
              lineHeight: "20px",
              color: INK_FAINTER,
              textAlign: "right",
              paddingRight: 8,
            }}
          >
            {i + 1}
          </div>
        ))}
      </div>
      <div style={{ paddingLeft: 44, paddingRight: 14, paddingTop: 14 }}>
        {lines.map((line, i) => (
          <MarkupLine key={i} line={line} />
        ))}
      </div>
    </div>
  );
}

function MarkupLine({ line }: { line: Line }) {
  if (line.kind === "blank") return <div style={{ height: 20 }} />;
  const changed = (line as { changed?: boolean }).changed;
  const baseStyle = {
    fontSize: 12,
    lineHeight: "20px",
    background: changed ? AMBER_SOFT : "transparent",
    marginLeft: changed ? -4 : 0,
    paddingLeft: changed ? 4 : 0,
    paddingRight: changed ? 4 : 0,
    borderRadius: changed ? 2 : 0,
  } as React.CSSProperties;
  if (line.kind === "kw") {
    return (
      <div className="font-mono" style={baseStyle}>
        <span style={{ color: AMBER, fontWeight: 600 }}>{line.word.padEnd(5, " ")}</span>
        <span style={{ color: INK }}>{line.rest}</span>
      </div>
    );
  }
  return (
    <div className="font-mono" style={baseStyle}>
      <span style={{ color: INK_FAINTER }}>      ↳ </span>
      <span style={{ color: INK, fontWeight: changed ? 500 : 400 }}>{line.text}</span>
    </div>
  );
}
