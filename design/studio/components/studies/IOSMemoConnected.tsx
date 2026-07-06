"use client";

/**
 * IOSMemoConnected — memo detail, re-architected.
 *
 * The donor (VoiceMemoDetailNext.swift) and even the first cleanup pass
 * (IOSMemo.tsx) share one structural flaw: the screen is a *stack of
 * equal-weight cards*. Title, a cramped mono meta-string, a bordered
 * transcript card, then a wall of gray action boxes — Share, Refine,
 * Listen, Ask Agent, Run CLI, Attach, workflow triggers, workflow runs —
 * plus a playback bar pinned far away at the bottom. Nothing connects the
 * words to the audio they came from, and in a monochrome world every box
 * reads at the same priority. It's a melange.
 *
 * This rebuild treats the memo as ONE document:
 *
 *   1. Source block (not a meta-string).
 *      Title leads. Underneath, a single humane "source line" — where and
 *      when it was captured — instead of `· MEMO · MAY 26 · 0:48 · 84 WORDS`.
 *
 *   2. Tape strip fused to the reading body  ← the connected move.
 *      Play + mag-tape waveform (VU bars · amber centerline · tape head) sit
 *      on the SAME raised paper as the transcript. The playhead lives IN the
 *      text: played words full ink, unplayed dim, an amber caret between.
 *      The transcript IS the audio, made readable.
 *
 *   3. Editing is the obvious thing you do to text — not a routed action.
 *      The donor's hero was "Refine in Compose", which reads as a separate
 *      AI surface, not "edit these words". So editing is now direct: an
 *      Edit/Done control in the header (the iOS-canonical gesture) and a tap
 *      anywhere in the body drops a caret and brings up the keyboard. No
 *      Accept/Cancel — Done just commits (it auto-saves; ⌘Z undoes). The AI
 *      transform survives, honestly relabelled "Refine ✨" and demoted to the
 *      tool rail, where it belongs as one secondary verb among several.
 *
 *   4. Monochrome, but with hierarchy.
 *      One amber accent (live signal only: play, centerline, tape head,
 *      in-text playhead, the editing caret, Done) + one elevation (raised
 *      paper vs flat tools). Not ten equal borders.
 *
 * Named parts (also in <NamesMarginalia> on the route): Source line ·
 * Tape strip · Tape head · Playhead caret · Reading body · Editing field ·
 * Edit / Done · Tool rail · Workflows drawer.
 */

import { StatusBar } from "./primitives/StatusBar";

type Mode = "reading" | "editing" | "transcribing";

const TITLE = "Notes on cockpit chassis depth";
const SOURCE = { device: "iPhone", date: "May 26", time: "1:24 PM" };
const DURATION = "0:48";
const ELAPSED = "0:18";
// Fraction of the way through playback — drives both the tape head and the
// in-text playhead so the waveform and the words stay in lockstep.
const PROGRESS = 0.38;

const MEMO_BODY =
  "The cockpit should feel like one instrument, not three stacked strips. Identity on the left, status on the right, trackpad in the middle, key row beneath — all inside the same bounded chassis. The transcript card should toggle in place on top of the trackpad, not occupy its own row. We keep the diagonals at full opacity behind it so the instrument is still readable.";

const WORD_COUNT = MEMO_BODY.trim().split(/\s+/).length;

export function IOSMemoConnected({ mode = "reading" }: { mode?: Mode }) {
  const editing = mode === "editing";
  return (
    <div className="flex h-full flex-col" style={{ background: "var(--theme-canvas)" }}>
      <MemoAnimationStyles />
      <StatusBar />
      <Header editing={editing} />

      <div className="flex-1 overflow-y-auto px-5 pb-6 pt-1">
        <SourceBlock />
        <Document mode={mode} />
        {!editing && (
          <>
            <ToolRail />
            <WorkflowsDrawer />
          </>
        )}
      </div>

      {editing && <KeyboardDock />}
    </div>
  );
}

function MemoAnimationStyles() {
  return (
    <style>{`
      @keyframes memo-transcribe-scan {
        0% { transform: translateX(-115%); opacity: 0; }
        12% { opacity: 0.75; }
        84% { opacity: 0.75; }
        100% { transform: translateX(320%); opacity: 0; }
      }

      @keyframes memo-transcribe-needle {
        0% { left: 0%; opacity: 0; }
        10% { opacity: 1; }
        88% { opacity: 1; }
        100% { left: 100%; opacity: 0; }
      }

      @keyframes memo-braille-dot {
        0%, 100% { opacity: 0.24; transform: scale(0.72); }
        34% { opacity: 1; transform: scale(1); }
      }

      .memo-transcribe-scan {
        animation: memo-transcribe-scan 2.15s cubic-bezier(0.45, 0, 0.2, 1) infinite;
      }

      .memo-transcribe-needle,
      .memo-mini-scan {
        animation: memo-transcribe-needle 2.15s cubic-bezier(0.45, 0, 0.2, 1) infinite;
      }

      .memo-mini-scan {
        animation-duration: 1.65s;
      }

      .memo-braille-dot {
        animation: memo-braille-dot 0.95s ease-in-out infinite;
        box-shadow: 0 0 5px var(--theme-amber-glow, var(--theme-amber));
      }
    `}</style>
  );
}

// ── Header ──────────────────────────────────────────────────────────
// Reading: Back · MEMO · Edit. Editing: the back arrow yields to a Done
// that commits (auto-saved already — no Cancel). Edit/Done is the obvious,
// expected way to edit text on iOS.

function Header({ editing }: { editing: boolean }) {
  return (
    <div className="flex items-center justify-between px-4 pb-2 pt-2">
      {editing ? (
        <span className="w-14" aria-hidden />
      ) : (
        <button
          className="flex w-14 items-center gap-1.5 px-1 text-[12px]"
          style={{ color: "var(--theme-ink-dim)", fontFamily: "var(--theme-font-mono)" }}
          aria-label="Back to memos"
        >
          <Chevron dir="left" />
          Memos
        </button>
      )}
      <span
        className="text-[10px] tracking-[0.24em]"
        style={{ color: "var(--theme-ink-muted)", fontFamily: "var(--theme-font-mono)" }}
      >
        {editing ? "EDITING" : "MEMO"}
      </span>
      {editing ? (
        <button
          className="w-14 text-right text-[13px] font-semibold"
          style={{ color: "var(--theme-amber)", fontFamily: "var(--theme-font-body)" }}
        >
          Done
        </button>
      ) : (
        <div className="flex w-14 items-center justify-end gap-3">
          <button
            className="text-[13px]"
            style={{ color: "var(--theme-amber)", fontFamily: "var(--theme-font-body)" }}
            aria-label="Edit memo"
          >
            Edit
          </button>
          <button className="text-[15px]" style={{ color: "var(--theme-ink-muted)" }} aria-label="More">
            ⋯
          </button>
        </div>
      )}
    </div>
  );
}

// ── Source block ────────────────────────────────────────────────────

function SourceBlock() {
  return (
    <div className="flex flex-col gap-2 pt-3 pb-4">
      <h1
        className="text-[23px] leading-[1.16] tracking-[-0.012em]"
        style={{ color: "var(--theme-ink)", fontFamily: "var(--theme-font-display)", fontWeight: 500 }}
      >
        {TITLE}
      </h1>
      <div
        className="flex items-center gap-1.5 text-[11px]"
        style={{ color: "var(--theme-ink-muted)", fontFamily: "var(--theme-font-mono)" }}
      >
        <DeviceGlyph />
        <span>{SOURCE.device}</span>
        <Dot />
        <span>{SOURCE.date}</span>
        <Dot />
        <span>{SOURCE.time}</span>
      </div>
    </div>
  );
}

// ── Document: tape strip fused to the reading / editing body ────────
// One raised paper surface. Reading shows the bound playhead; editing
// slims the transport (you're working on the words, not the audio) and
// turns the body into a live text field.

function Document({ mode }: { mode: Mode }) {
  const editing = mode === "editing";
  const transcribing = mode === "transcribing";
  return (
    <div
      className="mb-6 overflow-hidden rounded-2xl"
      style={{
        background: "var(--theme-paper)",
        boxShadow: editing
          ? "inset 0 0 0 1.5px var(--theme-amber), 0 10px 26px -16px var(--theme-card-shadow, rgba(20,16,12,0.28))"
          : "inset 0 0 0 1px var(--theme-edge-faint), 0 10px 26px -16px var(--theme-card-shadow, rgba(20,16,12,0.28))",
      }}
    >
      {editing ? <TapeChip /> : transcribing ? <TranscribingTapeStrip /> : <TapeStrip />}
      <div style={{ height: 1, background: "var(--theme-edge-faint)" }} aria-hidden />
      {editing ? <EditingField /> : transcribing ? <TranscribingBody /> : <ReadingBody />}
    </div>
  );
}

// ── Tape strip (reading) ────────────────────────────────────────────

function TapeStrip() {
  return (
    <div className="flex items-center gap-3 px-4 py-3.5">
      <button
        className="grid h-9 w-9 flex-none place-items-center rounded-full"
        style={{ background: "var(--theme-amber)", color: "var(--theme-canvas)" }}
        aria-label="Play"
      >
        <PlayIcon />
      </button>
      <TapeWaveform />
      <span
        className="flex-none text-[10.5px] tabular-nums tracking-[0.02em]"
        style={{ color: "var(--theme-ink-muted)", fontFamily: "var(--theme-font-mono)" }}
      >
        <span style={{ color: "var(--theme-ink)" }}>{ELAPSED}</span>
        <span style={{ color: "var(--theme-ink-faint)" }}> / {DURATION}</span>
      </span>
    </div>
  );
}

// ── Tape chip (editing) ─────────────────────────────────────────────
// While editing the words, the transport recedes to a quiet label — the
// audio is still there, just not the focus.

function TapeChip() {
  return (
    <div className="flex items-center gap-2 px-4 py-2.5">
      <span style={{ color: "var(--theme-ink-faint)" }}>
        <PlayIcon />
      </span>
      <span
        className="text-[10px] tracking-[0.14em]"
        style={{ color: "var(--theme-ink-muted)", fontFamily: "var(--theme-font-mono)" }}
      >
        TAPE · {DURATION}
      </span>
    </div>
  );
}

function TapeWaveform() {
  const bars = [
    5, 8, 6, 11, 14, 9, 17, 12, 8, 6, 15, 19, 13, 9, 7, 12, 16, 10, 7, 5,
    9, 13, 18, 14, 10, 6, 8, 12, 7, 5, 9, 6,
  ];
  const headIndex = Math.round(bars.length * PROGRESS);
  return (
    <div className="relative flex h-7 flex-1 items-center">
      <div
        className="absolute left-0 right-0"
        style={{ height: 1, background: "var(--theme-amber-soft, var(--theme-amber))", opacity: 0.5 }}
        aria-hidden
      />
      <div className="relative flex flex-1 items-center justify-between">
        {bars.map((h, i) => {
          const played = i <= headIndex;
          return (
            <span
              key={i}
              style={{
                width: 2,
                height: `${h}px`,
                borderRadius: 1,
                background: played ? "var(--theme-amber)" : "var(--theme-ink-muted)",
                opacity: played ? 0.9 : 0.4,
              }}
            />
          );
        })}
        <div
          className="absolute top-1/2 -translate-y-1/2"
          style={{
            left: `${(headIndex / (bars.length - 1)) * 100}%`,
            width: 1.5,
            height: 26,
            background: "var(--theme-amber)",
            boxShadow: "0 0 6px var(--theme-amber-glow, var(--theme-amber))",
          }}
          aria-hidden
        />
      </div>
    </div>
  );
}

// ── Tape strip (transcribing) ───────────────────────────────────────
// Inverse of recording: the captured tape is fixed, and the head travels
// left-to-right over it as if the machine is re-reading the signal.

function TranscribingTapeStrip() {
  return (
    <div className="flex items-center gap-3 px-4 py-3.5">
      <button
        className="grid h-9 w-9 flex-none place-items-center rounded-full"
        style={{
          background: "var(--theme-canvas-alt, var(--theme-amber-faint))",
          color: "var(--theme-ink-muted)",
          boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
        }}
        aria-label="Play recording"
      >
        <PlayIcon />
      </button>
      <TranscribingSignalWaveform />
      <span
        className="flex-none text-[10.5px] tabular-nums tracking-[0.02em]"
        style={{ color: "var(--theme-ink-muted)", fontFamily: "var(--theme-font-mono)" }}
      >
        <span style={{ color: "var(--theme-ink)" }}>0:00</span>
        <span style={{ color: "var(--theme-ink-faint)" }}> / {DURATION}</span>
      </span>
    </div>
  );
}

function TranscribingSignalWaveform() {
  const bars = [
    5, 8, 6, 11, 14, 9, 17, 12, 8, 6, 15, 19, 13, 9, 7, 12, 16, 10, 7, 5,
    9, 13, 18, 14, 10, 6, 8, 12, 7, 5, 9, 6,
  ];
  return (
    <div
      className="relative flex h-8 flex-1 items-center overflow-hidden rounded-[9px] px-1.5"
      style={{
        background: "var(--theme-canvas-alt, transparent)",
        boxShadow: "inset 0 0 0 1px var(--theme-edge-faint)",
      }}
      aria-hidden
    >
      <div
        className="absolute left-2 right-2 top-1/2"
        style={{
          height: 1,
          background: "var(--theme-amber-soft, var(--theme-amber))",
          opacity: 0.45,
        }}
      />
      <div className="relative flex flex-1 items-center justify-between">
        {bars.map((h, i) => (
          <span
            key={i}
            style={{
              width: 2,
              height: `${h}px`,
              borderRadius: 1,
              background: "var(--theme-ink-muted)",
              opacity: i % 5 === 0 ? 0.62 : 0.38,
            }}
          />
        ))}
      </div>
      <div className="memo-transcribe-scan absolute inset-y-1 left-0 w-[34%]">
        <div
          className="h-full w-full"
          style={{
            background:
              "linear-gradient(90deg, transparent 0%, var(--theme-amber-faint) 38%, var(--theme-amber) 52%, transparent 100%)",
            opacity: 0.72,
            mixBlendMode: "plus-lighter",
          }}
        />
      </div>
      <div
        className="memo-transcribe-needle absolute top-1/2 h-7 w-[1.5px] -translate-y-1/2"
        style={{
          background: "var(--theme-amber)",
          boxShadow: "0 0 7px var(--theme-amber-glow, var(--theme-amber))",
        }}
      />
    </div>
  );
}

function TranscribingBody() {
  return (
    <div className="px-4 py-4">
      <div className="flex items-center gap-3">
        <BrailleSignal />
        <div className="flex min-w-0 flex-1 flex-col gap-1">
          <span
            className="text-[13px] italic"
            style={{ color: "var(--theme-ink-muted)", fontFamily: "var(--theme-font-body)" }}
          >
            Transcribing…
          </span>
          <span
            className="text-[9.5px] tracking-[0.14em]"
            style={{ color: "var(--theme-ink-faint)", fontFamily: "var(--theme-font-mono)" }}
          >
            0 WORDS
          </span>
        </div>
        <MiniSignalPass />
      </div>
    </div>
  );
}

function BrailleSignal() {
  return (
    <span
      className="grid h-7 w-5 flex-none grid-cols-2 place-items-center gap-x-1 gap-y-[3px]"
      aria-hidden
    >
      {Array.from({ length: 6 }).map((_, i) => (
        <span
          key={i}
          className="memo-braille-dot h-[5px] w-[5px] rounded-full"
          style={{
            background: "var(--theme-amber)",
            animationDelay: `${i * 95}ms`,
          }}
        />
      ))}
    </span>
  );
}

function MiniSignalPass() {
  const bars = [5, 9, 13, 7, 16, 10, 6, 12, 8, 14, 6, 10];
  return (
    <span className="relative flex h-7 w-20 flex-none items-center overflow-hidden" aria-hidden>
      <span
        className="absolute left-0 right-0 top-1/2"
        style={{ height: 1, background: "var(--theme-amber)", opacity: 0.28 }}
      />
      <span className="relative flex w-full items-center justify-between">
        {bars.map((h, i) => (
          <span
            key={i}
            style={{
              width: 2,
              height: `${h}px`,
              borderRadius: 1,
              background: "var(--theme-ink-muted)",
              opacity: 0.42,
            }}
          />
        ))}
      </span>
      <span
        className="memo-mini-scan absolute top-1/2 h-6 w-[1.5px] -translate-y-1/2"
        style={{
          background: "var(--theme-amber)",
          boxShadow: "0 0 6px var(--theme-amber-glow, var(--theme-amber))",
        }}
      />
    </span>
  );
}

// ── Reading body ────────────────────────────────────────────────────
// The transcript as the audio made readable: played words full ink,
// unplayed dim, amber playhead between. Tappable to edit.

function ReadingBody() {
  const words = MEMO_BODY.split(" ");
  const head = Math.round(words.length * PROGRESS);
  return (
    <div className="px-4 pb-4 pt-4">
      <p className="text-[15px] leading-[1.62]" style={{ fontFamily: "var(--theme-font-body)" }}>
        {words.map((w, i) => {
          const played = i < head;
          return (
            <span key={i}>
              <span style={{ color: played ? "var(--theme-ink)" : "var(--theme-ink-muted)" }}>{w}</span>
              {i === head - 1 && (
                <span
                  aria-hidden
                  style={{
                    display: "inline-block",
                    width: 1.5,
                    height: "0.95em",
                    margin: "0 1px -0.1em 2px",
                    background: "var(--theme-amber)",
                    boxShadow: "0 0 5px var(--theme-amber-glow, var(--theme-amber))",
                    verticalAlign: "baseline",
                  }}
                />
              )}{" "}
            </span>
          );
        })}
      </p>
      <div
        className="mt-3 flex items-center gap-1.5 text-[10px] tracking-[0.1em]"
        style={{ color: "var(--theme-ink-faint)", fontFamily: "var(--theme-font-mono)" }}
      >
        <span>{WORD_COUNT} WORDS</span>
        <Dot />
        <span>VERBATIM</span>
      </div>
    </div>
  );
}

// ── Editing field ───────────────────────────────────────────────────
// Tap put a caret in the words. Plain editable text — no karaoke dimming,
// the whole transcript is full ink. A selected word + a live amber caret
// sell "you're editing text". A quiet line states the contract: it saves
// itself; undo is the safety net. No Accept/Cancel.

function EditingField() {
  // Split so we can show a selection highlight + blinking caret mid-text.
  const head = "The cockpit should feel like one instrument, not three stacked strips. Identity on the left, status on the right, trackpad in the middle, key row beneath — all inside the same ";
  const selected = "bounded";
  const tail =
    " chassis. The transcript card should toggle in place on top of the trackpad, not occupy its own row. We keep the diagonals at full opacity behind it so the instrument is still readable.";
  return (
    <div className="px-4 pb-4 pt-4">
      <p className="text-[15px] leading-[1.62]" style={{ color: "var(--theme-ink)", fontFamily: "var(--theme-font-body)" }}>
        {head}
        <span
          style={{
            background: "var(--theme-amber-faint)",
            boxShadow: "inset 0 0 0 1px var(--theme-amber-soft, var(--theme-amber))",
            borderRadius: 2,
            padding: "0 1px",
          }}
        >
          {selected}
        </span>
        <span
          className="memo-caret"
          aria-hidden
          style={{
            display: "inline-block",
            width: 1.5,
            height: "1.05em",
            margin: "0 0 -0.18em 1px",
            background: "var(--theme-amber)",
            verticalAlign: "baseline",
          }}
        />
        {tail}
      </p>
      <div
        className="mt-3 flex items-center gap-1.5 text-[10px] tracking-[0.08em]"
        style={{ color: "var(--theme-ink-faint)", fontFamily: "var(--theme-font-mono)" }}
      >
        <SaveGlyph />
        <span>SAVES AUTOMATICALLY</span>
        <Dot />
        <span>⌘Z TO UNDO</span>
      </div>
    </div>
  );
}

// ── Keyboard dock (editing) ─────────────────────────────────────────
// A slim input-accessory bar above the (implied) keyboard. This is where
// the AI transform now lives while you're in the words: honestly labelled,
// clearly a different verb than typing.

function KeyboardDock() {
  return (
    <div className="flex-none">
      <div
        className="flex items-center justify-between px-4 py-2.5"
        style={{
          background: "var(--theme-paper)",
          boxShadow: "inset 0 1px 0 var(--theme-edge-faint)",
        }}
      >
        <button
          className="flex items-center gap-2 rounded-full px-3 py-1.5 text-[12px]"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-body)",
            boxShadow: "inset 0 0 0 1px var(--theme-amber-soft, var(--theme-amber))",
          }}
        >
          <SparkleIcon />
          Refine with AI
        </button>
        <span className="text-[14px]" style={{ color: "var(--theme-ink-muted)" }} aria-label="Dismiss keyboard">
          ⌄
        </span>
      </div>
      {/* Implied iOS keyboard — three faint key rows, just enough to read
          as "the keyboard is up". */}
      <div className="flex flex-col gap-1.5 px-1.5 pb-2 pt-2" style={{ background: "var(--theme-canvas-alt, var(--theme-paper))" }}>
        {[10, 9, 7].map((n, r) => (
          <div key={r} className="flex justify-center gap-1">
            {Array.from({ length: n }).map((_, k) => (
              <span
                key={k}
                style={{
                  width: r === 2 ? 16 : 26,
                  height: 30,
                  borderRadius: 4,
                  background: "var(--theme-paper)",
                  boxShadow: "0 1px 0 var(--theme-edge-faint)",
                  opacity: 0.85,
                }}
              />
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Tool rail (reading) ─────────────────────────────────────────────
// One flat row of secondary verbs. Refine ✨ is now here — the AI
// transform as one quiet option, no longer masquerading as the editor.

function ToolRail() {
  const tools = [
    { icon: <ShareIcon />, label: "Share" },
    { icon: <CopyIcon />, label: "Copy" },
    { icon: <PaperclipIcon />, label: "Attach" },
    { icon: <SparkleIcon />, label: "Refine" },
  ];
  return (
    <div className="mb-5 flex items-stretch justify-between gap-1.5">
      {tools.map((t) => (
        <button
          key={t.label}
          className="flex flex-1 flex-col items-center gap-1.5 rounded-xl py-2.5"
          style={{ background: "var(--theme-canvas-alt, transparent)" }}
        >
          <span style={{ color: "var(--theme-ink-dim)" }}>{t.icon}</span>
          <span
            className="text-[9.5px] tracking-[0.1em]"
            style={{ color: "var(--theme-ink-muted)", fontFamily: "var(--theme-font-mono)" }}
          >
            {t.label.toUpperCase()}
          </span>
        </button>
      ))}
    </div>
  );
}

// ── Workflows drawer (reading) ──────────────────────────────────────

function WorkflowsDrawer() {
  return (
    <button
      className="flex w-full items-center gap-3 rounded-xl px-3.5 py-3"
      style={{ boxShadow: "inset 0 0 0 1px var(--theme-edge-subtle, var(--theme-edge-faint))" }}
    >
      <span
        className="grid h-7 w-7 place-items-center rounded-md text-[12px]"
        style={{ background: "var(--theme-amber-faint)", color: "var(--theme-amber)" }}
      >
        ⌘
      </span>
      <span className="flex flex-1 flex-col items-start">
        <span className="text-[12.5px]" style={{ color: "var(--theme-ink)", fontFamily: "var(--theme-font-body)" }}>
          Workflows
        </span>
        <span
          className="text-[9.5px] tracking-[0.08em]"
          style={{ color: "var(--theme-ink-muted)", fontFamily: "var(--theme-font-mono)" }}
        >
          2 AVAILABLE · 1 RUN
        </span>
      </span>
      <span style={{ color: "var(--theme-ink-muted)" }}>
        <Chevron dir="down" />
      </span>
    </button>
  );
}

// ── Glyphs ──────────────────────────────────────────────────────────

function Dot() {
  return <span style={{ color: "var(--theme-ink-faint)" }}>·</span>;
}

function DeviceGlyph() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3" fill="none" aria-hidden>
      <rect x="3.5" y="1" width="5" height="10" rx="1.2" stroke="currentColor" strokeWidth="1" />
      <line x1="5.4" y1="9.4" x2="6.6" y2="9.4" stroke="currentColor" strokeWidth="1" strokeLinecap="round" />
    </svg>
  );
}

function SaveGlyph() {
  return (
    <svg viewBox="0 0 12 12" className="h-2.5 w-2.5" fill="none" aria-hidden>
      <path d="M2 6.2L4.6 8.8L10 3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function Chevron({ dir }: { dir: "left" | "right" | "down" }) {
  const d =
    dir === "left"
      ? "M6.5 1.5L3 5L6.5 8.5"
      : dir === "right"
        ? "M3.5 1.5L7 5L3.5 8.5"
        : "M1.5 3.5L5 7L8.5 3.5";
  return (
    <svg viewBox="0 0 10 10" className="h-2.5 w-2.5" fill="none" aria-hidden>
      <path d={d} stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg viewBox="0 0 14 14" className="h-3.5 w-3.5" fill="currentColor" aria-hidden>
      <path d="M4 3L11 7L4 11Z" />
    </svg>
  );
}

function SparkleIcon() {
  return (
    <svg viewBox="0 0 16 16" className="h-[18px] w-[18px]" fill="none" aria-hidden>
      <path d="M8 1.5L9.2 5.6L13.3 6.8L9.2 8L8 12L6.8 8L2.7 6.8L6.8 5.6L8 1.5Z" stroke="currentColor" strokeWidth="1.1" strokeLinejoin="round" />
      <path d="M12.7 10.5L13.2 12L14.7 12.5L13.2 13L12.7 14.5L12.2 13L10.7 12.5L12.2 12L12.7 10.5Z" fill="currentColor" stroke="none" />
    </svg>
  );
}

function ShareIcon() {
  return (
    <svg viewBox="0 0 16 16" className="h-[18px] w-[18px]" fill="none" aria-hidden>
      <path d="M8 2V10M8 2L5 5M8 2L11 5M3 9V12.5C3 13.05 3.45 13.5 4 13.5H12C12.55 13.5 13 13.05 13 12.5V9" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CopyIcon() {
  return (
    <svg viewBox="0 0 16 16" className="h-[18px] w-[18px]" fill="none" aria-hidden>
      <rect x="5.5" y="5.5" width="8" height="8" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
      <path d="M3.5 10.5H2.8C2.36 10.5 2 10.14 2 9.7V3.3C2 2.86 2.36 2.5 2.8 2.5H9.2C9.64 2.5 10 2.86 10 3.3V4" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

function PaperclipIcon() {
  return (
    <svg viewBox="0 0 16 16" className="h-[18px] w-[18px]" fill="none" aria-hidden>
      <path d="M11 6L6.5 10.5C5.7 11.3 5.7 12.6 6.5 13.4C7.3 14.2 8.6 14.2 9.4 13.4L13.5 9.3C14.9 7.9 14.9 5.6 13.5 4.2C12.1 2.8 9.8 2.8 8.4 4.2L4.3 8.3C2.2 10.4 2.2 13.8 4.3 15.9" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
