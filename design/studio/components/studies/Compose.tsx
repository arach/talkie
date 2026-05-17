"use client";

/**
 * Compose — turns on existing text.
 *
 * The mental model is NOT chat / Q&A / prompt-and-respond. It's a
 * text editor where:
 *  1. Your existing document is the subject (e.g., a conference bio).
 *  2. The mic dictates new content INTO it at the cursor.
 *  3. The voice command captures an instruction ("clean up the
 *     intro", "tighten the second paragraph") that gets routed
 *     to a model, which returns a transformation rendered as a diff.
 *  4. You accept or discard the diff.
 *
 * State machine (in narrative order):
 *   idle       · document shown, caret active, mic + voice cmd ready
 *   dictating  · mic is hot, new text appearing at cursor
 *   listening  · voice command mode — capturing instruction
 *   generating · model is computing the transformation
 *   diff       · inline diff (strikethrough removed + added) ready
 *                to accept / discard
 *
 * Action layout:
 *   - Title (the document name) in header, small model chip beside it
 *   - Document body fills the editor card; floating mic over its bottom
 *   - Thin quick-transformations row (shorter / polish / connect / etc)
 *   - Action tray: voice cmd · cursor · keyboard
 *
 * Pure theme component — reads --theme-* vars. Drop into <PhoneFrame>.
 */

import type { CSSProperties } from "react";
import { StatusBar } from "./primitives/StatusBar";
import { ChannelLabel } from "./primitives/ChannelLabel";
import { Chip } from "./primitives/Chip";

export type ComposeState =
  | "idle"
  | "dictating"
  | "listening"
  | "generating"
  | "diff";

export const COMPOSE_STATES: { key: ComposeState; label: string }[] = [
  { key: "idle", label: "Idle" },
  { key: "dictating", label: "Dictating" },
  { key: "listening", label: "Voice command" },
  { key: "generating", label: "Generating" },
  { key: "diff", label: "Diff · v1 → v2" },
];

interface ComposeProps {
  state: ComposeState;
}

/** The document under iteration. Lifted out so all states share
 *  the same source text — diff and dictation are EDITS of this,
 *  not separate content. */
const BIO_PARAGRAPHS = [
  "Art is the founder of Talkie, an everywhere-capture system that turns voice into structured artifacts.",
  "Previously at Notion (design) and Linear (notifications). He's been building voice-first software since 2014.",
];

export function Compose({ state }: ComposeProps) {
  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />

      <Header state={state} />

      {/* Document body — the bio. The floating mic anchors over the
          bottom of this card; state-specific overlays go inside. */}
      <div className="relative flex-1 px-3 pt-2 pb-1">
        <DocumentBody state={state} />
        <FloatingMic state={state} />
      </div>

      {/* Thin quick-transformations row. Hidden during diff so the
          comparison breathes. */}
      {state !== "diff" ? <QuickTransforms state={state} /> : null}

      <ActionTray state={state} />
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Header — document title + small model chip (which model handles
 * voice commands). No send button — there are no prompts to send.
 * ────────────────────────────────────────────────────────────────── */

function Header({ state }: { state: ComposeState }) {
  return (
    <div
      className="flex items-center justify-between gap-3 px-3 pt-1.5 pb-2"
      style={{ borderBottom: "0.5px solid var(--theme-edge-faint)" }}
    >
      {/* Back to "Bio" — replaces Done so the document context lives
       *  in the chrome instead of crowding the header center. */}
      <button
        className="inline-flex items-center gap-0.5 text-[13px] font-medium"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-body)",
        }}
      >
        <span aria-hidden>‹</span>
        Bio
      </button>

      {/* Centered: · COMPOSE WITH · ✦ Sonnet 4.6 ▾ — the model is the
       *  hero. Diff state appends · v1 → v2 to the eyebrow. */}
      <div className="flex flex-col items-center gap-0.5">
        <span
          className="text-[8px] font-semibold uppercase tracking-[0.24em]"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {state === "diff"
            ? "compose with · v1 → v2"
            : "compose with"}
        </span>
        <button
          aria-label="Choose model"
          className="inline-flex items-center gap-1.5 text-[15px] leading-none"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-display)",
            fontWeight: "var(--theme-display-weight, 500)",
            letterSpacing: "var(--theme-display-tracking, -0.018em)",
          }}
        >
          <span aria-hidden style={{ color: "var(--theme-amber)" }}>
            ✦
          </span>
          Sonnet 4.6
          <span
            style={{ color: "var(--theme-ink-faint)", fontSize: 12 }}
          >
            ▾
          </span>
        </button>
      </div>

      {/* Right: overflow / version actions — placeholder dot trio. */}
      <button
        aria-label="More"
        className="text-[14px]"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-body)",
        }}
      >
        ⋯
      </button>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Document body — renders the bio, with state-specific overlays.
 * ────────────────────────────────────────────────────────────────── */

function DocumentBody({ state }: { state: ComposeState }) {
  if (state === "diff") return <DiffBody />;

  return (
    <div className="relative h-full" style={cardSurface()}>
      <div className="flex h-full flex-col gap-3 p-4">
        <p style={paraStyle()}>{BIO_PARAGRAPHS[0]}</p>
        <p style={paraStyle()}>
          {state === "dictating" ? (
            <>
              {BIO_PARAGRAPHS[1]}{" "}
              <span style={liveDictationStyle()}>
                His current focus is voice-first capture across iPhone, Watch, and
              </span>
              <Caret />
            </>
          ) : (
            <>
              {BIO_PARAGRAPHS[1]}
              {state === "idle" ? <Caret /> : null}
            </>
          )}
        </p>

        {/* State badges below the text where appropriate */}
        {state === "listening" ? <ListeningStrip /> : null}
        {state === "generating" ? <GeneratingStrip /> : null}
      </div>
    </div>
  );
}

function ListeningStrip() {
  return (
    <div
      className="mt-auto flex items-center gap-2 rounded-md px-3 py-2"
      style={{
        background: "var(--theme-amber-faint)",
        border: "0.5px solid var(--theme-amber-soft)",
      }}
    >
      <span className="flex items-center gap-1" aria-hidden>
        {[0, 1, 2, 3].map((i) => (
          <span
            key={i}
            className="inline-block w-[2px] rounded-full"
            style={{
              height: 4 + (i % 3) * 5,
              background: "var(--theme-amber)",
              animation: `bus-pulse 1.2s ease-in-out ${i * 0.12}s infinite`,
            }}
          />
        ))}
      </span>
      <span
        className="text-[10px] font-semibold uppercase tracking-[0.20em]"
        style={{
          color: "var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        Listening
      </span>
      <span
        className="text-[12px] italic"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-body)",
        }}
      >
        "make the connection between Notion and Talkie clearer…"
      </span>
    </div>
  );
}

function GeneratingStrip() {
  return (
    <div
      className="mt-auto flex items-center gap-2 rounded-md px-3 py-2"
      style={{
        background: "var(--theme-canvas-alt)",
        border: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      <Spinner />
      <ChannelLabel tier="status">Sonnet 4.6 · iterating</ChannelLabel>
      <span
        className="ml-auto text-[10px]"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        ~3s
      </span>
    </div>
  );
}

/* Diff body — inline strikethrough + added text. The bio is shown
 * with v1 removals struck through and v2 additions highlighted in
 * the theme accent. Accept/Discard sit in the action tray for this
 * state (handled by ActionTray). */
function DiffBody() {
  return (
    <div className="relative h-full" style={cardSurface()}>
      <div className="flex h-full flex-col gap-3 p-4">
        <p style={paraStyle()}>{BIO_PARAGRAPHS[0]}</p>
        <p style={paraStyle()}>
          <span style={removed()}>Previously at Notion (design) and Linear (notifications). </span>
          <span style={added()}>
            The thread runs through his work at Notion (where he designed the editor) and Linear (where he led notifications) — both ways of turning fast, lightweight input into structured artifacts.{" "}
          </span>
          He's been building voice-first software since 2014.
        </p>
        <div className="mt-auto flex items-center justify-between pt-1">
          <ChannelLabel tier="status">
            <span style={{ color: "rgba(196, 58, 28, 0.85)" }}>−1</span>{" "}
            <span style={{ color: "var(--theme-amber)" }}>+1</span> sentence
          </ChannelLabel>
          <span
            className="text-[10px]"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            v2 · just now
          </span>
        </div>
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Quick transformations row
 * ────────────────────────────────────────────────────────────────── */

function QuickTransforms({ state }: { state: ComposeState }) {
  const muted = state === "generating" || state === "listening";
  return (
    <div
      className="flex items-center gap-1.5 px-3 py-1.5"
      style={{
        borderTop: "0.5px solid var(--theme-edge-faint)",
        borderBottom: "0.5px solid var(--theme-edge-faint)",
        background: "var(--theme-canvas)",
        opacity: muted ? 0.5 : 1,
      }}
    >
      <ChannelLabel tier="status" className="flex-none">
        Quick
      </ChannelLabel>
      <div className="flex flex-1 items-center gap-1.5 overflow-hidden">
        <Chip variant="command">Shorter</Chip>
        <Chip variant="command">Polish</Chip>
        <Chip variant="command">Connect</Chip>
        <Chip variant="command">Fix grammar</Chip>
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Action tray — voice cmd · cursor · keyboard
 * (mic lives over the textarea; no mic here)
 *
 * Diff state replaces the row with Discard · Refine cmd · Accept.
 * ────────────────────────────────────────────────────────────────── */

function ActionTray({ state }: { state: ComposeState }) {
  if (state === "diff") {
    return (
      <div
        className="flex items-center justify-between gap-3 px-3 py-2.5"
        style={{ background: "var(--theme-canvas)" }}
      >
        <Chip variant="filter">Discard</Chip>
        <Chip variant="filter">Refine command</Chip>
        <Chip variant="filter" active>
          Accept
        </Chip>
      </div>
    );
  }

  return (
    <div
      className="flex items-center justify-between gap-3 px-5 py-2.5"
      style={{ background: "var(--theme-canvas)" }}
    >
      <VoiceCommandButton active={state === "listening"} />
      <CursorPad />
      <KeyboardButton />
    </div>
  );
}

function VoiceCommandButton({ active }: { active: boolean }) {
  return (
    <button
      aria-label="Voice command"
      className="flex h-9 w-9 items-center justify-center rounded-full transition-colors"
      style={
        active
          ? {
              background: "var(--theme-amber)",
              color: "var(--theme-paper)",
              boxShadow: "0 0 8px var(--theme-amber-glow)",
            }
          : {
              background: "var(--theme-paper)",
              color: "var(--theme-ink-dim)",
              border: "0.5px solid var(--theme-edge-faint)",
            }
      }
    >
      <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
        {/* "((·))" — voice command waveform brackets */}
        <g
          stroke="currentColor"
          strokeWidth={1.1}
          strokeLinecap="round"
          fill="none"
        >
          <path d="M 4 4 a 5 5 0 0 0 0 8" />
          <path d="M 12 4 a 5 5 0 0 1 0 8" />
          <path d="M 6 6 a 2.5 2.5 0 0 0 0 4" />
          <path d="M 10 6 a 2.5 2.5 0 0 1 0 4" />
        </g>
        <circle cx={8} cy={8} r={1.3} fill="currentColor" />
      </svg>
    </button>
  );
}

function CursorPad() {
  return (
    <button
      aria-label="Move cursor"
      className="flex h-9 w-9 items-center justify-center rounded-full"
      style={{
        background: "var(--theme-paper)",
        color: "var(--theme-ink-dim)",
        border: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
        <g
          stroke="currentColor"
          strokeWidth={1}
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M 8 3 L 8 5 M 6 4 L 8 3 L 10 4" />
          <path d="M 8 13 L 8 11 M 6 12 L 8 13 L 10 12" />
          <path d="M 3 8 L 5 8 M 4 6 L 3 8 L 4 10" />
          <path d="M 13 8 L 11 8 M 12 6 L 13 8 L 12 10" />
        </g>
      </svg>
    </button>
  );
}

function KeyboardButton() {
  return (
    <button
      aria-label="Show keyboard"
      className="flex h-9 w-9 items-center justify-center rounded-full"
      style={{
        background: "var(--theme-paper)",
        color: "var(--theme-ink-dim)",
        border: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      <svg viewBox="0 0 16 16" fill="none" className="h-4 w-4">
        <rect
          x={2}
          y={4.5}
          width={12}
          height={7}
          rx={1.2}
          stroke="currentColor"
          strokeWidth={0.9}
        />
        <g stroke="currentColor" strokeWidth={0.7} strokeLinecap="round">
          <line x1={4} y1={7} x2={4.4} y2={7} />
          <line x1={6.5} y1={7} x2={6.9} y2={7} />
          <line x1={9} y1={7} x2={9.4} y2={7} />
          <line x1={11.5} y1={7} x2={11.9} y2={7} />
          <line x1={5} y1={9.5} x2={11} y2={9.5} />
        </g>
      </svg>
    </button>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Floating mic — for inline dictation. State-driven:
 *   idle/listening/diff · secondary outlined paper
 *   dictating           · red recording state (currently hot)
 *   generating          · disabled / muted
 * ────────────────────────────────────────────────────────────────── */

function FloatingMic({ state }: { state: ComposeState }) {
  const base: CSSProperties = {
    position: "absolute",
    left: "50%",
    bottom: "16px",
    transform: "translateX(-50%)",
    width: 48,
    height: 48,
    borderRadius: "50%",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    transition: "all 0.18s ease",
    zIndex: 5,
  };

  if (state === "dictating") {
    return (
      <button
        aria-label="Stop dictation"
        style={{
          ...base,
          background: "var(--theme-rec)",
          color: "white",
          boxShadow:
            "0 4px 12px -6px var(--theme-rec-glow), inset 0 0.5px 0 rgba(255,255,255,0.20)",
        }}
      >
        <span
          aria-hidden
          style={{
            display: "block",
            width: 14,
            height: 14,
            background: "currentColor",
            borderRadius: 2,
          }}
        />
      </button>
    );
  }

  if (state === "generating") {
    return (
      <button
        aria-label="Dictate (disabled while generating)"
        disabled
        style={{
          ...base,
          background: "var(--theme-paper)",
          color: "var(--theme-ink-subtle)",
          border: "0.5px solid var(--theme-edge-faint)",
          opacity: 0.55,
        }}
      >
        <MicGlyph />
      </button>
    );
  }

  // idle / listening / diff
  return (
    <button
      aria-label="Dictate"
      style={{
        ...base,
        background: "var(--theme-paper)",
        color: "var(--theme-amber)",
        border: "1px solid var(--theme-amber-soft)",
        boxShadow:
          "0 4px 12px -6px var(--theme-amber-glow), inset 0 0.5px 0 rgba(255,255,255,0.20)",
      }}
    >
      <MicGlyph />
    </button>
  );
}

function MicGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-6 w-6">
      <rect
        x={9}
        y={3}
        width={6}
        height={11}
        rx={3}
        stroke="currentColor"
        strokeWidth={1.4}
      />
      <path
        d="M 6 11 v 1 a 6 6 0 0 0 12 0 v-1 M 12 18 v 3 M 8 21 h 8"
        stroke="currentColor"
        strokeWidth={1.4}
        strokeLinecap="round"
      />
    </svg>
  );
}

/* ─────────────────────────────────────────────────────────────────
 * Small helpers
 * ────────────────────────────────────────────────────────────────── */

function cardSurface(): CSSProperties {
  return {
    background: "var(--theme-paper)",
    border: "0.5px solid var(--theme-edge-faint)",
    borderRadius: 10,
    boxShadow: "var(--theme-card-shadow-strong, inset 0 0.5px 0 rgba(255,255,255,0.20))",
    height: "100%",
  };
}

function paraStyle(): CSSProperties {
  return {
    margin: 0,
    fontSize: 15,
    lineHeight: 1.5,
    color: "var(--theme-ink)",
    fontFamily: "var(--theme-font-body)",
    letterSpacing: "-0.005em",
  };
}

function liveDictationStyle(): CSSProperties {
  return {
    color: "var(--theme-amber)",
    fontStyle: "italic",
  };
}

function removed(): CSSProperties {
  return {
    textDecoration: "line-through",
    textDecorationColor: "rgba(196, 58, 28, 0.5)",
    color: "var(--theme-ink-faint)",
    background: "rgba(196, 58, 28, 0.05)",
    borderRadius: 2,
    padding: "0 1px",
  };
}

function added(): CSSProperties {
  return {
    color: "var(--theme-ink)",
    background: "var(--theme-amber-faint)",
    borderBottom: "1px solid var(--theme-amber-soft)",
    borderRadius: 2,
    padding: "0 1px",
  };
}

function Caret() {
  return (
    <span
      aria-hidden
      className="ml-0.5 inline-block h-3 w-[1.5px] align-middle animate-pulse"
      style={{ background: "var(--theme-amber)" }}
    />
  );
}

function Spinner() {
  return (
    <span
      aria-hidden
      className="inline-block h-3 w-3 rounded-full"
      style={{
        border: "1.3px solid var(--theme-edge-dim)",
        borderTopColor: "var(--theme-amber)",
        animation: "spin 0.9s linear infinite",
      }}
    />
  );
}
