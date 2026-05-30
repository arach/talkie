"use client";

/**
 * Mac Agent Home — restrained conversation surface.
 *
 * Discipline:
 *   - One accent color (amber), used only for live/working state.
 *   - One sans family for all body. Mono only for file paths, model
 *     ids, and timecodes.
 *   - Three weights (regular, medium, semibold). Five sizes (11, 12,
 *     13, 14, 15). Spacing on a 4/8/12/16/24/32 scale.
 *   - No gradients. No tinted chips. No decorative dots. Typography
 *     and whitespace do the hierarchy.
 *   - Borders only where structurally needed; hover/selected via
 *     background alone.
 *
 * Each Talkie reply tucks its work (a one-line summary, the action
 * log of what the agent did, and a receipt) behind a quiet "Show
 * work" link.
 */

import React from "react";
import { SCOPE } from "@/lib/scope-tokens";

// ── Types ─────────────────────────────────────────────────────────────

type JobStatus = "waiting" | "running" | "done" | "failed";
type ActionKind = "read" | "write" | "run" | "search" | "think";
type TurnSource = "voice" | "typed";

interface Action {
  kind: ActionKind;
  target: string;
  detail?: string;
  status: JobStatus;
}

interface Turn {
  id: string;
  source: TurnSource;
  askedAt: string;
  returnedAt?: string;
  status: JobStatus;
  identity: { provider: string; model: string; runtime: string };
  ask: string;
  ack: string;
  spoken?: string;
  response?: string;
  summary?: string;
  actions: Action[];
  latency?: string;
  played?: boolean;
}

interface Conversation {
  id: string;
  title: string;
  startedAt: string;
  lastActivity: string;
  preview?: string;
  turns: Turn[];
}

const ACTION_GLYPH: Record<ActionKind, string> = {
  read:   "R",
  write:  "W",
  run:    "$",
  search: "?",
  think:  "·",
};

// One reader column for header, transcript, composer — every outer edge aligns.
const READER_COLUMN = 720;
const READER_GUTTER = 32;

// ── Fixtures ──────────────────────────────────────────────────────────

const TURNS: Turn[] = [
  {
    id: "T-176",
    source: "voice",
    askedAt: "10:58",
    returnedAt: "10:59",
    status: "done",
    identity: { provider: "openai", model: "gpt-5.1-mini", runtime: "walkie-node" },
    ask: "Draft three taglines for the conversation surface — I want one that doesn't sound like a chat app.",
    ack: "Three drafts coming up. Keeping it product-flavored, not marketing.",
    spoken:
      "Closest one feels like 'A room where the conversation does the work.' Want me to push on that one, or try a fresh batch?",
    response:
      "Three drafts: (1) “Say it once, let Talkie keep working.” (2) “A room where the conversation does the work.” (3) “Talk back — Talkie's still here.”",
    summary: "Drafted three taglines from the project's voice and tone notes; no files touched.",
    latency: "32s",
    played: true,
    actions: [
      { kind: "read",  target: "docs/voice/tone.md",       detail: "84 lines",    status: "done" },
      { kind: "think", target: "Drafted three candidates", detail: "no tool use", status: "done" },
    ],
  },
  {
    id: "T-180",
    source: "typed",
    askedAt: "11:21",
    returnedAt: "11:23",
    status: "done",
    identity: { provider: "anthropic", model: "claude-opus-4.7", runtime: "talkie-agent" },
    ask: "What's actually in AgentHomeView today? I want to know what I'd port back.",
    ack: "Reading the Swift surface and the executor trace view now.",
    spoken:
      "It's already a conversation — trunk plus per-turn cards with transcript, ack, threads, response, and a continue affordance. Sidebar is just topics.",
    response:
      "AgentHomeView is an HStack(sidebar | detail). Detail renders AgentHomeExecutorTraceView (trunk + per-turn header, transcript, ack, threads, response, spoken summary with Continue) and a prompt bar. Status is polled every 5s from the Node runtime.",
    summary: "Read the three files that make up Agent Home in Swift and summarized the shape.",
    latency: "1m 04s",
    played: true,
    actions: [
      { kind: "read",   target: "AgentHomeView.swift",                detail: "578 lines", status: "done" },
      { kind: "read",   target: "AgentHomeExecutorTraceView.swift",   detail: "906 lines", status: "done" },
      { kind: "read",   target: "AgentHomeActivityStore.swift",       detail: "600 lines", status: "done" },
      { kind: "search", target: 'grep "AgentHomeExecutorJob"',         detail: "12 hits",   status: "done" },
    ],
  },
  {
    id: "T-184",
    source: "voice",
    askedAt: "11:42",
    returnedAt: "11:46",
    status: "done",
    identity: { provider: "openai", model: "gpt-5.1-codex", runtime: "codex-walkie" },
    ask: "Take a studio design pass for Agent Home. The product abstraction is one conversation surface — topics, turns, attached threads, returned answers.",
    ack: "Got it. Reshaping the studio route around the conversation, not the dashboard.",
    spoken:
      "Studio pass is up. The surface reads as a normal conversation now — two voices, tight rhythm, work tucked behind a quiet show-work link. Take a look and tell me what to push on.",
    response:
      "Reframed the studio component as a linear conversation. Each session lives in the sidebar; the feed is You → Talkie back-and-forth; every Talkie reply tucks its work (what was read, written, run) behind a quiet show-work link.",
    summary:
      "Read the existing Swift surface (≈2,100 lines), rewrote the studio component from scratch, updated the route, and confirmed the page compiles.",
    latency: "3m 48s",
    played: true,
    actions: [
      { kind: "read",  target: "AgentHomeView.swift",                 detail: "578 lines",    status: "done" },
      { kind: "read",  target: "AgentHomeExecutorTraceView.swift",    detail: "906 lines",    status: "done" },
      { kind: "read",  target: "AgentHomeActivityStore.swift",        detail: "600 lines",    status: "done" },
      { kind: "read",  target: "design/studio/lib/scope-tokens.ts",   detail: "110 lines",    status: "done" },
      { kind: "write", target: "components/studies/MacAgentHome.tsx", detail: "+584 / -1402", status: "done" },
      { kind: "write", target: "app/mac-agent-home/page.tsx",         detail: "+52 / -57",    status: "done" },
      { kind: "run",   target: "curl localhost:3001/mac-agent-home",  detail: "200 OK",       status: "done" },
    ],
  },
  {
    id: "T-189",
    source: "voice",
    askedAt: "12:04",
    status: "running",
    identity: { provider: "openai", model: "gpt-5.1-codex", runtime: "codex-walkie" },
    ask: "Now run a feasibility pass on porting this back to AgentHomeView — what's mechanical, what needs the activity store to grow, and what's purely visual.",
    ack: "On it. Splitting into mechanical, store, and visual buckets.",
    summary: "Walking the three Swift files and comparing surfaces to the studio shape.",
    latency: "00:42",
    actions: [
      { kind: "read",   target: "AgentHomeView.swift",                  detail: "578 lines", status: "done" },
      { kind: "read",   target: "AgentHomeExecutorTraceView.swift",     detail: "906 lines", status: "done" },
      { kind: "read",   target: "AgentHomeActivityStore.swift",                              status: "running" },
      { kind: "search", target: 'grep "AgentHomeExecutorJob|Activity"',                      status: "waiting" },
    ],
  },
];

const CONVERSATIONS: Conversation[] = [
  { id: "agent-home-design", title: "Reshape Agent Home as a conversation", startedAt: "10:58",     lastActivity: "now",       turns: TURNS },
  { id: "runtime-audit",     title: "Executor runtime audit",                 startedAt: "yesterday", lastActivity: "1h",        turns: [] },
  { id: "standup-note",      title: "Standup note · navigation perf",         startedAt: "yesterday", lastActivity: "3h",        turns: [] },
  { id: "tagline-batch",     title: "Conversation surface taglines",          startedAt: "2d ago",    lastActivity: "yesterday", turns: [] },
  { id: "tlk-021-recap",     title: "TLK-021 recap for studio",               startedAt: "3d ago",    lastActivity: "2d ago",    turns: [] },
];

// ── Public ────────────────────────────────────────────────────────────

export interface MacAgentHomeProps {
  liveTurn?: boolean;
  expandedTurnId?: string;
  /** Render with no turns — surfaces the IdleHero in place of the transcript. */
  emptyState?: boolean;
}

export function MacAgentHome({
  liveTurn = true,
  expandedTurnId = "T-184",
  emptyState = false,
}: MacAgentHomeProps = {}) {
  const conversation = emptyState ? EMPTY_CONVERSATION : CONVERSATIONS[0];
  const turns = liveTurn
    ? conversation.turns
    : conversation.turns.filter((turn) => turn.status !== "running");
  const orderedTurns = [...turns].sort((a, b) => a.askedAt.localeCompare(b.askedAt));

  return (
    <section
      className="mx-auto overflow-hidden rounded-md"
      style={{
        width: "100%",
        maxWidth: 1180,
        background: SCOPE.canvas,
        color: SCOPE.ink,
        border: `0.5px solid ${SCOPE.edge}`,
        boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
        // Studio house style: mono for body and chrome, display (Newsreader)
        // reserved for headlines. Matches MacWalkie / MacMemoDetail.
        fontFamily: "var(--theme-font-mono)",
        WebkitFontSmoothing: "antialiased",
        MozOsxFontSmoothing: "grayscale",
        textRendering: "optimizeLegibility",
      }}
    >
      <Titlebar />
      <div className="grid" style={{ gridTemplateColumns: "240px minmax(0, 1fr)", minHeight: 800 }}>
        <Sidebar selectedId={conversation.id} />
        <Reader
          conversation={{ ...conversation, turns: orderedTurns }}
          expandedTurnId={expandedTurnId}
          idle={emptyState}
        />
      </div>
    </section>
  );
}

// A fresh, unnamed conversation. The sidebar entry exists (so the user
// sees their click registered) but the transcript is empty and the
// reader collapses into the IdleHero.
const EMPTY_CONVERSATION: Conversation = {
  id: "new-conversation",
  title: "New conversation",
  startedAt: "now",
  lastActivity: "now",
  turns: [],
};

// ── Titlebar ──────────────────────────────────────────────────────────

function Titlebar() {
  return (
    <div
      className="flex items-center gap-2 px-4 py-2.5"
      style={{ borderBottom: `0.5px solid ${SCOPE.edge}`, background: SCOPE.chrome }}
    >
      <div className="flex gap-1.5">
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
      </div>
      <div
        className="mx-auto text-[9px] font-mono uppercase"
        style={{
          color: SCOPE.inkFaint,
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.20em",
        }}
      >
        Talkie Agent
      </div>
      <div className="invisible flex gap-1.5">
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
        <span className="h-3 w-3 rounded-full" />
      </div>
    </div>
  );
}

// ── Sidebar ───────────────────────────────────────────────────────────

function Sidebar({ selectedId }: { selectedId: string }) {
  return (
    <aside className="flex min-w-0 flex-col" style={{ background: SCOPE.pane, borderRight: `0.5px solid ${SCOPE.edge}` }}>
      <div className="px-4 pt-4">
        <NewConversationButton />
      </div>

      <nav className="mt-3 flex flex-1 flex-col overflow-auto px-2 pb-4">
        {CONVERSATIONS.map((c, index) => {
          const prev = CONVERSATIONS[index - 1];
          const showGroup = !prev || groupOf(prev) !== groupOf(c);
          return (
            <React.Fragment key={c.id}>
              {showGroup ? <GroupLabel label={groupOf(c)} first={index === 0} /> : null}
              <ConversationRow conversation={c} selected={c.id === selectedId} />
            </React.Fragment>
          );
        })}
      </nav>
    </aside>
  );
}

function NewConversationButton() {
  return (
    <button
      type="button"
      className="flex w-full items-center justify-between rounded-[8px] px-3 py-2 text-[12.5px]"
      style={{
        background: SCOPE.white,
        color: SCOPE.ink,
        border: `0.5px solid ${SCOPE.edgeSubtle}`,
        fontWeight: 500,
        boxShadow: "0 0.5px 0 rgba(255,255,255,0.6) inset, 0 1px 1px rgba(28,28,26,0.02)",
      }}
    >
      <span className="flex items-center gap-2">
        <span
          className="text-[14px] leading-none"
          style={{ color: SCOPE.inkFainter, fontWeight: 400, marginTop: -1 }}
        >
          ＋
        </span>
        New conversation
      </span>
      <span
        className="text-[10px]"
        style={{
          color: SCOPE.inkFainter,
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.05em",
        }}
      >
        ⌘N
      </span>
    </button>
  );
}

function groupOf(c: Conversation): string {
  if (c.startedAt === "10:58") return "Today";
  if (c.startedAt === "yesterday") return "Yesterday";
  return "Earlier";
}

function GroupLabel({ label, first }: { label: string; first: boolean }) {
  return (
    <div
      className={`px-3 pb-1.5 text-[9px] uppercase ${first ? "pt-2" : "pt-4"}`}
      style={{
        color: SCOPE.inkFainter,
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.20em",
        fontWeight: 500,
      }}
    >
      · {label}
    </div>
  );
}

function ConversationRow({ conversation, selected }: { conversation: Conversation; selected: boolean }) {
  const live = conversation.turns.some((t) => t.status === "running");
  return (
    <button
      type="button"
      className="flex w-full items-center justify-between gap-2 rounded-[7px] px-3 py-2 text-left"
      style={{
        background: selected ? SCOPE.white : "transparent",
        boxShadow: selected ? "0 0.5px 1px rgba(28,28,26,0.04), 0 0.5px 0 rgba(28,28,26,0.03)" : "none",
      }}
    >
      <span
        className="min-w-0 flex-1 truncate text-[12px] leading-snug"
        style={{ color: SCOPE.ink, fontWeight: selected ? 600 : 400 }}
      >
        {conversation.title}
      </span>
      {live ? (
        <span className="flex items-center gap-1.5">
          <span
            className="text-[10.5px]"
            style={{ color: SCOPE.amberDeep, fontWeight: 600 }}
          >
            live
          </span>
          <span
            className="h-1.5 w-1.5 rounded-full"
            style={{ background: SCOPE.amber, boxShadow: `0 0 0 3px ${SCOPE.amberFaint}` }}
          />
        </span>
      ) : (
        <span className="text-[10.5px]" style={{ color: SCOPE.inkFainter, fontWeight: 500 }}>
          {conversation.lastActivity}
        </span>
      )}
    </button>
  );
}

// ── Reader ────────────────────────────────────────────────────────────

function Reader({
  conversation,
  expandedTurnId,
  idle = false,
}: {
  conversation: Conversation;
  expandedTurnId?: string;
  idle?: boolean;
}) {
  // Idle mode replaces the transcript + pinned-composer with a centered
  // IdleHero that owns the composer itself. The pinned composer at the
  // bottom is hidden so the hero's composer is the single focal point.
  if (idle) {
    return (
      <main className="flex min-w-0 flex-col" style={{ background: SCOPE.canvas }}>
        <ReaderHeader conversation={conversation} />
        <div className="flex-1 overflow-auto">
          <IdleHero conversation={conversation} />
        </div>
      </main>
    );
  }

  return (
    <main className="flex min-w-0 flex-col" style={{ background: SCOPE.canvas }}>
      <ReaderHeader conversation={conversation} />
      <div className="flex-1 overflow-auto">
        <div
          className="pb-8 pt-7"
          style={{ maxWidth: READER_COLUMN, paddingLeft: READER_GUTTER, paddingRight: READER_GUTTER, boxSizing: "content-box" }}
        >
          <Transcript turns={conversation.turns} expandedTurnId={expandedTurnId} />
        </div>
      </div>
      <Composer conversation={conversation} />
    </main>
  );
}

function ReaderHeader({ conversation }: { conversation: Conversation }) {
  const live = conversation.turns.some((t) => t.status === "running");
  return (
    <header className="border-b" style={{ borderColor: SCOPE.ruleSoft }}>
      <div
        className="flex items-center justify-between gap-3 py-5"
        style={{ maxWidth: READER_COLUMN, paddingLeft: READER_GUTTER, paddingRight: READER_GUTTER, boxSizing: "content-box" }}
      >
        <div className="min-w-0">
          <div
            className="mb-1.5 text-[9px] uppercase"
            style={{
              color: SCOPE.inkFainter,
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.20em",
              fontWeight: 500,
            }}
          >
            · Conversation
          </div>
          <h1
            className="truncate text-[22px] leading-tight"
            style={{
              color: SCOPE.ink,
              fontFamily: "var(--theme-font-display)",
              fontWeight: 500,
              letterSpacing: -0.3,
            }}
          >
            {conversation.title}
          </h1>
          <p className="mt-1.5 text-[11.5px]" style={{ color: SCOPE.inkFaint, fontWeight: 400 }}>
            Today {conversation.startedAt}
            <span style={{ color: SCOPE.inkFainter }}> · </span>
            {conversation.turns.length} {conversation.turns.length === 1 ? "turn" : "turns"}
            {live ? (
              <>
                <span style={{ color: SCOPE.inkFainter }}> · </span>
                <span style={{ color: SCOPE.amberDeep, fontWeight: 600 }}>working now</span>
              </>
            ) : null}
          </p>
        </div>
      </div>
    </header>
  );
}

// ── Transcript ────────────────────────────────────────────────────────

function Transcript({ turns, expandedTurnId }: { turns: Turn[]; expandedTurnId?: string }) {
  if (turns.length === 0) {
    return <EmptyRoom />;
  }
  // Turns within the same session are usually minutes apart — that does
  // not deserve a visual break. Absolute times live on hover, per
  // message (see Speech). If consecutive turns end up more than a day
  // apart, drop a DateDivider between them. (Not needed by the current
  // fixture but the hook is here.)
  return (
    <div className="flex flex-col gap-7">
      {turns.map((turn, index) => {
        const prev = turns[index - 1];
        const showDate = prev ? hoursBetween(prev.askedAt, turn.askedAt) >= 24 : false;
        return (
          <React.Fragment key={turn.id}>
            {showDate ? <DateDivider label={turn.askedAt} /> : null}
            <TurnBlock turn={turn} expanded={turn.id === expandedTurnId} />
          </React.Fragment>
        );
      })}
    </div>
  );
}

function hoursBetween(_a: string, _b: string): number {
  // Fixture stub. Real data carries Date objects; this is intentionally
  // 0 so the studio fixture never renders a divider.
  return 0;
}

function DateDivider({ label }: { label: string }) {
  return (
    <div className="my-2 flex items-center gap-3" aria-hidden>
      <span className="h-px flex-1" style={{ background: SCOPE.ruleSoft }} />
      <span
        className="text-[10px] uppercase"
        style={{
          color: SCOPE.inkFainter,
          fontFamily: "var(--theme-font-mono)",
          fontWeight: 500,
          letterSpacing: "0.18em",
        }}
      >
        {label}
      </span>
      <span className="h-px flex-1" style={{ background: SCOPE.ruleSoft }} />
    </div>
  );
}

function EmptyRoom() {
  // Used only as a fallback inside Transcript (e.g. if a populated
  // conversation drops to zero turns at runtime). The first-class
  // "fresh conversation" surface is IdleHero, rendered by Reader.
  return (
    <div className="mx-auto mt-12 max-w-[280px] text-center">
      <p className="text-[13px]" style={{ color: SCOPE.inkMid, fontWeight: 500 }}>
        Say something to start.
      </p>
      <p className="mt-1 text-[11px]" style={{ color: SCOPE.inkFainter }}>
        type below, or hold ⌃⌥⌘T to talk
      </p>
    </div>
  );
}

// ── IdleHero ──────────────────────────────────────────────────────────
//
// First-class surface for a fresh conversation. Borrows from MacWalkie's
// "press to transmit" idle state but quieted into something that reads
// editorial rather than instrumental:
//
//   - Headline is a question, not a command.
//   - One amber focal point (the mic disc) — the rest is ink-on-paper.
//   - Composer is *inside* the hero (focused-by-default in real life)
//     so the next action is obvious without needing a chrome handoff.
//   - Starters are conversational ("where did I leave off?"), not
//     feature labels ("Verbal · Async · Context · Channels").
//
// The intent: starting a new conversation should feel like opening a
// fresh notebook page — frequent, low-friction, slightly inviting.

function IdleHero({ conversation }: { conversation: Conversation }) {
  return (
    <div
      className="mx-auto flex flex-col items-stretch"
      style={{
        maxWidth: READER_COLUMN,
        paddingLeft: READER_GUTTER,
        paddingRight: READER_GUTTER,
        paddingTop: 64,
        paddingBottom: 32,
        boxSizing: "content-box",
      }}
    >
      <div className="flex flex-col items-center gap-5 text-center">
        <IdleMic />

        <div className="flex flex-col gap-2">
          <span
            className="text-[10px] uppercase"
            style={{
              color: SCOPE.inkFainter,
              fontFamily: "var(--theme-font-mono)",
              fontWeight: 500,
              letterSpacing: "0.22em",
            }}
          >
            · NEW CONVERSATION
          </span>
          <h2
            className="text-[26px] leading-tight"
            style={{
              color: SCOPE.ink,
              fontFamily: "var(--theme-font-display)",
              fontWeight: 500,
              letterSpacing: -0.4,
            }}
          >
            What are you working on?
          </h2>
          <p
            className="text-[12px]"
            style={{
              color: SCOPE.inkFaint,
              fontFamily: "var(--theme-font-mono)",
              fontWeight: 400,
            }}
          >
            say it, type it, or hold{" "}
            <kbd
              className="rounded px-1.5 py-[1px] text-[10.5px]"
              style={{
                color: SCOPE.inkMid,
                background: SCOPE.white,
                border: `0.5px solid ${SCOPE.edgeSubtle}`,
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.04em",
              }}
            >
              ⌃⌥⌘T
            </kbd>{" "}
            for Walkie
          </p>
        </div>
      </div>

      <div className="mt-8">
        <Composer conversation={conversation} />
      </div>

      <Starters />
    </div>
  );
}

function IdleMic() {
  return (
    <div className="relative">
      <span
        aria-hidden
        className="absolute inset-0 rounded-full"
        style={{
          background: SCOPE.amberFaint,
          transform: "scale(1.55)",
          opacity: 0.55,
          filter: "blur(8px)",
        }}
      />
      <div
        className="relative flex h-14 w-14 items-center justify-center rounded-full"
        style={{
          background: SCOPE.amber,
          color: SCOPE.white,
          boxShadow:
            "0 0.5px 0 rgba(255,255,255,0.7) inset, 0 1px 2px rgba(28,28,26,0.10), 0 6px 14px rgba(196,125,28,0.18)",
        }}
      >
        <MicGlyph tint={SCOPE.white} large />
      </div>
    </div>
  );
}

const STARTER_PROMPTS: { label: string; hint?: string }[] = [
  { label: "Where did I leave off?", hint: "recent activity" },
  { label: "Search my memos for …",  hint: "library" },
  { label: "What's in my tray?",     hint: "captures" },
];

function Starters() {
  return (
    <div className="mt-7 flex flex-col items-center gap-3">
      <span
        className="text-[9px] uppercase"
        style={{
          color: SCOPE.inkFainter,
          fontFamily: "var(--theme-font-mono)",
          fontWeight: 500,
          letterSpacing: "0.22em",
        }}
      >
        · OR PICK UP SOMETHING
      </span>
      <div className="flex flex-wrap items-center justify-center gap-1.5">
        {STARTER_PROMPTS.map((p) => (
          <StarterChip key={p.label} label={p.label} hint={p.hint} />
        ))}
      </div>
    </div>
  );
}

function StarterChip({ label, hint }: { label: string; hint?: string }) {
  return (
    <button
      type="button"
      className="group flex items-center gap-2 rounded-full px-3 py-1.5 transition"
      style={{
        background: SCOPE.white,
        border: `0.5px solid ${SCOPE.edgeSubtle}`,
        boxShadow: "0 0.5px 0 rgba(255,255,255,0.6) inset, 0 0.5px 1px rgba(28,28,26,0.03)",
        color: SCOPE.ink,
        fontFamily: "var(--theme-font-mono)",
        fontSize: 11.5,
        fontWeight: 500,
      }}
    >
      <span style={{ color: SCOPE.inkMid }}>{label}</span>
      {hint ? (
        <span
          className="text-[9px] uppercase"
          style={{
            color: SCOPE.inkFainter,
            letterSpacing: "0.18em",
            fontWeight: 500,
          }}
        >
          {hint}
        </span>
      ) : null}
    </button>
  );
}

// ── Turn ──────────────────────────────────────────────────────────────

function TurnBlock({ turn, expanded }: { turn: Turn; expanded: boolean }) {
  const [open, setOpen] = React.useState(expanded);
  React.useEffect(() => setOpen(expanded), [expanded]);

  const isLive = turn.status === "running";
  const talkieBody = isLive ? turn.ack : turn.spoken ?? turn.ack;

  return (
    <div
      className="flex flex-col gap-5"
      style={{
        borderLeft: isLive ? `2px solid ${SCOPE.amber}` : "2px solid transparent",
        paddingLeft: isLive ? 14 : 16,
        transition: "border-color 200ms ease",
      }}
    >
      <Speech speaker="You" body={turn.ask} time={turn.askedAt} />
      <Speech
        speaker="Talkie"
        meta={isLive ? "working" : turn.latency}
        live={isLive}
        body={talkieBody}
        italic={isLive}
        time={turn.returnedAt ?? turn.askedAt}
        footer={<ShowWork turn={turn} open={open} onToggle={() => setOpen((v) => !v)} />}
      />
    </div>
  );
}

interface SpeechProps {
  speaker: "You" | "Talkie";
  meta?: string;
  live?: boolean;
  body: string;
  italic?: boolean;
  time?: string;
  footer?: React.ReactNode;
}

function Speech({ speaker, meta, live = false, body, italic = false, time, footer }: SpeechProps) {
  const isTalkie = speaker === "Talkie";
  return (
    <div className="group grid gap-x-3" style={{ gridTemplateColumns: "26px minmax(0, 1fr)" }}>
      <Avatar speaker={speaker} live={live} />
      <div className="min-w-0">
        <div className="flex items-baseline gap-2">
          <span
            className="text-[10px] uppercase"
            style={{
              color: SCOPE.ink,
              fontWeight: 600,
              letterSpacing: "0.18em",
            }}
          >
            {speaker}
          </span>
          {meta ? (
            <span
              className="text-[10px] tabular-nums"
              style={{
                color: live ? SCOPE.amberDeep : SCOPE.inkFainter,
                fontWeight: live ? 600 : 500,
              }}
            >
              · {meta}
            </span>
          ) : null}
          {live ? (
            <span
              className="ml-0.5 h-1.5 w-1.5 rounded-full"
              style={{ background: SCOPE.amber, boxShadow: `0 0 0 3px ${SCOPE.amberFaint}` }}
              aria-hidden
            />
          ) : null}
          {time ? (
            <span
              className="ml-auto pl-3 text-[10px] tabular-nums opacity-0 transition-opacity duration-150 group-hover:opacity-100"
              style={{ color: SCOPE.inkFainter, fontWeight: 500 }}
              title={`Sent at ${time}`}
            >
              {time}
            </span>
          ) : null}
        </div>
        <p
          className="mt-1.5 text-[13px] leading-[1.55]"
          style={{
            color: italic ? SCOPE.inkMid : SCOPE.ink,
            fontStyle: italic ? "italic" : "normal",
            fontWeight: 400,
          }}
        >
          {italic ? <>“{body}”</> : body}
        </p>
        {footer ? <div className="mt-3">{footer}</div> : null}
      </div>
    </div>
  );
}

function Avatar({ speaker, live }: { speaker: "You" | "Talkie"; live: boolean }) {
  const isTalkie = speaker === "Talkie";
  const initial = isTalkie ? "T" : "Y";
  const bg = isTalkie ? SCOPE.amberFaint : "rgba(35,36,35,0.05)";
  const fg = isTalkie ? SCOPE.amberDeep : SCOPE.inkMid;
  return (
    <span
      className="flex h-[22px] w-[22px] items-center justify-center rounded-[6px] text-[10.5px]"
      style={{
        background: bg,
        color: fg,
        fontWeight: 600,
        letterSpacing: -0.2,
        marginTop: 1,
      }}
      aria-hidden
    >
      {initial}
    </span>
  );
}

// ── Show work ─────────────────────────────────────────────────────────

function ShowWork({ turn, open, onToggle }: { turn: Turn; open: boolean; onToggle: () => void }) {
  return (
    <>
      <button
        type="button"
        onClick={onToggle}
        className="text-[11px]"
        style={{ color: SCOPE.inkFainter, fontWeight: 500 }}
      >
        {open ? "Hide work" : "Show work"}
      </button>
      {open ? <WorkBlock turn={turn} /> : null}
    </>
  );
}

function WorkBlock({ turn }: { turn: Turn }) {
  return (
    <div className="mt-3 flex flex-col gap-3">
      {turn.summary ? (
        <p className="text-[12.5px] leading-snug" style={{ color: SCOPE.inkMid, fontWeight: 400 }}>
          {turn.summary}
        </p>
      ) : null}

      {turn.actions.length > 0 ? (
        <ul className="flex flex-col gap-[3px]">
          {turn.actions.map((action, index) => (
            <ActionRow key={`${action.kind}-${index}`} action={action} />
          ))}
        </ul>
      ) : null}

      {turn.response && turn.response !== turn.spoken ? (
        <p className="text-[12.5px] leading-snug" style={{ color: SCOPE.inkMid, fontWeight: 400 }}>
          {turn.response}
        </p>
      ) : null}

      <p
        className="text-[10.5px]"
        style={{ color: SCOPE.inkFainter, fontFamily: "var(--theme-font-mono)", fontWeight: 500 }}
      >
        {turn.identity.provider} / {turn.identity.model} · {turn.latency ?? "—"}
      </p>
    </div>
  );
}

function ActionRow({ action }: { action: Action }) {
  const isLive = action.status === "running";
  const isQueued = action.status === "waiting";
  const isFailed = action.status === "failed";

  return (
    <li
      className="flex items-center gap-2.5 text-[11.5px]"
      style={{ color: isQueued ? SCOPE.inkFainter : SCOPE.inkMid, opacity: isQueued ? 0.75 : 1 }}
    >
      <span
        className="w-[10px] shrink-0 text-center text-[10.5px]"
        style={{
          color: isFailed ? SCOPE.alert : SCOPE.inkFainter,
          fontFamily: "var(--theme-font-mono)",
          fontWeight: 600,
        }}
      >
        {ACTION_GLYPH[action.kind]}
      </span>
      <span
        className="min-w-0 flex-1 truncate"
        style={{
          fontFamily: "var(--theme-font-mono)",
          fontSize: 11.5,
          color: isQueued ? SCOPE.inkFainter : SCOPE.ink,
          fontWeight: 400,
        }}
      >
        {action.target}
      </span>
      {action.detail ? (
        <span
          className="text-[10.5px] tabular-nums"
          style={{ color: SCOPE.inkFainter, fontFamily: "var(--theme-font-mono)", fontWeight: 500 }}
        >
          {action.detail}
        </span>
      ) : null}
      {isLive ? (
        <span className="h-1.5 w-1.5 rounded-full" style={{ background: SCOPE.amber }} aria-hidden />
      ) : isQueued ? (
        <span className="text-[10px]" style={{ color: SCOPE.inkFainter, fontWeight: 500 }}>queued</span>
      ) : isFailed ? (
        <span className="text-[10px]" style={{ color: SCOPE.alert, fontWeight: 600 }}>failed</span>
      ) : null}
    </li>
  );
}

// ── Composer ──────────────────────────────────────────────────────────

function Composer({ conversation }: { conversation: Conversation }) {
  const placeholder =
    conversation.turns.length === 0
      ? "Say something — or hold ⌃⌥⌘T to talk"
      : "Reply — type, or hold ⌃⌥⌘T to talk";

  return (
    <div
      className="pb-6 pt-4"
      style={{ background: `linear-gradient(180deg, transparent, ${SCOPE.canvas} 40%)` }}
    >
      <div
        style={{ maxWidth: READER_COLUMN, paddingLeft: READER_GUTTER, paddingRight: READER_GUTTER, boxSizing: "content-box" }}
      >
      <div
        className="flex items-center gap-2.5 rounded-[14px] px-3 py-2.5"
        style={{
          background: SCOPE.white,
          border: `0.5px solid ${SCOPE.edge}`,
          boxShadow:
            "0 0.5px 0 rgba(255,255,255,0.7) inset, 0 1px 2px rgba(28,28,26,0.04), 0 12px 28px rgba(28,28,26,0.06)",
        }}
      >
        <button
          type="button"
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full transition"
          style={{
            color: SCOPE.amberDeep,
            background: SCOPE.amberFaint,
          }}
          title="Hold to talk · ⌃⌥⌘T"
        >
          <MicGlyph tint={SCOPE.amberDeep} />
        </button>
        <textarea
          rows={1}
          placeholder={placeholder}
          className="min-h-[22px] flex-1 resize-none bg-transparent px-1 text-[13px] leading-[1.5] outline-none placeholder:text-[var(--placeholder)]"
          style={{
            color: SCOPE.ink,
            ["--placeholder" as string]: SCOPE.inkFainter,
            fontWeight: 400,
          }}
        />
        <button
          type="button"
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full transition"
          style={{
            color: SCOPE.inkFainter,
            background: "transparent",
          }}
          title="Send (⏎)"
        >
          <SendGlyph tint={SCOPE.inkFainter} />
        </button>
      </div>
      </div>
    </div>
  );
}

// ── Glyphs ────────────────────────────────────────────────────────────

function MicGlyph({ tint, large = false }: { tint: string; large?: boolean }) {
  const size = large ? "h-6 w-6" : "h-4 w-4";
  const sw = large ? 1.4 : 1.1;
  return (
    <svg viewBox="0 0 16 16" className={size} aria-hidden>
      <rect x={6} y={2.5} width={4} height={7} rx={2} stroke={tint} strokeWidth={sw} fill="none" />
      <path d="M3.5 8.5 a4.5 4.5 0 0 0 9 0" stroke={tint} strokeWidth={sw} fill="none" strokeLinecap="round" />
      <line x1={8} y1={13} x2={8} y2={14.2} stroke={tint} strokeWidth={sw} strokeLinecap="round" />
    </svg>
  );
}

function SendGlyph({ tint }: { tint: string }) {
  return (
    <svg viewBox="0 0 16 16" className="h-4 w-4" aria-hidden>
      <path d="M2.5 8 L13 3 L8 13.5 L7 9 Z" stroke={tint} strokeWidth={1.1} fill="none" strokeLinejoin="round" />
    </svg>
  );
}
