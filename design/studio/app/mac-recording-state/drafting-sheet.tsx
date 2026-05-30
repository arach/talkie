"use client";

/**
 * Drafting Sheet — the magnetic tape is the protagonist.
 *
 * Editorial paper frame: masthead (sequence · LIVE · timecode · engine
 * · device), a brass marginal rule down the gutter, italic byline at
 * the foot. The body itself is no longer typeset — no "Drafting" word,
 * no em-dash polyline, no "forming…" ghost. Just a majestic magnetic
 * tape running across the body, audio etched onto it as the speaker
 * talks. On settle the tape decays and the finished transcript blooms
 * in the same slot; the sheet then folds into the memo row.
 */

import React from "react";
import {
  TreatmentSection,
  Stage,
  Note,
  Homescreen,
  HOMESCREEN_OVERLAY_TOP,
  HOMESCREEN_FIRST_ROW_TOP,
  HOMESCREEN_ROW_HEIGHT,
  AMBER,
  BRASS,
  INK,
  INK_FAINT,
  INK_FAINTER,
  CREAM,
  useElapsed,
  useTimeline,
  smoothstep,
  lerp,
} from "./shared";

// ── Sheet geometry ───────────────────────────────────────────────────

const SHEET_WIDTH = 560;
const SHEET_PAD_X = 40;
const SHEET_PAD_Y = 28;
// A hair brighter than the home CREAM so the sheet reads as a separate
// piece of paper resting on top, not as a cutout of the surface.
const SHEET_PAPER = "#FCFBF8";
const SHEET_RADIUS = 4;
const SHEET_EDGE = "rgba(35,36,35,0.10)";
const SHEET_SHADOW =
  "0 10px 36px rgba(0,0,0,0.06), 0 1px 0 rgba(0,0,0,0.04)";

// The body's magnetic tape — promoted from a small sliver under the
// em-dash to the protagonist. Full body width minus the brass rule +
// gutter. Bars are doubled in markup so the scroll loops seamlessly.
const TAPE_HEIGHT       = 44;
const TAPE_BAR_COUNT    = 96;
const TAPE_BAR_WIDTH    = 2;
const TAPE_BAR_GAP      = 1;

// ── Composition root ─────────────────────────────────────────────────

export function DraftingSheet() {
  return (
    <TreatmentSection
      eyebrow="· Drafting Sheet · paper + tape"
      title="Editorial paper, magnetic-tape body"
      hint="masthead · brass gutter · majestic tape · byline"
    >
      <Stage>
        <Homescreen>
          <DraftingSheetAlive />
        </Homescreen>
      </Stage>
      <Note>
        A sheet of editorial paper lifts onto the home page — a hair
        brighter than the cream below, a 1px ink edge, a soft paper-lift
        shadow. The masthead is a printer&rsquo;s slug{" "}
        (<code>· R-0421 · LIVE · 0:14</code> on the left, mic + engine
        on the right), a brass marginal rule draws down the gutter on a{" "}
        <code>scaleY 0 → 1</code>, and the body is the magnetic tape:
        sprocket dashes top and bottom, amber audio bars feeding right
        → left as the speaker talks. No words inside the body, no rule
        above it — just paper, brass gutter, and tape. The byline at
        the foot keeps the destination context;{" "}
        <code>× CANCEL</code> sits in the top-right corner; a solid
        brass <code>[ STOP ⌘. ]</code> pill floats below the sheet.
      </Note>

      <Stage tall>
        <DraftingSheetSettler />
      </Stage>
      <Note>
        Settle: the tape decays — bars freeze, then the whole strip
        fades. In the same slot the finished transcript blooms in
        italic Newsreader serif —{" "}
        <em>&ldquo;Q1 plan recap with Sam — agreed on the Tuesday
        ship date.&rdquo;</em> Then the sheet folds: scaleY collapses
        from the top, the paper slides down to the first memo slot,
        and the new row materializes around where it lands — brass
        dot leader, italic title, just-now stamp. The sheet became a
        memo.
      </Note>
    </TreatmentSection>
  );
}

// ── Alive composition ────────────────────────────────────────────────

function DraftingSheetAlive() {
  const elapsed = useElapsed(true, 14);
  return (
    <BirthSheet>
      <DraftingSheetPaper elapsed={elapsed} mode="recording" />
      <StopPill />
    </BirthSheet>
  );
}

/**
 * Wraps the sheet in the studio's birth animation — fades in with a
 * gentle upward translate, no scale change. Internal beats (masthead
 * fade, brass-rule draw, tape fade-in, stop pill) are layered via CSS
 * classes that key off the same 7s loop the page root provides.
 */
function BirthSheet({ children }: { children: React.ReactNode }) {
  const [k, setK] = React.useState(0);
  React.useEffect(() => {
    const id = setInterval(() => setK((x) => x + 1), 7000);
    return () => clearInterval(id);
  }, []);
  return (
    <div
      key={k}
      className="absolute left-1/2"
      style={{
        top: HOMESCREEN_OVERLAY_TOP,
        transform: "translateX(-50%)",
        width: SHEET_WIDTH,
      }}
    >
      <div className="ds-birth">{children}</div>
      <style>{`
        .ds-birth {
          animation: ds-birth-sheet 7s cubic-bezier(0.22, 1, 0.36, 1);
          transform-origin: center top;
        }
        @keyframes ds-birth-sheet {
          0%   { opacity: 0; transform: translateY(14px); }
          18%  { opacity: 1; transform: translateY(0); }
          100% { opacity: 1; transform: translateY(0); }
        }
        .ds-birth-rule {
          transform-origin: top;
          animation: ds-birth-rule 7s cubic-bezier(0.22, 1, 0.36, 1);
        }
        @keyframes ds-birth-rule {
          0%, 10%  { transform: scaleY(0); opacity: 0.7; }
          22%      { transform: scaleY(1); opacity: 1; }
          100%     { transform: scaleY(1); opacity: 1; }
        }
        .ds-birth-tape {
          animation: ds-birth-tape 7s cubic-bezier(0.22, 1, 0.36, 1);
        }
        @keyframes ds-birth-tape {
          0%, 18%  { opacity: 0; transform: translateY(4px); }
          34%      { opacity: 1; transform: translateY(0); }
          100%     { opacity: 1; transform: translateY(0); }
        }
        .ds-birth-stop {
          animation: ds-birth-stop 7s cubic-bezier(0.22, 1, 0.36, 1);
        }
        @keyframes ds-birth-stop {
          0%, 40% { opacity: 0; transform: translateY(-4px); }
          56%     { opacity: 1; transform: translateY(0); }
          100%    { opacity: 1; transform: translateY(0); }
        }
        .ds-dot-pulse {
          animation: ds-dot-pulse 1.8s ease-in-out infinite;
        }
        @keyframes ds-dot-pulse {
          0%, 100% { opacity: 0.55; box-shadow: 0 0 0 0 rgba(196,125,28,0.0), 0 0 3px rgba(196,125,28,0.5); }
          50%      { opacity: 1.0;  box-shadow: 0 0 0 3px rgba(196,125,28,0.18), 0 0 6px rgba(196,125,28,0.7); }
        }
        /* Magnetic-tape bars scroll right → left on a calm 9s loop.
           Bars are doubled in markup so translateX(-50%) wraps
           seamlessly. */
        .ds-tape-scroll {
          animation: ds-tape-scroll 9s linear infinite;
          will-change: transform;
        }
        @keyframes ds-tape-scroll {
          0%   { transform: translateX(0); }
          100% { transform: translateX(-50%); }
        }
      `}</style>
    </div>
  );
}

// ── The sheet itself ─────────────────────────────────────────────────

/**
 * The sheet of paper. Two visual modes:
 *   - "recording": magnetic tape playing in the body, no words.
 *   - "settle":    the tape is fading out and the transcript line is
 *                  crossfading in to occupy the same slot. `xfade`
 *                  (0..1) drives the swap.
 */
function DraftingSheetPaper({
  elapsed,
  mode,
  xfade = 0,
  tapeFade = 0,
}: {
  elapsed: number;
  mode: "recording" | "settle";
  /** 0 = show tape, 1 = show finished transcript. */
  xfade?: number;
  /** 0 = full tape; 1 = tape fully faded. Used during settle. */
  tapeFade?: number;
}) {
  const m = Math.floor(elapsed / 60);
  const s = elapsed % 60;
  const timecode = `${m}:${s.toString().padStart(2, "0")}`;

  return (
    <div
      style={{
        position: "relative",
        width: SHEET_WIDTH,
        background: SHEET_PAPER,
        borderRadius: SHEET_RADIUS,
        border: `1px solid ${SHEET_EDGE}`,
        boxShadow: SHEET_SHADOW,
        padding: `${SHEET_PAD_Y}px ${SHEET_PAD_X}px`,
      }}
    >
      {/* Top-right cancel — sits above the masthead in the corner. */}
      <button
        type="button"
        tabIndex={-1}
        aria-label="Cancel"
        className="font-mono uppercase"
        style={{
          position: "absolute",
          top: 10,
          right: 12,
          background: "transparent",
          border: "none",
          color: INK_FAINTER,
          fontSize: 9,
          letterSpacing: "0.28em",
          fontWeight: 600,
          lineHeight: 1,
          padding: 0,
          cursor: "pointer",
        }}
      >
        × Cancel
      </button>

      {/* Masthead — printer's slug. Live dot · sequence · LIVE · tc on
          the left; engine + device on the right. */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          marginBottom: 20,
        }}
      >
        <span
          aria-hidden
          className="ds-dot-pulse"
          style={{
            display: "block",
            width: 6,
            height: 6,
            borderRadius: 6,
            background: AMBER,
          }}
        />
        <MastheadCaps>· R-0421 · LIVE · {timecode}</MastheadCaps>
        <span style={{ flex: 1 }} />
        <MastheadCaps>Parakeet · MacBook Pro</MastheadCaps>
      </div>

      {/* Body row — brass marginal rule + the tape (or, on settle, the
          transcript line crossfading in). No hairline rule above this
          row: the body is the tape, and the tape doesn't want a ceiling. */}
      <div style={{ display: "flex", minHeight: TAPE_HEIGHT }}>
        <div
          aria-hidden
          className="ds-birth-rule"
          style={{
            width: 1,
            background: BRASS,
            alignSelf: "stretch",
            borderRadius: 0.5,
            boxShadow: `0 0 4px rgba(154,106,34,0.30)`,
          }}
        />
        <div style={{ paddingLeft: 18, flex: 1, position: "relative" }}>
          {/* The tape, fading out on settle. */}
          <div
            className="ds-birth-tape"
            style={{
              opacity: (1 - xfade) * (1 - tapeFade),
              transition: "none",
            }}
          >
            <MagneticTape />
          </div>

          {/* Settled transcript line. Sits in the same slot as the
              tape so the swap is a true crossfade. Vertically centered
              against the tape's middle line. */}
          {mode === "settle" && (
            <div
              className="font-display"
              style={{
                position: "absolute",
                top: 0,
                bottom: 0,
                left: 18,
                right: 0,
                display: "flex",
                alignItems: "center",
                opacity: xfade,
                color: INK,
                fontSize: 16,
                lineHeight: 1.42,
                fontStyle: "italic",
                fontWeight: 400,
                letterSpacing: "-0.005em",
                transform: `translateY(${(1 - xfade) * 4}px)`,
              }}
            >
              “Q1 plan recap with Sam — agreed on the Tuesday ship
              date.”
            </div>
          )}
        </div>
      </div>

      {/* Hairline rule above the byline. */}
      <div
        aria-hidden
        style={{
          height: 0,
          borderTop: "0.5px solid rgba(35,36,35,0.10)",
          marginTop: 22,
          marginBottom: 12,
        }}
      />

      {/* Foot byline — italic serif destination on the left, mono
          shortcut on the right. */}
      <div
        style={{
          display: "flex",
          alignItems: "baseline",
          gap: 10,
        }}
      >
        <span
          style={{
            color: INK_FAINT,
            fontSize: 11,
            fontStyle: "italic",
            fontFamily:
              "Newsreader, 'Source Serif Pro', Georgia, serif",
          }}
        >
          Recording to Memos · destination 4 of today
        </span>
        <span style={{ flex: 1 }} />
        <span
          className="font-mono uppercase"
          style={{
            color: INK_FAINTER,
            fontSize: 9,
            letterSpacing: "0.26em",
            fontWeight: 600,
          }}
        >
          ⌘. STOP
        </span>
      </div>
    </div>
  );
}

function MastheadCaps({ children }: { children: React.ReactNode }) {
  return (
    <span
      className="font-mono uppercase"
      style={{
        color: INK_FAINT,
        fontSize: 9,
        letterSpacing: "0.32em",
        fontWeight: 600,
        lineHeight: 1,
      }}
    >
      {children}
    </span>
  );
}

// ── Magnetic tape (the body) ─────────────────────────────────────────

/**
 * Full-body magnetic tape — the recording itself. Sprocket-dashed
 * rails top and bottom, warm-tan substrate, amber audio bars
 * scrolling right → left. A faint amber write-head glow at the right
 * edge marks where the audio is being etched in.
 */
function MagneticTape() {
  return (
    <div
      style={{
        position: "relative",
        width: "100%",
        height: TAPE_HEIGHT,
      }}
    >
      {/* Top sprocket rail */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          height: 1,
          backgroundImage:
            "repeating-linear-gradient(90deg, rgba(154,106,34,0.50) 0 2px, transparent 2px 6px)",
        }}
      />
      {/* Tape body — warm-tan substrate with a subtle vertical sheen,
          rounded to soften the edges against the cream paper. */}
      <div
        style={{
          position: "absolute",
          top: 2,
          bottom: 2,
          left: 0,
          right: 0,
          overflow: "hidden",
          background:
            "linear-gradient(180deg, rgba(154,106,34,0.06) 0%, rgba(154,106,34,0.12) 50%, rgba(154,106,34,0.06) 100%)",
          borderRadius: 1,
        }}
      >
        {/* Scrolling bars */}
        <div
          className="ds-tape-scroll"
          style={{
            display: "flex",
            alignItems: "center",
            height: "100%",
            width: "200%",
            gap: TAPE_BAR_GAP,
            paddingInline: 4,
          }}
        >
          {TAPE_BARS.map((h, i) => (
            <TapeBar key={`a-${i}`} h={h} />
          ))}
          {TAPE_BARS.map((h, i) => (
            <TapeBar key={`b-${i}`} h={h} />
          ))}
        </div>
        {/* Write-head glow — the right edge is where audio is being
            etched in. A soft amber column lit by a drop-shadow. */}
        <div
          aria-hidden
          style={{
            position: "absolute",
            top: 4,
            bottom: 4,
            right: 0,
            width: 2,
            background: AMBER,
            opacity: 0.55,
            filter: "drop-shadow(0 0 6px rgba(232,154,60,0.7))",
          }}
        />
      </div>
      {/* Bottom sprocket rail */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          right: 0,
          height: 1,
          backgroundImage:
            "repeating-linear-gradient(90deg, rgba(154,106,34,0.50) 0 2px, transparent 2px 6px)",
        }}
      />
    </div>
  );
}

/**
 * Deterministic bar heights — looks like recorded speech, not noise.
 * Same seed across renders so the pattern is stable.
 */
const TAPE_BARS = Array.from({ length: TAPE_BAR_COUNT }, (_, i) => {
  const seed = Math.sin((i + 1) * 12.9898) * 43758.5453;
  const r = Math.abs(seed - Math.floor(seed));
  // Envelope so the strip "speaks" in clusters rather than flatlining.
  const env =
    0.55 + 0.30 * Math.sin(i * 0.34 + 1.1) + 0.12 * Math.sin(i * 0.91);
  return Math.max(0.15, Math.min(0.95, r * env));
});

function TapeBar({ h }: { h: number }) {
  return (
    <span
      style={{
        display: "block",
        width: TAPE_BAR_WIDTH,
        flexShrink: 0,
        height: `${(h * 100).toFixed(0)}%`,
        borderRadius: 0.5,
        background: AMBER,
        opacity: 0.82,
      }}
    />
  );
}

// ── Stop pill floating below the sheet ───────────────────────────────

function StopPill() {
  return (
    <div
      className="ds-birth-stop"
      style={{
        display: "flex",
        justifyContent: "center",
        marginTop: 12,
      }}
    >
      <button
        type="button"
        tabIndex={-1}
        aria-label="Stop"
        className="font-mono uppercase"
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 8,
          padding: "5px 12px",
          borderRadius: 2,
          background: BRASS,
          color: CREAM,
          border: "0.5px solid rgba(154,106,34,0.45)",
          fontSize: 9,
          letterSpacing: "0.26em",
          fontWeight: 700,
          lineHeight: 1,
          boxShadow: "0 4px 10px rgba(154,106,34,0.28)",
        }}
      >
        <span style={{ opacity: 0.85 }}>[</span>
        <span
          className="block rounded-[1px]"
          style={{ width: 6, height: 6, background: CREAM }}
        />
        <span>Stop</span>
        <span style={{ opacity: 0.75 }}>⌘.</span>
        <span style={{ opacity: 0.85 }}>]</span>
      </button>
    </div>
  );
}

// ── Settle composition ───────────────────────────────────────────────

/**
 * The sheet folds into the memos list. Timeline phases (over 11s):
 *
 *   0.00 – 0.12  hold recording, tape scrolling
 *   0.12 – 0.30  tape fades out
 *   0.20 – 0.40  finished transcript crossfades into the same slot
 *   0.50 – 0.74  the sheet folds — scaleY 1 → 0.12 from top, slides
 *                down toward the first memo row position
 *   0.65 – 0.90  the new memo row materializes inside the list
 *   0.90 – 1.00  hold; loop
 */
function DraftingSheetSettler() {
  const progress = useTimeline(11000);

  const tapeFade = smoothstep(progress, 0.12, 0.30);
  const xfade    = smoothstep(progress, 0.20, 0.40);
  const fold     = smoothstep(progress, 0.50, 0.74);
  const reveal   = smoothstep(progress, 0.65, 0.90);

  const scaleY = lerp(1, 0.12, fold);
  const translateY = lerp(
    0,
    HOMESCREEN_FIRST_ROW_TOP - HOMESCREEN_OVERLAY_TOP,
    fold,
  );
  const sheetOpacity = 1 - smoothstep(progress, 0.78, 0.92);

  return (
    <Homescreen highlightSlot>
      <div
        className="absolute left-1/2"
        style={{
          top: HOMESCREEN_OVERLAY_TOP,
          transform: `translateX(-50%) translateY(${translateY}px) scaleY(${scaleY})`,
          transformOrigin: "center top",
          width: SHEET_WIDTH,
          opacity: sheetOpacity,
        }}
      >
        <DraftingSheetPaper
          elapsed={14}
          mode="settle"
          xfade={xfade}
          tapeFade={tapeFade}
        />
      </div>

      <FoldedRowReveal reveal={reveal} />
    </Homescreen>
  );
}

/**
 * The new memo row materializing in the first slot of the list. Sits
 * on top of the MemoListMock placeholder row from `highlightSlot`.
 */
function FoldedRowReveal({ reveal }: { reveal: number }) {
  if (reveal <= 0.01) return null;
  return (
    <div
      className="pointer-events-none absolute flex items-center gap-3 py-2"
      style={{
        top: HOMESCREEN_FIRST_ROW_TOP,
        left: 18,
        right: 18,
        height: HOMESCREEN_ROW_HEIGHT,
        opacity: reveal,
      }}
    >
      <span
        className="block h-1.5 w-1.5 rounded-full"
        style={{ background: BRASS }}
      />
      <span
        className="flex-1 truncate font-display"
        style={{
          color: INK,
          fontSize: 13,
          fontStyle: "italic",
          transform: `translateY(${(1 - reveal) * 3}px)`,
        }}
      >
        Q1 plan recap with Sam
      </span>
      <span
        className="font-mono tabular-nums"
        style={{ fontSize: 10, color: INK_FAINT }}
      >
        0:14
      </span>
      <span
        className="font-mono uppercase"
        style={{
          fontSize: 10,
          color: INK_FAINTER,
          letterSpacing: "0.18em",
        }}
      >
        just now
      </span>
    </div>
  );
}
