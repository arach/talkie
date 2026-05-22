"use client";

/**
 * Mac Skill Forge — three framings for the skill-authoring surface.
 *
 * Premise (from the exploration):
 *   - A "skill" is a semantic description of what Talkie should do
 *     when a trigger fires. Not a drag-and-drop workflow graph.
 *   - The syntax is dictatable, diffable, agent-writable.
 *   - The console is already running; pipe a skill at it and see output.
 *   - Editor is a WebKit-hosted CodeMirror — native code editing isn't
 *     worth the lift for what's a side affordance.
 *
 * This study renders the SAME stub skill ("Log Bug") in three layouts,
 * stacked vertically, so the framings can be compared at a glance:
 *
 *   A. MARKUP-PRIMARY — editor is the surface, agent + outline are rails.
 *   B. CHAT-DRIVEN    — chat composes, markup is the receipt.
 *   C. TRIFOLD        — chat + markup + derived map, three lenses on one source.
 *
 * Source of truth across all three: the markup. Other panes are lenses.
 */

import React from "react";

// ─── Tokens (match MacCompose palette) ───────────────────────────────

const CREAM       = "#F8F8F7";
const PAPER       = "#E7E7E6";
const INK         = "#232423";
const INK_FAINT   = "rgba(35,36,35,0.55)";
const INK_FAINTER = "rgba(35,36,35,0.32)";
const INK_RULE    = "rgba(35,36,35,0.18)";
const INK_RULE_S  = "rgba(35,36,35,0.10)";
const AMBER       = "#C47D1C";
const BRASS       = "#9A6A22";
const EDGE        = "#DEDEDD";

// ─── Stub skill content (shared across all three framings) ───────────

type Line =
  | { kind: "kw"; word: "WHEN" | "WITH" | "DO" | "THEN"; rest: string }
  | { kind: "sub"; text: string }
  | { kind: "blank" };

const SKILL_NAME = "Log Bug";

const SKILL_LINES: Line[] = [
  { kind: "kw",  word: "WHEN", rest: 'voice "log bug"' },
  { kind: "blank" },
  { kind: "kw",  word: "WITH", rest: "region screenshot" },
  { kind: "sub", text: "last paragraph" },
  { kind: "blank" },
  { kind: "kw",  word: "DO",   rest: "github.issue" },
  { kind: "sub", text: "title  ← derive from selection" },
  { kind: "sub", text: "body   ← selection + screenshot" },
  { kind: "blank" },
  { kind: "kw",  word: "THEN", rest: "voice ack" },
];

const OUTLINE: { label: string; items: string[] }[] = [
  { label: "Trigger", items: ['voice · "log bug"'] },
  { label: "Inputs",  items: ["region screenshot", "last paragraph"] },
  { label: "Action",  items: ["github.issue"] },
  { label: "Confirm", items: ["voice ack"] },
];

const CONSOLE_LINES: { ok: boolean; text: string }[] = [
  { ok: true, text: "captured 1 region · 1 paragraph" },
  { ok: true, text: "github.issue #842 — “Notch flicker after transcription”" },
  { ok: true, text: "voice ack · 1.2s" },
];

const CHAT_THREAD: { who: "you" | "agent"; text: string }[] = [
  { who: "you",   text: "make a skill that logs a bug when i say “log bug”." },
  { who: "agent", text: "Drafted. It grabs a region screenshot + your last paragraph and opens a GitHub issue." },
  { who: "you",   text: "add a voice ack at the end." },
  { who: "agent", text: "Done — added THEN voice ack." },
];

// ─── Starter gallery content ─────────────────────────────────────────

type Starter = {
  code: string;
  category: string;
  name: string;
  byline: string;
  pipeline: { kw: "WHEN" | "WITH" | "DO" | "THEN"; tag: string }[];
  status: "READY" | "DRAFT";
};

const STARTERS: Starter[] = [
  {
    code: "S-0024",
    category: "Productivity",
    name: "Log Bug",
    byline: 'You see the bug, you say "log bug." A region, your last sentence, a GitHub issue — done.',
    pipeline: [
      { kw: "WHEN", tag: "voice" },
      { kw: "WITH", tag: "region" },
      { kw: "DO",   tag: "github" },
      { kw: "THEN", tag: "ack" },
    ],
    status: "READY",
  },
  {
    code: "S-0011",
    category: "Comms",
    name: "Daily Standup",
    byline: "Three bullets, Claude tightens the language, posted to #standup before you stand up.",
    pipeline: [
      { kw: "WHEN", tag: "voice" },
      { kw: "WITH", tag: "dictation" },
      { kw: "DO",   tag: "slack" },
      { kw: "THEN", tag: "ack" },
    ],
    status: "READY",
  },
  {
    code: "S-0007",
    category: "Personal",
    name: "Capture Thought",
    byline: "For the half-formed ideas — a quick voice memo, auto-tagged, filed to your library.",
    pipeline: [
      { kw: "WHEN", tag: "voice" },
      { kw: "WITH", tag: "dictation" },
      { kw: "DO",   tag: "library" },
      { kw: "THEN", tag: "tag" },
    ],
    status: "DRAFT",
  },
];

// ─── Composition root ────────────────────────────────────────────────

export function MacSkillForge() {
  return (
    <div style={{ width: 1180, background: CREAM }} className="flex flex-col">
      <ForgeHeader />
      <SectionBreak label="starters" hint="pick one, run it, or fork into edit mode" />
      <StarterGallery />
      <FramingBreak label="A · markup-primary" hint="syntax is the surface · outline + console are rails" />
      <FramingA />
      <FramingBreak label="B · chat-driven" hint="agent composes the markup · you tweak, then run" />
      <FramingB />
      <FramingBreak label="C · trifold" hint="chat · markup · derived map — three lenses, one source" />
      <FramingC />
      <ForgeFooter />
    </div>
  );
}

// ─── Header (shared) ─────────────────────────────────────────────────

function ForgeHeader() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 18, paddingBottom: 14, background: CREAM }}>
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: INK_FAINT }}>
          · SKILL FORGE · S-0024 ·
        </span>
        <span className="font-display italic" style={{ color: INK_FAINT, fontSize: 13 }}>
          browse starters · or fork into edit mode
        </span>
        <div className="ml-auto flex items-center gap-3">
          <Chip label="DRAFT" tone="ink" />
          <span className="font-mono text-[10px] uppercase tracking-[0.18em]" style={{ color: INK_FAINT }}>
            last run · 6m ago
          </span>
        </div>
      </div>
      <h2
        className="font-display tracking-tight"
        style={{ color: INK, fontSize: 30, fontWeight: 500, lineHeight: 1, marginTop: 8 }}
      >
        {SKILL_NAME}
      </h2>
    </div>
  );
}

function FramingBreak({ label, hint }: { label: string; hint: string }) {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 28, paddingBottom: 10 }}>
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.30em]" style={{ color: AMBER }}>
          {label}
        </span>
        <span className="font-display italic" style={{ color: INK_FAINT, fontSize: 12 }}>
          {hint}
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: INK_RULE_S }} />
      </div>
    </div>
  );
}

// Sibling of FramingBreak — ink-toned (quiet) rather than amber.
// Used for the starters section so the framing comparisons remain
// the loudest signal on the page.
function SectionBreak({ label, hint }: { label: string; hint: string }) {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 22, paddingBottom: 10 }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono text-[9px] font-semibold uppercase tracking-[0.30em]"
          style={{ color: INK_FAINT }}
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

// ─── Starter gallery ─────────────────────────────────────────────────

function StarterGallery() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 4 }}>
      <div className="grid gap-4" style={{ gridTemplateColumns: "repeat(3, 1fr)" }}>
        {STARTERS.map((s) => (
          <StarterCard key={s.code} starter={s} />
        ))}
      </div>
      <div style={{ height: 4 }} />
    </div>
  );
}

function StarterCard({ starter }: { starter: Starter }) {
  const isReady = starter.status === "READY";
  return (
    <div
      style={{
        background: PAPER,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        padding: "16px 16px 14px 16px",
        display: "flex",
        flexDirection: "column",
        minHeight: 196,
      }}
    >
      {/* Eyebrow */}
      <div className="flex items-baseline gap-2" style={{ marginBottom: 6 }}>
        <span
          className="font-mono font-semibold uppercase tracking-[0.26em]"
          style={{ fontSize: 9, color: INK_FAINT }}
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

      {/* Title */}
      <div
        className="font-display tracking-tight"
        style={{ color: INK, fontSize: 20, fontWeight: 500, lineHeight: 1.1, marginBottom: 6 }}
      >
        {starter.name}
      </div>

      {/* Byline */}
      <p
        className="font-display italic"
        style={{ color: INK_FAINT, fontSize: 12, lineHeight: 1.45, margin: 0 }}
      >
        {starter.byline}
      </p>

      {/* Pipeline preview */}
      <div style={{ marginTop: 12, marginBottom: 12 }}>
        <div style={{ height: 1, background: INK_RULE_S, marginBottom: 10 }} />
        <div className="flex items-baseline gap-2 flex-wrap">
          {starter.pipeline.map((p, i) => (
            <React.Fragment key={i}>
              <span
                className="font-mono"
                style={{ fontSize: 10, lineHeight: "14px" }}
              >
                <span style={{ color: AMBER, fontWeight: 600 }}>{p.kw}</span>
                <span style={{ color: INK, marginLeft: 4 }}>{p.tag}</span>
              </span>
              {i < starter.pipeline.length - 1 && (
                <span
                  className="font-mono"
                  style={{ fontSize: 10, color: INK_FAINTER }}
                >
                  ·
                </span>
              )}
            </React.Fragment>
          ))}
        </div>
      </div>

      {/* Footer */}
      <div className="mt-auto flex items-center justify-between">
        <Chip label={starter.status} tone={isReady ? "amber" : "ink"} />
        <div className="flex items-center gap-2">
          <span
            className="font-mono uppercase tracking-[0.20em]"
            style={{ fontSize: 9, color: INK_FAINTER }}
          >
            edit
          </span>
          <span
            className="font-mono uppercase tracking-[0.22em]"
            style={{
              fontSize: 9,
              fontWeight: 600,
              color: AMBER,
              borderBottom: `1px solid ${AMBER}`,
              paddingBottom: 1,
            }}
          >
            {isReady ? "USE →" : "OPEN →"}
          </span>
        </div>
      </div>
    </div>
  );
}

function ForgeFooter() {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 26, paddingBottom: 24 }}>
      <div style={{ height: 1, background: INK_RULE_S, marginBottom: 12 }} />
      <p
        className="font-display italic"
        style={{ color: INK_FAINT, fontSize: 13, lineHeight: 1.6 }}
      >
        Source of truth is the markup. Chat is a mutator that edits it.
        Map is a read-only visualization derived from it. Form (not shown)
        is an opt-in editor for one node at a time when the markup turns fiddly.
      </p>
    </div>
  );
}

// ─── A · Markup-primary ──────────────────────────────────────────────

function FramingA() {
  return (
    <Surface>
      <div className="flex gap-5">
        <div style={{ flex: "1 1 0%" }}>
          <PaneHeader title="markup" sub="codemirror · webkit" />
          <MarkupEditor lines={SKILL_LINES} height={236} />
        </div>
        <div style={{ width: 220 }}>
          <PaneHeader title="outline" sub="derived" />
          <OutlinePane />
        </div>
      </div>
      <div style={{ height: 14 }} />
      <ConsolePane lines={CONSOLE_LINES} />
    </Surface>
  );
}

// ─── B · Chat-driven ─────────────────────────────────────────────────

function FramingB() {
  return (
    <Surface>
      <div className="flex gap-5">
        <div style={{ flex: "1.25 1 0%" }}>
          <PaneHeader title="agent" sub="claude sonnet 4.6 · co-author" />
          <ChatPane thread={CHAT_THREAD} />
        </div>
        <div style={{ flex: "1 1 0%" }}>
          <PaneHeader title="markup" sub="agent writes · you tweak" muted />
          <MarkupEditor lines={SKILL_LINES} height={280} muted />
        </div>
      </div>
      <div style={{ height: 12 }} />
      <ConsoleStrip />
    </Surface>
  );
}

// ─── C · Trifold ─────────────────────────────────────────────────────

function FramingC() {
  return (
    <Surface>
      <div className="flex gap-4">
        <div style={{ width: 252 }}>
          <PaneHeader title="agent" sub="chat" />
          <ChatPane thread={CHAT_THREAD.slice(-2)} compact />
        </div>
        <div style={{ flex: "1 1 0%" }}>
          <PaneHeader title="markup" sub="source of truth" />
          <MarkupEditor lines={SKILL_LINES} height={236} />
        </div>
        <div style={{ width: 224 }}>
          <PaneHeader title="map" sub="derived" />
          <MapPane />
        </div>
      </div>
    </Surface>
  );
}

// ─── Pane primitives ─────────────────────────────────────────────────

function Surface({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ paddingLeft: 32, paddingRight: 32, paddingTop: 8, paddingBottom: 4 }}>
      {children}
    </div>
  );
}

function PaneHeader({ title, sub, muted }: { title: string; sub?: string; muted?: boolean }) {
  return (
    <div className="flex items-baseline justify-between" style={{ marginBottom: 8 }}>
      <span
        className="font-mono font-semibold uppercase tracking-[0.24em]"
        style={{ color: muted ? INK_FAINTER : INK_FAINT, fontSize: 9 }}
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

function Chip({ label, tone }: { label: string; tone: "amber" | "ink" }) {
  const isAmber = tone === "amber";
  return (
    <span
      className="font-mono uppercase tracking-[0.22em]"
      style={{
        fontSize: 9,
        fontWeight: 600,
        color: isAmber ? AMBER : INK_FAINT,
        border: `1px solid ${isAmber ? AMBER : INK_RULE}`,
        padding: "3px 8px",
        borderRadius: 2,
        background: isAmber ? "rgba(196,125,28,0.06)" : "transparent",
      }}
    >
      {label}
    </span>
  );
}

// ─── Markup editor mock ──────────────────────────────────────────────

function MarkupEditor({
  lines,
  height,
  muted,
}: {
  lines: Line[];
  height: number;
  muted?: boolean;
}) {
  return (
    <div
      style={{
        background: muted ? "rgba(244,241,234,0.55)" : PAPER,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        height,
        position: "relative",
        overflow: "hidden",
      }}
    >
      {/* Gutter (line numbers) */}
      <div
        style={{
          position: "absolute",
          top: 0,
          bottom: 0,
          left: 0,
          width: 32,
          borderRight: `1px solid ${INK_RULE_S}`,
          background: "rgba(35,36,35,0.02)",
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
      {/* Code body */}
      <div style={{ paddingLeft: 44, paddingRight: 14, paddingTop: 14 }}>
        {lines.map((line, i) => (
          <MarkupLine key={i} line={line} muted={muted} />
        ))}
      </div>
      {/* Caret hint, bottom right */}
      <div
        className="font-mono uppercase tracking-[0.20em]"
        style={{
          position: "absolute",
          bottom: 8,
          right: 12,
          fontSize: 9,
          color: INK_FAINTER,
        }}
      >
        ⌘↵ run · ⌘S save
      </div>
    </div>
  );
}

function MarkupLine({ line, muted }: { line: Line; muted?: boolean }) {
  if (line.kind === "blank") {
    return <div style={{ height: 20 }} />;
  }
  if (line.kind === "kw") {
    return (
      <div className="font-mono" style={{ fontSize: 12, lineHeight: "20px" }}>
        <span style={{ color: muted ? "rgba(196,125,28,0.6)" : AMBER, fontWeight: 600 }}>
          {line.word.padEnd(5, " ")}
        </span>
        <span style={{ color: muted ? INK_FAINT : INK }}>{line.rest}</span>
      </div>
    );
  }
  return (
    <div className="font-mono" style={{ fontSize: 12, lineHeight: "20px" }}>
      <span style={{ color: INK_FAINTER }}>      ↳ </span>
      <span style={{ color: muted ? INK_FAINT : INK }}>{line.text}</span>
    </div>
  );
}

// ─── Outline pane ────────────────────────────────────────────────────

function OutlinePane() {
  return (
    <div
      style={{
        background: PAPER,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        height: 236,
        padding: "14px 14px",
      }}
    >
      {OUTLINE.map((section, i) => (
        <div key={section.label} style={{ marginBottom: i === OUTLINE.length - 1 ? 0 : 12 }}>
          <div
            className="font-mono font-semibold uppercase tracking-[0.22em]"
            style={{ fontSize: 9, color: BRASS, marginBottom: 4 }}
          >
            {section.label}
          </div>
          {section.items.map((it) => (
            <div
              key={it}
              className="font-mono"
              style={{ fontSize: 11, color: INK, lineHeight: "18px" }}
            >
              {it}
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

// ─── Chat pane ───────────────────────────────────────────────────────

function ChatPane({
  thread,
  compact,
}: {
  thread: { who: "you" | "agent"; text: string }[];
  compact?: boolean;
}) {
  const h = compact ? 236 : 280;
  return (
    <div
      style={{
        background: CREAM,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        height: h,
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
            style={{ fontSize: 12.5, lineHeight: 1.5, color: INK, fontStyle: m.who === "agent" ? "italic" : "normal" }}
          >
            {m.text}
          </div>
        </div>
      ))}
      <div style={{ flex: 1 }} />
      <ChatInputRow />
    </div>
  );
}

function ChatInputRow() {
  return (
    <div
      className="flex items-center gap-2"
      style={{
        borderTop: `1px solid ${INK_RULE_S}`,
        paddingTop: 8,
      }}
    >
      <span
        className="font-mono"
        style={{ fontSize: 11, color: INK_FAINT }}
      >
        ▌
      </span>
      <span className="font-display italic" style={{ fontSize: 12, color: INK_FAINTER }}>
        ask the agent · or dictate
      </span>
      <div className="ml-auto flex items-center gap-2">
        <Chip label="VOICE" tone="amber" />
      </div>
    </div>
  );
}

// ─── Console panes ───────────────────────────────────────────────────

function ConsolePane({ lines }: { lines: { ok: boolean; text: string }[] }) {
  return (
    <div
      style={{
        background: PAPER,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        padding: "12px 14px",
      }}
    >
      <div className="flex items-baseline justify-between" style={{ marginBottom: 8 }}>
        <span
          className="font-mono font-semibold uppercase tracking-[0.24em]"
          style={{ fontSize: 9, color: INK_FAINT }}
        >
          · console · last run
        </span>
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: INK_FAINTER }}
        >
          12:04:18 · 2.1s
        </span>
      </div>
      <div className="font-mono" style={{ fontSize: 11.5, lineHeight: "20px", color: INK }}>
        <div style={{ color: AMBER }}>{"> run skill log-bug"}</div>
        {lines.map((l, i) => (
          <div key={i}>
            <span style={{ color: l.ok ? BRASS : "#B14B3C", marginRight: 8 }}>✓</span>
            {l.text}
          </div>
        ))}
      </div>
    </div>
  );
}

function ConsoleStrip() {
  return (
    <div
      className="flex items-center gap-3"
      style={{
        background: PAPER,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        padding: "8px 14px",
      }}
    >
      <span
        className="font-mono font-semibold uppercase tracking-[0.24em]"
        style={{ fontSize: 9, color: INK_FAINT }}
      >
        · console
      </span>
      <span className="font-mono" style={{ fontSize: 11, color: INK }}>
        <span style={{ color: BRASS, marginRight: 6 }}>✓</span>
        github.issue #842 · voice ack 1.2s
      </span>
      <div className="ml-auto">
        <Chip label="RUN" tone="amber" />
      </div>
    </div>
  );
}

// ─── Map pane ────────────────────────────────────────────────────────

function MapPane() {
  const nodes = [
    { kind: "trigger", label: "voice" },
    { kind: "input",   label: "screenshot" },
    { kind: "input",   label: "paragraph" },
    { kind: "action",  label: "github.issue" },
    { kind: "confirm", label: "voice ack" },
  ];
  return (
    <div
      style={{
        background: PAPER,
        border: `1px solid ${INK_RULE_S}`,
        borderRadius: 4,
        height: 236,
        padding: "16px 14px",
      }}
    >
      {nodes.map((n, i) => (
        <div key={n.label}>
          <MapNode kind={n.kind} label={n.label} />
          {i < nodes.length - 1 && <MapConnector />}
        </div>
      ))}
    </div>
  );
}

function MapNode({ kind, label }: { kind: string; label: string }) {
  const glyph = ({
    trigger: "○",
    input:   "◇",
    action:  "▢",
    confirm: "○",
  } as Record<string, string>)[kind] ?? "·";
  const isAction = kind === "action";
  return (
    <div className="flex items-baseline gap-2">
      <span
        className="font-mono"
        style={{
          fontSize: 13,
          color: isAction ? AMBER : INK_FAINT,
          width: 14,
          display: "inline-block",
        }}
      >
        {glyph}
      </span>
      <span
        className="font-mono uppercase tracking-[0.10em]"
        style={{
          fontSize: 10.5,
          color: isAction ? AMBER : INK,
          fontWeight: isAction ? 600 : 400,
        }}
      >
        {label}
      </span>
    </div>
  );
}

function MapConnector() {
  return (
    <div
      style={{
        marginLeft: 6,
        height: 14,
        width: 1,
        background: INK_RULE,
      }}
    />
  );
}
