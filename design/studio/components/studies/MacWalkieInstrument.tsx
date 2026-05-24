"use client";

/**
 * Mac Walkie — Direction 2 · "Instrument" (Pearl + Chiffon)
 *
 * Keeps the alternation idea from the dark-mode draft but lifts the
 * TALKIE bays to Scope's light bay materials so the surface stays in
 * the same daylight as the rest of the app:
 *
 *   - USER turns        →  Scope canvas substrate (the page itself).
 *   - TALKIE verbal     →  Pearl bay (cool, #F5F8FA · ink #2A2E32).
 *   - TALKIE async job  →  Chiffon bay (warm, #FAF5E8 · ink #2A2520).
 *
 * Three surface textures in one document — the *material* signals the
 * speaker and mode without resorting to dark contrast. Amber stays as
 * the accent, tuned per bay (cool #D49236 on Pearl, warm #9A6A22 on
 * Chiffon).
 *
 * Showcase composition: async + verbal mix, so all three materials
 * appear in one view.
 */

// Material tokens lifted from lib/schemes.ts (Pearl + Chiffon entries).
// Inlined so this study reads standalone without depending on a
// scheme attribute being set upstream.
const PEARL = {
  bg: "#F5F8FA",
  stripTop:
    "linear-gradient(to bottom, #FBFCFE 0%, #F2F5F7 60%, #E5E9ED 100%)",
  ink: "#2A2E32",
  inkFaint: "#6E737B",
  inkSubtle: "#8A8F96",
  accent: "#D49236",
  accentGlow: "rgba(212, 146, 54, 0.12)",
  edge: "rgba(20, 24, 28, 0.08)",
  edgeStrong: "rgba(20, 24, 28, 0.18)",
};

const CHIFFON = {
  bg: "#FAF5E8",
  stripTop:
    "linear-gradient(to bottom, #FDF8EB 0%, #F5F0E2 60%, #ECE7D6 100%)",
  ink: "#2A2520",
  inkFaint: "#7B6E60",
  inkSubtle: "#928576",
  accent: "#9A6A22",
  accentGlow: "rgba(154, 106, 34, 0.10)",
  edge: "rgba(60, 40, 20, 0.10)",
  edgeStrong: "rgba(154, 106, 34, 0.32)",
};

export function MacWalkieInstrument() {
  return (
    <div
      className="flex h-full flex-col"
      style={{
        background: "var(--theme-canvas)",
        fontFamily: "var(--theme-font-sans)",
      }}
    >
      <Header />
      <Hairline />
      <Conversation />
      <PromptBar />
    </div>
  );
}

// ── Chrome ─────────────────────────────────────────────────────────

function Header() {
  return (
    <div className="flex items-center justify-between px-6 pt-4 pb-3">
      <div className="flex items-center gap-3">
        <span
          className="text-[10px] font-medium uppercase"
          style={{
            color: "var(--theme-ink-dim)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.30em",
          }}
        >
          TALKIE · WALKIE
        </span>
        <ChannelLozenge code="CH-01" label="NIGHTOPS" />
      </div>

      <div className="flex items-center gap-3">
        <Telemetry label="UPTIME" value="2:14:08" />
        <Telemetry label="TURNS" value="07" />
        <Telemetry label="MODEL" value="OPUS 4.7" />
      </div>
    </div>
  );
}

function ChannelLozenge({ code, label }: { code: string; label: string }) {
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-[3px] text-[10px]"
      style={{
        border: "0.5px solid var(--theme-edge-faint)",
        background: "var(--theme-paper)",
        color: "var(--theme-ink)",
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.10em",
      }}
    >
      <span
        className="relative inline-block h-1.5 w-1.5 rounded-full"
        style={{ background: PEARL.accent }}
      >
        <span
          className="absolute inset-0 animate-ping rounded-full"
          style={{ background: PEARL.accent, opacity: 0.5 }}
        />
      </span>
      {code} · {label}
    </span>
  );
}

function Telemetry({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col items-end gap-0.5 leading-none">
      <span
        className="text-[8px] uppercase"
        style={{
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.20em",
        }}
      >
        {label}
      </span>
      <span
        className="text-[11px] tabular-nums"
        style={{
          color: "var(--theme-ink)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {value}
      </span>
    </div>
  );
}

function Hairline() {
  return (
    <div
      className="h-px w-full"
      style={{ background: "var(--theme-edge-faint)" }}
    />
  );
}

// ── Conversation ──────────────────────────────────────────────────

function Conversation() {
  return (
    <div className="flex flex-1 flex-col overflow-auto">
      <UserTurn
        code="T01"
        body="Pull the last three memos with the bridge team and start me a summary."
        meta="9:38a · live mic · 3.6s"
      />
      <PearlAckTurn
        code="T02"
        body="On it. I'll surface a draft when ready."
        meta="opus 4.7 · 0.6s · ack"
      />
      <ChiffonJobRow
        code="T03"
        title="Bridge-team memo summary"
        steps={[
          { label: "library.query(tag=bridge, limit=3)", state: "done", duration: "0.21s" },
          { label: "summarize(memos, format=brief)", state: "active", duration: "running…" },
          { label: "compose.stage(title=Bridge brief)", state: "pending", duration: "—" },
        ]}
        elapsed="0:48"
      />
      <UserTurn
        code="T04"
        body="While that runs — who owns the keyboard demo Friday?"
        meta="9:39a · live mic · 2.2s"
      />
      <PearlReplyTurn
        code="T05"
        body="Mira. She committed Tuesday to have it ready for the studio demo."
        meta="opus 4.7 · 1.7s · 198t"
      />
    </div>
  );
}

// ── Turn rows ─────────────────────────────────────────────────────

function UserTurn({
  code,
  body,
  meta,
}: {
  code: string;
  body: string;
  meta: string;
}) {
  return (
    <div
      className="flex flex-col gap-2 px-6 py-4"
      style={{
        borderBottom: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <TurnCode code={code} bay="canvas" />
          <Lab bay="canvas">· USER</Lab>
          <WaveformInline />
        </div>
        <Meta bay="canvas">{meta}</Meta>
      </div>
      <p
        className="text-[13px] leading-[1.55]"
        style={{
          color: "var(--theme-ink)",
          maxWidth: 640,
        }}
      >
        {body}
      </p>
    </div>
  );
}

function PearlAckTurn({
  code,
  body,
  meta,
}: {
  code: string;
  body: string;
  meta: string;
}) {
  return (
    <PearlRow
      code={code}
      meta={meta}
      flag={<ModeFlag glyph="♪" label="VERBAL · ACK" tone="pearl" />}
    >
      <p
        className="text-[14px] italic leading-[1.5]"
        style={{
          color: PEARL.ink,
          fontFamily: "var(--theme-font-display)",
        }}
      >
        “{body}”
      </p>
    </PearlRow>
  );
}

function PearlReplyTurn({
  code,
  body,
  meta,
}: {
  code: string;
  body: string;
  meta: string;
}) {
  return (
    <PearlRow
      code={code}
      meta={meta}
      flag={<ModeFlag glyph="♪" label="VERBAL · AUTO-READ" tone="pearl" />}
    >
      <p
        className="text-[13px] leading-[1.55]"
        style={{ color: PEARL.ink, maxWidth: 640 }}
      >
        {body}
      </p>
      <ActionRow tone="pearl" />
    </PearlRow>
  );
}

function ChiffonJobRow({
  code,
  title,
  steps,
  elapsed,
}: {
  code: string;
  title: string;
  steps: { label: string; state: "done" | "active" | "pending"; duration: string }[];
  elapsed: string;
}) {
  return (
    <ChiffonRow
      code={code}
      meta={`${elapsed} elapsed`}
      flag={<ModeFlag glyph="⟳" label="ASYNC · IN FLIGHT" tone="chiffon" />}
    >
      <div className="flex flex-col gap-3">
        <div
          className="flex items-center justify-between text-[11px]"
          style={{
            color: CHIFFON.ink,
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.04em",
          }}
        >
          <span>{title}</span>
          <span style={{ color: CHIFFON.inkSubtle }}>job://walkie/t03</span>
        </div>

        <div
          className="flex flex-col rounded-sm"
          style={{
            background: "rgba(255,255,255,0.42)",
            border: `0.5px solid ${CHIFFON.edge}`,
          }}
        >
          {steps.map((step, i) => (
            <StepLine key={step.label} index={i + 1} {...step} />
          ))}
        </div>
      </div>
    </ChiffonRow>
  );
}

// ── Bay shells (Pearl + Chiffon) ──────────────────────────────────

function PearlRow({
  code,
  meta,
  flag,
  children,
}: {
  code: string;
  meta: string;
  flag: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div
      className="relative flex flex-col gap-3 px-6 py-4"
      style={{
        background: PEARL.stripTop,
        borderBottom: `0.5px solid ${PEARL.edge}`,
        boxShadow: `inset 0 1px 0 rgba(255,255,255,0.6)`,
      }}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <TurnCode code={code} bay="pearl" />
          <Lab bay="pearl">· TALKIE</Lab>
          {flag}
        </div>
        <Meta bay="pearl">{meta}</Meta>
      </div>
      {children}
    </div>
  );
}

function ChiffonRow({
  code,
  meta,
  flag,
  children,
}: {
  code: string;
  meta: string;
  flag: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div
      className="relative flex flex-col gap-3 px-6 py-4"
      style={{
        background: CHIFFON.stripTop,
        borderBottom: `0.5px solid ${CHIFFON.edge}`,
        boxShadow: `inset 0 1px 0 rgba(255,255,255,0.6)`,
      }}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <TurnCode code={code} bay="chiffon" />
          <Lab bay="chiffon">· TALKIE</Lab>
          {flag}
        </div>
        <Meta bay="chiffon">{meta}</Meta>
      </div>
      {children}
    </div>
  );
}

function StepLine({
  index,
  label,
  state,
  duration,
}: {
  index: number;
  label: string;
  state: "done" | "active" | "pending";
  duration: string;
}) {
  const palette =
    state === "done"
      ? { color: CHIFFON.ink, glyph: "✓", dim: CHIFFON.inkFaint }
      : state === "active"
        ? { color: CHIFFON.accent, glyph: "▸", dim: CHIFFON.accent }
        : { color: CHIFFON.inkSubtle, glyph: "·", dim: CHIFFON.inkSubtle };

  return (
    <div
      className="grid items-center gap-3 px-3 py-1.5 text-[11px]"
      style={{
        gridTemplateColumns: "18px 12px 1fr auto",
        fontFamily: "var(--theme-font-mono)",
        borderBottom: state === "pending" ? "none" : `0.5px dotted ${CHIFFON.edge}`,
      }}
    >
      <span style={{ color: CHIFFON.inkSubtle }} className="tabular-nums">
        {String(index).padStart(2, "0")}
      </span>
      <span
        className={state === "active" ? "animate-pulse" : ""}
        style={{ color: palette.dim }}
      >
        {palette.glyph}
      </span>
      <span style={{ color: palette.color }}>{label}</span>
      <span className="tabular-nums" style={{ color: palette.dim }}>
        {duration}
      </span>
    </div>
  );
}

// ── Shared primitives ─────────────────────────────────────────────

type Bay = "canvas" | "pearl" | "chiffon";

const bayInk = (bay: Bay) =>
  bay === "pearl"
    ? PEARL.inkFaint
    : bay === "chiffon"
      ? CHIFFON.inkFaint
      : "var(--theme-ink-faint)";

const bayAccent = (bay: Bay) =>
  bay === "chiffon" ? CHIFFON.accent : PEARL.accent;

const bayEdge = (bay: Bay) =>
  bay === "pearl"
    ? PEARL.edgeStrong
    : bay === "chiffon"
      ? CHIFFON.edgeStrong
      : "var(--theme-edge-faint)";

function TurnCode({ code, bay }: { code: string; bay: Bay }) {
  const accent = bay !== "canvas";
  return (
    <span
      className="rounded-full px-1.5 py-0.5 text-[9px] font-medium tracking-[0.20em]"
      style={{
        color: accent ? bayAccent(bay) : "var(--theme-ink-faint)",
        border: `0.5px solid ${bayEdge(bay)}`,
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      {code}
    </span>
  );
}

function Lab({ bay, children }: { bay: Bay; children: React.ReactNode }) {
  return (
    <span
      className="text-[10px] font-medium uppercase"
      style={{
        color: bayInk(bay),
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.22em",
      }}
    >
      {children}
    </span>
  );
}

function Meta({ bay, children }: { bay: Bay; children: React.ReactNode }) {
  return (
    <span
      className="text-[10px] tabular-nums"
      style={{
        color: bayInk(bay),
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      {children}
    </span>
  );
}

function ModeFlag({
  glyph,
  label,
  tone,
}: {
  glyph: string;
  label: string;
  tone: "pearl" | "chiffon";
}) {
  const m = tone === "chiffon" ? CHIFFON : PEARL;
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-1.5 py-[2px] text-[9px]"
      style={{
        background: m.accentGlow,
        color: m.accent,
        border: `0.5px solid ${m.accent}`,
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.18em",
      }}
    >
      <span>{glyph}</span>
      {label}
    </span>
  );
}

function WaveformInline() {
  return (
    <span className="ml-1 inline-flex items-end gap-[2px]">
      {[3, 6, 4, 8, 5, 9, 6, 4, 7].map((h, i) => (
        <span
          key={i}
          style={{
            width: 2,
            height: h,
            background: "var(--theme-ink-faint)",
            borderRadius: 1,
          }}
        />
      ))}
    </span>
  );
}

function ActionRow({ tone }: { tone: "pearl" | "chiffon" }) {
  const m = tone === "chiffon" ? CHIFFON : PEARL;
  return (
    <div
      className="flex items-center gap-1.5 pt-2 text-[10px]"
      style={{ fontFamily: "var(--theme-font-mono)" }}
    >
      {["Save as memo", "Replay", "Refine"].map((label) => (
        <button
          key={label}
          className="rounded-full px-2 py-1 text-[10px] uppercase"
          style={{
            border: `0.5px solid ${m.edgeStrong}`,
            color: m.accent,
            letterSpacing: "0.16em",
          }}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

// ── Prompt bar ────────────────────────────────────────────────────

function PromptBar() {
  return (
    <div
      className="flex items-center gap-3 px-5 py-3.5"
      style={{
        borderTop: "0.5px solid var(--theme-edge-faint)",
        background: "var(--theme-paper)",
      }}
    >
      <TurnCode code="T06" bay="canvas" />

      <div
        className="flex flex-1 items-center gap-3 rounded-full px-4 py-2"
        style={{
          background: "var(--theme-canvas)",
          border: "0.5px solid var(--theme-edge-faint)",
        }}
      >
        <span
          className="text-[9px] font-medium uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.20em",
          }}
        >
          Hold
        </span>
        {["⇧", "⌃", "⌥", "⌘"].map((k) => (
          <Keycap key={k} label={k} />
        ))}
        <Keycap label="T" wide />
        <span
          className="flex-1 text-[12px]"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          to transmit · release to send
        </span>
        <span
          className="text-[9px] uppercase"
          style={{
            color: PEARL.accent,
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.18em",
          }}
        >
          auto · ♪ pearl / ⟳ chiffon
        </span>
      </div>

      <button
        className="rounded-full px-3 py-2 text-[10px] uppercase"
        style={{
          border: "0.5px solid var(--theme-edge-faint)",
          color: "var(--theme-ink-faint)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.18em",
        }}
      >
        Type instead
      </button>
    </div>
  );
}

function Keycap({ label, wide = false }: { label: string; wide?: boolean }) {
  return (
    <span
      className={`flex items-center justify-center text-[10px] font-medium ${
        wide ? "px-2" : "px-1.5"
      }`}
      style={{
        height: 20,
        minWidth: 20,
        background: "var(--theme-paper)",
        border: "0.5px solid var(--theme-edge-faint)",
        color: "var(--theme-ink)",
        fontFamily: "var(--theme-font-mono)",
        borderRadius: 3,
      }}
    >
      {label}
    </span>
  );
}
