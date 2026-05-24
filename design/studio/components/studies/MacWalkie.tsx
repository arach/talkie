"use client";

/**
 * Mac Walkie — agentic transmission surface for the Hyper+T loop.
 *
 * Inherits Ask AI's vocabulary (T01/T02 turn codes, USER/TALKIE
 * speakers, model · latency · tokens meta) and extends it with two
 * Mac-only concepts:
 *
 *   - **Transmission mode** — every TALKIE turn lands as either
 *     VERBAL ♪ (direct conversational answer, auto-spoken back) or
 *     ASYNC ⟳ (computer-use job that takes minutes; agent gives a
 *     short verbal ack, then reports back as work progresses).
 *
 *   - **Auto-listen** — unlike iOS Ask AI where "Listen" is a chip
 *     after the fact, a Mac walkie turn pipes the response body
 *     through SelectionSpeechPlaybackController automatically. The
 *     ♪ glyph next to the turn header signals "this got spoken."
 *
 * Variants cover the conversational shapes we expect day-to-day:
 *   - idle    empty channel; Hyper+T affordance is the hero.
 *   - verbal  fast back-and-forth, all short verbal turns.
 *   - async   a long-running computer-use job in flight with step log.
 *   - mixed   verbal turns continue while an async job is still working.
 */

export type MacWalkieVariant = "idle" | "verbal" | "async" | "mixed";

export const MAC_WALKIE_VARIANTS: { key: MacWalkieVariant; label: string }[] = [
  { key: "idle", label: "Idle" },
  { key: "verbal", label: "Verbal" },
  { key: "async", label: "Async" },
  { key: "mixed", label: "Mixed" },
];

export function MacWalkie({ variant }: { variant: MacWalkieVariant }) {
  return (
    <div
      className="flex h-full flex-col"
      style={{
        background: "var(--theme-canvas)",
        fontFamily: "var(--theme-font-sans)",
      }}
    >
      <Header />
      <Divider />

      <div className="flex-1 overflow-hidden">
        {variant === "idle" && <IdleState />}
        {variant === "verbal" && <VerbalState />}
        {variant === "async" && <AsyncState />}
        {variant === "mixed" && <MixedState />}
      </div>

      <PromptBar variant={variant} />
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
        <ChannelChip code="CH-01" label="NIGHTOPS" />
      </div>

      <div className="flex items-center gap-2">
        <ModeKey glyph="♪" label="VERBAL" />
        <ModeKey glyph="⟳" label="ASYNC" />
        <button
          aria-label="Close"
          className="flex h-6 w-6 items-center justify-center rounded-full"
          style={{
            background: "var(--theme-edge-faint)",
            color: "var(--theme-ink-faint)",
          }}
        >
          <svg viewBox="0 0 12 12" className="h-2.5 w-2.5" fill="none">
            <path
              d="M2 2 L 10 10 M 10 2 L 2 10"
              stroke="currentColor"
              strokeWidth={1.2}
              strokeLinecap="round"
            />
          </svg>
        </button>
      </div>
    </div>
  );
}

function ChannelChip({ code, label }: { code: string; label: string }) {
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2 py-[3px] text-[10px] font-medium"
      style={{
        border: "0.5px solid var(--theme-edge-faint)",
        color: "var(--theme-ink-faint)",
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.10em",
      }}
    >
      <span
        className="inline-block h-1.5 w-1.5 rounded-full"
        style={{ background: "var(--theme-amber)" }}
      />
      {code} · {label}
    </span>
  );
}

function ModeKey({ glyph, label }: { glyph: string; label: string }) {
  return (
    <span
      className="inline-flex items-center gap-1 text-[9px]"
      style={{
        color: "var(--theme-ink-faint)",
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.20em",
      }}
    >
      <span style={{ color: "var(--theme-amber)" }}>{glyph}</span>
      {label}
    </span>
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

// ── Idle ──────────────────────────────────────────────────────────

function IdleState() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-6 px-8 text-center">
      <div
        className="flex h-14 w-14 items-center justify-center rounded-full"
        style={{
          border: "1px solid var(--theme-amber)",
          color: "var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        <span className="text-[18px] font-medium">T</span>
      </div>

      <div className="flex flex-col gap-1.5">
        <div
          className="text-[22px] font-light leading-tight"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-display)",
          }}
        >
          Press &amp; hold to transmit.
        </div>
        <div
          className="text-[11px]"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.18em",
          }}
        >
          ⇧ ⌃ ⌥ ⌘ T · WALKIE-TALKIE STYLE · RELEASE TO SEND
        </div>
      </div>

      <div
        className="grid w-full max-w-[440px] grid-cols-2 gap-2 pt-4 text-left text-[11px]"
        style={{
          color: "var(--theme-ink-dim)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        <Hint glyph="♪" title="Verbal" body="Short answers come back spoken." />
        <Hint glyph="⟳" title="Async" body="Long jobs ack now, report later." />
        <Hint glyph="◎" title="Context" body="Selection, clipboard, recent tray." />
        <Hint glyph="↻" title="Channels" body="Switch agent personas per channel." />
      </div>
    </div>
  );
}

function Hint({ glyph, title, body }: { glyph: string; title: string; body: string }) {
  return (
    <div
      className="flex items-start gap-2 rounded-md px-3 py-2.5"
      style={{
        background: "var(--theme-paper)",
        border: "0.5px solid var(--theme-edge-faint)",
      }}
    >
      <span
        className="text-[12px]"
        style={{ color: "var(--theme-amber)" }}
      >
        {glyph}
      </span>
      <div className="flex flex-col gap-0.5">
        <span
          className="text-[10px] uppercase"
          style={{
            color: "var(--theme-ink)",
            letterSpacing: "0.18em",
          }}
        >
          {title}
        </span>
        <span style={{ color: "var(--theme-ink-faint)" }}>{body}</span>
      </div>
    </div>
  );
}

// ── Conversation states ───────────────────────────────────────────

function VerbalState() {
  return (
    <ConversationScroll>
      <Turn
        speaker="USER"
        code="T01"
        body="What's on my calendar tomorrow?"
        meta="9:42a · live mic · 1.4s"
      />
      <Turn
        speaker="TALKIE"
        code="T02"
        mode="verbal"
        body="Three meetings. 10am standup, noon with Mira, 4pm bridge review. Light afternoon after that."
        meta="opus 4.7 · 2.1s · 312t"
      />
      <Turn
        speaker="USER"
        code="T03"
        body="Anything I should prep?"
        meta="just now · live mic"
      />
      <Turn
        speaker="TALKIE"
        code="T04"
        mode="verbal"
        body="Thinking…"
        meta="opus 4.7 · 0.3s"
        thinking
      />
    </ConversationScroll>
  );
}

function AsyncState() {
  return (
    <ConversationScroll>
      <Turn
        speaker="USER"
        code="T01"
        body="Move the Mira lunch to 1pm, check no conflicts, and email her the update."
        meta="9:42a · live mic · 4.1s"
      />
      <Turn
        speaker="TALKIE"
        code="T02"
        mode="verbal"
        body="Ten-four. Working on it — I'll come back when it's done."
        meta="opus 4.7 · 0.8s · ack"
      />
      <AsyncJobTurn
        code="T03"
        title="Reschedule + notify Mira"
        steps={[
          { label: "calendar.shift_event(mira-lunch → 13:00)", state: "done" },
          { label: "calendar.check_conflicts(13:00-14:00)", state: "done" },
          { label: "mail.draft(to=mira, subject=Lunch moved)", state: "active" },
          { label: "mail.send", state: "pending" },
        ]}
        elapsed="0:34"
      />
    </ConversationScroll>
  );
}

function MixedState() {
  return (
    <ConversationScroll>
      <Turn
        speaker="USER"
        code="T01"
        body="Pull the last three memos with the bridge team and start me a summary."
        meta="9:38a · live mic · 3.6s"
      />
      <Turn
        speaker="TALKIE"
        code="T02"
        mode="verbal"
        body="On it. I'll surface a draft when ready."
        meta="opus 4.7 · 0.6s · ack"
      />
      <AsyncJobTurn
        code="T03"
        title="Bridge-team memo summary"
        steps={[
          { label: "library.query(tag=bridge, limit=3)", state: "done" },
          { label: "summarize(memos, format=brief)", state: "active" },
          { label: "compose.stage(title=Bridge brief)", state: "pending" },
        ]}
        elapsed="0:48"
      />
      <Turn
        speaker="USER"
        code="T04"
        body="While that runs — who owns the keyboard demo Friday?"
        meta="9:39a · live mic · 2.2s"
      />
      <Turn
        speaker="TALKIE"
        code="T05"
        mode="verbal"
        body="Mira. She committed Tuesday to have it ready for the studio demo."
        meta="opus 4.7 · 1.7s · 198t"
      />
      <Turn
        speaker="USER"
        code="T06"
        body="Cool, remind me tomorrow morning."
        meta="just now · live mic"
      />
      <Turn
        speaker="TALKIE"
        code="T07"
        mode="verbal"
        body="Thinking…"
        meta="opus 4.7 · 0.2s"
        thinking
      />
    </ConversationScroll>
  );
}

// ── Turn primitives ───────────────────────────────────────────────

function ConversationScroll({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col overflow-auto">{children}</div>
  );
}

function Turn({
  speaker,
  code,
  body,
  meta,
  mode,
  thinking = false,
}: {
  speaker: "USER" | "TALKIE";
  code: string;
  body: string;
  meta: string;
  mode?: "verbal" | "async";
  thinking?: boolean;
}) {
  const isTalkie = speaker === "TALKIE";
  return (
    <div
      className="flex flex-col gap-2.5 px-6 py-4"
      style={{ borderBottom: "0.5px solid var(--theme-edge-faint)" }}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <TurnCode code={code} accent={isTalkie} />
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
          {isTalkie && mode === "verbal" && <ModeFlag glyph="♪" label="VERBAL · AUTO-READ" />}
          {isTalkie && mode === "async" && <ModeFlag glyph="⟳" label="ASYNC" />}
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
        className={`whitespace-pre-line text-[13px] leading-[1.5] ${
          thinking ? "italic" : ""
        }`}
        style={{
          color: thinking ? "var(--theme-ink-faint)" : "var(--theme-ink)",
          maxWidth: "640px",
        }}
      >
        {thinking ? (
          <span className="inline-flex items-center gap-1.5">
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

      {isTalkie && !thinking && mode === "verbal" && <TurnActions />}
    </div>
  );
}

function TurnCode({ code, accent }: { code: string; accent: boolean }) {
  return (
    <span
      className="rounded-full px-1.5 py-0.5 text-[9px] font-medium tracking-[0.20em]"
      style={{
        color: accent ? "var(--theme-amber)" : "var(--theme-ink-faint)",
        border: `0.5px solid ${
          accent ? "var(--theme-amber)" : "var(--theme-edge-faint)"
        }`,
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      {code}
    </span>
  );
}

function ModeFlag({ glyph, label }: { glyph: string; label: string }) {
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-1.5 py-[2px] text-[9px]"
      style={{
        background: "var(--theme-amber)",
        color: "var(--theme-paper)",
        fontFamily: "var(--theme-font-mono)",
        letterSpacing: "0.18em",
      }}
    >
      <span>{glyph}</span>
      {label}
    </span>
  );
}

function TurnActions() {
  return (
    <div
      className="flex items-center gap-1.5 pt-1 text-[10px]"
      style={{ fontFamily: "var(--theme-font-mono)" }}
    >
      <ActionChip label="Save as memo" />
      <ActionChip label="Replay" />
      <ActionChip label="Refine" />
    </div>
  );
}

function ActionChip({ label }: { label: string }) {
  return (
    <button
      className="rounded-full px-2 py-1 text-[10px] uppercase"
      style={{
        border: "0.5px solid var(--theme-edge-faint)",
        color: "var(--theme-ink-faint)",
        letterSpacing: "0.16em",
      }}
    >
      {label}
    </button>
  );
}

// ── Async job turn ────────────────────────────────────────────────

type StepState = "done" | "active" | "pending";

function AsyncJobTurn({
  code,
  title,
  steps,
  elapsed,
}: {
  code: string;
  title: string;
  steps: { label: string; state: StepState }[];
  elapsed: string;
}) {
  return (
    <div
      className="flex flex-col gap-3 px-6 py-4"
      style={{ borderBottom: "0.5px solid var(--theme-edge-faint)" }}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <TurnCode code={code} accent />
          <span
            className="text-[10px] font-medium uppercase"
            style={{
              color: "var(--theme-ink-faint)",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.22em",
            }}
          >
            · TALKIE
          </span>
          <ModeFlag glyph="⟳" label="ASYNC · IN FLIGHT" />
        </div>
        <span
          className="text-[10px]"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {elapsed} elapsed
        </span>
      </div>

      <div
        className="rounded-md px-3 py-3"
        style={{
          background: "var(--theme-paper)",
          border: "0.5px solid var(--theme-edge-faint)",
        }}
      >
        <div
          className="text-[12px] mb-2"
          style={{
            color: "var(--theme-ink)",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {title}
        </div>
        <div className="flex flex-col gap-1.5">
          {steps.map((step) => (
            <StepRow key={step.label} {...step} />
          ))}
        </div>
      </div>
    </div>
  );
}

function StepRow({ label, state }: { label: string; state: StepState }) {
  const glyph =
    state === "done" ? "✓" : state === "active" ? "◌" : "·";
  const color =
    state === "done"
      ? "var(--theme-ink)"
      : state === "active"
        ? "var(--theme-amber)"
        : "var(--theme-ink-faint)";
  return (
    <div
      className="flex items-center gap-2 text-[11px]"
      style={{
        color,
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      <span
        className={`inline-block w-3 ${state === "active" ? "animate-pulse" : ""}`}
        style={{ color: "inherit" }}
      >
        {glyph}
      </span>
      <span>{label}</span>
    </div>
  );
}

// ── Prompt bar ────────────────────────────────────────────────────

function PromptBar({ variant }: { variant: MacWalkieVariant }) {
  const nextCode =
    variant === "idle"
      ? "T01"
      : variant === "verbal"
        ? "T05"
        : variant === "async"
          ? "T04"
          : "T08";

  return (
    <div
      className="flex items-center gap-3 px-5 py-4"
      style={{
        borderTop: "0.5px solid var(--theme-edge-faint)",
        background: "var(--theme-paper)",
      }}
    >
      <span
        className="rounded-full px-2 py-1 text-[9px] font-medium tracking-[0.20em]"
        style={{
          color: "var(--theme-amber)",
          border: "0.5px solid var(--theme-amber)",
          fontFamily: "var(--theme-font-mono)",
        }}
      >
        {nextCode}
      </span>

      <div
        className="flex flex-1 items-center gap-3 rounded-full px-4 py-2"
        style={{
          background: "var(--theme-canvas)",
          border: "0.5px solid var(--theme-edge-faint)",
        }}
      >
        <span
          className="text-[10px] font-medium uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.22em",
          }}
        >
          Hold
        </span>
        <Keycap label="⇧" />
        <Keycap label="⌃" />
        <Keycap label="⌥" />
        <Keycap label="⌘" />
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
          className="text-[10px] uppercase"
          style={{
            color: "var(--theme-ink-faint)",
            fontFamily: "var(--theme-font-mono)",
            letterSpacing: "0.18em",
          }}
        >
          auto · ♪ / ⟳
        </span>
      </div>

      <button
        aria-label="Type instead"
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
      className={`flex items-center justify-center rounded text-[10px] font-medium ${
        wide ? "px-2" : "px-1.5"
      }`}
      style={{
        height: "20px",
        minWidth: "20px",
        background: "var(--theme-paper)",
        border: "0.5px solid var(--theme-edge-faint)",
        color: "var(--theme-ink)",
        fontFamily: "var(--theme-font-mono)",
      }}
    >
      {label}
    </span>
  );
}
