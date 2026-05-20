"use client";

/**
 * Read Aloud — TTS playback surface. Talkie's instrument-style take
 * on a media player: small transport up top, "tuner" controls below
 * (voice picker, rate, pitch), queue at the bottom.
 *
 * Backed by SpeechSynthesisService on iOS (same one that drives the
 * Listen toggle in VoiceMemoDetailNext / CaptureDetailNext). This
 * surface is the top-level entry point for queuing multiple items
 * and adjusting voice/rate/pitch globally.
 *
 * Three variants:
 *  - idle: nothing playing, source picker shown
 *  - playing: active transport + waveform indicator
 *  - queue: showing the up-next list (3+ queued)
 */

import { useState } from "react";
import { StatusBar } from "./primitives/StatusBar";

export type ReadAloudVariant = "idle" | "playing" | "queue";

export const READALOUD_VARIANTS: { key: ReadAloudVariant; label: string }[] = [
  { key: "idle", label: "Idle" },
  { key: "playing", label: "Playing" },
  { key: "queue", label: "Queue" },
];

export function ReadAloudStudy({ variant }: { variant: ReadAloudVariant }) {
  // Source viewer is optional — default ON when something is playing
  // so the listener can follow along; togglable per session.
  const [showSource, setShowSource] = useState(true);

  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--theme-canvas)" }}
    >
      <StatusBar />
      <Header />
      <Divider />

      <div className="flex-1 overflow-auto px-4 pt-2 pb-20">
        {variant === "idle" && <IdleState />}
        {variant !== "idle" && (
          <>
            <NowReading variant={variant} />
            <SourceViewer
              expanded={showSource}
              onToggle={() => setShowSource((v) => !v)}
            />
          </>
        )}
        <VoiceControls />
        {variant === "queue" && <QueueList />}
      </div>
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
        TALKIE · READ ALOUD
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

function SectionHeader({ text }: { text: string }) {
  return (
    <div
      className="flex items-center pt-4 pb-1.5"
      style={{ borderBottom: "0.5px solid var(--theme-edge-faint)" }}
    >
      <span
        className="text-[10px] font-medium uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        {text}
      </span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Idle state — nothing playing, source picker
// ─────────────────────────────────────────────────────────────

function IdleState() {
  return (
    <div className="flex flex-col gap-4 pt-2">
      <SectionHeader text="PICK A SOURCE" />
      <div className="flex flex-col gap-2">
        {[
          { code: "S01", label: "Recent memo", hint: "Conference Bio · 31w" },
          { code: "S02", label: "Recent capture", hint: "Scope dashboard notes" },
          { code: "S03", label: "Library selection", hint: "Tap to choose" },
          { code: "S04", label: "Ask AI response", hint: "T02 · 2m ago" },
        ].map((s) => (
          <SourceRow key={s.code} {...s} />
        ))}
      </div>
    </div>
  );
}

function SourceRow({
  code,
  label,
  hint,
}: {
  code: string;
  label: string;
  hint: string;
}) {
  return (
    <button
      className="flex items-center gap-3 rounded-md px-3 py-2.5"
      style={{
        background: "var(--theme-paper)",
        border: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      <span
        className="text-[9px] font-medium uppercase"
        style={{
          color: "var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        {code}
      </span>
      <div className="flex flex-1 flex-col items-start text-left">
        <span className="text-[13px]" style={{ color: "var(--theme-ink)" }}>
          {label}
        </span>
        <span
          className="text-[10px]"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {hint}
        </span>
      </div>
      <svg viewBox="0 0 16 16" className="h-4 w-4" fill="none">
        <path
          d="M 6 4 L 10 8 L 6 12"
          stroke="var(--theme-ink-faint)"
          strokeWidth={1.2}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </button>
  );
}

// ─────────────────────────────────────────────────────────────
// Now Reading + Transport
// ─────────────────────────────────────────────────────────────

function NowReading({ variant }: { variant: "playing" | "queue" }) {
  return (
    <div className="flex flex-col gap-3 pt-2">
      <span
        className="text-[10px] font-medium uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        NOW READING
      </span>

      <div
        className="leading-tight"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-display)",
          fontWeight: 400,
          fontSize: 19,
        }}
      >
        Conference Bio
      </div>
      <span
        className="text-[10px] font-medium uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        COMPOSE · 31 WORDS · 0:24 / 1:08
      </span>

      <Waveform />

      <Transport />
    </div>
  );
}

function Waveform() {
  // 32-bar pseudo-waveform; first ~14 bars "played" (accent), rest faint.
  const bars = Array.from({ length: 32 }, (_, i) => {
    const seed = (i * 9301 + 49297) % 233280;
    const h = 20 + (seed % 26);
    return { h, played: i < 14 };
  });
  return (
    <div className="flex items-center justify-between gap-0.5">
      {bars.map((b, i) => (
        <span
          key={i}
          aria-hidden
          className="rounded-sm"
          style={{
            width: 4,
            height: b.h,
            background: b.played
              ? "var(--theme-amber)"
              : "var(--theme-ink-faint)",
            opacity: b.played ? 0.9 : 0.28,
          }}
        />
      ))}
    </div>
  );
}

function Transport() {
  return (
    <div className="flex items-center justify-center gap-7 pt-2">
      <TransportButton kind="back" />
      <TransportButton kind="play" big />
      <TransportButton kind="forward" />
    </div>
  );
}

function TransportButton({
  kind,
  big = false,
}: {
  kind: "back" | "play" | "forward";
  big?: boolean;
}) {
  const size = big ? 56 : 36;
  return (
    <button
      aria-label={kind}
      className="flex items-center justify-center rounded-full"
      style={{
        width: size,
        height: size,
        background: big ? "var(--theme-amber)" : "transparent",
        color: big ? "var(--theme-paper)" : "var(--theme-ink)",
        border: big ? "none" : "0.5px solid var(--theme-edge-faint)",
      }}
    >
      {kind === "back" && (
        <svg viewBox="0 0 16 16" className="h-4 w-4" fill="currentColor">
          <path d="M 11 3 L 4 8 L 11 13 z" />
          <rect x={3} y={3.5} width={1} height={9} />
        </svg>
      )}
      {kind === "play" && (
        <svg viewBox="0 0 16 16" className="h-5 w-5" fill="currentColor">
          <path d="M 5 3 L 13 8 L 5 13 z" />
        </svg>
      )}
      {kind === "forward" && (
        <svg viewBox="0 0 16 16" className="h-4 w-4" fill="currentColor">
          <path d="M 5 3 L 12 8 L 5 13 z" />
          <rect x={12} y={3.5} width={1} height={9} />
        </svg>
      )}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────
// Source viewer — optional transcript-style follow-along
// ─────────────────────────────────────────────────────────────

function SourceViewer({
  expanded,
  onToggle,
}: {
  expanded: boolean;
  onToggle: () => void;
}) {
  // Pseudo-paragraph chunks. Index 1 (zero-based) is "currently
  // reading" — matches the waveform's ~14/32 playback progress.
  const chunks = [
    "I'm a designer working at the intersection of voice interfaces and instrument-grade tooling.",
    "My background spans broadcast audio, editorial publishing, and software product design.",
    "I'm currently exploring how voice-first capture can fit into desk and pocket workflows without giving up the precision of a hardware console.",
    "Talk to me about voice UI, instrument vocabulary, channel-label semantics, or anything radio.",
  ];
  const playingIdx = 1;

  return (
    <div className="mt-4">
      <button
        onClick={onToggle}
        className="flex w-full items-center pt-3 pb-1.5"
        style={{ borderBottom: "0.5px solid var(--theme-edge-faint)" }}
      >
        <span
          className="text-[10px] font-medium uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.22em",
          }}
        >
          SOURCE
        </span>
        <div className="flex-1" />
        <span
          className="text-[10px] font-medium uppercase"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.20em",
          }}
        >
          {expanded ? "HIDE" : "SHOW"}
        </span>
      </button>

      {expanded && (
        <div
          className="mt-3 rounded-md p-3"
          style={{
            background: "var(--theme-paper)",
            border: "0.5px solid var(--theme-edge-faint)",
          }}
        >
          <div className="flex flex-col gap-2.5">
            {chunks.map((c, i) => (
              <SourceChunk
                key={i}
                text={c}
                state={
                  i < playingIdx
                    ? "played"
                    : i === playingIdx
                      ? "playing"
                      : "upcoming"
                }
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function SourceChunk({
  text,
  state,
}: {
  text: string;
  state: "played" | "playing" | "upcoming";
}) {
  const color =
    state === "played"
      ? "var(--theme-ink-faint)"
      : state === "playing"
        ? "var(--theme-ink)"
        : "var(--theme-ink-faint)";

  const opacity = state === "upcoming" ? 0.55 : 1;

  return (
    <div className="flex gap-2.5">
      <div
        className="rounded-sm"
        style={{
          width: 2,
          minHeight: 16,
          background:
            state === "playing" ? "var(--theme-amber)" : "transparent",
        }}
      />
      <p
        className="m-0 text-[12.5px] leading-relaxed"
        style={{
          color,
          opacity,
          fontFamily: "var(--theme-font-body)",
        }}
      >
        {text}
      </p>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Voice / rate / pitch controls — instrument-style row fields
// ─────────────────────────────────────────────────────────────

function VoiceControls() {
  return (
    <div className="mt-2">
      <SectionHeader text="VOICE" />
      <ControlRow label="Voice" value="Samantha · en-US" />
      <ControlRow label="Rate" value="1.0×" slider />
      <ControlRow label="Pitch" value="1.0" slider />
      <ControlRow label="Auto-pause" value="On sentences" />
    </div>
  );
}

function ControlRow({
  label,
  value,
  slider = false,
}: {
  label: string;
  value: string;
  slider?: boolean;
}) {
  return (
    <div
      className="flex items-center justify-between"
      style={{
        height: 44,
        borderBottom: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      <span className="text-[12px]" style={{ color: "var(--theme-ink)" }}>
        {label}
      </span>
      <div className="flex items-center gap-2">
        {slider && (
          <div
            className="h-1 w-20 rounded-full"
            style={{ background: "var(--theme-edge-faint)" }}
          >
            <div
              className="h-1 rounded-full"
              style={{
                width: "55%",
                background: "var(--theme-amber)",
              }}
            />
          </div>
        )}
        <span
          className="text-[12px] tabular-nums"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {value}
        </span>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Queue
// ─────────────────────────────────────────────────────────────

function QueueList() {
  const items = [
    { title: "Idea: offline-first sync architecture", meta: "1:42" },
    { title: "Meeting notes — product roadmap", meta: "2:18" },
    { title: "Keyboard configurator reference", meta: "0:54" },
  ];
  return (
    <div className="mt-2">
      <SectionHeader text={`UP NEXT · ${items.length}`} />
      {items.map((item, i) => (
        <div
          key={item.title}
          className="flex items-center justify-between"
          style={{
            height: 44,
            borderBottom:
              i < items.length - 1
                ? "0.5px solid var(--theme-edge-faint)"
                : "none",
          }}
        >
          <div className="flex items-center gap-2.5">
            <span
              className="text-[9px] font-medium uppercase"
              style={{
                color: "var(--theme-ink-faint)",
                fontFamily: "var(--theme-font-mono)",
                letterSpacing: "0.22em",
              }}
            >
              {String(i + 1).padStart(2, "0")}
            </span>
            <span
              className="truncate text-[13px]"
              style={{ color: "var(--theme-ink)" }}
            >
              {item.title}
            </span>
          </div>
          <span
            className="text-[10px] tabular-nums"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            {item.meta}
          </span>
        </div>
      ))}
    </div>
  );
}
