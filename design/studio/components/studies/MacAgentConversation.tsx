"use client";

/**
 * Mac Agent Conversation — revamp of the Conversations tab.
 *
 * Revises the live AgentHomeView per direction:
 *   - No top status strip (runtime/adapters/bridge) — it lived on Home now.
 *   - Sidebar is just the conversation list + a quiet "+" to start one.
 *     Creating a conversation opens an AGENT PICKER (pick who you talk to).
 *   - The adapter roster is gone from the always-on sidebar; it's a subtle
 *     "Agents" settings entry in the footer, kept apart from global Settings.
 *   - Per-conversation settings move to a TOP-RIGHT gear in the reader.
 *   - The active agent rides next to the INPUT (composer), so "who am I
 *     talking to" sits where you type — not scattered up top.
 *
 * Two toggles capture the ambiguous calls:
 *   - agentPlacement: "composer" (chip above the input) vs "header"
 *     (chip in the top-right cluster).
 *   - surface: "active" (a real transcript) vs "new" (agent picker open,
 *     idle hero).
 *
 * House style mirrors Agent Home: Talkie's cool-gray Scope substrate and ink
 * hierarchy, steel Agent chrome, one signal-blue interaction color, mono for
 * paths / timecodes, and one serif moment for the conversation title.
 */

import React from "react";
import { SCOPE } from "@/lib/scope-tokens";

const AGENT = {
  chrome: "#E7EBEE",
  signal: "#486888",
  signalStrong: "#314E6B",
  signalFaint: "rgba(72,104,136,0.10)",
  signalBorder: "rgba(72,104,136,0.28)",
  signalGlow: "rgba(72,104,136,0.22)",
};

// ── Types / fixtures ──────────────────────────────────────────────────

interface Agent {
  id: string;
  name: string;
  status: "ready" | "setup" | "offline";
  isDefault?: boolean;
  hint: string;
}

const AGENTS: Agent[] = [
  { id: "codex", name: "Codex", status: "ready", isDefault: true, hint: "gpt-5.1-codex" },
  { id: "claude", name: "Claude Code", status: "ready", hint: "claude-opus-4.8" },
  { id: "opencode", name: "OpenCode", status: "ready", hint: "local" },
  { id: "pi", name: "Pi", status: "ready", hint: "reasoning" },
  { id: "echo", name: "Echo", status: "ready", hint: "voice" },
];

interface Conversation {
  id: string;
  title: string;
  wire?: string;
  group: "Today" | "Earlier";
  stamp: string;
  working?: boolean;
}

const CONVERSATIONS: Conversation[] = [
  { id: "ch-01", title: "CH 01", wire: "reply:agent38", group: "Today", stamp: "1m", working: false },
  { id: "memos", title: "Search my memos for …", wire: "err:walkie9", group: "Earlier", stamp: "12d" },
  { id: "general", title: "General", wire: "err:walkie5", group: "Earlier", stamp: "12d" },
];

interface Turn {
  speaker: "You" | "Talkie";
  body: string;
  meta?: string;
  time: string;
}

const TURNS: Turn[] = [
  {
    speaker: "You",
    time: "1m 55s",
    body: "Are you able to get some actions to happen? Like research the latest announcement by NVIDIA about laptop chip production.",
  },
  {
    speaker: "Talkie",
    time: "1m 55s",
    meta: "Codex · 1m 55s",
    body: "Researched the latest NVIDIA laptop-chip announcement. NVIDIA announced RTX Spark, a Windows PC/laptop “superchip” for local AI agents, creators, and gaming, at GTC Taipei / Computex 2026.",
  },
];

const READER_COLUMN = 720;
const READER_GUTTER = 32;

export type ConversationSurface = "active" | "new";

export interface MacAgentConversationProps {
  surface?: ConversationSurface;
}

// ── Public ────────────────────────────────────────────────────────────

export function MacAgentConversation({
  surface = "active",
}: MacAgentConversationProps = {}) {
  const isNew = surface === "new";
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
        fontFamily: "var(--theme-font-mono)",
        WebkitFontSmoothing: "antialiased",
        MozOsxFontSmoothing: "grayscale",
        textRendering: "optimizeLegibility",
      }}
    >
      <Titlebar />
      <div className="grid" style={{ gridTemplateColumns: "248px minmax(0, 1fr)", minHeight: 760 }}>
        <Sidebar creatingNew={isNew} />
        <Reader isNew={isNew} />
      </div>
    </section>
  );
}

// ── Titlebar ──────────────────────────────────────────────────────────

function Titlebar() {
  return (
    <div
      className="flex items-center gap-2 px-4 py-2.5"
      style={{ borderBottom: `0.5px solid ${SCOPE.edge}`, background: AGENT.chrome }}
    >
      <div className="flex gap-1.5">
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
        <span className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
      </div>
      <div
        className="mx-auto text-[9px] uppercase"
        style={{ color: SCOPE.inkFaint, letterSpacing: "0.20em" }}
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

function Sidebar({ creatingNew }: { creatingNew: boolean }) {
  return (
    <aside
      className="flex min-w-0 flex-col"
      style={{ background: AGENT.chrome, borderRight: `0.5px solid ${SCOPE.edge}` }}
    >
      {/* List header — quiet "+" replaces the big New conversation button.
          Starting one just drops you into the main area; the agent is picked
          there (beside the composer), not in a top-left popover. */}
      <div className="flex items-center justify-between px-4 pt-4 pb-1">
        <span
          className="text-[9.5px] font-semibold uppercase"
          style={{ color: SCOPE.inkFainter, letterSpacing: "0.14em" }}
        >
          Conversations
        </span>
        <NewButton active={creatingNew} />
      </div>

      <nav className="mt-1 flex flex-1 flex-col overflow-auto px-2 pb-2">
        {CONVERSATIONS.map((c, i) => {
          const prev = CONVERSATIONS[i - 1];
          const showGroup = !prev || prev.group !== c.group;
          return (
            <React.Fragment key={c.id}>
              {showGroup ? <GroupLabel label={c.group} first={i === 0} /> : null}
              <ConversationRow conversation={c} selected={c.id === "ch-01" && !creatingNew} />
            </React.Fragment>
          );
        })}
      </nav>

      <SidebarFooter />
    </aside>
  );
}

function NewButton({ active }: { active: boolean }) {
  return (
    <button
      type="button"
      className="flex h-[22px] w-[22px] items-center justify-center rounded-[6px]"
      style={{
        background: active ? AGENT.signalFaint : "transparent",
        color: active ? AGENT.signal : SCOPE.inkFaint,
        border: `0.5px solid ${active ? AGENT.signalBorder : SCOPE.edgeSubtle}`,
      }}
      title="New conversation — pick an agent"
    >
      <span className="text-[14px] leading-none" style={{ marginTop: -1 }}>＋</span>
    </button>
  );
}

function GroupLabel({ label, first }: { label: string; first: boolean }) {
  return (
    <div
      className="px-3 text-[9px] font-semibold uppercase"
      style={{
        color: SCOPE.inkFainter,
        letterSpacing: "0.16em",
        paddingTop: first ? 8 : 16,
        paddingBottom: 6,
      }}
    >
      · {label}
    </div>
  );
}

function ConversationRow({ conversation, selected }: { conversation: Conversation; selected: boolean }) {
  return (
    <button
      type="button"
      className="flex w-full flex-col gap-[3px] rounded-[7px] px-3 py-2 text-left"
      style={{
        background: selected ? SCOPE.white : "transparent",
        boxShadow: selected ? "0 0.5px 1px rgba(28,28,26,0.04)" : "none",
      }}
    >
      <div className="flex items-center gap-2">
        <span
          className="flex-1 truncate text-[12px]"
          style={{ color: SCOPE.ink, fontWeight: selected ? 600 : 400 }}
        >
          {conversation.title}
        </span>
        {conversation.working ? (
          <span className="h-[6px] w-[6px] rounded-full" style={{ background: AGENT.signal }} />
        ) : (
          <span className="text-[10.5px]" style={{ color: SCOPE.inkFainter }}>
            {conversation.stamp}
          </span>
        )}
      </div>
      {conversation.wire ? (
        <span
          className="truncate text-[10px]"
          style={{ color: selected ? AGENT.signalStrong : SCOPE.inkFainter }}
        >
          ↩ CH-01 · TALKIE · {conversation.wire}
        </span>
      ) : null}
    </button>
  );
}

/**
 * Footer holds two DISTINCT settings entries, deliberately not a single
 * cluster: a subtle "Agents" band (the relocated adapter roster, now a
 * settings entry) bracketed by rules, then global Settings below it.
 */
function SidebarFooter() {
  const configured = AGENTS.length;
  return (
    <div className="mt-auto">
      <div style={{ borderTop: `0.5px solid ${SCOPE.edgeSubtle}` }} />
      <button
        type="button"
        className="flex w-full items-center gap-2 px-4 py-2.5 text-left"
        title="Manage agents & adapters"
      >
        <AgentsGlyph tint={SCOPE.inkFaint} />
        <span className="text-[11px]" style={{ color: SCOPE.inkMid }}>
          {configured} agents configured
        </span>
        <span className="ml-auto text-[10px]" style={{ color: SCOPE.inkFainter }}>
          Manage ›
        </span>
      </button>

      <div style={{ borderTop: `0.5px solid ${SCOPE.edgeSubtle}` }} />
      <button
        type="button"
        className="flex w-full items-center gap-2 px-4 py-2.5 text-left"
        title="Open Settings"
      >
        <GearGlyph tint={SCOPE.inkFaint} />
        <span className="text-[11.5px] font-medium" style={{ color: SCOPE.inkFaint }}>
          Settings
        </span>
      </button>
    </div>
  );
}

// ── Reader ────────────────────────────────────────────────────────────

function Reader({ isNew }: { isNew: boolean }) {
  return (
    <div className="flex flex-col" style={{ background: SCOPE.canvas }}>
      <ReaderHeader isNew={isNew} />
      <div style={{ borderTop: `0.5px solid ${SCOPE.edgeSubtle}` }} />

      {isNew ? (
        <IdleHero />
      ) : (
        <>
          <div className="flex-1 overflow-auto">
            <div
              className="flex flex-col gap-7"
              style={{
                maxWidth: READER_COLUMN + READER_GUTTER * 2,
                padding: `24px ${READER_GUTTER}px`,
              }}
            >
              {TURNS.map((t, i) => (
                <Speech key={i} turn={t} />
              ))}
            </div>
          </div>
          <Composer />
        </>
      )}
    </div>
  );
}

function ReaderHeader({ isNew }: { isNew: boolean }) {
  return (
    <div
      className="flex items-start gap-3"
      style={{ maxWidth: READER_COLUMN + READER_GUTTER * 2, padding: `22px ${READER_GUTTER}px 18px` }}
    >
      <div className="flex min-w-0 flex-col gap-1.5">
        <span
          className="text-[9px] font-semibold uppercase"
          style={{ color: SCOPE.inkFainter, letterSpacing: "0.16em" }}
        >
          · Conversation
        </span>
        <span
          className="truncate text-[22px]"
          style={{ color: SCOPE.ink, fontWeight: 500, fontFamily: "var(--theme-font-serif, Newsreader, serif)" }}
        >
          {isNew ? "New conversation" : "CH 01"}
        </span>
        <span className="truncate text-[11.5px]" style={{ color: SCOPE.inkFaint }}>
          {isNew ? "Draft" : "Earlier 9d · 1 turn"}
        </span>
      </div>

      <div className="ml-auto flex items-center gap-2">
        {/* Agent VOICE — speak replies aloud (TTS). A speaker, not a mic. */}
        {!isNew ? <VoiceToggle /> : null}
        <IconButton title="Conversation settings">
          <GearGlyph tint={SCOPE.inkFaint} />
        </IconButton>
        <IconButton title="Close">
          <span className="text-[12px] font-semibold" style={{ color: SCOPE.inkFaint }}>
            ✕
          </span>
        </IconButton>
      </div>
    </div>
  );
}

function Speech({ turn }: { turn: Turn }) {
  const isTalkie = turn.speaker === "Talkie";
  return (
    <div className="flex items-start gap-3">
      <div
        className="flex h-[22px] w-[22px] items-center justify-center rounded-[6px] text-[10.5px] font-semibold"
        style={{
          background: isTalkie ? AGENT.signalFaint : "rgba(35,36,35,0.05)",
          color: isTalkie ? AGENT.signalStrong : SCOPE.inkMid,
        }}
      >
        {isTalkie ? "T" : "Y"}
      </div>
      <div className="flex min-w-0 flex-col gap-1.5">
        <div className="flex items-center gap-2">
          <span
            className="text-[10px] font-semibold uppercase"
            style={{ color: SCOPE.ink, letterSpacing: "0.12em" }}
          >
            {turn.speaker}
          </span>
          {turn.meta ? (
            <span className="text-[10px]" style={{ color: SCOPE.inkFainter }}>
              · {turn.meta}
            </span>
          ) : null}
        </div>
        <span className="text-[13px] leading-relaxed" style={{ color: SCOPE.ink }}>
          {turn.body}
        </span>
        {isTalkie ? (
          <span className="text-[11px]" style={{ color: SCOPE.inkFainter }}>
            Details
          </span>
        ) : null}
      </div>
    </div>
  );
}

// ── Composer ──────────────────────────────────────────────────────────

/**
 * One input bar carries everything: the AGENT SELECTOR sits inside the
 * input (left), and the mic + send controls are consolidated together on
 * the right. The block hugs the bottom edge, close to the feed.
 */
function Composer() {
  return (
    <div style={{ background: SCOPE.canvas }}>
      <div style={{ maxWidth: READER_COLUMN + READER_GUTTER * 2, padding: `0 ${READER_GUTTER}px 18px` }}>
        <InputBar placeholder="Reply by voice or text" />
      </div>
    </div>
  );
}

function IdleHero() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-5 px-8 py-14">
      <div
        className="flex h-14 w-14 items-center justify-center rounded-full"
        style={{ background: AGENT.signal, boxShadow: `0 8px 22px ${AGENT.signalGlow}` }}
      >
        <MicGlyph tint="#fff" large />
      </div>
      <div className="flex flex-col items-center gap-2">
        <span className="text-[9px] font-semibold uppercase" style={{ color: SCOPE.inkFainter, letterSpacing: "0.18em" }}>
          · New conversation
        </span>
        <span
          className="text-[26px]"
          style={{ color: SCOPE.ink, fontWeight: 500, fontFamily: "var(--theme-font-serif, Newsreader, serif)" }}
        >
          What are you working on?
        </span>
      </div>
      <div style={{ width: 520 }}>
        <InputBar placeholder="Say something, or type here" />
      </div>
    </div>
  );
}

/**
 * The single input bar: [ agent selector | text | mic · send ].
 * Agent selection lives in the input; mic + send share one control cluster.
 */
function InputBar({ placeholder }: { placeholder: string }) {
  return (
    <div
      className="flex items-center gap-2.5 rounded-[14px] py-2 pl-2 pr-2.5"
      style={{
        background: SCOPE.white,
        border: `0.5px solid ${SCOPE.edgeSubtle}`,
        boxShadow: "0 1px 1px rgba(0,0,0,0.04), 0 12px 22px rgba(0,0,0,0.05)",
      }}
    >
      <AgentChip />
      <span className="h-5 w-px shrink-0" style={{ background: SCOPE.edgeSubtle }} />
      <span className="flex-1 truncate text-[13px]" style={{ color: SCOPE.inkFaint }}>
        {placeholder}
      </span>
      <div className="flex items-center gap-1.5">
        <button
          type="button"
          className="flex h-7 w-7 items-center justify-center rounded-full"
          style={{ background: AGENT.signalFaint }}
          title="Voice input"
        >
          <MicGlyph tint={AGENT.signalStrong} />
        </button>
        <button
          type="button"
          className="flex h-7 w-7 items-center justify-center rounded-full"
          style={{ background: "rgba(35,36,35,0.06)" }}
          title="Send"
        >
          <SendGlyph tint={SCOPE.inkFainter} />
        </button>
      </div>
    </div>
  );
}

/** The active agent as a compact, switchable chip — lives inside the input. */
function AgentChip() {
  const agent = AGENTS[0];
  return (
    <button
      type="button"
      className="flex shrink-0 items-center gap-1.5 rounded-full px-2 py-1"
      style={{ background: AGENT.signalFaint, border: `0.5px solid ${AGENT.signalBorder}` }}
      title="Switch agent"
    >
      <span className="h-[6px] w-[6px] rounded-full" style={{ background: "#3FA66A" }} />
      <span className="text-[11px] font-semibold" style={{ color: AGENT.signalStrong }}>
        {agent.name}
      </span>
      <span className="text-[9px]" style={{ color: AGENT.signal }}>
        ▾
      </span>
    </button>
  );
}

/** Agent VOICE toggle (TTS) — speak replies aloud. A speaker, not a mic. */
function VoiceToggle() {
  const on = true; // shown enabled in the mock
  return (
    <button
      type="button"
      title="Agent voice — read replies aloud"
      className="flex h-[26px] w-[26px] items-center justify-center rounded-full"
      style={{
        background: on ? AGENT.signalFaint : "rgba(35,36,35,0.04)",
        border: on ? `0.5px solid ${AGENT.signalBorder}` : "0.5px solid transparent",
      }}
    >
      <SpeakerGlyph tint={on ? AGENT.signalStrong : SCOPE.inkFaint} />
    </button>
  );
}

function IconButton({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <button
      type="button"
      title={title}
      className="flex h-[26px] w-[26px] items-center justify-center rounded-full"
      style={{ background: "rgba(35,36,35,0.04)" }}
    >
      {children}
    </button>
  );
}

// ── Glyphs ────────────────────────────────────────────────────────────

function MicGlyph({ tint, large = false }: { tint: string; large?: boolean }) {
  const s = large ? 20 : 12;
  return (
    <svg width={s} height={s} viewBox="0 0 16 16" fill="none">
      <rect x="6" y="2" width="4" height="7" rx="2" fill={tint} />
      <path d="M4 8a4 4 0 0 0 8 0" stroke={tint} strokeWidth="1.2" fill="none" />
      <path d="M8 12v2M6 14h4" stroke={tint} strokeWidth="1.2" />
    </svg>
  );
}

function SendGlyph({ tint }: { tint: string }) {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none">
      <path d="M2 8l12-5-5 12-2-5-5-2z" stroke={tint} strokeWidth="1.2" fill="none" strokeLinejoin="round" />
    </svg>
  );
}

function SpeakerGlyph({ tint }: { tint: string }) {
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
      <path d="M3 6h2.4L8.4 3.2v9.6L5.4 10H3z" fill={tint} />
      <path d="M10.6 6.2c1.1 1 1.1 3.6 0 4.6M12.3 4.5c2 1.9 2 6.1 0 8" stroke={tint} strokeWidth="1.1" strokeLinecap="round" fill="none" />
    </svg>
  );
}

function AgentsGlyph({ tint }: { tint: string }) {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none">
      <circle cx="6" cy="6" r="2.2" stroke={tint} strokeWidth="1.2" />
      <path d="M2.4 13c0-2 1.6-3.3 3.6-3.3S9.6 11 9.6 13" stroke={tint} strokeWidth="1.2" fill="none" />
      <circle cx="11.2" cy="6.6" r="1.7" stroke={tint} strokeWidth="1.05" />
      <path d="M10.2 9.8c1.9-.1 3.4 1 3.4 3.2" stroke={tint} strokeWidth="1.05" fill="none" />
    </svg>
  );
}

function GearGlyph({ tint }: { tint: string }) {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none">
      <circle cx="8" cy="8" r="2.4" stroke={tint} strokeWidth="1.2" />
      <path
        d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4"
        stroke={tint}
        strokeWidth="1.2"
      />
    </svg>
  );
}
