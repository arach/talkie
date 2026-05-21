"use client";

import React from "react";
import { StudioPage } from "@/components/StudioPage";

/**
 * Mac Talkie — Recording state (V3).
 *
 * V1 (oscilloscope / chart recorder / tape counter) — out, too cosplay.
 * V2 (frontispiece / aperture / open page) — frontispiece and open-page
 *    drop-cap both landed; aperture was a maybe. Direction confirmed
 *    2026-05-19: refine the two paper-native directions.
 *
 *   A.   Title bar pill — always-on baseline.
 *   I.   Frontispiece — book title page treatment. Hairline rules
 *                       bracketing eyebrow / monumental serif timer /
 *                       italic byline / amber ink flourish. Type
 *                       specimen with editorial structure.
 *   II.  Drop cap + wave — just "R" and an amber flowing wave. No
 *                          sentence, no margin stack — the letter and
 *                          the wave do all the work. Time tucked
 *                          beneath as a footnote.
 */

const TALKIE_INK = "#232423";
const TALKIE_INK_FAINT = "rgba(35,36,35,0.55)";
const TALKIE_INK_FAINTER = "rgba(35,36,35,0.32)";
const TALKIE_CREAM = "#F8F8F7";
const TALKIE_PAPER = "#E7E7E6";
const SCOPE_AMBER = "#C47D1C";
const SCOPE_AMBER_GLOW = "#E89A3C";
const REC_RED = "#C03A2A";

export default function MacRecordingStateStudy() {
  return (
    <StudioPage
      eyebrow="Recording state · V3 — frontispiece + drop cap"
      title="Mac Talkie — Recording"
      help="A is always-on · I is the book-page frontispiece · II is the drop cap + wave alone"
    >
      <div className="flex flex-col gap-14 py-6">
        <Variant
          eyebrow="· A · Title bar pill"
          title="Ships as-is — always on"
          hint="constant · not the design question"
        >
          <ChromeRow>
            <PillInline />
          </ChromeRow>
        </Variant>

        <Variant
          eyebrow="· I · Frontispiece"
          title="Book title page — bracketed by hairlines, italic byline"
          hint="structured · ceremonial · most editorial"
        >
          <ChromeRow>
            <PillInline />
          </ChromeRow>
          <CanvasGap>
            <FrontispieceSurface />
          </CanvasGap>
          <Note>
            The field is bracketed by two hairline rules so it reads as
            a typeset title page rather than a free-floating display.
            Eyebrow at top in mono caps, monumental Newsreader serif
            timer at center, italic byline beneath it (
            <em>since 3:42 PM · 19 May 2026</em>), amber ink flourish
            anchoring the bottom of the field. Below the lower rule,
            mono meta in the footer slot — target app + word estimate
            on one side, stop hint on the other.
          </Note>
        </Variant>

        <Variant
          eyebrow="· II · Drop cap + wave"
          title="Just the letter and the wave — no sentence"
          hint="minimal · poetic · the wave does the talking"
        >
          <ChromeRow>
            <PillInline />
          </ChromeRow>
          <CanvasGap>
            <DropCapWaveSurface />
          </CanvasGap>
          <Note>
            The opening sentence is gone. What remains is the serif{" "}
            <em>R</em> as a single beat and an amber wave streaming out
            of it like the rest of the word being written in audio.
            Time and target app sit in a tiny mono footnote at the
            bottom — a caption to the image, not a label inside it.
            The wave is taller and more textured than the frontispiece
            flourish; here it's the protagonist.
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

function ChromeRow({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="flex items-center justify-center gap-3 rounded-md px-6 py-3"
      style={{
        background: TALKIE_PAPER,
        border: `0.5px solid #DEDEDD`,
        minHeight: 52,
      }}
    >
      {children}
    </div>
  );
}

function CanvasGap({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="flex items-center justify-center rounded-md"
      style={{
        background: TALKIE_CREAM,
        border: `0.5px dashed rgba(26,22,18,0.10)`,
        minHeight: 400,
        padding: 36,
      }}
    >
      {children}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Section A — pill in the title bar

function PillInline() {
  return (
    <div
      className="flex items-center gap-2 rounded-full px-3.5 py-1.5"
      style={{ background: TALKIE_INK }}
    >
      <RecMark />
      <span
        className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em]"
        style={{ color: REC_RED, opacity: 0.92 }}
      >
        REC
      </span>
      <span
        className="font-mono text-[10px] font-medium tracking-[0.06em] tabular-nums"
        style={{ color: TALKIE_CREAM }}
      >
        0:14
      </span>
      <MiniWaveform />
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Section I — Frontispiece (book title page)

function FrontispieceSurface() {
  return (
    <div
      className="relative flex flex-col"
      style={{
        width: 880,
        maxWidth: "100%",
        padding: "12px 72px 16px",
      }}
    >
      {/* top hairline */}
      <div
        style={{ height: 0.5, background: "rgba(35,36,35,0.18)" }}
      />

      <div className="flex flex-col items-center gap-7 py-12">
        {/* eyebrow */}
        <div
          className="flex items-center gap-3 font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
          style={{ color: TALKIE_INK_FAINT }}
        >
          <RecMark />
          <span>Recording</span>
          <span style={{ color: TALKIE_INK_FAINTER }}>·</span>
          <span>Library</span>
          <span style={{ color: TALKIE_INK_FAINTER }}>·</span>
          <span>Scope</span>
        </div>

        {/* monumental serif timer */}
        <div
          className="font-display tabular-nums"
          style={{
            color: TALKIE_INK,
            fontSize: 196,
            lineHeight: 0.88,
            letterSpacing: "-0.045em",
            fontWeight: 400,
          }}
        >
          0:14
        </div>

        {/* italic byline */}
        <div
          className="font-display"
          style={{
            color: TALKIE_INK_FAINT,
            fontSize: 16,
            letterSpacing: "0.005em",
            fontStyle: "italic",
            fontWeight: 400,
          }}
        >
          since 3:42 PM · 19 May 2026
        </div>

        {/* amber ink flourish */}
        <InkFlourish width={680} height={56} amplitude={0.45} strokeWidth={1.6} />
      </div>

      {/* bottom hairline */}
      <div
        style={{ height: 0.5, background: "rgba(35,36,35,0.18)" }}
      />

      {/* below-rule meta */}
      <div
        className="flex items-baseline justify-between pt-3 font-mono text-[10px] uppercase tracking-[0.28em]"
        style={{ color: TALKIE_INK_FAINT }}
      >
        <span>iTerm2 · 42 words est</span>
        <span>⌘. stop</span>
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Section II — Drop cap + wave (minimal)

function DropCapWaveSurface() {
  return (
    <div
      className="flex w-full flex-col"
      style={{
        width: 1020,
        maxWidth: "100%",
        padding: "48px 80px 40px",
      }}
    >
      <div className="flex items-center gap-7">
        <span
          className="font-display"
          style={{
            color: TALKIE_INK,
            fontSize: 232,
            lineHeight: 0.78,
            letterSpacing: "-0.05em",
            fontWeight: 400,
            marginTop: -10, // optical balance against wave midline
          }}
        >
          R
        </span>
        <InkFlourish
          width={720}
          height={148}
          amplitude={0.7}
          strokeWidth={2.2}
          dramatic
        />
      </div>

      {/* footnote-style caption */}
      <div
        className="mt-10 flex items-baseline justify-between font-mono text-[10px] uppercase tracking-[0.28em]"
        style={{ color: TALKIE_INK_FAINT }}
      >
        <span className="tabular-nums">0:14 · iTerm2 · 42 words est</span>
        <span>⌘. stop</span>
      </div>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Shared visuals

function InkFlourish({
  width,
  height,
  amplitude = 0.45,
  strokeWidth = 1.6,
  dramatic = false,
}: {
  width: number;
  height: number;
  amplitude?: number;
  strokeWidth?: number;
  dramatic?: boolean;
}) {
  // Amplitude is a fraction of half-height.
  const points: string[] = [];
  const n = 280;
  const mid = height / 2;
  const amp = (height / 2) * amplitude;
  for (let i = 0; i <= n; i++) {
    const x = (i / n) * width;
    const t = i / n;
    // soft taper at both edges
    const fade = Math.sin(Math.PI * t);
    const y =
      mid +
      fade *
        (Math.sin(i * 0.18) * (amp * 0.46) +
          Math.sin(i * 0.07 + 1.2) * (amp * 0.28) +
          Math.sin(i * 0.42 + 0.5) * (amp * 0.18) +
          Math.sin(i * 0.91 + 0.3) * (amp * 0.08));
    points.push(`${x.toFixed(2)},${y.toFixed(2)}`);
  }
  const gradId = `inkFlourishGradient-${dramatic ? "d" : "f"}-${width}-${height}`;
  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      aria-hidden
      style={{ flexShrink: 0 }}
    >
      <defs>
        <linearGradient id={gradId} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor={SCOPE_AMBER} stopOpacity="0" />
          <stop
            offset={dramatic ? "4%" : "10%"}
            stopColor={SCOPE_AMBER}
            stopOpacity="0.95"
          />
          <stop
            offset={dramatic ? "94%" : "90%"}
            stopColor={SCOPE_AMBER}
            stopOpacity="0.9"
          />
          <stop offset="100%" stopColor={SCOPE_AMBER} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polyline
        points={points.join(" ")}
        fill="none"
        stroke={`url(#${gradId})`}
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        style={
          dramatic
            ? {
                filter: `drop-shadow(0 0 2.5px ${SCOPE_AMBER_GLOW}55)`,
              }
            : undefined
        }
      />
    </svg>
  );
}

function RecMark() {
  return (
    <span
      className="block h-2 w-2 rounded-full"
      style={{
        background: REC_RED,
        boxShadow:
          "0 0 0 2px rgba(192,58,42,0.25), 0 0 4px rgba(192,58,42,0.6)",
      }}
    />
  );
}

function MiniWaveform() {
  const bars = React.useMemo(
    () =>
      Array.from({ length: 14 }, (_, i) =>
        2 + Math.round(7 * Math.abs(Math.sin(i * 1.618)))
      ),
    []
  );
  return (
    <span className="flex items-center gap-[2px]" aria-hidden>
      {bars.map((h, i) => (
        <span
          key={i}
          className="block w-[2px] rounded-full"
          style={{
            height: `${h}px`,
            background: "rgba(251,251,250,0.55)",
          }}
        />
      ))}
    </span>
  );
}
