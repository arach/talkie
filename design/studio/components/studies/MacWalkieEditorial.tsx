"use client";

/**
 * Mac Walkie — Direction 3 · "Editorial"
 *
 * Frame the surface as a transmission *log document*, not a chat
 * panel. Each session is a printable record: eyebrow, serif headline,
 * each turn as a paragraph with a margin-noted turn code + mode flag
 * + meta. Async jobs render as inset code blocks with a left rule,
 * like a court reporter's stage directions. The walkie session feels
 * like something you'd archive in the Library.
 *
 * Showcase composition: mixed — both verbal turns and an async job
 * in flight, so the marginalia is visible across speaker types.
 */

export function MacWalkieEditorial() {
  return (
    <div
      className="flex h-full flex-col"
      style={{
        background: "var(--theme-paper)",
        fontFamily: "var(--theme-font-sans)",
      }}
    >
      <Masthead />
      <Hairline />
      <Document />
      <PromptBar />
    </div>
  );
}

// ── Masthead ──────────────────────────────────────────────────────

function Masthead() {
  return (
    <div className="flex flex-col gap-4 px-12 pt-8 pb-6">
      <div className="flex items-center justify-between">
        <span
          className="text-[10px] uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.32em",
          }}
        >
          Transmission log · CH-01 · NIGHTOPS
        </span>
        <span
          className="text-[10px] tabular-nums"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          Thu · May 23 · 09:38–09:42 · 7 turns
        </span>
      </div>

      <div className="flex items-end justify-between gap-6">
        <h1
          className="text-[34px] leading-[1.05] tracking-[-0.01em]"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-display)",
            fontStyle: "italic",
            fontWeight: 400,
          }}
        >
          Bridge brief &amp;<br />
          Friday demo owner.
        </h1>
        <div className="flex flex-col items-end gap-1 pb-1">
          <span
            className="text-[10px] uppercase"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.20em",
            }}
          >
            Recorded · Walkie · ⇧⌃⌥⌘T
          </span>
          <span
            className="text-[10px]"
            style={{
              color: "var(--theme-ink-dim)",
              fontFamily: "var(--theme-font-mono)",
            }}
          >
            opus 4.7 · channel · NIGHTOPS
          </span>
        </div>
      </div>
    </div>
  );
}

function Hairline() {
  return (
    <div
      className="mx-12 h-px"
      style={{ background: "var(--theme-edge-faint)" }}
    />
  );
}

// ── Document body ─────────────────────────────────────────────────

function Document() {
  return (
    <div className="flex flex-1 flex-col overflow-auto px-12 py-6">
      <Entry
        code="T01"
        speaker="USER"
        meta="09:38 · live mic · 3.6s"
        body="Pull the last three memos with the bridge team and start me a summary."
      />
      <Entry
        code="T02"
        speaker="TALKIE"
        mode="verbal"
        meta="opus 4.7 · 0.6s · ack"
        body="“On it. I'll surface a draft when ready.”"
        italic
      />
      <JobEntry
        code="T03"
        title="Bridge-team memo summary"
        steps={[
          { label: "library.query(tag=bridge, limit=3)", state: "done" },
          { label: "summarize(memos, format=brief)", state: "active" },
          { label: "compose.stage(title=Bridge brief)", state: "pending" },
        ]}
        elapsed="0:48"
      />
      <Entry
        code="T04"
        speaker="USER"
        meta="09:39 · live mic · 2.2s"
        body="While that runs — who owns the keyboard demo Friday?"
      />
      <Entry
        code="T05"
        speaker="TALKIE"
        mode="verbal"
        meta="opus 4.7 · 1.7s · 198t"
        body="Mira. She committed Tuesday to have it ready for the studio demo."
      />
      <Entry
        code="T06"
        speaker="USER"
        meta="just now · live mic"
        body="Cool. Remind me tomorrow morning."
      />
      <Entry
        code="T07"
        speaker="TALKIE"
        mode="thinking"
        meta="opus 4.7 · 0.2s"
        body="Thinking…"
        italic
      />
    </div>
  );
}

// ── Entry (paragraph + marginalia) ────────────────────────────────

function Entry({
  code,
  speaker,
  body,
  meta,
  mode,
  italic = false,
}: {
  code: string;
  speaker: "USER" | "TALKIE";
  body: string;
  meta: string;
  mode?: "verbal" | "async" | "thinking";
  italic?: boolean;
}) {
  const isTalkie = speaker === "TALKIE";
  return (
    <article
      className="grid items-baseline gap-x-6 py-3.5"
      style={{
        gridTemplateColumns: "108px 1fr 132px",
        borderBottom: "0.5px dashed var(--theme-edge-faint)",
      }}
    >
      {/* Left margin — turn code + speaker */}
      <div className="flex flex-col gap-1">
        <span
          className="text-[10px] font-medium tabular-nums"
          style={{
            color: isTalkie ? "var(--theme-amber)" : "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.16em",
          }}
        >
          {code}
        </span>
        <span
          className="text-[9px] uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.24em",
          }}
        >
          {speaker}
        </span>
      </div>

      {/* Body */}
      <p
        className="text-[14px] leading-[1.6]"
        style={{
          color:
            mode === "thinking" ? "var(--theme-ink-faint)" : "var(--theme-ink)",
          fontFamily: italic ? "var(--theme-font-display)" : "var(--theme-font-sans)",
          fontStyle: italic ? "italic" : "normal",
          maxWidth: 560,
        }}
      >
        {body}
        {mode === "thinking" && (
          <span
            className="ml-1.5 inline-block h-1.5 w-1.5 animate-pulse rounded-full align-middle"
            style={{ background: "var(--theme-amber)" }}
          />
        )}
      </p>

      {/* Right margin — mode + meta */}
      <div className="flex flex-col items-end gap-1">
        {mode === "verbal" && <MarginFlag glyph="♪" label="auto-read" />}
        {mode === "async" && <MarginFlag glyph="⟳" label="async" />}
        <span
          className="text-[9px] tabular-nums"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.04em",
          }}
        >
          {meta}
        </span>
      </div>
    </article>
  );
}

function MarginFlag({ glyph, label }: { glyph: string; label: string }) {
  return (
    <span
      className="inline-flex items-center gap-1 text-[9px] uppercase"
      style={{
        color: "var(--theme-amber)",
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.18em",
      }}
    >
      <span style={{ fontSize: 11 }}>{glyph}</span>
      {label}
    </span>
  );
}

// ── Job entry ─────────────────────────────────────────────────────

function JobEntry({
  code,
  title,
  steps,
  elapsed,
}: {
  code: string;
  title: string;
  steps: { label: string; state: "done" | "active" | "pending" }[];
  elapsed: string;
}) {
  return (
    <article
      className="grid items-start gap-x-6 py-3.5"
      style={{
        gridTemplateColumns: "108px 1fr 132px",
        borderBottom: "0.5px dashed var(--theme-edge-faint)",
      }}
    >
      <div className="flex flex-col gap-1">
        <span
          className="text-[10px] font-medium tabular-nums"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.16em",
          }}
        >
          {code}
        </span>
        <span
          className="text-[9px] uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.24em",
          }}
        >
          TALKIE
        </span>
      </div>

      <div className="flex flex-col gap-2" style={{ maxWidth: 560 }}>
        <span
          className="text-[12px] italic"
          style={{
            color: "var(--theme-ink-dim)",
            fontFamily: "var(--theme-font-display)",
          }}
        >
          [stage direction · {title.toLowerCase()}]
        </span>
        <div
          className="flex flex-col gap-1 py-2 pl-3"
          style={{
            borderLeft: "1.5px solid var(--theme-amber)",
            background:
              "linear-gradient(90deg, rgba(255,169,64,0.05) 0%, transparent 80%)",
          }}
        >
          {steps.map((step, i) => (
            <JobLine key={step.label} index={i + 1} {...step} />
          ))}
        </div>
      </div>

      <div className="flex flex-col items-end gap-1">
        <MarginFlag glyph="⟳" label="in flight" />
        <span
          className="text-[9px] tabular-nums"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {elapsed} elapsed
        </span>
      </div>
    </article>
  );
}

function JobLine({
  index,
  label,
  state,
}: {
  index: number;
  label: string;
  state: "done" | "active" | "pending";
}) {
  const palette =
    state === "done"
      ? { color: "var(--theme-ink)", glyph: "✓", dim: "var(--theme-ink-faint)" }
      : state === "active"
        ? { color: "var(--theme-amber)", glyph: "▸", dim: "var(--theme-amber)" }
        : { color: "var(--theme-ink-faint)", glyph: "·", dim: "var(--theme-ink-faint)" };

  return (
    <div
      className="grid items-center gap-3 text-[12px]"
      style={{
        gridTemplateColumns: "20px 14px 1fr",
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      <span style={{ color: "var(--theme-ink-faint)" }} className="tabular-nums">
        {String(index).padStart(2, "0")}
      </span>
      <span
        className={state === "active" ? "animate-pulse" : ""}
        style={{ color: palette.dim }}
      >
        {palette.glyph}
      </span>
      <span style={{ color: palette.color }}>{label}</span>
    </div>
  );
}

// ── Prompt bar ────────────────────────────────────────────────────

function PromptBar() {
  return (
    <div
      className="flex items-center justify-between gap-4 px-12 py-5"
      style={{
        borderTop: "0.5px solid var(--theme-edge-faint)",
        background: "var(--theme-canvas)",
      }}
    >
      <div className="flex items-center gap-2 text-[10px]">
        <span
          className="uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.22em",
          }}
        >
          T08 ·
        </span>
        <span
          style={{
            color: "var(--theme-ink-dim)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.06em",
          }}
        >
          press &amp; hold ⇧⌃⌥⌘T to add a transmission · release to send
        </span>
      </div>
      <div className="flex items-center gap-2">
        <span
          className="text-[9px] uppercase"
          style={{
            color: "var(--theme-amber)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.20em",
          }}
        >
          auto-route · ♪ / ⟳
        </span>
        <button
          className="rounded px-3 py-1.5 text-[10px] uppercase"
          style={{
            border: "0.5px solid var(--theme-edge-faint)",
            color: "var(--theme-ink-dim)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.18em",
            background: "var(--theme-paper)",
          }}
        >
          Type instead
        </button>
      </div>
    </div>
  );
}
