"use client";

import React from "react";
import { StudioPage } from "@/components/StudioPage";

/**
 * Mac Talkie — Recording state · lifecycle storyboard.
 *
 * Four keyframes of the memo recording overlay on the home screen.
 * Use this page to design the animation that connects them.
 *
 *   1. Start.       Overlay arrives on the home screen. Scale +
 *                   fade-in; eyebrow first, then the wave drawn in,
 *                   then the caption settles. ~600ms.
 *   2. Recording.   Live wave breathing on voice level; timer ticks;
 *                   mic + engine context in the eyebrow. Resting.
 *   3. Hover.       Same surface; Cancel + Stop pills fade in. ⌘./Esc
 *                   keyboard paths bypass hover.
 *   4. Settle →     Wave decays into a baseline; transcript emerges
 *      memo.        in place; card scales down + lands as a row in
 *                   the memos list. (Alt destinations: Library card,
 *                   Talkie chrome pill — a separate decision.)
 */

const TALKIE_INK = "#232423";
const TALKIE_INK_FAINT = "rgba(35,36,35,0.55)";
const TALKIE_INK_FAINTER = "rgba(35,36,35,0.32)";
const TALKIE_CREAM = "#F8F8F7";
const TALKIE_PAPER = "#E7E7E6";
const SCOPE_AMBER = "#C47D1C";
const SCOPE_AMBER_GLOW = "#E89A3C";
const REC_RED = "#C03A2A";

const CARD_RADIUS = 22;

export default function MacRecordingStateStudy() {
  return (
    <StudioPage
      eyebrow="Recording state · lifecycle"
      title="Mac Talkie — Recording animation"
      help="1 start · 2 recording · 3 hover · 4 settle into a memo"
    >
      <KeyframeStyles />
      <div className="flex flex-col gap-14 py-6">
        <Variant
          eyebrow="· 1 · Start"
          title="Overlay arrives on the home screen"
          hint="scale-in · staggered reveal · ~600ms · loops every 4.5s"
        >
          <Stage>
            <Homescreen>
              <BirthAnimator>
                <StageOneCard />
              </BirthAnimator>
            </Homescreen>
          </Stage>
          <Note>
            Card lifts from <code>scale(0.94)</code> + <code>opacity 0</code>{" "}
            to its resting size; the eyebrow lights first, the amber wave
            is drawn in left → right via stroke-dash, then the caption
            slides up. Keep it quiet — this isn't an entrance, it's a
            surface becoming present.
          </Note>
        </Variant>

        <Variant
          eyebrow="· 2 · Recording · alive"
          title="Wave breathes on voice level · timer ticks · mic + engine in the eyebrow"
          hint="continuous · resting (no hover)"
        >
          <Stage>
            <Homescreen>
              <StageTwoCard />
            </Homescreen>
          </Stage>
          <Note>
            Wave amplitude is driven by an envelope follower over the
            mic input — fast attack, slow release. Eyebrow now carries{" "}
            <em>source</em> metadata (mic · engine); caption carries{" "}
            <em>progress</em> (timer · target app · word estimate).
            Question to settle: does the mic + engine chip belong here,
            or only inside a hover/inspect surface?
          </Note>
        </Variant>

        <Variant
          eyebrow="· 3 · Hover"
          title="Cancel + Stop pills fade in"
          hint="opacity 0 → 1 · 180ms"
        >
          <Stage>
            <Homescreen>
              <StageThreeCard />
            </Homescreen>
          </Stage>
          <Note>
            Same card as state 2; the caption row reveals the Cancel
            (Esc) and Stop (⌘.) pills on pointer-enter. Keyboard
            shortcuts stay live regardless of hover so muscle-memory
            users never need to chase the card with the mouse.
          </Note>
        </Variant>

        <Variant
          eyebrow="· 4 · Settle → memo"
          title="Wave decays · transcript emerges · card lands in the memos list"
          hint="loop · 5.5s cycle · destination = home memos list"
        >
          <Stage tall>
            <StageFourSettler />
          </Stage>
          <Note>
            On stop, the wave amplitude decays toward a baseline; the
            transcript emerges along that baseline (left → right mask +
            6pt rise). The card then scales down and translates into
            the top slot of the memos table — title borrowed from the
            transcript, duration carried over, time stamped{" "}
            <em>just now</em>. Alternate destinations to consider: the
            Library card · the Talkie chrome pill when home isn't
            visible.
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

function Stage({ children, tall }: { children: React.ReactNode; tall?: boolean }) {
  return (
    <div
      className="flex items-center justify-center rounded-md"
      style={{
        background: TALKIE_CREAM,
        border: `0.5px dashed rgba(26,22,18,0.10)`,
        minHeight: tall ? 720 : 540,
        padding: 24,
      }}
    >
      {children}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Homescreen scaffold — minimal mock so the overlay reads "on top of".

function Homescreen({
  children,
  highlightSlot = false,
}: {
  children: React.ReactNode;
  highlightSlot?: boolean;
}) {
  return (
    <div
      className="relative w-full"
      style={{
        maxWidth: 960,
        background: TALKIE_PAPER,
        borderRadius: 14,
        padding: "12px 18px 20px",
        boxShadow: "0 1px 0 rgba(0,0,0,0.04), 0 14px 30px rgba(0,0,0,0.06)",
        border: "0.5px solid rgba(35,36,35,0.10)",
      }}
    >
      <FakeChrome />
      <div className="opacity-[0.62]">
        <MemoListMock highlightTop={highlightSlot} />
      </div>
      {/* Overlay sits in the upper portion of the home page so the memo
          list below stays visible as living context — this is what the
          card is going to land in, so it needs to be felt under it. */}
      <div
        className="pointer-events-none absolute inset-x-0 flex justify-center"
        style={{ top: 88 }}
      >
        <div className="pointer-events-auto">{children}</div>
      </div>
    </div>
  );
}

function FakeChrome() {
  return (
    <div className="flex items-center justify-between pb-3">
      <div className="flex items-center gap-1.5">
        <span className="block h-2.5 w-2.5 rounded-full bg-[#FF5F57]" />
        <span className="block h-2.5 w-2.5 rounded-full bg-[#FEBC2E]" />
        <span className="block h-2.5 w-2.5 rounded-full bg-[#28C840]" />
      </div>
      <PillInline />
      <span style={{ width: 36 }} />
    </div>
  );
}

function MemoListMock({ highlightTop }: { highlightTop: boolean }) {
  const rows: {
    title: string;
    duration: string;
    time: string;
    placeholder?: boolean;
  }[] = [
    highlightTop
      ? { title: "—", duration: "0:14", time: "now", placeholder: true }
      : { title: "Q1 plan recap with Sam", duration: "0:14", time: "3:42 PM" },
    { title: "Notes on the onboarding cut", duration: "1:08", time: "11:20 AM" },
    { title: "Sketch ideas for the timer surface", duration: "0:42", time: "Yesterday" },
    { title: "Walking thoughts on pricing", duration: "2:17", time: "Mon" },
    { title: "Voice memo · 2 follow-ups for Lina", duration: "0:53", time: "Sun" },
    { title: "Reading on quiet UI vs. busy UI", duration: "1:42", time: "Sat" },
  ];
  return (
    <div className="flex flex-col" style={{ borderTop: `0.5px solid rgba(35,36,35,0.10)` }}>
      <div
        className="flex items-center justify-between py-2 font-mono text-[10px] uppercase tracking-[0.22em]"
        style={{ color: TALKIE_INK_FAINT }}
      >
        <span>Memos</span>
        <span style={{ color: TALKIE_INK_FAINTER }}>4 today</span>
      </div>
      {rows.map((r, i) => (
        <div
          key={i}
          className="flex items-center gap-3 py-2"
          style={{
            borderTop: `0.5px solid rgba(35,36,35,0.08)`,
            background: r.placeholder ? "rgba(196,125,28,0.06)" : "transparent",
            transition: "background 240ms ease-out",
          }}
        >
          <span
            className="block h-1.5 w-1.5 rounded-full"
            style={{ background: r.placeholder ? SCOPE_AMBER : TALKIE_INK_FAINTER }}
          />
          <span
            className="flex-1 truncate font-display text-[13px]"
            style={{
              color: r.placeholder ? TALKIE_INK_FAINTER : TALKIE_INK,
              fontStyle: r.placeholder ? "italic" : "normal",
            }}
          >
            {r.title}
          </span>
          <span
            className="font-mono text-[10px] tabular-nums"
            style={{ color: TALKIE_INK_FAINT }}
          >
            {r.duration}
          </span>
          <span
            className="font-mono text-[10px] uppercase tracking-[0.18em]"
            style={{ color: TALKIE_INK_FAINTER }}
          >
            {r.time}
          </span>
        </div>
      ))}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Card shell — the glass overlay all states share.

function CardShell({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: React.CSSProperties;
}) {
  return (
    <div
      className="relative flex flex-col gap-6"
      style={{
        width: 620,
        maxWidth: "100%",
        padding: "24px 40px",
        borderRadius: CARD_RADIUS,
        // Frosted glass: heavy backdrop blur with a translucent paper
        // tint so the homescreen behind is felt but not legible.
        background:
          `linear-gradient(180deg, rgba(255,255,255,0.68) 0%, rgba(255,255,255,0.32) 38%, rgba(255,255,255,0.10) 100%), ${TALKIE_PAPER}BF`,
        backdropFilter: "blur(22px) saturate(1.25)",
        WebkitBackdropFilter: "blur(22px) saturate(1.25)",
        boxShadow:
          "0 14px 40px rgba(0,0,0,0.14), inset 0 0.5px 0 rgba(255,255,255,0.65)",
        border: "1px solid rgba(35,36,35,0.07)",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// State 1 — Start (birth animation)

function BirthAnimator({ children }: { children: React.ReactNode }) {
  const [k, setK] = React.useState(0);
  React.useEffect(() => {
    const id = setInterval(() => setK((x) => x + 1), 7000);
    return () => clearInterval(id);
  }, []);
  return (
    <div key={k} className="cs-birth">
      {children}
    </div>
  );
}

function StageOneCard() {
  return (
    <CardShell>
      <div className="cs-birth-eyebrow">
        <Eyebrow stage={1} />
      </div>
      <div className="flex justify-center" style={{ height: 96 }}>
        <DrawInFlourish width={520} height={96} />
      </div>
      <div className="cs-birth-caption">
        <CaptionRow elapsed={0} hovered={false} />
      </div>
    </CardShell>
  );
}

// ──────────────────────────────────────────────────────────────────────
// State 2 — Recording (alive)

function StageTwoCard() {
  const elapsed = useElapsed(true, 14);
  return (
    <CardShell>
      <Eyebrow stage={2} />
      <div className="flex justify-center" style={{ height: 96 }}>
        <LiveFlourish width={520} height={96} />
      </div>
      <CaptionRow elapsed={elapsed} hovered={false} />
    </CardShell>
  );
}

// ──────────────────────────────────────────────────────────────────────
// State 3 — Hover

function StageThreeCard() {
  const elapsed = useElapsed(true, 14);
  return (
    <CardShell>
      <Eyebrow stage={3} />
      <div className="flex justify-center" style={{ height: 96 }}>
        <LiveFlourish width={520} height={96} />
      </div>
      <CaptionRow elapsed={elapsed} hovered />
    </CardShell>
  );
}

// ──────────────────────────────────────────────────────────────────────
// State 4 — Settle → memo

function StageFourSettler() {
  // Slowed from 5.5s → 11s so each phase is genuinely observable.
  const progress = useTimeline(11000);
  // Phase windows along the 11s cycle (each ~1.5–2.5s):
  //   0.00 → 0.12  hold recording (1.32s — settle the eye)
  //   0.12 → 0.32  wave decays toward baseline (2.2s)
  //   0.28 → 0.52  transcript emerges along baseline (2.64s)
  //   0.52 → 0.74  card scales down + translates to row (2.42s)
  //   0.72 → 0.90  destination row fills in (1.98s)
  //   0.90 → 1.00  hold filled state (1.1s)
  const decay = smoothstep(progress, 0.12, 0.32);
  const transcript = smoothstep(progress, 0.28, 0.52);
  const land = smoothstep(progress, 0.52, 0.74);
  const filled = smoothstep(progress, 0.72, 0.90);

  // Card stays anchored at its overlay position and compacts in
  // place — it crystallizes into the row beneath rather than
  // physically traveling across the page. transformOrigin is the
  // top edge so the card's top stays aligned with the destination
  // row as it shrinks down.
  const cardScale = 1 - land * 0.58;
  const cardOffsetY = land * 24;
  const cardOpacity = 1 - filled * 0.95;

  return (
    <div
      className="relative w-full"
      style={{
        maxWidth: 960,
        background: TALKIE_PAPER,
        borderRadius: 14,
        padding: "12px 18px 20px",
        boxShadow: "0 1px 0 rgba(0,0,0,0.04), 0 14px 30px rgba(0,0,0,0.06)",
        border: "0.5px solid rgba(35,36,35,0.10)",
      }}
    >
      <FakeChrome />
      <MemoListMock highlightTop />

      {/* Card overlay — anchored just above the destination row and
          compacting into it rather than translating past the list. */}
      <div
        className="absolute left-1/2"
        style={{
          top: 88,
          transform: `translate(-50%, ${cardOffsetY}px) scale(${cardScale})`,
          transformOrigin: "center top",
          opacity: cardOpacity,
          transition: "none",
        }}
      >
        <CardShell>
          <Eyebrow stage={4} />
          <div
            className="flex justify-center"
            style={{ height: 96, position: "relative" }}
          >
            <LiveFlourish
              width={520}
              height={96}
              ampBase={lerp(0.50, 0.06, decay)}
              ampVariance={lerp(0.28, 0.0, decay)}
            />
            <div
              className="pointer-events-none absolute inset-x-0 flex items-center justify-center px-4 text-center font-display"
              style={{
                color: TALKIE_INK,
                top: "44%",
                transform: `translateY(${(1 - transcript) * 6}px)`,
                opacity: transcript,
                fontSize: 16,
                lineHeight: 1.4,
              }}
            >
              <span
                style={{
                  WebkitMaskImage: `linear-gradient(90deg, #000 ${transcript * 100}%, transparent ${transcript * 100}%)`,
                  maskImage: `linear-gradient(90deg, #000 ${transcript * 100}%, transparent ${transcript * 100}%)`,
                }}
              >
                Q1 plan recap with Sam — agreed on the Tuesday ship date.
              </span>
            </div>
          </div>
          <CaptionRow elapsed={14} hovered={false} />
        </CardShell>
      </div>

      {/* Filled-row glow that materializes the new memo in place */}
      <FillReveal filled={filled} />
    </div>
  );
}

function FillReveal({ filled }: { filled: number }) {
  // The MemoListMock's first row is the placeholder; this overlay
  // sits on top of it and fades the real content in as `filled` rises.
  if (filled <= 0.01) return null;
  return (
    <div
      className="pointer-events-none absolute left-[18px] right-[18px] flex items-center gap-3 py-2"
      style={{
        // Lines up with first row in MemoListMock: 12 (top padding) +
        // FakeChrome height (~36) + memos header (~28) + border (0.5).
        top: 12 + 36 + 28,
        height: 28,
        opacity: filled,
        transition: "opacity 160ms ease-out",
      }}
    >
      <span
        className="block h-1.5 w-1.5 rounded-full"
        style={{ background: SCOPE_AMBER }}
      />
      <span
        className="flex-1 truncate font-display text-[13px]"
        style={{ color: TALKIE_INK }}
      >
        Q1 plan recap with Sam
      </span>
      <span
        className="font-mono text-[10px] tabular-nums"
        style={{ color: TALKIE_INK_FAINT }}
      >
        0:14
      </span>
      <span
        className="font-mono text-[10px] uppercase tracking-[0.18em]"
        style={{ color: TALKIE_INK_FAINTER }}
      >
        just now
      </span>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Shared overlay pieces

function Eyebrow({ stage }: { stage: 1 | 2 | 3 | 4 }) {
  const verb = stage === 4 ? "TRANSCRIBING" : "RECORDING";
  const chips =
    stage === 1
      ? ["LIBRARY", "SCOPE"]
      : ["MACBOOK PRO MIC", "PARAKEET"];

  return (
    <div
      className="flex items-center gap-3 font-mono text-[10px] font-semibold uppercase tracking-[0.36em]"
      style={{ color: TALKIE_INK_FAINT }}
    >
      <RecMark active={stage !== 4} />
      <span>{verb}</span>
      {chips.map((c, i) => (
        <React.Fragment key={i}>
          <span style={{ color: TALKIE_INK_FAINTER }}>·</span>
          <span>{c}</span>
        </React.Fragment>
      ))}
    </div>
  );
}

function CaptionRow({
  elapsed,
  hovered,
}: {
  elapsed: number;
  hovered: boolean;
}) {
  const m = Math.floor(elapsed / 60);
  const s = elapsed % 60;
  const timeStr = `${m}:${s.toString().padStart(2, "0")}`;
  const words = Math.max(0, Math.round(elapsed / 0.32));
  return (
    <div className="flex items-center">
      <span
        className="font-mono text-[10px] uppercase tracking-[0.28em] tabular-nums"
        style={{ color: TALKIE_INK_FAINT }}
      >
        {timeStr} · iTerm2 · {words} words est
      </span>
      <span className="ml-auto flex items-center gap-3.5">
        <SurfaceButton kind="cancel" visible={hovered} />
        <SurfaceButton kind="stop" visible={hovered} />
      </span>
    </div>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Live amber wave + draw-in variant

function LiveFlourish({
  width,
  height,
  strokeWidth = 2.4,
  ampBase = 0.5,
  ampVariance = 0.25,
  // Positive = peaks travel right → left. Larger magnitude = faster
  // visible streaming motion (not just undulation). Tuned with the
  // lowered spatial frequencies below so peaks are big enough to
  // actually see traveling across the canvas.
  phaseSpeed = 4.5,
}: {
  width: number;
  height: number;
  strokeWidth?: number;
  ampBase?: number;
  ampVariance?: number;
  phaseSpeed?: number;
}) {
  const ref = React.useRef<SVGPolylineElement | null>(null);

  React.useEffect(() => {
    let raf = 0;
    const start = performance.now();
    const N = 220;

    const tick = (now: number) => {
      const t = (now - start) / 1000;
      const breath =
        ampBase +
        ampVariance * 0.65 * Math.sin(t * 1.6) +
        ampVariance * 0.35 * Math.sin(t * 3.9 + 1.1);
      const amp = (height / 2) * Math.max(0.06, breath);
      const mid = height / 2;
      const phase = t * phaseSpeed;
      const pts: string[] = [];
      for (let i = 0; i <= N; i++) {
        const x = (i / N) * width;
        const u = i / N;
        const fade = Math.sin(Math.PI * u);
        // Lower spatial frequencies than the original Swift port —
        // peaks are wider, so their travel across the canvas reads
        // as flow, not just undulation in place.
        const y =
          mid +
          fade *
            (Math.sin(i * 0.10 + phase) * (amp * 0.50) +
              Math.sin(i * 0.04 + 1.2 + phase * 0.55) * (amp * 0.30) +
              Math.sin(i * 0.24 + 0.5 + phase * 0.85) * (amp * 0.16) +
              Math.sin(i * 0.55 + 0.3 + phase * 1.3) * (amp * 0.06));
        pts.push(`${x.toFixed(2)},${y.toFixed(2)}`);
      }
      if (ref.current) ref.current.setAttribute("points", pts.join(" "));
      raf = requestAnimationFrame(tick);
    };

    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [width, height, ampBase, ampVariance, phaseSpeed]);

  const gradId = `live-flourish-${width}-${height}`;
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
          <stop offset="6%" stopColor={SCOPE_AMBER} stopOpacity="0.95" />
          <stop offset="94%" stopColor={SCOPE_AMBER} stopOpacity="0.9" />
          <stop offset="100%" stopColor={SCOPE_AMBER} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polyline
        ref={ref}
        points=""
        fill="none"
        stroke={`url(#${gradId})`}
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        style={{ filter: `drop-shadow(0 0 2.5px ${SCOPE_AMBER_GLOW}55)` }}
      />
    </svg>
  );
}

function DrawInFlourish({ width, height }: { width: number; height: number }) {
  const pts = React.useMemo(() => {
    const out: string[] = [];
    const N = 220;
    const amp = (height / 2) * 0.5;
    const mid = height / 2;
    for (let i = 0; i <= N; i++) {
      const x = (i / N) * width;
      const u = i / N;
      const fade = Math.sin(Math.PI * u);
      const y =
        mid +
        fade *
          (Math.sin(i * 0.18) * (amp * 0.46) +
            Math.sin(i * 0.07 + 1.2) * (amp * 0.28) +
            Math.sin(i * 0.42 + 0.5) * (amp * 0.18));
      out.push(`${x.toFixed(2)},${y.toFixed(2)}`);
    }
    return out.join(" ");
  }, [width, height]);
  const gradId = `drawin-flourish-${width}-${height}`;
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
          <stop offset="6%" stopColor={SCOPE_AMBER} stopOpacity="0.95" />
          <stop offset="94%" stopColor={SCOPE_AMBER} stopOpacity="0.9" />
          <stop offset="100%" stopColor={SCOPE_AMBER} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polyline
        className="cs-birth-wave"
        points={pts}
        fill="none"
        stroke={`url(#${gradId})`}
        strokeWidth={2.4}
        strokeLinecap="round"
        style={{ filter: `drop-shadow(0 0 2.5px ${SCOPE_AMBER_GLOW}55)` }}
      />
    </svg>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Title bar pill + atoms

function PillInline() {
  return (
    <div
      className="flex items-center gap-2 rounded-full px-3.5 py-1.5"
      style={{ background: TALKIE_INK }}
    >
      <RecMark active />
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

function RecMark({ active = true }: { active?: boolean }) {
  return (
    <span
      className="block h-2 w-2 rounded-full"
      style={{
        background: active ? REC_RED : TALKIE_INK_FAINTER,
        boxShadow: active
          ? "0 0 0 2px rgba(192,58,42,0.25), 0 0 4px rgba(192,58,42,0.6)"
          : "none",
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

function SurfaceButton({
  kind,
  visible,
}: {
  kind: "cancel" | "stop";
  visible: boolean;
}) {
  const isStop = kind === "stop";
  return (
    <button
      type="button"
      tabIndex={-1}
      className="flex items-center gap-1.5 rounded-full px-3 py-1 font-mono text-[10px] uppercase tracking-[0.22em]"
      style={{
        background: isStop ? REC_RED : "transparent",
        color: isStop ? TALKIE_CREAM : TALKIE_INK,
        border: isStop
          ? "1px solid rgba(192,58,42,0)"
          : "1px solid rgba(35,36,35,0.18)",
        opacity: visible ? 1 : 0,
        pointerEvents: visible ? "auto" : "none",
        transition: "opacity 180ms ease-out",
      }}
    >
      {isStop ? (
        <>
          <span
            className="block h-2 w-2 rounded-[1px]"
            style={{ background: TALKIE_CREAM }}
          />
          <span>Stop</span>
          <span style={{ opacity: 0.65, letterSpacing: "0.18em" }}>⌘.</span>
        </>
      ) : (
        <>
          <span>Cancel</span>
          <span style={{ opacity: 0.55, letterSpacing: "0.18em" }}>Esc</span>
        </>
      )}
    </button>
  );
}

// ──────────────────────────────────────────────────────────────────────
// Hooks + math

function useElapsed(active: boolean, start: number) {
  const [t, setT] = React.useState(start);
  React.useEffect(() => {
    if (!active) return;
    const id = setInterval(() => {
      setT((x) => (x >= start + 60 ? start : x + 1));
    }, 1000);
    return () => clearInterval(id);
  }, [active, start]);
  return t;
}

function useTimeline(durationMs: number) {
  const [progress, setProgress] = React.useState(0);
  React.useEffect(() => {
    let raf = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const t = ((now - start) % durationMs) / durationMs;
      setProgress(t);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [durationMs]);
  return progress;
}

function smoothstep(x: number, a: number, b: number) {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}

// ──────────────────────────────────────────────────────────────────────
// Keyframe styles for the birth animation

function KeyframeStyles() {
  return (
    <style>{`
      /* Birth is a 7s loop. The card spends the first 28% (≈2s)
         materializing — heavy blur dissolves, scale settles, opacity
         resolves. Everything inside the card staggers within that
         same window. Then ~5s of quiet, resting state before the
         next loop. Slower than v1 (4.5s) so the materialization is
         observable instead of perfunctory. */

      .cs-birth {
        animation: cs-birth-card 7s cubic-bezier(0.22, 1, 0.36, 1);
        transform-origin: center top;
      }
      @keyframes cs-birth-card {
        0%   {
          opacity: 0;
          transform: translateY(14px) scale(0.93);
          filter: blur(22px);
        }
        12%  {
          opacity: 0.55;
          transform: translateY(6px) scale(0.97);
          filter: blur(12px);
        }
        28%  {
          opacity: 1;
          transform: translateY(0) scale(1);
          filter: blur(0);
        }
        100% {
          opacity: 1;
          transform: translateY(0) scale(1);
          filter: blur(0);
        }
      }

      .cs-birth-eyebrow {
        animation: cs-birth-eyebrow 7s cubic-bezier(0.22, 1, 0.36, 1);
      }
      @keyframes cs-birth-eyebrow {
        0%, 6%  { opacity: 0; transform: translateY(4px); }
        20%     { opacity: 1; transform: translateY(0); }
        100%    { opacity: 1; transform: translateY(0); }
      }

      .cs-birth-caption {
        animation: cs-birth-caption 7s cubic-bezier(0.22, 1, 0.36, 1);
      }
      @keyframes cs-birth-caption {
        0%, 22% { opacity: 0; transform: translateY(6px); }
        34%     { opacity: 1; transform: translateY(0); }
        100%    { opacity: 1; transform: translateY(0); }
      }

      .cs-birth-wave {
        stroke-dasharray: 1200;
        stroke-dashoffset: 1200;
        animation: cs-birth-draw 7s cubic-bezier(0.22, 1, 0.36, 1);
      }
      @keyframes cs-birth-draw {
        0%, 14% { stroke-dashoffset: 1200; }
        32%     { stroke-dashoffset: 0; }
        100%    { stroke-dashoffset: 0; }
      }
    `}</style>
  );
}
