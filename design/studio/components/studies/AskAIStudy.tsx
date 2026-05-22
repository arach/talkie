"use client";

/**
 * Ask AI — agentic loop surface. Prompt input at the bottom, turns
 * stack upward. Each turn has a channel-label header (T01 · USER /
 * T02 · TALKIE), a body, and trailing telemetry (latency, tokens,
 * model). The "loop" is the multi-turn back-and-forth — agent
 * presets seed common patterns (Summarize, Extract action items,
 * Rewrite).
 */

import { StatusBar } from "./primitives/StatusBar";

export type AskAIVariant = "idle" | "thinking" | "loop";

export const ASKAI_VARIANTS: { key: AskAIVariant; label: string }[] = [
  { key: "idle", label: "Idle" },
  { key: "thinking", label: "Thinking" },
  { key: "loop", label: "Multi-turn" },
];

export function AskAIStudy({ variant }: { variant: AskAIVariant }) {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />
      <Header />
      <Divider />

      <div className="flex-1 overflow-hidden">
        {variant === "idle" && <Idle />}
        {variant === "thinking" && <Thinking />}
        {variant === "loop" && <Loop />}
      </div>

      <PromptBar variant={variant} />
    </div>
  );
}

function Header() {
  return (
    <div className="flex items-center justify-between px-5 pt-3 pb-2.5">
      <span
        className="text-[10px] font-medium uppercase"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.28em",
        }}
      >
        TALKIE · ASK AI
      </span>
      <button
        aria-label="Close"
        className="flex h-7 w-7 items-center justify-center rounded-full"
        style={{
          background: "var(--theme-edge-faint)",
          color: "var(--theme-ink-faint)",
        }}
      >
        <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none">
          <path
            d="M2 2 L 10 10 M 10 2 L 2 10"
            stroke="currentColor"
            strokeWidth={1.2}
            strokeLinecap="round"
          />
        </svg>
      </button>
    </div>
  );
}

function Divider() {
  return (
    <div
      className="h-px w-full"
      style={{ background: "var(--theme-edge-faint)" }}
    />
  );
}

function Idle() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-5 px-6 text-center">
      <div
        className="text-[20px] font-light leading-tight"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-display)",
        }}
      >
        What would you like to ask?
      </div>

      <div className="grid w-full max-w-[260px] grid-cols-2 gap-2">
        {["Summarize", "Action items", "Rewrite", "Explain"].map((p) => (
          <button
            key={p}
            className="rounded-md px-2 py-2.5 text-[11px]"
            style={{
              background: "var(--theme-paper)",
              color: "var(--theme-ink)",
              border: "0.5px solid var(--theme-edge-faint)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            {p}
          </button>
        ))}
      </div>

      <div
        className="text-[10px] uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        OR · TYPE · DICTATE · ATTACH ·
      </div>
    </div>
  );
}

function Thinking() {
  return (
    <div className="flex h-full flex-col">
      <Turn
        speaker="USER"
        code="T01"
        body="Summarize last week's meetings, keep it under 5 bullets"
        meta="just now"
      />
      <Turn
        speaker="TALKIE"
        code="T02"
        body="Thinking…"
        meta="opus 4.7 · 0.4s"
        thinking
      />
    </div>
  );
}

function Loop() {
  return (
    <div className="flex h-full flex-col overflow-auto">
      <Turn
        speaker="USER"
        code="T01"
        body="Summarize last week's meetings, keep it under 5 bullets"
        meta="2m ago"
      />
      <Turn
        speaker="TALKIE"
        code="T02"
        body={`• Roadmap freeze pushed to Friday\n• Mira committed to keyboard demo by Tue\n• Bridge protocol v2.1 lands w/ release\n• Hire freeze through Q2\n• Studio Friday demo at 3pm`}
        meta="opus 4.7 · 2.8s · 612t"
      />
      <Turn
        speaker="USER"
        code="T03"
        body="Add what each person owns"
        meta="just now"
      />
      <Turn
        speaker="TALKIE"
        code="T04"
        body="Thinking…"
        meta="opus 4.7 · 0.2s"
        thinking
      />
    </div>
  );
}

function Turn({
  speaker,
  code,
  body,
  meta,
  thinking = false,
}: {
  speaker: "USER" | "TALKIE";
  code: string;
  body: string;
  meta: string;
  thinking?: boolean;
}) {
  const isTalkie = speaker === "TALKIE";
  return (
    <div
      className="flex flex-col gap-2 px-4 py-3"
      style={{ borderBottom: "0.5px solid var(--theme-edge-faint)" }}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span
            className="rounded-full px-1.5 py-0.5 text-[9px] font-medium tracking-[0.20em]"
            style={{
              color: isTalkie ? "var(--theme-amber)" : "var(--theme-ink-faint)",
              border: `0.5px solid ${
                isTalkie ? "var(--theme-amber)" : "var(--theme-edge-faint)"
              }`,
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            {code}
          </span>
          <span
            className="text-[10px] font-medium uppercase"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.22em",
            }}
          >
            · {speaker}
          </span>
        </div>
        <span
          className="text-[10px]"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {meta}
        </span>
      </div>

      <div
        className={`whitespace-pre-line text-[13px] leading-snug ${
          thinking ? "italic" : ""
        }`}
        style={{
          color: thinking ? "var(--theme-ink-faint)" : "var(--theme-ink)",
        }}
      >
        {thinking ? (
          <span className="inline-flex items-center gap-1">
            {body}
            <span
              className="inline-block h-1.5 w-1.5 animate-pulse rounded-full"
              style={{ background: "var(--theme-amber)" }}
            />
          </span>
        ) : (
          body
        )}
      </div>
    </div>
  );
}

function PromptBar({ variant }: { variant: AskAIVariant }) {
  return (
    <div
      className="flex items-center gap-2 px-3 py-3"
      style={{
        borderTop: "0.5px solid var(--theme-edge-faint)",
        background: "var(--theme-paper)",
      }}
    >
      <div
        className="flex flex-1 items-center gap-2 rounded-full px-3 py-2"
        style={{
          background: "var(--theme-canvas)",
          border: "0.5px solid var(--theme-edge-faint)",
        }}
      >
        <span
          className="text-[8px] font-medium uppercase"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.22em",
          }}
        >
          T
          {variant === "idle"
            ? "01"
            : variant === "thinking"
              ? "03"
              : "05"}
        </span>
        <input
          className="flex-1 bg-transparent text-[13px] outline-none"
          placeholder="Ask anything…"
          style={{ color: "var(--theme-ink)" }}
        />
      </div>

      <button
        aria-label="Send"
        className="flex h-9 w-9 items-center justify-center rounded-full"
        style={{
          background: "var(--theme-amber)",
          color: "var(--theme-paper)",
        }}
      >
        <svg viewBox="0 0 16 16" className="h-4 w-4" fill="currentColor">
          <path d="M2 8 L 13 3 L 9 8 L 13 13 L 2 8 z" />
        </svg>
      </button>
    </div>
  );
}
