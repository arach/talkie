"use client";

/**
 * Mac Capture Markup — talk to your screenshot.
 *
 * Premise (commission 2026-05-24 · revised through three walkthroughs):
 *   Markup is delegated to CleanShot X today (TrayViewer.swift line 1090).
 *   The Talkie-native path is voice + image. Two states, one window —
 *     1. ASK:       the screenshot, drawing tools above, talk below.
 *     2. TOUCH UP:  the agent applied markup; same layout. Pick a
 *                   layer and its chip slots into the talk bar.
 *
 *   The window has two input zones:
 *     · TOP — drawing toolbar. Manual primitives: rect, arrow, line,
 *             text, blur. Press M to toggle (always visible in this
 *             study so the affordance is legible).
 *     · BOTTOM — talk bar. Voice mic and text input live here, equal
 *             weight, with the selection chip riding alongside the text
 *             so "select and speak" is a single gesture.
 *
 *   Earlier drafts merged everything into one row at the bottom.
 *   Operator review: pull the drawing tools up to the top where they
 *   belong (every editor in the universe puts them there) and leave the
 *   bottom for talking.
 *
 * Markup means literal markup: lines, guides, drawings, text. The agent
 * emits structured tool calls (markup.rect / markup.arrow / markup.label
 * / markup.guide / markup.blur) into a sidecar JSON next to the PNG.
 * The image is never re-encoded.
 *
 * Architecture (unchanged): ephemeral WKWebView panel, spawn on demand,
 * discard on accept/cancel. Pattern is already in-house
 * (HomeAppWidgetView, LearnKnowledgeWebView). Not surfaced as a visual
 * motif — it's just "the markup window."
 *
 * Palette: PEARL on FROST (matches MacCaptureDetail). Amber/brass
 * reserved for agent voice — tool calls, listening pulse, primary
 * action.
 */

import React from "react";

import { SCOPE } from "@/lib/scope-tokens";

// ─── Tokens ──────────────────────────────────────────────────────────

const T = {
  page:        SCOPE.canvas,
  pane:        SCOPE.pane,
  chrome:      SCOPE.chrome,
  rail:        SCOPE.rail,
  ink:         SCOPE.ink,
  inkMid:      SCOPE.inkMid,
  inkFaint:    SCOPE.inkFaint,
  inkFainter:  SCOPE.inkFainter,
  inkRule:     SCOPE.rule,
  inkRuleS:    SCOPE.ruleSubtle,
  inkRuleSec:  SCOPE.ruleSection,
  edge:        SCOPE.edge,
  ruleSoft:    SCOPE.ruleSoft,
  amber:       SCOPE.amber,
  amberDeep:   SCOPE.amberDeep,
  amberFaint:  SCOPE.amberFaint,
  amberSoft:   SCOPE.amberSoft,
  brass:       SCOPE.brass,
  alert:       SCOPE.alert,
  alertSoft:   SCOPE.alertSoft,
};

// Markup overlay tones — saturated stroke, low-alpha fill so underlying
// pixels still read.
const MARKUP = {
  ringAlert:   "#D03A1C",
  fillAlert:   "rgba(208,58,28,0.10)",
  ringAmber:   "#C47D1C",
  fillAmber:   "rgba(196,125,28,0.12)",
  ringInk:     "rgba(35,36,35,0.85)",
  fillInk:     "rgba(35,36,35,0.06)",
  guide:       "rgba(196,125,28,0.55)",
  labelBg:     "rgba(20,24,30,0.84)",
  labelInk:    "#FFFFFF",
};

// ─── Composition root ────────────────────────────────────────────────

/**
 * Speak Strip in isolation, using the canonical "1c · AskStateNarrow"
 * config. Exported so `/mac-capture-markup-compare` can mount the same
 * pixels Swift is porting to, without dragging the whole composition
 * (window chrome, canvas, marginalia) along for the ride.
 */
export function MacCaptureMarkupSpeakStrip() {
  return (
    <SpeakStrip
      placeholder="what should we mark up?"
      examples={[
        "circle the error and label it",
        "draw a horizontal guide",
        "blur the email",
        "arrow title → failed line",
      ]}
      scopeBadge="global · whole image"
    />
  );
}

/**
 * Full 1c "AskStateNarrow" composition — markup window chrome, drawing
 * toolbar, canvas with the mocked screenshot, and the speak strip below.
 * Exported so the compare page can mount the full studio surface 1:1
 * against a full-window Swift screenshot. The page hides the marginalia
 * (NamesMarginalia + CaptionStrip) by wrapping in a div that omits the
 * Surface chrome — see `app/mac-capture-markup-compare/page.tsx`.
 */
export function MacCaptureMarkupAskNarrow() {
  return (
    <MarkupWindow
      title="Markup · C-0017"
      subtitle="captured 2s ago · speak strip · pass verdict on canvas"
    >
      <ToolToolbar active={null} />
      <div
        className="relative flex items-center justify-center"
        style={{ background: T.rail, padding: "26px 26px" }}
      >
        <MockedScreenshotWithMarkup markup={false} />
        <PassVerdict status="idle" />
      </div>
      <SpeakStrip
        placeholder="what should we mark up?"
        examples={[
          "circle the error and label it",
          "draw a horizontal guide",
          "blur the email",
          "arrow title → failed line",
        ]}
        scopeBadge="global · whole image"
      />
    </MarkupWindow>
  );
}

export function MacCaptureMarkup() {
  return (
    <div style={{ width: 1180, background: T.page }} className="flex flex-col">
      <StudyHeader />
      <SectionBreak
        label="1 · ask"
        hint="screenshot captured · drawing tools above · talk bar below"
      />
      <AskState />
      <SectionBreak
        label="1b · ask · compact bar"
        hint="proposed · composer band ~40pt · hint trimmed · same affordances"
      />
      <AskStateCompact />
      <SectionBreak
        label="1c · ask · speak strip + canvas verdict"
        hint="mic → narrow circle · accept/cancel leaves the strip and pins to canvas"
      />
      <AskStateNarrow />
      <SectionBreak
        label="2 · touch up"
        hint="agent marked it up · pick a layer · its chip rides into the talk bar"
      />
      <TouchUpState />
      <SectionBreak
        label="3 · toolbar redesign · style stack + canvas tools"
        hint="tools left · contextual style right · zoom floats bottom-right · esc cancel removed"
      />
      <ToolbarRedesignState />
      <ToolbarStyleVariants />
      <SectionBreak
        label="4 · save · export · share"
        hint="markup is a computed doc · save persists it · export materializes a flat PNG/JPEG · share is why"
      />
      <SaveShareState />
      <SectionBreak
        label="5 · level up · intern viewer + speak strip v2"
        hint="the bottom band, leveled up — the intern accounts for its pass · the mic speaks in mag-tape"
      />
      <LevelUpState />
      <StudyFooter />
    </div>
  );
}

/**
 * Focused view of just the "5 · level up" exploration — the streaming
 * Work Thread (right rail) + Speak Strip v2. Exported so it gets its own
 * sidebar route instead of living at the foot of the full study.
 */
export function MacCaptureMarkupLevelUp() {
  return (
    <div style={{ width: 1180, background: T.page }} className="flex flex-col">
      <div style={{ padding: "20px 32px 6px 32px" }}>
        <div className="flex items-baseline gap-3">
          <span
            className="font-mono font-semibold uppercase tracking-[0.32em]"
            style={{ color: T.inkFaint, fontSize: 9 }}
          >
            · CAPTURE MARKUP · level up · the bottom band
          </span>
          <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 13 }}>
            stream what the agent's doing · log-style on the right · the mic speaks in mag-tape
          </span>
          <div className="ml-auto flex items-center gap-3">
            <Chip label="CONCEPT" tone="amber" />
            <span
              className="font-mono uppercase tracking-[0.18em]"
              style={{ color: T.inkFaint, fontSize: 10 }}
            >
              ports to · CaptureMarkupPanelChrome.swift
            </span>
          </div>
        </div>
        <h2
          className="font-display tracking-tight"
          style={{ color: T.ink, fontSize: 30, fontWeight: 500, lineHeight: 1, marginTop: 8 }}
        >
          Level up · Work Thread + Speak Strip
        </h2>
        <p
          className="font-display italic"
          style={{ color: T.inkFaint, fontSize: 13, lineHeight: 1.6, marginTop: 10, maxWidth: 820 }}
        >
          Hitting RUN used to say "RUNNING" and leave you staring. Now the
          right rail is a <em>Work Thread</em> — the agent's run streamed
          log-style, a line per step as each mark lands, with a live node
          at the head. And the composer is no longer a dead field: tap the
          mic and the prompt lane becomes a magnetic-tape waveform while
          you talk.
        </p>
      </div>
      <LevelUpState />
      <StudyFooter />
    </div>
  );
}

// ─── Header / breaks / footer ────────────────────────────────────────

function StudyHeader() {
  return (
    <div style={{ padding: "20px 32px 14px 32px" }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono font-semibold uppercase tracking-[0.32em]"
          style={{ color: T.inkFaint, fontSize: 9 }}
        >
          · CAPTURE MARKUP · tools above · talk below
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 13 }}>
          draw on top · talk at the bottom · select rides with the input
        </span>
        <div className="ml-auto flex items-center gap-3">
          <Chip label="CONCEPT" tone="ink" />
          <span
            className="font-mono uppercase tracking-[0.18em]"
            style={{ color: T.inkFaint, fontSize: 10 }}
          >
            replaces · CleanShot X delegate
          </span>
        </div>
      </div>
      <h2
        className="font-display tracking-tight"
        style={{ color: T.ink, fontSize: 30, fontWeight: 500, lineHeight: 1, marginTop: 8 }}
      >
        Markup
      </h2>
      <p
        className="font-display italic"
        style={{ color: T.inkFaint, fontSize: 13, lineHeight: 1.6, marginTop: 10, maxWidth: 780 }}
      >
        One surface, two states. Drawing tools sit in a toolbar at the
        top — where every editor puts them. Voice and typing share an
        input bar at the bottom — equal weight, conversational. Pick a
        layer and its chip slots into the input bar:{" "}
        <em>move down, recolor, rename to "API error."</em>
      </p>
    </div>
  );
}

function SectionBreak({ label, hint }: { label: string; hint: string }) {
  return (
    <div style={{ padding: "28px 32px 10px 32px" }}>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono font-semibold uppercase tracking-[0.30em]"
          style={{ color: T.amber, fontSize: 9 }}
        >
          {label}
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 12 }}>
          {hint}
        </span>
        <div className="ml-3 flex-1" style={{ height: 1, background: T.inkRuleS }} />
      </div>
    </div>
  );
}

function StudyFooter() {
  return (
    <div style={{ padding: "32px 32px 28px 32px" }}>
      <div style={{ height: 1, background: T.inkRuleS, marginBottom: 14 }} />
      <p
        className="font-display italic"
        style={{ color: T.inkFaint, fontSize: 13, lineHeight: 1.6 }}
      >
        Layers are a sidecar JSON next to the PNG. The capture itself is
        never re-encoded. If the agent gets it wrong, you say so, you
        draw over it, or you select the layer and speak the fix — you
        don't lose the original.
      </p>
    </div>
  );
}

// ─── State 1 · Ask ───────────────────────────────────────────────────
//
// Just-captured screenshot. Drawing toolbar on top, canvas in the
// middle, talk bar at the bottom. No selection chip — no layers yet.

function AskState() {
  return (
    <Surface>
      <MarkupWindow title="Markup · C-0017" subtitle="captured 2s ago">
        <ToolToolbar active={null} />
        <div
          className="flex items-center justify-center"
          style={{ background: T.rail, padding: "26px 26px" }}
        >
          <MockedScreenshotWithMarkup markup={false} />
        </div>
        <InputBar
          placeholder="tell the agent what to mark up…"
          examples={[
            "circle the error and label it",
            "draw a horizontal guide from the first word",
            "blur the email address",
            "arrow from the title to the failed line",
          ]}
          scopeBadge="global · whole image"
        />
        <CommitBar
          hint="nothing applied yet · accept unlocks after the agent runs"
          acceptDisabled
        />
      </MarkupWindow>
      <CaptionStrip
        text="Two input zones — drawing on top, talking on the bottom — each clear about its job. The toolbar holds primitives for hand-drawing; the bar at the foot is for voice or text. Run dispatches whatever you said or typed, against the whole image."
      />
    </Surface>
  );
}

// ─── State 1B · Ask · compact talk bar ───────────────────────────────
//
// Same two-band structure; tighter dimensions. Composer band drops from
// ~78pt (TRY row + 56pt composer + paddings) to ~58pt. Voice and Run
// buttons fill the composer height — no more amber pill floating in a
// taller container. Commit hint goes from a sentence to a status line.

function AskStateCompact() {
  return (
    <Surface>
      <MarkupWindow title="Markup · C-0017" subtitle="captured 2s ago · compact bar">
        <ToolToolbar active={null} />
        <div
          className="flex items-center justify-center"
          style={{ background: T.rail, padding: "26px 26px" }}
        >
          <MockedScreenshotWithMarkup markup={false} />
        </div>
        <CompactInputBar
          placeholder="tell the agent what to mark up…"
          examples={[
            "circle the error and label it",
            "draw a horizontal guide",
            "blur the email address",
            "arrow from title to failed line",
          ]}
          scopeBadge="global · whole image"
        />
        <CompactCommitBar hint="idle · accept after agent runs" acceptDisabled />
      </MarkupWindow>
      <CaptionStrip
        text="Composer band tightened (~40pt) so the voice pill and Run button fill the row instead of floating. The hint footer trades a full sentence ('nothing applied yet · accept unlocks after the agent runs') for a status line ('— idle · accept after agent runs'). Same affordances, less weight."
      />
    </Surface>
  );
}

function CompactInputBar({
  placeholder,
  selection,
  examples,
  scopeBadge,
}: {
  placeholder: string;
  selection?: { id: string; label: string; kind: string };
  examples?: string[];
  scopeBadge?: string;
}) {
  return (
    <div
      style={{
        background: T.chrome,
        borderTop: `0.5px solid ${T.inkRuleS}`,
        padding: "8px 12px 10px 12px",
      }}
    >
      {examples && examples.length > 0 && (
        <div className="flex items-center gap-2" style={{ flexWrap: "wrap", marginBottom: 6 }}>
          <span
            className="font-mono uppercase tracking-[0.20em]"
            style={{ fontSize: 9, color: T.inkFainter }}
          >
            · try
          </span>
          {examples.map((s) => (
            <span
              key={s}
              className="font-display italic"
              style={{
                fontSize: 10.5,
                color: T.inkFaint,
                padding: "2px 8px",
                border: `0.5px dashed ${T.inkRule}`,
                borderRadius: 999,
                background: T.pane,
              }}
            >
              {s}
            </span>
          ))}
          {scopeBadge && (
            <span
              className="ml-auto font-mono uppercase tracking-[0.18em]"
              style={{ fontSize: 9, color: T.inkFainter }}
            >
              {scopeBadge}
            </span>
          )}
        </div>
      )}

      <div
        className="flex items-stretch"
        style={{
          background: T.pane,
          border: `0.5px solid ${T.inkRule}`,
          borderRadius: 5,
          height: 40,
          boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset",
          overflow: "hidden",
        }}
      >
        <CompactVoiceButton />
        <Divider />
        <div className="flex items-center gap-2 flex-1 px-3">
          {selection && <SelectionChip selection={selection} />}
          <span
            className="font-display italic"
            style={{ fontSize: 12.5, color: T.inkFainter }}
          >
            {placeholder}
          </span>
          <span
            style={{
              display: "inline-block",
              width: 1,
              height: 13,
              background: T.amber,
              animation: "promptcaret 1s steps(2) infinite",
            }}
          />
        </div>
        <CompactRunButton />
      </div>
      <style jsx>{`
        @keyframes promptcaret {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0; }
        }
      `}</style>
    </div>
  );
}

function CompactVoiceButton() {
  return (
    <button
      className="flex items-center gap-1.5 px-2.5"
      style={{
        background: T.amberFaint,
        color: T.amberDeep,
      }}
      title="hold to speak"
    >
      <MicGlyph size={13} />
      <span
        className="font-mono font-semibold uppercase tracking-[0.18em]"
        style={{ fontSize: 9 }}
      >
        hold to speak
      </span>
    </button>
  );
}

function CompactRunButton() {
  return (
    <button
      className="flex items-center gap-1.5 px-3"
      style={{
        background: T.amber,
        color: "#fff",
      }}
    >
      <span
        className="font-mono font-semibold uppercase tracking-[0.20em]"
        style={{ fontSize: 9.5 }}
      >
        run
      </span>
      <span style={{ fontSize: 9.5 }}>⌘↵</span>
    </button>
  );
}

function CompactCommitBar({
  hint,
  acceptDisabled,
  accept,
}: {
  hint?: string;
  acceptDisabled?: boolean;
  accept?: "primary";
}) {
  return (
    <div
      className="flex items-center gap-3 px-3"
      style={{
        height: 26,
        background: T.chrome,
        borderTop: `0.5px solid ${T.inkRuleS}`,
      }}
    >
      {hint && (
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 8.5, color: T.inkFaint }}
        >
          — {hint}
        </span>
      )}
      <span className="flex-1" />
      <FootAction label="Cancel" tone={T.inkFaint} />
      <span className="mx-1 h-3 w-px" style={{ background: T.inkRule }} />
      <FootAction
        label="Accept"
        tone={acceptDisabled ? T.inkFainter : T.amber}
        primary={accept === "primary"}
        disabled={acceptDisabled}
      />
    </div>
  );
}

// ─── State 1C · Ask · speak strip + canvas verdict ───────────────────
//
// Iteration on 1B. Two structural moves:
//
//   1. The voice control collapses from a pill ("HOLD TO SPEAK") to a
//      narrow circular Mic. Frees horizontal space for the Prompt and
//      mirrors the dictation mic vocabulary used elsewhere in the app.
//
//   2. The Pass Verdict (accept / cancel) leaves the bottom strip and
//      pins to the canvas chrome itself, top-right. Verdicts belong
//      next to the visual change, not the command zone.
//
// The bottom band is now just the SPEAK STRIP — Mic · Prompt · Run.
// No commit footer. The verdict lives where the pass lives.
//
// (Names defined inline in the marginalia below.)

function AskStateNarrow() {
  return (
    <Surface>
      <MarkupWindow
        title="Markup · C-0017"
        subtitle="captured 2s ago · speak strip · pass verdict on canvas"
      >
        <ToolToolbar active={null} />
        <div
          className="relative flex items-center justify-center"
          style={{ background: T.rail, padding: "26px 26px" }}
        >
          <MockedScreenshotWithMarkup markup={false} />
          {/* Pass Verdict — pinned to canvas chrome. Idle until a pass
              exists, so accept/cancel both read disabled here. */}
          <PassVerdict status="idle" />
        </div>
        <SpeakStrip
          placeholder="what should we mark up?"
          examples={[
            "circle the error and label it",
            "draw a horizontal guide",
            "blur the email",
            "arrow title → failed line",
          ]}
          scopeBadge="global · whole image"
        />
      </MarkupWindow>
      <NamesMarginalia />
      <CaptionStrip
        text="The Mic is a narrow circle now — fast to recognize, cheap on horizontal space. The Prompt gets the room it earns. Accept/Cancel left the bottom strip; in this state nothing has run, so the verdict reads ‘no pass yet.’ Run it and the verdict goes live on the canvas, next to the markup it’s verdicting."
      />
    </Surface>
  );
}

function SpeakStrip({
  placeholder,
  selection,
  examples,
  scopeBadge,
}: {
  placeholder: string;
  selection?: { id: string; label: string; kind: string };
  examples?: string[];
  scopeBadge?: string;
}) {
  return (
    <div
      style={{
        background: T.chrome,
        borderTop: `0.5px solid ${T.inkRuleS}`,
        padding: "8px 14px 10px 14px",
      }}
    >
      {/* Examples row (above the strip proper) */}
      {examples && examples.length > 0 && (
        <div className="flex items-center gap-2" style={{ flexWrap: "wrap", marginBottom: 7 }}>
          <span
            className="font-mono uppercase tracking-[0.20em]"
            style={{ fontSize: 9, color: T.inkFainter }}
          >
            · try
          </span>
          {examples.map((s) => (
            <span
              key={s}
              className="font-display italic"
              style={{
                fontSize: 10.5,
                color: T.inkFaint,
                padding: "2px 8px",
                border: `0.5px dashed ${T.inkRule}`,
                borderRadius: 999,
                background: T.pane,
              }}
            >
              {s}
            </span>
          ))}
          {scopeBadge && !selection && (
            <span
              className="ml-auto font-mono uppercase tracking-[0.18em]"
              style={{ fontSize: 9, color: T.inkFainter }}
            >
              {scopeBadge}
            </span>
          )}
        </div>
      )}

      {/* Selection bar — same architectural slot as in InputBar. The
          chip is a scope signal, so it lives in its own row above the
          mic/prompt/run, not inside the prompt itself. */}
      {selection && <SelectionBar selection={selection} scopeBadge={scopeBadge} />}

      {/* Main row · Mic | Prompt | Run — three distinct elements */}
      <div className="flex items-center" style={{ gap: 10 }}>
        <NarrowMic />
        <div
          className="flex items-center gap-2 flex-1 px-3"
          style={{
            background: T.pane,
            border: `0.5px solid ${T.inkRule}`,
            borderRadius: 5,
            height: 34,
            boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset",
          }}
        >
          <span
            className="font-display italic"
            style={{ fontSize: 12.5, color: T.inkFainter }}
          >
            {placeholder}
          </span>
          <span
            style={{
              display: "inline-block",
              width: 1,
              height: 13,
              background: T.amber,
              animation: "promptcaret 1s steps(2) infinite",
            }}
          />
        </div>
        <CompactRunButton />
      </div>
      <style jsx>{`
        @keyframes promptcaret {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0; }
        }
      `}</style>
    </div>
  );
}

function NarrowMic() {
  return (
    <button
      className="flex items-center justify-center"
      style={{
        width: 32,
        height: 32,
        borderRadius: "50%",
        background: T.amberFaint,
        border: `0.5px solid ${T.amberSoft}`,
        color: T.amberDeep,
        flexShrink: 0,
        boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset",
      }}
      title="hold to speak"
      aria-label="hold to speak"
    >
      <MicGlyph size={14} />
    </button>
  );
}

function PassVerdict({ status }: { status: "idle" | "ready" }) {
  const ready = status === "ready";
  return (
    <div
      className="flex items-center gap-2"
      style={{
        position: "absolute",
        top: 12,
        right: 12,
        padding: "4px 4px 4px 10px",
        background: T.pane,
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 4,
        boxShadow: "0 2px 10px rgba(0,0,0,0.10)",
      }}
    >
      <span
        style={{
          display: "inline-block",
          width: 6,
          height: 6,
          borderRadius: 999,
          background: ready ? T.amber : T.inkFainter,
        }}
      />
      <span
        className="font-mono uppercase tracking-[0.18em]"
        style={{ fontSize: 9, color: T.inkFaint }}
      >
        {ready ? "pass ready" : "no pass yet"}
      </span>
      <span className="mx-0.5 h-3 w-px" style={{ background: T.inkRule }} />
      <VerdictAction label="Cancel" tone={T.inkFaint} disabled={!ready} />
      <VerdictAction
        label="Accept"
        tone={ready ? T.amber : T.inkFainter}
        primary={ready}
        disabled={!ready}
      />
    </div>
  );
}

function VerdictAction({
  label,
  tone,
  primary,
  disabled,
}: {
  label: string;
  tone: string;
  primary?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      className="font-mono font-semibold uppercase tracking-[0.20em]"
      disabled={disabled}
      style={{
        fontSize: 9,
        color: tone,
        opacity: disabled ? 0.55 : 1,
        padding: primary ? "4px 10px" : "4px 6px",
        background: primary ? T.amberFaint : "transparent",
        border: primary ? `0.5px solid ${T.amberSoft}` : "0.5px solid transparent",
        borderRadius: 3,
        cursor: disabled ? "not-allowed" : "pointer",
      }}
    >
      {label}
    </button>
  );
}

// Vocabulary. The studio is the canonical place to argue about names —
// every part below has one we mean to use in Swift, docs, and chat.

function NamesMarginalia() {
  const entries: [string, string][] = [
    ["Markup Window",  "the ephemeral panel hosting the canvas + tools + strip"],
    ["Tool Toolbar",   "top band · manual drawing primitives"],
    ["Canvas",         "the screenshot area, where Passes are applied"],
    ["Pass",           "one agent run, recorded as layers in the sidecar JSON"],
    ["Pass Verdict",   "accept / cancel cluster pinned to the canvas, top-right"],
    ["Speak Strip",    "bottom band · Mic + Prompt + Run"],
    ["Mic",            "narrow circular hold-to-speak control"],
    ["Prompt",         "text input · ⌘↵ runs"],
    ["Run",            "dispatch the prompt as the next Pass"],
    ["Examples",       "context-adaptive try-this chips above the strip"],
    ["Scope Badge",    "global · selected layer · region — what Run targets"],
    ["Selection Chip", "the layer-scope token that rides inside the Prompt"],
  ];
  return (
    <div
      style={{
        marginTop: 14,
        padding: "12px 16px",
        background: T.pane,
        border: `0.5px solid ${T.inkRuleS}`,
        borderRadius: 4,
      }}
    >
      <div
        className="flex items-baseline gap-3"
        style={{ marginBottom: 10 }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.24em]"
          style={{ fontSize: 9, color: T.amberDeep }}
        >
          · names · marginalia
        </span>
        <span
          className="font-display italic"
          style={{ fontSize: 11, color: T.inkFaint }}
        >
          what we call each part — same words in studio, Swift, and chat
        </span>
      </div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "150px 1fr",
          rowGap: 4,
          columnGap: 18,
        }}
      >
        {entries.map(([name, def]) => (
          <React.Fragment key={name}>
            <span
              className="font-mono font-semibold uppercase tracking-[0.16em]"
              style={{ fontSize: 10, color: T.amberDeep }}
            >
              {name}
            </span>
            <span
              className="font-display italic"
              style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.45 }}
            >
              {def}
            </span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

// ─── State 2 · Touch up ──────────────────────────────────────────────
//
// Agent applied markup. The image now carries lines, guides, drawings,
// and text. The composer is the same shape — tools, voice, text — but
// now carries a selection chip ("↳ ERROR · L2") when the user picks a
// layer. Speaking with a layer selected scopes the request to it:
// "move down 10 px", "make it red", "rename to API error", "delete."

function TouchUpState() {
  return (
    <Surface>
      <MarkupWindow title="Markup · C-0017" subtitle="4 layers · ran 1.4s ago">
        <ToolToolbar active="line" />
        <div className="flex" style={{ background: T.pane }}>
          <div
            className="flex-1 flex items-center justify-center"
            style={{ background: T.rail, padding: 22 }}
          >
            <MockedScreenshotWithMarkup selectedIndex={1} />
          </div>
          <LayersColumn selectedIndex={1} />
        </div>
        <InputBar
          placeholder="modify this layer · or speak another pass…"
          selection={{ id: "L2", label: "build failed line", kind: "rect" }}
          examples={[
            "move down 6 px",
            "make the ring red",
            "rename to 'API error'",
            "delete",
            "+ another pass · also blur the address",
          ]}
          scopeBadge="scoped · L2 selected"
        />
        <CommitBar
          hint="⌘Z undo · ⌘⇧Z redo · ⌘N another pass"
          accept="primary"
        />
      </MarkupWindow>
      <CaptionStrip
        text="Tools stay on top — Line is highlighted because the user pulled it out a moment ago to draw a connector. The selected layer (L2, the ellipse around the build-failed line) rides as a chip in the input bar at the foot. Speak or type — the placeholder shifted to layer-scoped suggestions. Run dispatches to the selected layer; with nothing selected, Run goes to the whole image."
      />
      <TouchUpDetail />
    </Surface>
  );
}

// ─── Layers column (touch-up secondary) ──────────────────────────────
//
// Tools moved out of here into the composer. This column is now just
// the layer list and a sidecar pointer. Click-to-select fires the
// selection chip into the composer.

function LayersColumn({ selectedIndex }: { selectedIndex?: number }) {
  return (
    <div
      style={{
        width: 232,
        borderLeft: `0.5px solid ${T.inkRuleS}`,
        background: T.page,
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div
        className="flex items-center gap-2 px-3"
        style={{
          height: 26,
          borderBottom: `0.5px solid ${T.inkRuleS}`,
          background: T.chrome,
        }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.22em]"
          style={{ fontSize: 8.5, color: T.inkFaint }}
        >
          · LAYERS
        </span>
        <span className="ml-auto font-mono uppercase tracking-[0.18em]" style={{ fontSize: 8.5, color: T.inkFainter }}>
          {LAYERS.length}
        </span>
      </div>
      {LAYERS.map((l, i) => (
        <LayerRow key={i} layer={l} selected={i === selectedIndex} />
      ))}
      <div className="mt-auto px-3 py-2" style={{ borderTop: `0.5px solid ${T.inkRuleS}` }}>
        <div
          className="font-mono uppercase tracking-[0.20em]"
          style={{ fontSize: 8, color: T.inkFaint, marginBottom: 4 }}
        >
          · sidecar
        </div>
        <div className="font-mono" style={{ fontSize: 9, color: T.inkMid }}>
          C-0017.markup.json
        </div>
        <div
          className="font-display italic"
          style={{ fontSize: 10.5, color: T.inkFaint, marginTop: 4, lineHeight: 1.4 }}
        >
          Selection drives the composer chip.
        </div>
      </div>
    </div>
  );
}

// ─── Drawing toolbar (top of the window) ─────────────────────────────
//
// Manual primitives — the things you can draw without the agent. Sits
// directly under the window chrome so it reads as the toolbar for the
// canvas below. Active tool gets the amber treatment.

type ToolId = "rect" | "arrow" | "line" | "text" | "blur";

const TOOLS: { id: ToolId; glyph: string; label: string }[] = [
  { id: "rect",  glyph: "▢", label: "Rect"  },
  { id: "arrow", glyph: "↗", label: "Arrow" },
  { id: "line",  glyph: "—", label: "Line"  },
  { id: "text",  glyph: "T", label: "Text"  },
  { id: "blur",  glyph: "▒", label: "Blur"  },
];

function ToolToolbar({ active }: { active: ToolId | null }) {
  return (
    <div
      className="flex items-center px-2"
      style={{
        height: 40,
        background: T.chrome,
        borderBottom: `0.5px solid ${T.inkRuleS}`,
        gap: 4,
      }}
    >
      {TOOLS.map((t) => {
        const on = t.id === active;
        return (
          <button
            key={t.id}
            title={t.label}
            className="flex items-center gap-1.5 px-2.5"
            style={{
              height: 28,
              color: on ? T.amberDeep : T.inkFaint,
              background: on ? T.amberFaint : "transparent",
              border: on ? `0.5px solid ${T.amberSoft}` : "0.5px solid transparent",
              borderRadius: 3,
            }}
          >
            <span className="font-mono" style={{ fontSize: 13, lineHeight: 1 }}>
              {t.glyph}
            </span>
            <span
              className="font-mono uppercase tracking-[0.16em]"
              style={{ fontSize: 9, lineHeight: 1 }}
            >
              {t.label}
            </span>
          </button>
        );
      })}
      <span className="flex-1" />
      <span
        className="font-mono uppercase tracking-[0.18em]"
        style={{ fontSize: 9, color: T.inkFainter }}
      >
        · M to toggle · V to select
      </span>
    </div>
  );
}

// ─── Talk bar (bottom of the window) ─────────────────────────────────
//
// Voice and text, equal weight, with the selection chip riding next
// to the text so "select and speak" is a single gesture. Above the
// row, an examples ghost strip — context-adaptive suggestions. Scope
// badge on the right tells you whether Run targets the whole image
// or just the selected layer.

function InputBar({
  placeholder,
  selection,
  examples,
  scopeBadge,
}: {
  placeholder: string;
  selection?: { id: string; label: string; kind: string };
  examples?: string[];
  scopeBadge?: string;
}) {
  return (
    <div
      style={{
        background: T.chrome,
        borderTop: `0.5px solid ${T.inkRuleS}`,
        padding: "12px 14px 14px 14px",
      }}
    >
      {/* Examples row */}
      {examples && examples.length > 0 && (
        <div className="flex items-center gap-2" style={{ flexWrap: "wrap", marginBottom: 8 }}>
          <span
            className="font-mono uppercase tracking-[0.20em]"
            style={{ fontSize: 9, color: T.inkFainter }}
          >
            · try
          </span>
          {examples.map((s) => (
            <span
              key={s}
              className="font-display italic"
              style={{
                fontSize: 11,
                color: T.inkFaint,
                padding: "3px 9px",
                border: `0.5px dashed ${T.inkRule}`,
                borderRadius: 999,
                background: T.pane,
              }}
            >
              {s}
            </span>
          ))}
          {scopeBadge && !selection && (
            <span
              className="ml-auto font-mono uppercase tracking-[0.18em]"
              style={{ fontSize: 9, color: T.inkFainter }}
            >
              {scopeBadge}
            </span>
          )}
        </div>
      )}

      {/* Selection bar — separate row above the composer when a layer
          is selected. Was embedded inside the composer (rode next to
          the prompt text) which read as disruptive. Pulling it up
          gives it the same architectural weight as the Examples row:
          a context strip, not a content fragment. */}
      {selection && <SelectionBar selection={selection} scopeBadge={scopeBadge} />}

      {/* Main row · voice | text | run · selection lives elsewhere now */}
      <div
        className="flex items-stretch"
        style={{
          background: T.pane,
          border: `0.5px solid ${T.inkRule}`,
          borderRadius: 6,
          minHeight: 56,
          boxShadow:
            "0 1px 0 rgba(255,255,255,0.55) inset, 0 4px 12px -2px rgba(0,0,0,0.05)",
          overflow: "hidden",
        }}
      >
        <VoiceButton />
        <Divider />
        <div className="flex items-center gap-2 flex-1 px-3">
          <span
            className="font-display italic"
            style={{ fontSize: 13, color: T.inkFainter }}
          >
            {placeholder}
          </span>
          <span
            style={{
              display: "inline-block",
              width: 1,
              height: 14,
              background: T.amber,
              animation: "promptcaret 1s steps(2) infinite",
            }}
          />
        </div>
        <RunButton />
      </div>
      <style jsx>{`
        @keyframes promptcaret {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0; }
        }
      `}</style>
    </div>
  );
}

// SelectionBar — context strip that lifts the selected-layer chip out
// of the composer and parks it directly above. Reads as "this is what
// you're acting on" without disrupting the clean composer row.
//
// Readability note: earlier draft used amberDeep text on amberFaint
// fill (~8% amber). The deep-on-pale-amber pairing washed out — too
// little contrast against amber-tinted ink. This revision flips the
// model: neutral pane background, ink text for the layer name (high
// contrast), amber reserved for the leading accent stripe + ID badge
// (the "scope indicator" semaphore). Amber stays sparse so it still
// reads as accent, not a fill.
function SelectionBar({
  selection,
  scopeBadge,
}: {
  selection: { id: string; label: string; kind: string };
  scopeBadge?: string;
}) {
  return (
    <div
      className="flex items-stretch"
      style={{
        marginBottom: 8,
        background: T.pane,
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 4,
        overflow: "hidden",
      }}
    >
      {/* Leading amber accent — the "scope active" semaphore. Thin
          stripe is enough; doesn't need to fill the row. */}
      <span style={{ width: 3, background: T.amber }} />

      <div className="flex items-center gap-2 flex-1" style={{ padding: "6px 10px" }}>
        <span
          className="font-mono uppercase tracking-[0.22em]"
          style={{ fontSize: 9, color: T.inkFainter }}
        >
          · scope
        </span>
        <span
          className="font-mono font-semibold uppercase tracking-[0.18em]"
          style={{
            fontSize: 9,
            color: T.amberDeep,
            padding: "2px 5px",
            background: T.amberFaint,
            border: `0.5px solid ${T.amberSoft}`,
            borderRadius: 2,
          }}
        >
          {selection.id}
        </span>
        <span
          className="font-display"
          style={{ fontSize: 12, color: T.ink, fontWeight: 500 }}
        >
          {selection.label}
        </span>
        <button
          title="Clear selection"
          aria-label="Clear selection"
          className="ml-1 flex items-center justify-center"
          style={{
            width: 16,
            height: 16,
            borderRadius: 999,
            background: "transparent",
            color: T.inkFaint,
            fontSize: 11,
            lineHeight: 1,
          }}
        >
          ×
        </button>
        {scopeBadge && (
          <span
            className="ml-auto font-mono uppercase tracking-[0.18em]"
            style={{ fontSize: 9, color: T.inkFainter }}
          >
            {scopeBadge}
          </span>
        )}
      </div>
    </div>
  );
}

// MicGlyph — small editorial mic SVG. Uses currentColor so it inherits
// from the parent button's text color (amberDeep on the speak strip,
// could swap to ink for a quieter context). Replaces the music note
// (♪) that was reading as audio playback rather than capture.
function MicGlyph({ size = 14 }: { size?: number }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={size}
      height={size}
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.4}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      {/* Capsule */}
      <rect x="6" y="2" width="4" height="7.5" rx="2" />
      {/* Yoke */}
      <path d="M3.5 8 A 4.5 4.5 0 0 0 12.5 8" />
      {/* Stand */}
      <line x1="8" y1="12.5" x2="8" y2="14" />
      <line x1="5.5" y1="14" x2="10.5" y2="14" />
    </svg>
  );
}

function Divider() {
  return <div style={{ width: 1, background: T.inkRuleS }} />;
}

function VoiceButton() {
  return (
    <button
      className="flex items-center gap-2 px-3"
      style={{
        background: T.amberFaint,
        color: T.amberDeep,
      }}
      title="hold to speak"
    >
      <MicGlyph size={15} />
      <span
        className="font-mono font-semibold uppercase tracking-[0.18em]"
        style={{ fontSize: 9.5 }}
      >
        hold to speak
      </span>
    </button>
  );
}

function SelectionChip({
  selection,
}: {
  selection: { id: string; label: string; kind: string };
}) {
  return (
    <span
      className="flex items-center gap-1.5"
      style={{
        height: 24,
        padding: "0 8px",
        background: T.amberFaint,
        border: `0.5px solid ${T.amberSoft}`,
        borderRadius: 3,
        color: T.amberDeep,
      }}
      title={`Selected layer · ${selection.label}`}
    >
      <span className="font-mono" style={{ fontSize: 10, lineHeight: 1 }}>↳</span>
      <span
        className="font-mono font-semibold uppercase tracking-[0.18em]"
        style={{ fontSize: 9 }}
      >
        {selection.id}
      </span>
      <span
        className="font-display italic"
        style={{ fontSize: 11, color: T.amberDeep, opacity: 0.85 }}
      >
        {selection.label}
      </span>
      <span style={{ fontSize: 10, opacity: 0.6, marginLeft: 2 }}>×</span>
    </span>
  );
}

function RunButton() {
  return (
    <button
      className="flex items-center gap-2 px-4"
      style={{
        background: T.amber,
        color: "#fff",
      }}
    >
      <span
        className="font-mono font-semibold uppercase tracking-[0.20em]"
        style={{ fontSize: 10 }}
      >
        run
      </span>
      <span style={{ fontSize: 10 }}>⌘↵</span>
    </button>
  );
}

function CommitBar({
  hint,
  acceptDisabled,
  accept,
}: {
  hint?: string;
  acceptDisabled?: boolean;
  accept?: "primary";
}) {
  return (
    <div
      className="flex items-center gap-3 px-4"
      style={{
        height: 34,
        background: T.chrome,
        borderTop: `0.5px solid ${T.inkRuleS}`,
      }}
    >
      {hint && (
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: T.inkFaint }}
        >
          · {hint}
        </span>
      )}
      <span className="flex-1" />
      <FootAction label="Cancel" tone={T.inkFaint} />
      <span className="mx-1 h-3 w-px" style={{ background: T.inkRule }} />
      <FootAction
        label="Accept"
        tone={acceptDisabled ? T.inkFainter : T.amber}
        primary={accept === "primary"}
        disabled={acceptDisabled}
      />
    </div>
  );
}

// ─── Touch-up detail (layer popover + select-and-speak vignette) ─────

function TouchUpDetail() {
  return (
    <div className="flex gap-4" style={{ marginTop: 14 }}>
      <DetailTile
        eyebrow="select and speak"
        title="The composer scopes to your selection"
        caption="Click a layer → its chip slots into the composer. Now voice and text apply to it. Same row, same Run button — what changes is the verb."
      >
        <SelectAndSpeakDemo />
      </DetailTile>
      <DetailTile
        eyebrow="layer popover"
        title="Or nudge / re-label / delete in place"
        caption="Hover-anchored popover for the keyboard-and-arrow path. Same actions the composer can dispatch by voice — different ergonomics for different moments."
      >
        <LayerPopoverDemo />
      </DetailTile>
    </div>
  );
}

function DetailTile({
  eyebrow,
  title,
  caption,
  children,
}: {
  eyebrow: string;
  title: string;
  caption: string;
  children: React.ReactNode;
}) {
  return (
    <div style={{ flex: "1 1 0%" }}>
      <PaneHeader title={eyebrow} sub="touch-up" />
      <div
        style={{
          background: T.pane,
          border: `1px solid ${T.inkRuleS}`,
          borderRadius: 4,
          padding: 16,
          minHeight: 196,
          display: "flex",
          flexDirection: "column",
          gap: 12,
        }}
      >
        <div
          className="font-display tracking-tight"
          style={{ color: T.ink, fontSize: 15, fontWeight: 500, lineHeight: 1.2 }}
        >
          {title}
        </div>
        {children}
        <p
          className="font-display italic"
          style={{ color: T.inkFaint, fontSize: 12, lineHeight: 1.5, marginTop: "auto" }}
        >
          {caption}
        </p>
      </div>
    </div>
  );
}

// A compact recreation of the composer with selection + dictation in
// progress, to make the "select and speak" loop self-evident.
function SelectAndSpeakDemo() {
  return (
    <div
      className="flex items-stretch"
      style={{
        background: T.pane,
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 4,
        minHeight: 44,
        overflow: "hidden",
      }}
    >
      <div
        className="flex items-center gap-1.5 px-2.5"
        style={{
          background: T.amberFaint,
          color: T.amberDeep,
          borderRight: `0.5px solid ${T.inkRule}`,
        }}
      >
        <span
          aria-hidden
          className="inline-block rounded-full"
          style={{
            width: 7,
            height: 7,
            background: T.amber,
            boxShadow: "0 0 7px rgba(196,125,28,0.65)",
            animation: "ssspulse 1.3s ease-in-out infinite",
          }}
        />
        <span className="font-mono font-semibold uppercase tracking-[0.18em]" style={{ fontSize: 9 }}>
          listening
        </span>
      </div>
      <div className="flex items-center gap-2 flex-1 px-3">
        <span
          className="flex items-center gap-1.5"
          style={{
            height: 22,
            padding: "0 7px",
            background: T.amberFaint,
            border: `0.5px solid ${T.amberSoft}`,
            borderRadius: 3,
            color: T.amberDeep,
          }}
        >
          <span className="font-mono" style={{ fontSize: 10 }}>↳</span>
          <span
            className="font-mono font-semibold uppercase tracking-[0.18em]"
            style={{ fontSize: 9 }}
          >
            L2
          </span>
          <span
            className="font-display italic"
            style={{ fontSize: 11, opacity: 0.85 }}
          >
            build failed line
          </span>
        </span>
        <span
          className="font-display italic"
          style={{ fontSize: 12, color: T.ink }}
        >
          move it down a touch and rename to “API error”…
        </span>
      </div>
      <style jsx>{`
        @keyframes ssspulse {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0.4; }
        }
      `}</style>
    </div>
  );
}

function LayerPopoverDemo() {
  return (
    <div
      className="relative"
      style={{
        height: 96,
        background: T.rail,
        borderRadius: 3,
        border: `0.5px solid ${T.inkRuleS}`,
        overflow: "hidden",
      }}
    >
      <div
        className="absolute"
        style={{
          left: 28,
          top: 28,
          width: 116,
          height: 38,
          border: `1.5px solid ${MARKUP.ringAlert}`,
          background: MARKUP.fillAlert,
          borderRadius: 2,
        }}
      />
      <div
        className="absolute font-mono"
        style={{
          left: 28,
          top: 12,
          fontSize: 9,
          padding: "2px 5px",
          background: MARKUP.labelBg,
          color: MARKUP.labelInk,
          letterSpacing: "0.08em",
          borderRadius: 2,
        }}
      >
        ERROR
      </div>
      <div
        className="absolute flex items-center gap-1.5 px-2"
        style={{
          left: 158,
          top: 34,
          height: 26,
          background: T.pane,
          border: `0.5px solid ${T.inkRule}`,
          borderRadius: 4,
          boxShadow: "0 4px 10px rgba(0,0,0,0.08)",
        }}
      >
        <PopoverGlyph label="←" />
        <PopoverGlyph label="↑" />
        <PopoverGlyph label="↓" />
        <PopoverGlyph label="→" />
        <span className="mx-0.5 h-3 w-px" style={{ background: T.inkRule }} />
        <PopoverGlyph label="A" tone="ink" />
        <span className="mx-0.5 h-3 w-px" style={{ background: T.inkRule }} />
        <PopoverGlyph label="⌫" tone="alert" />
      </div>
    </div>
  );
}

function PopoverGlyph({ label, tone = "faint" }: { label: string; tone?: "faint" | "ink" | "alert" }) {
  const color = tone === "alert" ? T.alert : tone === "ink" ? T.ink : T.inkFaint;
  return (
    <span className="font-mono" style={{ fontSize: 10, color, lineHeight: 1 }}>
      {label}
    </span>
  );
}

// ─── Shared window shell ─────────────────────────────────────────────

function MarkupWindow({
  title,
  subtitle,
  titleRight,
  children,
}: {
  title: string;
  subtitle?: string;
  titleRight?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div
      className="relative overflow-hidden"
      style={{
        background: T.page,
        borderRadius: 10,
        border: `0.5px solid ${T.edge}`,
        boxShadow:
          "0 1px 0 rgba(255,255,255,0.6) inset, 0 -1px 0 rgba(0,0,0,0.06) inset, 0 18px 44px -8px rgba(0,0,0,0.14), 0 4px 14px -2px rgba(0,0,0,0.08)",
      }}
    >
      <div
        className="relative flex items-center gap-2 px-3"
        style={{
          height: 32,
          background: T.chrome,
          borderBottom: `0.5px solid ${T.inkRuleS}`,
          // Document-action menus (Share) drop out of the title bar over the
          // canvas, so the bar can't clip its own overflow.
          zIndex: 5,
        }}
      >
        <span className="flex items-center gap-1.5">
          <span className="block rounded-full" style={{ width: 9, height: 9, background: "#FF5F57" }} />
          <span className="block rounded-full" style={{ width: 9, height: 9, background: "#FEBC2E" }} />
          <span className="block rounded-full" style={{ width: 9, height: 9, background: "#28C840" }} />
        </span>
        <span
          className="ml-3 font-mono font-semibold uppercase tracking-[0.20em]"
          style={{ fontSize: 9.5, color: T.ink }}
        >
          {title}
        </span>
        <span className="flex-1" />
        {subtitle && (
          <span
            className="font-mono uppercase tracking-[0.18em]"
            style={{ fontSize: 9, color: T.inkFaint }}
          >
            {subtitle}
          </span>
        )}
        {titleRight}
      </div>
      {children}
    </div>
  );
}

// ─── Mocked UI screenshot with optional markup overlays ──────────────

function MockedScreenshotWithMarkup({
  markup = true,
  selectedIndex,
}: {
  markup?: boolean;
  selectedIndex?: number;
}) {
  const w = 760;
  const h = 432;

  return (
    <div
      className="relative"
      style={{
        width: w,
        height: h,
        background: T.page,
        borderRadius: 4,
        border: `0.5px solid ${T.inkRule}`,
        boxShadow: "0 6px 18px rgba(0,0,0,0.08)",
        overflow: "hidden",
      }}
    >
      <div
        className="flex items-center gap-1.5 px-3"
        style={{
          height: 24,
          background: T.chrome,
          borderBottom: `0.5px solid ${T.inkRuleS}`,
        }}
      >
        <span className="block rounded-full" style={{ width: 8, height: 8, background: "#FF5F57" }} />
        <span className="block rounded-full" style={{ width: 8, height: 8, background: "#FEBC2E" }} />
        <span className="block rounded-full" style={{ width: 8, height: 8, background: "#28C840" }} />
        <span
          className="ml-auto font-mono"
          style={{ fontSize: 10, color: T.inkFaint, letterSpacing: "0.06em" }}
        >
          Talkie · Build Log
        </span>
      </div>
      <div style={{ position: "relative", padding: 20 }}>
        <div
          className="font-display tracking-tight"
          style={{ fontSize: 20, fontWeight: 500, color: T.ink, marginBottom: 12 }}
        >
          q1-plan.md · revisions
        </div>
        {[
          { w: 0.92, t: T.inkMid },
          { w: 0.76, t: T.inkMid },
          { w: 0.88, t: T.inkMid },
          { w: 0.58, t: T.inkMid },
          { w: 0.84, t: T.inkMid },
          { w: 1.0,  t: T.alert,    label: "Build failed: missing entitlement" },
          { w: 0.52, t: T.inkFaint, label: "contact: jane@usetalkie.com" },
          { w: 0.74, t: T.inkFaint },
        ].map((row, i) => (
          <div
            key={i}
            className="flex items-center"
            style={{ height: 14, marginBottom: 8 }}
          >
            {row.label ? (
              <span
                className="font-mono"
                style={{ fontSize: 10.5, color: row.t, letterSpacing: "0.04em" }}
              >
                {row.label}
              </span>
            ) : (
              <span
                className="block rounded-full"
                style={{
                  height: 6,
                  width: `${row.w * 100}%`,
                  maxWidth: `${row.w * 100}%`,
                  background: `color-mix(in srgb, ${row.t} 22%, transparent)`,
                }}
              />
            )}
          </div>
        ))}
      </div>

      {markup && <MarkupOverlays w={w} selectedIndex={selectedIndex} />}
    </div>
  );
}

// Layout math factored out so the overlays line up with the rows above.
// Row block starts at: padding-top (20) + title fontSize (20) + title
// margin-bottom (12) = 52, offset by chrome (24). Each row is 14 + 8.
function MarkupOverlays({ w, selectedIndex }: { w: number; selectedIndex?: number }) {
  const rowsTop = 24 + 20 + 20 + 12;
  const stride = 14 + 8;
  const buildFailedY = rowsTop + stride * 5;
  const emailY       = rowsTop + stride * 6;
  const titleY       = 24 + 20 + 10;

  // L1 guide is index 0; L2 ellipse is index 1; L3 label is index 2;
  // L4 arrow is index 3; L5 blur is index 4. selectedIndex tags the
  // ellipse selection (the same target shown in the composer chip).
  const sel = (i: number) => i === selectedIndex;

  return (
    <>
      {/* L1 · Horizontal guide */}
      <div
        className="absolute pointer-events-none"
        style={{
          left: 20,
          top: titleY + 18,
          width: w - 40,
          height: 0,
          borderTop: `1px dashed ${MARKUP.guide}`,
          opacity: 0.85,
        }}
      />

      {/* L2 · Ellipse around the "Build failed" line */}
      <div
        className="absolute pointer-events-none"
        style={{
          left: 14,
          top: buildFailedY - 4,
          width: w - 28,
          height: 22,
          border: `${sel(1) ? 2 : 1.5}px solid ${MARKUP.ringAlert}`,
          background: MARKUP.fillAlert,
          borderRadius: 999,
          boxShadow: sel(1) ? `0 0 0 3px rgba(196,125,28,0.30)` : "none",
        }}
      />

      {/* L3 · Label "ERROR" above the ellipse */}
      <div
        className="absolute pointer-events-none font-mono"
        style={{
          left: 14,
          top: buildFailedY - 22,
          fontSize: 9,
          padding: "2px 5px",
          background: MARKUP.labelBg,
          color: MARKUP.labelInk,
          letterSpacing: "0.10em",
          borderRadius: 2,
          textTransform: "uppercase",
          fontWeight: 700,
        }}
      >
        Error · L2
      </div>

      {/* L5 · Blur strip over the email address */}
      <div
        className="absolute pointer-events-none"
        style={{
          left: 18,
          top: emailY - 2,
          width: 260,
          height: 16,
          background: "rgba(20,24,30,0.08)",
          backdropFilter: "blur(4px)",
          WebkitBackdropFilter: "blur(4px)",
          border: `0.5px dashed ${MARKUP.ringInk}`,
          borderRadius: 2,
        }}
      />

      {/* L4 · Arrow from title to error */}
      <svg
        className="pointer-events-none absolute"
        style={{ left: 0, top: 0, width: w, height: 432 }}
      >
        <defs>
          <marker
            id="mu-arrow"
            markerWidth={8}
            markerHeight={8}
            refX={6}
            refY={3}
            orient="auto"
            markerUnits="strokeWidth"
          >
            <path d="M0,0 L0,6 L6,3 z" fill={MARKUP.ringAmber} />
          </marker>
        </defs>
        <path
          d={`M 36 ${titleY + 26} Q 56 ${(titleY + buildFailedY) / 2}, 42 ${buildFailedY - 2}`}
          stroke={MARKUP.ringAmber}
          strokeWidth={1.6}
          fill="none"
          markerEnd="url(#mu-arrow)"
        />
      </svg>

      {/* Selection callout — small chip next to the selected layer */}
      {selectedIndex === 1 && (
        <div
          className="absolute pointer-events-none font-mono font-semibold uppercase tracking-[0.18em]"
          style={{
            left: w - 84,
            top: buildFailedY - 22,
            fontSize: 8.5,
            padding: "2px 6px",
            background: T.amberFaint,
            color: T.amberDeep,
            border: `0.5px solid ${T.amberSoft}`,
            borderRadius: 2,
          }}
        >
          selected
        </div>
      )}
    </>
  );
}

// ─── Layers data + row ───────────────────────────────────────────────

const LAYERS: { kind: "guide" | "rect" | "arrow" | "label" | "blur"; label: string; agent: boolean }[] = [
  { kind: "guide", label: "horizontal · first word", agent: true  },
  { kind: "rect",  label: "build failed line",       agent: true  },
  { kind: "label", label: "ERROR",                   agent: true  },
  { kind: "arrow", label: "title → error",           agent: true  },
  { kind: "blur",  label: "email · row 6",           agent: false },
];

function LayerRow({
  layer,
  selected,
}: {
  layer: typeof LAYERS[number];
  selected?: boolean;
}) {
  const glyph: Record<typeof layer["kind"], string> = {
    guide: "—",
    rect:  "○",
    arrow: "↗",
    label: "T",
    blur:  "▒",
  };
  return (
    <div
      className="flex items-center gap-2 px-3"
      style={{
        height: 26,
        borderBottom: `0.5px solid ${T.inkRuleS}`,
        background: selected ? T.amberFaint : "transparent",
        borderLeft: selected ? `2px solid ${T.amber}` : "2px solid transparent",
      }}
    >
      <span className="font-mono" style={{ fontSize: 9, color: T.inkFainter, width: 10 }}>
        ◉
      </span>
      <span
        className="font-mono"
        style={{
          fontSize: 11,
          color:
            layer.kind === "rect"  ? T.alert :
            layer.kind === "arrow" ? T.amber :
            layer.kind === "blur"  ? T.inkMid :
            T.ink,
          width: 12,
          textAlign: "center",
        }}
      >
        {glyph[layer.kind]}
      </span>
      <span className="truncate" style={{ fontSize: 10.5, color: T.ink }}>
        {layer.label}
      </span>
      {layer.agent && (
        <span
          className="ml-auto inline-block rounded-full"
          style={{ width: 4, height: 4, background: T.amber }}
          aria-label="agent-authored"
        />
      )}
    </div>
  );
}

// ─── Bits ─────────────────────────────────────────────────────────────

function Surface({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ padding: "8px 32px 4px 32px" }}>
      {children}
    </div>
  );
}

function PaneHeader({ title, sub }: { title: string; sub?: string }) {
  return (
    <div className="flex items-baseline justify-between" style={{ marginBottom: 8 }}>
      <span
        className="font-mono font-semibold uppercase tracking-[0.24em]"
        style={{ color: T.inkFaint, fontSize: 9 }}
      >
        · {title}
      </span>
      {sub && (
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ color: T.inkFainter, fontSize: 9 }}
        >
          {sub}
        </span>
      )}
    </div>
  );
}

function Chip({ label, tone }: { label: string; tone: "amber" | "ink" }) {
  const isAmber = tone === "amber";
  return (
    <span
      className="font-mono uppercase tracking-[0.22em]"
      style={{
        fontSize: 9,
        fontWeight: 600,
        color: isAmber ? T.amber : T.inkFaint,
        border: `1px solid ${isAmber ? T.amber : T.inkRule}`,
        padding: "3px 8px",
        borderRadius: 2,
        background: isAmber ? T.amberFaint : "transparent",
      }}
    >
      {label}
    </span>
  );
}

function FootAction({
  label,
  tone,
  primary,
  disabled,
}: {
  label: string;
  tone: string;
  primary?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      className="font-mono font-semibold uppercase tracking-[0.20em]"
      disabled={disabled}
      style={{
        fontSize: 9.5,
        color: tone,
        opacity: disabled ? 0.55 : 1,
        padding: primary ? "5px 12px" : "5px 8px",
        background: primary ? T.amberFaint : "transparent",
        border: primary ? `0.5px solid ${T.amberSoft}` : "0.5px solid transparent",
        borderRadius: 3,
        cursor: disabled ? "not-allowed" : "pointer",
      }}
    >
      {label}
    </button>
  );
}

function CaptionStrip({ text }: { text: string }) {
  return (
    <p
      className="font-display italic"
      style={{ color: T.inkFaint, fontSize: 12, lineHeight: 1.55, marginTop: 12 }}
    >
      {text}
    </p>
  );
}

// ─── State 3 · Toolbar redesign · style stack + canvas tools ─────────
//
// The Swift markup window today crams *everything* into the top bar —
// tools, zoom, undo/redo, mode toggles, ESC CANCEL. That mixes three
// distinct purposes (drawing · viewport · dismiss) into one cluster.
//
// Redesign separates them:
//   · Top bar (LEFT)   — tool selection: rect / arrow / line / text / blur.
//   · Top bar (RIGHT)  — STYLE STACK · contextual to the current tool
//                        or selected layer. Stroke width, color, texture,
//                        fill for shapes; font size + color for text.
//                        Doubles as per-tool defaults — set them once,
//                        next shape inherits.
//   · Canvas (BOTTOM-RIGHT) — floating CANVAS ZOOM CLUSTER: − / + / FIT,
//                        modeled after the Hudson canvas pattern.
//                        Lives over the canvas, not in the toolbar.
//   · ESC CANCEL — gone. ⎋ still dismisses; the binding doesn't need a
//                  chip parked next to drawing tools that read as modes.

function ToolbarRedesignState() {
  return (
    <Surface>
      <MarkupWindow
        title="Markup · C-0017"
        subtitle="redesign · rect selected · style stack + floating zoom"
      >
        <ToolToolbarV2 active="rect" selection={{ kind: "rect" }} />
        <div
          className="relative flex items-center justify-center"
          style={{ background: T.rail, padding: "26px 26px", minHeight: 360 }}
        >
          <MockedScreenshotWithMarkup markup selectedIndex={1} />
          <CanvasZoomCluster />
          <PassVerdict status="ready" />
        </div>
        <SpeakStrip
          placeholder="modify this layer · or speak another pass…"
          examples={[
            "make the ring thicker",
            "switch to dashed",
            "color it amber",
            "add a label above it",
          ]}
          scopeBadge="scoped · L2 selected"
        />
      </MarkupWindow>
      <ToolbarRedesignMarginalia />
      <CaptionStrip
        text="Tools on the left, style on the right — same row, but the right half is now contextual to whatever's selected. Pick a rect: stroke, color, texture, fill. Pick text: font size + color. Zoom drops out of the top bar entirely and lives as a floating cluster over the canvas, the way Hudson does it. ESC stays on the keyboard; it doesn't need its own chip."
      />
    </Surface>
  );
}

// Three style-stack states shown side-by-side for comparison: idle (no
// selection · tool defaults), rect selected, text selected. Each one is
// just the toolbar — no canvas, no strip — so the reader can compare
// what the style half does across selections at a glance.

function ToolbarStyleVariants() {
  return (
    <Surface>
      <div className="flex flex-col gap-4" style={{ marginTop: 6 }}>
        <PaneHeader title="style stack · selection variants" sub="3 states" />
        <div
          className="flex flex-col"
          style={{
            background: T.page,
            border: `0.5px solid ${T.edge}`,
            borderRadius: 6,
            overflow: "hidden",
          }}
        >
          <ToolToolbarV2 active={null} selection={null} variantLabel="idle · tool defaults" />
          <ToolToolbarV2 active="rect" selection={{ kind: "rect" }} variantLabel="rect selected" />
          <ToolToolbarV2 active="text" selection={{ kind: "text" }} variantLabel="text selected" />
        </div>
        <CaptionStrip
          text="Idle reads as 'what will the next shape look like' — the style stack is the pen settings until you select something. Selecting a layer swaps the same controls to act on that layer. Text-selected drops stroke/fill controls (they're meaningless) and surfaces size + color instead. Same row, same neighborhood, different contents."
        />
      </div>
    </Surface>
  );
}

// ─── Tool Toolbar V2 — tools left · style stack right ────────────────

type StyleSelection = { kind: ToolId } | null;

function ToolToolbarV2({
  active,
  selection,
  variantLabel,
}: {
  active: ToolId | null;
  selection: StyleSelection;
  variantLabel?: string;
}) {
  return (
    <div
      className="flex items-center px-2"
      style={{
        height: 44,
        background: T.chrome,
        borderBottom: `0.5px solid ${T.inkRuleS}`,
        gap: 4,
      }}
    >
      {TOOLS.map((t) => {
        const on = t.id === active;
        return (
          <button
            key={t.id}
            title={t.label}
            className="flex items-center gap-1.5 px-2.5"
            style={{
              height: 28,
              color: on ? T.amberDeep : T.inkFaint,
              background: on ? T.amberFaint : "transparent",
              border: on ? `0.5px solid ${T.amberSoft}` : "0.5px solid transparent",
              borderRadius: 3,
            }}
          >
            <span className="font-mono" style={{ fontSize: 13, lineHeight: 1 }}>
              {t.glyph}
            </span>
            <span
              className="font-mono uppercase tracking-[0.16em]"
              style={{ fontSize: 9, lineHeight: 1 }}
            >
              {t.label}
            </span>
          </button>
        );
      })}

      <ToolbarDivider />

      <StyleStack selection={selection ?? (active ? { kind: active } : null)} />

      <span className="flex-1" />

      {variantLabel && (
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: T.inkFainter }}
        >
          {variantLabel}
        </span>
      )}
    </div>
  );
}

function ToolbarDivider() {
  return (
    <span
      style={{
        display: "inline-block",
        width: 1,
        height: 20,
        margin: "0 8px",
        background: T.inkRuleS,
      }}
    />
  );
}

// ─── Style Stack ──────────────────────────────────────────────────────
//
// Contextual to the current selection (or the active tool if nothing's
// selected). Branches once on `kind`:
//   · rect / arrow / line / blur  → stroke width + color + texture
//   · rect                        → ALSO fill (transparent / opaque)
//   · blur                        → intensity instead of color + texture
//   · text                        → font size + color (no stroke/texture)
//   · null                        → all swatches dimmed; reads as "no
//                                    selection — pick a tool to set defaults"

function StyleStack({ selection }: { selection: StyleSelection }) {
  if (!selection) {
    return (
      <span
        className="font-display italic"
        style={{ fontSize: 11, color: T.inkFainter }}
      >
        pick a tool · style applies to the next shape
      </span>
    );
  }

  if (selection.kind === "text") {
    return (
      <div className="flex items-center" style={{ gap: 10 }}>
        <FontSizeStepper />
        <MiniGroupDivider />
        <ColorRow />
      </div>
    );
  }

  if (selection.kind === "blur") {
    return (
      <div className="flex items-center" style={{ gap: 10 }}>
        <BlurIntensityStepper />
      </div>
    );
  }

  // Shape default: rect / arrow / line — stroke + color + texture, plus
  // fill for rect.
  return (
    <div className="flex items-center" style={{ gap: 10 }}>
      <StrokeWidthRow />
      <MiniGroupDivider />
      <ColorRow />
      <MiniGroupDivider />
      <TextureRow />
      {selection.kind === "rect" && (
        <>
          <MiniGroupDivider />
          <FillToggle />
        </>
      )}
    </div>
  );
}

function MiniGroupDivider() {
  return (
    <span
      style={{
        display: "inline-block",
        width: 1,
        height: 14,
        background: T.inkRuleS,
      }}
    />
  );
}

function StyleLabel({ text }: { text: string }) {
  return (
    <span
      className="font-mono uppercase tracking-[0.20em]"
      style={{ fontSize: 8.5, color: T.inkFainter }}
    >
      {text}
    </span>
  );
}

function StrokeWidthRow() {
  // Four discrete widths. Second one selected as the canonical default.
  const widths = [1, 2, 3, 5];
  const selected = 2;
  return (
    <div className="flex items-center" style={{ gap: 6 }}>
      <StyleLabel text="width" />
      <div className="flex items-center" style={{ gap: 3 }}>
        {widths.map((w) => {
          const on = w === selected;
          return (
            <button
              key={w}
              title={`${w}px stroke`}
              className="flex items-center justify-center"
              style={{
                width: 22,
                height: 22,
                borderRadius: 3,
                background: on ? T.amberFaint : "transparent",
                border: on ? `0.5px solid ${T.amberSoft}` : `0.5px solid ${T.inkRuleS}`,
              }}
            >
              <span
                style={{
                  display: "block",
                  width: 14,
                  height: w,
                  background: on ? T.amberDeep : T.inkFaint,
                  borderRadius: 1,
                }}
              />
            </button>
          );
        })}
      </div>
    </div>
  );
}

function ColorRow() {
  // Five swatches: ink · alert · amber · brass · ghost. Amber selected
  // as the canonical agent-overlay color.
  const swatches = [
    { color: T.ink,     label: "ink"   },
    { color: T.alert,   label: "alert" },
    { color: T.amber,   label: "amber" },
    { color: T.brass,   label: "brass" },
    { color: "#FFFFFF", label: "white" },
  ];
  const selected = 2;
  return (
    <div className="flex items-center" style={{ gap: 6 }}>
      <StyleLabel text="color" />
      <div className="flex items-center" style={{ gap: 3 }}>
        {swatches.map((s, i) => {
          const on = i === selected;
          return (
            <button
              key={s.label}
              title={s.label}
              className="block"
              style={{
                width: 16,
                height: 16,
                borderRadius: 999,
                background: s.color,
                border: on
                  ? `1.5px solid ${T.amberDeep}`
                  : `0.5px solid ${T.inkRule}`,
                boxShadow: on
                  ? `0 0 0 2px ${T.amberFaint}`
                  : "0 1px 0 rgba(255,255,255,0.55) inset",
              }}
            />
          );
        })}
      </div>
    </div>
  );
}

function TextureRow() {
  // Three options: solid, dashed, dotted. Solid selected by default.
  const textures: { id: string; preview: React.CSSProperties; label: string }[] = [
    { id: "solid",  preview: { borderTop: `2px solid ${T.ink}` },               label: "solid"  },
    { id: "dashed", preview: { borderTop: `2px dashed ${T.ink}` },              label: "dashed" },
    { id: "dotted", preview: { borderTop: `2px dotted ${T.ink}` },              label: "dotted" },
  ];
  const selected = "solid";
  return (
    <div className="flex items-center" style={{ gap: 6 }}>
      <StyleLabel text="texture" />
      <div className="flex items-center" style={{ gap: 3 }}>
        {textures.map((t) => {
          const on = t.id === selected;
          return (
            <button
              key={t.id}
              title={t.label}
              className="flex items-center justify-center"
              style={{
                width: 24,
                height: 22,
                borderRadius: 3,
                background: on ? T.amberFaint : "transparent",
                border: on ? `0.5px solid ${T.amberSoft}` : `0.5px solid ${T.inkRuleS}`,
              }}
            >
              <span style={{ display: "block", width: 16, ...t.preview }} />
            </button>
          );
        })}
      </div>
    </div>
  );
}

function FillToggle() {
  // Two states: outlined (transparent fill) vs filled. Outlined as
  // default since the rest of the markup vocabulary uses ringed shapes.
  const filled = false;
  return (
    <div className="flex items-center" style={{ gap: 6 }}>
      <StyleLabel text="fill" />
      <div className="flex items-center" style={{ gap: 3 }}>
        <button
          title="outline"
          className="flex items-center justify-center"
          style={{
            width: 22,
            height: 22,
            borderRadius: 3,
            background: !filled ? T.amberFaint : "transparent",
            border: !filled
              ? `0.5px solid ${T.amberSoft}`
              : `0.5px solid ${T.inkRuleS}`,
          }}
        >
          <span
            style={{
              display: "block",
              width: 12,
              height: 12,
              border: `1.5px solid ${!filled ? T.amberDeep : T.inkFaint}`,
              borderRadius: 2,
              background: "transparent",
            }}
          />
        </button>
        <button
          title="filled"
          className="flex items-center justify-center"
          style={{
            width: 22,
            height: 22,
            borderRadius: 3,
            background: filled ? T.amberFaint : "transparent",
            border: filled
              ? `0.5px solid ${T.amberSoft}`
              : `0.5px solid ${T.inkRuleS}`,
          }}
        >
          <span
            style={{
              display: "block",
              width: 12,
              height: 12,
              background: filled ? T.amberDeep : T.inkFaint,
              borderRadius: 2,
            }}
          />
        </button>
      </div>
    </div>
  );
}

function FontSizeStepper() {
  // Three preset sizes: S / M / L. Plus a mono caption so the chosen
  // size is legible at a glance. M selected as default.
  const sizes = ["S", "M", "L"];
  const selected = "M";
  return (
    <div className="flex items-center" style={{ gap: 6 }}>
      <StyleLabel text="size" />
      <div className="flex items-center" style={{ gap: 3 }}>
        {sizes.map((s) => {
          const on = s === selected;
          return (
            <button
              key={s}
              title={`Font size ${s}`}
              className="flex items-center justify-center font-mono"
              style={{
                width: 22,
                height: 22,
                borderRadius: 3,
                fontSize: 10,
                color: on ? T.amberDeep : T.inkFaint,
                background: on ? T.amberFaint : "transparent",
                border: on ? `0.5px solid ${T.amberSoft}` : `0.5px solid ${T.inkRuleS}`,
              }}
            >
              {s}
            </button>
          );
        })}
      </div>
    </div>
  );
}

function BlurIntensityStepper() {
  // Three discrete intensities. Mid selected.
  const sizes = [4, 8, 16];
  const selected = 8;
  return (
    <div className="flex items-center" style={{ gap: 6 }}>
      <StyleLabel text="blur" />
      <div className="flex items-center" style={{ gap: 3 }}>
        {sizes.map((b) => {
          const on = b === selected;
          return (
            <button
              key={b}
              title={`${b}px blur`}
              className="flex items-center justify-center font-mono"
              style={{
                width: 30,
                height: 22,
                borderRadius: 3,
                fontSize: 9.5,
                color: on ? T.amberDeep : T.inkFaint,
                background: on ? T.amberFaint : "transparent",
                border: on ? `0.5px solid ${T.amberSoft}` : `0.5px solid ${T.inkRuleS}`,
              }}
            >
              {b}px
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ─── Canvas Zoom Cluster — floating bottom-right ─────────────────────
//
// Hudson-style floating viewport controls. Lives over the canvas, not
// in the toolbar — viewport is a different category from drawing.
// Pinned bottom-right so the user's hand naturally lands there when
// reaching for a "zoom to fit" or a quick scale tweak; doesn't compete
// with the speak strip which lives further down and full-width.

function CanvasZoomCluster() {
  return (
    <div
      className="absolute flex items-center"
      style={{
        bottom: 14,
        right: 14,
        gap: 2,
        padding: 3,
        background: T.pane,
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 5,
        boxShadow:
          "0 1px 0 rgba(255,255,255,0.55) inset, 0 4px 12px rgba(0,0,0,0.10)",
      }}
    >
      <ZoomButton glyph="−" title="Zoom out" />
      <ZoomBadge text="100%" />
      <ZoomButton glyph="+" title="Zoom in" />
      <ZoomClusterDivider />
      <ZoomButton label="FIT" title="Fit to canvas" />
    </div>
  );
}

function ZoomButton({
  glyph,
  label,
  title,
}: {
  glyph?: string;
  label?: string;
  title: string;
}) {
  return (
    <button
      title={title}
      aria-label={title}
      className="flex items-center justify-center"
      style={{
        width: label ? 38 : 22,
        height: 22,
        borderRadius: 3,
        color: T.inkFaint,
        background: "transparent",
      }}
    >
      {glyph && (
        <span className="font-mono" style={{ fontSize: 12, lineHeight: 1 }}>
          {glyph}
        </span>
      )}
      {label && (
        <span
          className="font-mono uppercase tracking-[0.16em]"
          style={{ fontSize: 8.5, lineHeight: 1 }}
        >
          {label}
        </span>
      )}
    </button>
  );
}

function ZoomBadge({ text }: { text: string }) {
  return (
    <span
      className="font-mono tabular-nums"
      style={{
        fontSize: 9.5,
        color: T.inkMid,
        padding: "0 4px",
        minWidth: 38,
        textAlign: "center",
      }}
    >
      {text}
    </span>
  );
}

function ZoomClusterDivider() {
  return (
    <span
      style={{
        display: "inline-block",
        width: 1,
        height: 14,
        margin: "0 2px",
        background: T.inkRuleS,
      }}
    />
  );
}

// Vocabulary entries specific to the redesigned toolbar.

function ToolbarRedesignMarginalia() {
  const entries: [string, string][] = [
    ["Tool Toolbar V2",    "the redesigned top band — tools left · style stack right"],
    ["Style Stack",        "contextual editor for the active tool or selected layer"],
    ["Stroke Row",         "width picker · 4 discrete weights · doubles as default"],
    ["Color Row",          "5 swatch palette · ink · alert · amber · brass · white"],
    ["Texture Row",        "solid · dashed · dotted · applies to shape borders"],
    ["Fill Toggle",        "outlined vs filled — rect only · meaningless for arrows / lines"],
    ["Font Size Stepper",  "S / M / L · text-only · stroke/texture drop out"],
    ["Blur Intensity",     "4/8/16 px · replaces color + texture for blur tool"],
    ["Canvas Zoom Cluster", "floating bottom-right · − / 100% / + / fit · Hudson pattern"],
  ];
  return (
    <div
      style={{
        marginTop: 14,
        padding: "12px 16px",
        background: T.pane,
        border: `0.5px solid ${T.inkRuleS}`,
        borderRadius: 4,
      }}
    >
      <div
        className="flex items-baseline gap-3"
        style={{ marginBottom: 10 }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.24em]"
          style={{ fontSize: 9, color: T.amberDeep }}
        >
          · toolbar redesign · names
        </span>
        <span
          className="font-display italic"
          style={{ fontSize: 11, color: T.inkFaint }}
        >
          additions to the Capture Markup vocabulary
        </span>
      </div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "180px 1fr",
          rowGap: 4,
          columnGap: 18,
        }}
      >
        {entries.map(([name, def]) => (
          <React.Fragment key={name}>
            <span
              className="font-mono font-semibold uppercase tracking-[0.16em]"
              style={{ fontSize: 10, color: T.amberDeep }}
            >
              {name}
            </span>
            <span
              className="font-display italic"
              style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.45 }}
            >
              {def}
            </span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

// ─── State 4 · Save · Export · Share ─────────────────────────────────
//
// The markup is a COMPUTED document — a list of layers in a sidecar JSON,
// not a baked image. That distinction is the whole feature:
//
//   · SAVE    persists the computed doc. The source PNG is never touched
//             and we never flatten to pixels — the markup stays editable
//             forever (re-open, re-style, re-prompt).
//   · EXPORT  materializes the computed doc → a flat PNG / JPEG artifact,
//             on demand, at 1× or 2×. Rendered on the way out; the doc it
//             came from is unchanged.
//   · SHARE   is *why* you export — a concrete file to hand off. "Exports
//             are just a different way to save." (operator · 2026-05-28)
//
// Two consequences for the chrome:
//   1. Document-level actions leave the talk strip (which goes back to
//      pure mic · prompt · run) and move into a title-bar ACTION CLUSTER.
//   2. That cluster carries a PERSISTENT "computed · N layers · saved Xs
//      ago" readout — the original complaint was "I can't tell it saved."
//      A 1.4s flash isn't state; a standing readout is.

function SaveShareState() {
  return (
    <Surface>
      <ComputedVsMaterialized />
      <MarkupWindow
        title="Markup · C-0017"
        titleRight={<DocActionCluster shareOpen savedAgo="3s ago" layers={4} />}
      >
        <ToolToolbarV2 active={null} selection={null} />
        <div
          className="relative flex items-center justify-center"
          style={{ background: T.rail, padding: "26px 26px", minHeight: 360 }}
        >
          <MockedScreenshotWithMarkup markup selectedIndex={1} />
          <CanvasZoomCluster />
        </div>
        <SpeakStrip
          placeholder="speak or type another pass…"
          examples={[
            "circle the error and label it",
            "blur the email",
            "arrow title → failed line",
          ]}
          scopeBadge="global · whole image"
        />
      </MarkupWindow>
      <ExportConfirmStrip />
      <SaveShareMarginalia />
      <PreviewShareNote />
      <CaptionStrip
        text="Save and Share are siblings, not a sequence. Save persists the computed layer doc — editable, non-destructive, the source of truth. Share opens the export matrix: PNG or JPEG, 1× or 2×, rendered to the Talkie exports folder on the way out. The original capture is never re-encoded and the markup never gets flattened into the thing you keep — only into the thing you send. The title-bar readout makes the save state legible at all times, which is the part that was missing."
      />
    </Surface>
  );
}

// ─── The model · computed doc → materialized artifact ────────────────
//
// Leads the section because it's the *why*. Three boxes: the untouched
// source, the computed doc that SAVE persists, and the flat artifact that
// EXPORT renders. The arrow is one-way — export reads the doc, never
// writes back to it.

function ComputedVsMaterialized() {
  return (
    <div style={{ marginBottom: 14 }}>
      <PaneHeader title="the model · computed → materialized" sub="why save ≠ export" />
      <div
        className="flex items-stretch"
        style={{
          background: T.pane,
          border: `0.5px solid ${T.inkRuleS}`,
          borderRadius: 6,
          padding: "16px 18px",
          gap: 14,
        }}
      >
        <ModelBox
          tone="ink"
          kicker="source"
          title="C-0017.png"
          line="the raw capture · never re-encoded"
          glyph="▦"
        />
        <ModelGlue label="+" />
        <ModelBox
          tone="amber"
          kicker="computed doc · SAVE persists this"
          title="C-0017.markup.json"
          line="layers · rect · arrow · label · blur — editable forever"
          glyph="❖"
          primary
        />
        <ModelArrow label="EXPORT renders →" />
        <ModelBox
          tone="ink"
          kicker="materialized · SHARE hands this off"
          title="C-0017@2x.png"
          line="flat pixels · made on demand · not kept as state"
          glyph="◳"
        />
      </div>
    </div>
  );
}

function ModelBox({
  tone,
  kicker,
  title,
  line,
  glyph,
  primary,
}: {
  tone: "ink" | "amber";
  kicker: string;
  title: string;
  line: string;
  glyph: string;
  primary?: boolean;
}) {
  const accent = tone === "amber" ? T.amberDeep : T.inkMid;
  return (
    <div
      className="flex-1"
      style={{
        background: primary ? T.amberFaint : T.page,
        border: `0.5px solid ${primary ? T.amberSoft : T.inkRuleS}`,
        borderRadius: 5,
        padding: "11px 12px",
        minWidth: 0,
      }}
    >
      <div className="flex items-center gap-2" style={{ marginBottom: 7 }}>
        <span className="font-mono" style={{ fontSize: 13, color: accent, lineHeight: 1 }}>
          {glyph}
        </span>
        <span
          className="font-mono font-semibold uppercase tracking-[0.18em]"
          style={{ fontSize: 8, color: accent }}
        >
          {kicker}
        </span>
      </div>
      <div className="font-mono" style={{ fontSize: 12, color: T.ink, marginBottom: 4 }}>
        {title}
      </div>
      <div
        className="font-display italic"
        style={{ fontSize: 11, color: T.inkFaint, lineHeight: 1.4 }}
      >
        {line}
      </div>
    </div>
  );
}

function ModelGlue({ label }: { label: string }) {
  return (
    <div className="flex items-center">
      <span className="font-mono" style={{ fontSize: 14, color: T.inkFainter }}>
        {label}
      </span>
    </div>
  );
}

function ModelArrow({ label }: { label: string }) {
  return (
    <div className="flex flex-col items-center justify-center" style={{ minWidth: 96 }}>
      <span
        className="font-mono font-semibold uppercase tracking-[0.16em]"
        style={{ fontSize: 8, color: T.amberDeep, marginBottom: 3, textAlign: "center" }}
      >
        {label}
      </span>
      <div style={{ width: "100%", height: 1, background: T.amberSoft }} />
      <span
        className="font-display italic"
        style={{ fontSize: 9, color: T.inkFainter, marginTop: 3 }}
      >
        one-way
      </span>
    </div>
  );
}

// ─── Title-bar document action cluster ───────────────────────────────
//
// Save state + the two document actions, parked top-right in the window
// chrome where a document's actions belong. The standing readout is the
// fix for "I can't tell it saved": dot + "computed · N layers · saved Xs
// ago" is always visible, not a transient flash.

function DocActionCluster({
  shareOpen,
  savedAgo,
  layers,
}: {
  shareOpen?: boolean;
  savedAgo: string;
  layers: number;
}) {
  return (
    <div className="relative flex items-center gap-2.5">
      <SaveStatusReadout savedAgo={savedAgo} layers={layers} />
      <span className="h-3.5 w-px" style={{ background: T.inkRule }} />
      <DocActionButton label="Save" kbd="⌘S" />
      <DocActionButton label="Share" caret tone="amber" active={shareOpen} />
      {shareOpen && <ShareMenu />}
    </div>
  );
}

function SaveStatusReadout({ savedAgo, layers }: { savedAgo: string; layers: number }) {
  return (
    <span className="flex items-center gap-1.5" title="The computed markup doc is saved to its sidecar.">
      <span
        className="inline-block rounded-full"
        style={{ width: 6, height: 6, background: T.amber, boxShadow: "0 0 5px rgba(196,125,28,0.55)" }}
      />
      <span
        className="font-mono uppercase tracking-[0.16em]"
        style={{ fontSize: 8.5, color: T.inkFaint }}
      >
        computed · {layers} layers · saved {savedAgo}
      </span>
    </span>
  );
}

function DocActionButton({
  label,
  kbd,
  caret,
  tone = "ink",
  active,
}: {
  label: string;
  kbd?: string;
  caret?: boolean;
  tone?: "ink" | "amber";
  active?: boolean;
}) {
  const amber = tone === "amber";
  return (
    <button
      className="flex items-center gap-1.5"
      style={{
        height: 22,
        padding: "0 8px",
        borderRadius: 4,
        color: amber ? T.amberDeep : T.inkMid,
        background: active ? T.amberFaint : amber ? T.amberFaint : "transparent",
        border: `0.5px solid ${active || amber ? T.amberSoft : T.inkRule}`,
      }}
    >
      <span
        className="font-mono font-semibold uppercase tracking-[0.18em]"
        style={{ fontSize: 9 }}
      >
        {label}
      </span>
      {kbd && (
        <span className="font-mono" style={{ fontSize: 8.5, opacity: 0.7 }}>
          {kbd}
        </span>
      )}
      {caret && (
        <span className="font-mono" style={{ fontSize: 8, lineHeight: 1, opacity: 0.8 }}>
          ▾
        </span>
      )}
    </button>
  );
}

// ─── Share menu — the predetermined export matrix ────────────────────
//
// Drops from the Share button. Two formats × two scales, each a one-click
// render to the exports folder. The header reframes it as the operator
// did: this is a way to *save out*, and the doc you're editing stays a
// computed doc. Footer names the fixed destination.

function ShareMenu() {
  const rows: { fmt: string; scale: string; note: string; primary?: boolean }[] = [
    { fmt: "PNG", scale: "1×", note: "lossless · native size" },
    { fmt: "PNG", scale: "2×", note: "lossless · retina", primary: true },
    { fmt: "JPEG", scale: "1×", note: "smaller · for chat / email" },
    { fmt: "JPEG", scale: "2×", note: "smaller · retina" },
  ];
  return (
    <div
      className="absolute"
      style={{
        top: "calc(100% + 6px)",
        right: 0,
        width: 268,
        background: T.pane,
        border: `0.5px solid ${T.inkRule}`,
        borderRadius: 6,
        boxShadow: "0 12px 30px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.10)",
        overflow: "hidden",
        zIndex: 20,
      }}
    >
      <div
        className="flex items-baseline gap-2 px-3"
        style={{ height: 30, borderBottom: `0.5px solid ${T.inkRuleS}`, background: T.chrome }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.20em]"
          style={{ fontSize: 8.5, color: T.amberDeep }}
        >
          · share · export a flat copy
        </span>
      </div>
      <p
        className="font-display italic"
        style={{ fontSize: 10.5, color: T.inkFaint, lineHeight: 1.4, padding: "8px 12px 6px 12px" }}
      >
        Render the markup to pixels. The computed doc stays editable —
        this just makes a copy to send.
      </p>
      <div style={{ padding: "2px 6px 6px 6px" }}>
        {rows.map((r) => (
          <button
            key={`${r.fmt}-${r.scale}`}
            className="flex items-center gap-2 w-full"
            style={{
              padding: "6px 8px",
              borderRadius: 4,
              background: r.primary ? T.amberFaint : "transparent",
              border: `0.5px solid ${r.primary ? T.amberSoft : "transparent"}`,
              textAlign: "left",
            }}
          >
            <span
              className="font-mono font-semibold uppercase tracking-[0.16em]"
              style={{
                fontSize: 9,
                color: r.primary ? T.amberDeep : T.ink,
                width: 34,
              }}
            >
              {r.fmt}
            </span>
            <span
              className="font-mono"
              style={{
                fontSize: 9,
                color: r.primary ? T.amberDeep : T.inkMid,
                padding: "1px 5px",
                borderRadius: 2,
                border: `0.5px solid ${r.primary ? T.amberSoft : T.inkRuleS}`,
              }}
            >
              {r.scale}
            </span>
            <span
              className="font-display italic flex-1"
              style={{ fontSize: 10.5, color: T.inkFaint }}
            >
              {r.note}
            </span>
            {r.primary && (
              <span
                className="font-mono uppercase tracking-[0.14em]"
                style={{ fontSize: 7.5, color: T.amberDeep }}
              >
                default
              </span>
            )}
          </button>
        ))}
      </div>
      <div
        className="flex items-center gap-1.5 px-3"
        style={{ height: 26, borderTop: `0.5px solid ${T.inkRuleS}`, background: T.chrome }}
      >
        <span className="font-mono" style={{ fontSize: 9, color: T.inkFainter }}>
          ↳
        </span>
        <span
          className="font-mono uppercase tracking-[0.14em]"
          style={{ fontSize: 8, color: T.inkFaint }}
        >
          Talkie / Exports
        </span>
        <span className="flex-1" />
        <span
          className="font-display italic"
          style={{ fontSize: 9.5, color: T.inkFainter }}
        >
          opens after export
        </span>
      </div>
    </div>
  );
}

// ─── Post-export confirmation ────────────────────────────────────────
//
// Export is a hand-off, so it needs a receipt. Shows what was written and
// where, with a Reveal affordance. Distinct from the SAVE readout (which
// is about the computed doc); this is about the artifact that just left.

function ExportConfirmStrip() {
  return (
    <div
      className="flex items-center gap-3"
      style={{
        marginTop: 12,
        padding: "9px 12px",
        background: T.pane,
        border: `0.5px solid ${T.amberSoft}`,
        borderRadius: 5,
      }}
    >
      <span
        className="flex items-center justify-center rounded-full"
        style={{ width: 18, height: 18, background: T.amberFaint, color: T.amberDeep, fontSize: 11 }}
      >
        ✓
      </span>
      <span className="font-mono" style={{ fontSize: 11, color: T.ink }}>
        C-0017@2x.png
      </span>
      <span
        className="font-display italic"
        style={{ fontSize: 11, color: T.inkFaint }}
      >
        rendered to{" "}
        <span className="font-mono" style={{ fontSize: 10.5, color: T.inkMid }}>
          Talkie / Exports
        </span>{" "}
        · 1.2 MB · PNG · 2×
      </span>
      <span className="flex-1" />
      <button
        className="font-mono font-semibold uppercase tracking-[0.18em]"
        style={{
          fontSize: 8.5,
          color: T.amberDeep,
          padding: "4px 9px",
          background: T.amberFaint,
          border: `0.5px solid ${T.amberSoft}`,
          borderRadius: 3,
        }}
      >
        Reveal in Finder
      </button>
    </div>
  );
}

// ─── Preview parity note ─────────────────────────────────────────────
//
// Share belongs anywhere you're looking at a capture, not just inside the
// markup editor. The capture Preview gets the same Share ▾ control, so a
// quick PNG/JPEG export doesn't require opening markup at all.

function PreviewShareNote() {
  return (
    <div className="flex gap-4" style={{ marginTop: 14 }}>
      <div style={{ flex: "1 1 0%" }}>
        <PaneHeader title="same control in preview" sub="capture preview" />
        <div
          style={{
            background: T.pane,
            border: `1px solid ${T.inkRuleS}`,
            borderRadius: 4,
            padding: 16,
            display: "flex",
            flexDirection: "column",
            gap: 12,
          }}
        >
          <MiniPreviewCard />
          <p
            className="font-display italic"
            style={{ color: T.inkFaint, fontSize: 12, lineHeight: 1.5 }}
          >
            The capture Preview shows the same Share ▾ next to Markup. If the
            shot has a computed doc, Share renders it flat; if it&apos;s bare, Share
            exports the raw capture in the chosen format. One verb, one menu,
            both surfaces.
          </p>
        </div>
      </div>
      <div style={{ flex: "1 1 0%" }}>
        <PaneHeader title="what doesn't change" sub="invariants" />
        <div
          style={{
            background: T.pane,
            border: `1px solid ${T.inkRuleS}`,
            borderRadius: 4,
            padding: 16,
            display: "flex",
            flexDirection: "column",
            gap: 8,
          }}
        >
          {[
            ["source PNG", "never re-encoded · the capture you took is the capture on disk"],
            ["computed doc", "the only thing SAVE writes · stays editable across sessions"],
            ["export", "always a fresh artifact · reading the doc, never mutating it"],
            ["drag-out", "the existing ⇱ DRAG PNG handle is the same renderer, now also a menu"],
          ].map(([k, v]) => (
            <div key={k} className="flex gap-2" style={{ alignItems: "baseline" }}>
              <span
                className="font-mono font-semibold uppercase tracking-[0.14em]"
                style={{ fontSize: 8.5, color: T.amberDeep, width: 92, flexShrink: 0 }}
              >
                {k}
              </span>
              <span
                className="font-display italic"
                style={{ fontSize: 11, color: T.inkMid, lineHeight: 1.4 }}
              >
                {v}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function MiniPreviewCard() {
  return (
    <div
      className="relative"
      style={{
        height: 120,
        background: T.rail,
        borderRadius: 4,
        border: `0.5px solid ${T.inkRuleS}`,
        overflow: "hidden",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          width: 150,
          height: 92,
          background: T.page,
          borderRadius: 3,
          border: `0.5px solid ${T.inkRule}`,
          boxShadow: "0 4px 12px rgba(0,0,0,0.08)",
        }}
      />
      {/* Floating action row, bottom-right — mirrors the markup title bar */}
      <div
        className="absolute flex items-center gap-1.5"
        style={{
          bottom: 10,
          right: 10,
          padding: 3,
          background: T.pane,
          border: `0.5px solid ${T.inkRule}`,
          borderRadius: 5,
          boxShadow: "0 4px 12px rgba(0,0,0,0.10)",
        }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.16em]"
          style={{ fontSize: 8, color: T.inkMid, padding: "3px 7px" }}
        >
          Markup
        </span>
        <span className="h-3 w-px" style={{ background: T.inkRule }} />
        <span
          className="flex items-center gap-1 font-mono font-semibold uppercase tracking-[0.16em]"
          style={{
            fontSize: 8,
            color: T.amberDeep,
            padding: "3px 7px",
            background: T.amberFaint,
            border: `0.5px solid ${T.amberSoft}`,
            borderRadius: 3,
          }}
        >
          Share <span style={{ fontSize: 7 }}>▾</span>
        </span>
      </div>
    </div>
  );
}

// ─── Save · Export · Share vocabulary ────────────────────────────────

function SaveShareMarginalia() {
  const entries: [string, string][] = [
    ["Computed Doc", "the markup as layers in the sidecar JSON — the editable source of truth"],
    ["Save", "persist the computed doc · ⌘S · never flattens · original untouched"],
    ["Export", "render the computed doc → a flat PNG / JPEG artifact, on demand"],
    ["Share", "the reason to export — a concrete file to hand off"],
    ["Action Cluster", "title-bar zone · save readout + Save + Share · out of the talk strip"],
    ["Save Readout", "standing 'computed · N layers · saved Xs ago' — replaces the 1.4s flash"],
    ["Share Menu", "the predetermined matrix · PNG / JPEG × 1× / 2×"],
    ["Format Preset", "one row in the matrix · format + scale → one-click export"],
    ["Exports Folder", "fixed destination · Talkie / Exports · reveal after write"],
  ];
  return (
    <div
      style={{
        marginTop: 14,
        padding: "12px 16px",
        background: T.pane,
        border: `0.5px solid ${T.inkRuleS}`,
        borderRadius: 4,
      }}
    >
      <div className="flex items-baseline gap-3" style={{ marginBottom: 10 }}>
        <span
          className="font-mono font-semibold uppercase tracking-[0.24em]"
          style={{ fontSize: 9, color: T.amberDeep }}
        >
          · save · share · names
        </span>
        <span className="font-display italic" style={{ fontSize: 11, color: T.inkFaint }}>
          computed doc vs materialized artifact — the words we keep in Swift + chat
        </span>
      </div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "140px 1fr",
          rowGap: 4,
          columnGap: 18,
        }}
      >
        {entries.map(([name, def]) => (
          <React.Fragment key={name}>
            <span
              className="font-mono font-semibold uppercase tracking-[0.16em]"
              style={{ fontSize: 10, color: T.amberDeep }}
            >
              {name}
            </span>
            <span
              className="font-display italic"
              style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.45 }}
            >
              {def}
            </span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

// ─── State 5 · Level up · work thread + speak strip v2 ───────────────
//
// The bottom band was "lacking" (operator · 2026-05-29). A first pass
// added a tidy "pass receipt" strip between canvas and composer.
// Operator cut it: don't summarize after the fact — SHOW the agent
// working, what it's doing, streaming. Work-thread / log style, parked
// in the empty rail on the right of the window (the one circled in the
// 2026-05-29 markup).
//
// So this section levels up two things:
//
//   1. WORK THREAD — a streaming run log on the RIGHT RAIL. As the agent
//      runs it writes a line per step — read · plan · then each mark as
//      it lands (guide · rect · label · blur) — a live node pulsing at
//      the head of the thread. When the pass finishes the thread stays
//      as the record, footed with "pass 1 · 4 marks · 1.4s" and a single
//      `↶ undo` (⌘Z). No accept/cancel commit-gate.
//
//   2. SPEAK STRIP v2 — the composer gets live states. Idle is a clean
//      mic · prompt · run. While RECORDING, the prompt lane becomes a
//      magnetic-tape waveform — VU bars, amber centerline, tape-head
//      marker — the house voice aesthetic, instead of a dead field.
//
// The right rail is contextual, the way the toolbar's style stack is:
// the WORK THREAD while/after a run, the layer INSPECTOR when you select
// a mark. One rail, the content that matters right now.

type StripMode = "idle" | "recording" | "running";
type ThreadEntry = {
  t: string;
  verb: string;
  detail: string;
  kind: "meta" | "mark";
  status: "done" | "active" | "pending";
};

function LevelUpState() {
  return (
    <Surface>
      <MarkupWindow
        title="Markup · C-0017"
        subtitle="leveled up · pass 1 · work thread on the right"
      >
        <ToolToolbarV2 active={null} selection={null} />
        <div className="flex" style={{ background: T.pane }}>
          <div
            className="relative flex-1 flex items-center justify-center"
            style={{ background: T.rail, padding: 22, minHeight: 360 }}
          >
            <MockedScreenshotWithMarkup markup />
            <CanvasZoomCluster />
          </div>
          <WorkThread mode="done" />
        </div>
        <SpeakStripV2
          mode="idle"
          placeholder="speak or type another pass…"
          examples={[
            "circle the error and label it",
            "blur the email",
            "arrow title → failed line",
          ]}
          scopeBadge="global · whole image"
        />
      </MarkupWindow>
      <LevelUpDetail />
      <LevelUpMarginalia />
      <CaptionStrip
        text="Two upgrades, both to the right and the foot of the window. The Work Thread streams the run as it happens — read the capture, plan the marks, then a line per mark as it lands — log-style in the right rail, so you watch what the agent is doing instead of staring at a spinner that only says RUNNING. When it's done the thread is the record: four marks, 1.4 seconds, one ⌘Z to walk it back. And the Speak Strip is no longer a dead field — tap the mic and the prompt lane becomes a magnetic-tape waveform so the machine visibly hears you."
      />
      <style jsx global>{`
        @keyframes promptcaret { 0%, 100% { opacity: 1; } 50% { opacity: 0; } }
        @keyframes recpulse { 0% { opacity: 0.7; transform: scale(1); } 100% { opacity: 0; transform: scale(1.4); } }
        @keyframes threadpulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }
      `}</style>
    </Surface>
  );
}

// ─── Work Thread · the streaming run log ─────────────────────────────
//
// Right rail of the markup window (mirrors LayersColumn's slot). A header
// with a live indicator; a vertical thread spine with one node per step;
// a footer that's the pass summary + undo (done) or a live status
// (working). Reads as a build log / activity thread, not a tidy receipt.

function WorkThread({ mode }: { mode: "working" | "done" }) {
  const working = mode === "working";
  const entries: ThreadEntry[] = [
    { t: "0.0s", verb: "read", detail: "capture · 760×432", kind: "meta", status: "done" },
    { t: "0.3s", verb: "plan", detail: "4 marks queued", kind: "meta", status: "done" },
    { t: "0.6s", verb: "guide", detail: "horizontal · first word", kind: "mark", status: "done" },
    { t: "0.9s", verb: "rect", detail: "build-failed line", kind: "mark", status: "done" },
    { t: "1.2s", verb: "label", detail: "“Error”", kind: "mark", status: working ? "active" : "done" },
    { t: "1.4s", verb: "blur", detail: "email row", kind: "mark", status: working ? "pending" : "done" },
  ];
  return (
    <div
      style={{
        width: 288,
        flexShrink: 0,
        borderLeft: `0.5px solid ${T.inkRuleS}`,
        background: T.page,
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* header */}
      <div
        className="flex items-center gap-2 px-3"
        style={{ height: 26, borderBottom: `0.5px solid ${T.inkRuleS}`, background: T.chrome }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.22em]"
          style={{ fontSize: 8.5, color: T.inkFaint }}
        >
          · WORK THREAD
        </span>
        <span className="flex-1" />
        <span
          className="inline-block rounded-full"
          style={{
            width: 6,
            height: 6,
            background: working ? T.amber : T.inkFainter,
            boxShadow: working ? "0 0 5px rgba(196,125,28,0.6)" : "none",
            animation: working ? "threadpulse 1.2s ease-in-out infinite" : "none",
          }}
        />
        <span
          className="font-mono uppercase tracking-[0.16em]"
          style={{ fontSize: 8, color: working ? T.amberDeep : T.inkFainter }}
        >
          {working ? "live" : "done"}
        </span>
      </div>

      {/* thread body */}
      <div style={{ padding: "8px 0", flex: 1, overflow: "auto" }}>
        {entries.map((e, i) => (
          <ThreadRow
            key={i}
            entry={e}
            first={i === 0}
            last={i === entries.length - 1 && !working}
          />
        ))}
        {working && <ThreadCaretRow />}
      </div>

      {/* footer */}
      {working ? (
        <div
          className="flex items-center gap-2 px-3"
          style={{ height: 30, borderTop: `0.5px solid ${T.inkRuleS}`, background: T.chrome }}
        >
          <span
            className="inline-block rounded-full"
            style={{ width: 6, height: 6, background: T.amber, animation: "threadpulse 1.2s ease-in-out infinite" }}
          />
          <span className="font-display italic" style={{ fontSize: 11, color: T.inkMid }}>
            drawing pass 1…
          </span>
          <span className="flex-1" />
          <span className="font-mono uppercase tracking-[0.16em]" style={{ fontSize: 8, color: T.inkFainter }}>
            ⎋ stop
          </span>
        </div>
      ) : (
        <div
          className="flex items-center gap-2 px-3"
          style={{ height: 30, borderTop: `0.5px solid ${T.inkRuleS}`, background: T.chrome }}
        >
          <span
            className="font-mono font-semibold uppercase tracking-[0.16em]"
            style={{ fontSize: 8.5, color: T.amberDeep }}
          >
            pass 1
          </span>
          <span className="font-mono" style={{ fontSize: 9, color: T.inkFaint }}>
            4 marks · 1.4s
          </span>
          <span className="flex-1" />
          <button
            className="flex items-center gap-1"
            title="Undo the whole pass"
            style={{ height: 20, padding: "0 7px", borderRadius: 4, background: "transparent", border: `0.5px solid ${T.inkRule}`, color: T.inkMid }}
          >
            <span className="font-mono" style={{ fontSize: 10, lineHeight: 1 }}>↶</span>
            <span className="font-mono font-semibold uppercase tracking-[0.16em]" style={{ fontSize: 8 }}>undo</span>
            <span className="font-mono" style={{ fontSize: 8, opacity: 0.7 }}>⌘Z</span>
          </button>
        </div>
      )}
    </div>
  );
}

function ThreadRow({
  entry,
  first,
  last,
}: {
  entry: ThreadEntry;
  first: boolean;
  last: boolean;
}) {
  const { t, verb, detail, kind, status } = entry;
  const done = status === "done";
  const active = status === "active";
  const pending = status === "pending";
  const isMark = kind === "mark";
  const nodeColor = pending ? T.inkRule : isMark ? T.amber : T.inkFainter;
  return (
    <div
      className="relative flex items-center"
      style={{
        minHeight: 26,
        paddingLeft: 26,
        paddingRight: 12,
        gap: 7,
        opacity: pending ? 0.5 : 1,
      }}
    >
      {/* thread spine */}
      <span
        className="absolute"
        style={{
          left: 13,
          top: first ? "50%" : 0,
          bottom: last ? "50%" : 0,
          width: 1,
          background: T.inkRuleS,
        }}
      />
      {/* node */}
      <span
        className="absolute"
        style={{
          left: 13,
          top: "50%",
          width: isMark ? 7 : 5,
          height: isMark ? 7 : 5,
          transform: "translate(-50%, -50%)",
          borderRadius: 999,
          background: done || active ? nodeColor : "transparent",
          border: `1px solid ${nodeColor}`,
          boxShadow: active ? "0 0 0 3px rgba(196,125,28,0.18)" : "none",
          animation: active ? "threadpulse 1.1s ease-in-out infinite" : "none",
        }}
      />
      <span
        className="font-mono tabular-nums"
        style={{ fontSize: 8.5, color: T.inkFainter, width: 22, flexShrink: 0 }}
      >
        {t}
      </span>
      <span
        className="font-mono font-semibold"
        style={{
          fontSize: 10,
          color: active ? T.amberDeep : isMark ? T.ink : T.inkFaint,
          width: 34,
          flexShrink: 0,
        }}
      >
        {verb}
      </span>
      <span
        className="font-display italic truncate"
        style={{ fontSize: 10.5, color: active ? T.ink : T.inkFaint, minWidth: 0 }}
      >
        {detail}
      </span>
    </div>
  );
}

// The live tail of the thread while a pass is in flight — a blinking
// caret hanging off the spine, "the next line is being written."
function ThreadCaretRow() {
  return (
    <div
      className="relative flex items-center"
      style={{ minHeight: 22, paddingLeft: 26, paddingRight: 12 }}
    >
      <span
        className="absolute"
        style={{ left: 13, top: 0, bottom: "50%", width: 1, background: T.inkRuleS }}
      />
      <span
        style={{
          display: "inline-block",
          width: 1,
          height: 12,
          background: T.amber,
          animation: "promptcaret 1s steps(2) infinite",
        }}
      />
    </div>
  );
}

// ─── Speak Strip v2 ──────────────────────────────────────────────────
//
// Same three-element rhythm (Mic · Prompt · Run) plus a quieter Save,
// but the prompt lane is now stateful: idle shows the placeholder +
// caret; recording swaps it for the magnetic-tape waveform.

function SpeakStripV2({
  mode,
  placeholder,
  examples,
  scopeBadge,
  value,
}: {
  mode: StripMode;
  placeholder: string;
  examples: string[];
  scopeBadge?: string;
  value?: string;
}) {
  const recording = mode === "recording";
  const running = mode === "running";
  const laneBorder = recording ? "rgba(208,58,28,0.40)" : T.inkRule;
  return (
    <div
      style={{
        background: T.chrome,
        borderTop: `0.5px solid ${T.inkRuleS}`,
        padding: "8px 14px 10px 14px",
      }}
    >
      {/* Context row — TRY chips when idle, a LISTENING banner when hot */}
      {recording ? (
        <div className="flex items-center gap-2" style={{ marginBottom: 7 }}>
          <span
            className="inline-block rounded-full"
            style={{ width: 6, height: 6, background: T.alert }}
          />
          <span
            className="font-mono font-semibold uppercase tracking-[0.20em]"
            style={{ fontSize: 9, color: T.alert }}
          >
            · listening
          </span>
          <span
            className="font-display italic"
            style={{ fontSize: 10.5, color: T.inkFaint }}
          >
            tap the mic or press ↵ to stop · transcript drops into the prompt
          </span>
          <span className="flex-1" />
          <span
            className="font-mono uppercase tracking-[0.18em]"
            style={{ fontSize: 9, color: T.alert }}
          >
            rec
          </span>
        </div>
      ) : (
        examples.length > 0 && (
          <div
            className="flex items-center gap-2"
            style={{ flexWrap: "wrap", marginBottom: 7 }}
          >
            <span
              className="font-mono uppercase tracking-[0.20em]"
              style={{ fontSize: 9, color: T.inkFainter }}
            >
              · try
            </span>
            {examples.map((s) => (
              <span
                key={s}
                className="font-display italic"
                style={{
                  fontSize: 10.5,
                  color: T.inkFaint,
                  padding: "2px 8px",
                  border: `0.5px dashed ${T.inkRule}`,
                  borderRadius: 999,
                  background: T.pane,
                }}
              >
                {s}
              </span>
            ))}
            {scopeBadge && (
              <span
                className="ml-auto font-mono uppercase tracking-[0.18em]"
                style={{ fontSize: 9, color: T.inkFainter }}
              >
                {scopeBadge}
              </span>
            )}
          </div>
        )
      )}

      {/* Main row · Mic | Prompt/Waveform | Save | Run */}
      <div className="flex items-center" style={{ gap: 10 }}>
        <LevelMic recording={recording} />
        <div
          className="flex items-center"
          style={{
            flex: 1,
            minWidth: 0,
            background: T.pane,
            border: `0.5px solid ${laneBorder}`,
            borderRadius: 5,
            height: 34,
            boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset",
            overflow: "hidden",
          }}
        >
          {recording ? (
            <MagTapeWaveform />
          ) : (
            <PromptLane placeholder={placeholder} value={value} running={running} />
          )}
        </div>
        <SaveChip dimmed={recording || running} />
        <RunChip mode={mode} />
      </div>
    </div>
  );
}

function PromptLane({
  placeholder,
  value,
  running,
}: {
  placeholder: string;
  value?: string;
  running?: boolean;
}) {
  return (
    <div
      className="flex items-center gap-2"
      style={{ flex: 1, padding: "0 12px", opacity: running ? 0.6 : 1 }}
    >
      {value ? (
        <span className="font-display" style={{ fontSize: 13, color: T.ink }}>
          {value}
        </span>
      ) : (
        <>
          <span
            className="font-display italic"
            style={{ fontSize: 13, color: T.inkFainter }}
          >
            {placeholder}
          </span>
          <span
            style={{
              display: "inline-block",
              width: 1,
              height: 14,
              background: T.amber,
              animation: "promptcaret 1s steps(2) infinite",
            }}
          />
        </>
      )}
    </div>
  );
}

// Magnetic-tape waveform — the house voice aesthetic (VU bars + amber
// centerline + tape-head marker). Fixed bar heights so it renders
// identically on server + client (no hydration drift). Bars near the
// head warm to amber; the tail dims as "not yet recorded."
function MagTapeWaveform({ elapsed = "0:04" }: { elapsed?: string }) {
  const bars = [
    3, 6, 10, 7, 12, 8, 5, 9, 14, 10, 6, 11, 7, 4, 8, 12, 9, 6, 10, 5, 8, 13,
    7, 11, 6, 4, 8, 5, 7, 4, 6, 3,
  ];
  const headIndex = 23; // tape-head sits just past the last "recorded" bar
  return (
    <div
      className="flex items-center"
      style={{ flex: 1, gap: 8, padding: "0 12px", position: "relative" }}
    >
      <span
        className="font-mono tabular-nums"
        style={{ fontSize: 10, color: T.amberDeep }}
      >
        {elapsed}
      </span>
      <div
        className="relative flex items-center"
        style={{ flex: 1, height: 22, gap: 1.5, minWidth: 0 }}
      >
        {/* amber centerline */}
        <span
          className="absolute"
          style={{
            left: 0,
            right: 0,
            top: "50%",
            height: 1,
            background: T.amber,
            opacity: 0.5,
            transform: "translateY(-50%)",
          }}
        />
        {bars.map((h, i) => (
          <span
            key={i}
            style={{
              width: 2,
              height: h,
              borderRadius: 1,
              flexShrink: 0,
              background:
                i > headIndex ? T.inkRule : i > headIndex - 4 ? T.amber : T.inkMid,
              opacity: i > headIndex ? 0.4 : 1,
            }}
          />
        ))}
        {/* tape-head marker */}
        <span
          className="absolute"
          style={{
            left: `${(headIndex / bars.length) * 100}%`,
            top: -3,
            bottom: -3,
            width: 1.5,
            background: T.amberDeep,
          }}
        />
        <span
          className="absolute"
          style={{
            left: `${(headIndex / bars.length) * 100}%`,
            top: -7,
            width: 0,
            height: 0,
            borderLeft: "3px solid transparent",
            borderRight: "3px solid transparent",
            borderTop: `4px solid ${T.amberDeep}`,
            transform: "translateX(-50%)",
          }}
        />
      </div>
    </div>
  );
}

function LevelMic({ recording }: { recording?: boolean }) {
  return (
    <button
      className="relative flex items-center justify-center"
      title={recording ? "tap to stop" : "tap to record"}
      style={{
        width: 34,
        height: 34,
        borderRadius: "50%",
        flexShrink: 0,
        background: recording ? "rgba(208,58,28,0.14)" : T.amberFaint,
        border: `0.5px solid ${recording ? "rgba(208,58,28,0.45)" : T.amberSoft}`,
        color: recording ? T.alert : T.amberDeep,
        boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset",
      }}
    >
      {recording ? (
        <span style={{ width: 10, height: 10, borderRadius: 2, background: T.alert }} />
      ) : (
        <MicGlyph size={15} />
      )}
      {recording && (
        <span
          className="absolute"
          style={{
            inset: -3,
            borderRadius: "50%",
            border: "1px solid rgba(208,58,28,0.45)",
            animation: "recpulse 1.4s ease-out infinite",
          }}
        />
      )}
    </button>
  );
}

function SaveChip({ dimmed }: { dimmed?: boolean }) {
  return (
    <button
      className="flex items-center gap-1.5 px-3"
      style={{
        height: 34,
        borderRadius: 5,
        background: T.amberFaint,
        border: `0.5px solid ${T.amberSoft}`,
        color: T.amberDeep,
        opacity: dimmed ? 0.5 : 1,
        flexShrink: 0,
      }}
    >
      <span style={{ fontSize: 9.5 }}>⌘S</span>
      <span
        className="font-mono font-semibold uppercase tracking-[0.18em]"
        style={{ fontSize: 9 }}
      >
        save
      </span>
    </button>
  );
}

function RunChip({ mode }: { mode: StripMode }) {
  const running = mode === "running";
  const dim = mode !== "idle";
  return (
    <button
      className="flex items-center gap-1.5 px-4"
      style={{
        height: 34,
        borderRadius: 5,
        background: T.amber,
        color: "#fff",
        opacity: dim ? 0.5 : 1,
        flexShrink: 0,
      }}
    >
      <span
        className="font-mono font-semibold uppercase tracking-[0.20em]"
        style={{ fontSize: 9.5 }}
      >
        {running ? "running" : "run"}
      </span>
      {!running && <span style={{ fontSize: 9.5 }}>⌘↵</span>}
    </button>
  );
}

// ─── Level-up detail tiles ───────────────────────────────────────────
//
// The two new behaviors shown in their live states side-by-side: the
// intern mid-pass (streaming), and the composer mid-recording (waveform).

function LevelUpDetail() {
  return (
    <div className="flex gap-4" style={{ marginTop: 14 }}>
      <DetailTile
        eyebrow="show it working"
        title="The thread streams the run"
        caption="As the agent runs, the right rail writes a line per step — read the capture, plan the marks, then guide · rect · label · blur as each one lands. A live node pulses at the head; the next line is a blinking caret. You watch what it's doing, not a spinner that only says RUNNING."
      >
        <div
          style={{
            display: "flex",
            justifyContent: "center",
            background: T.rail,
            borderRadius: 5,
            padding: 14,
          }}
        >
          <div
            style={{
              border: `0.5px solid ${T.inkRule}`,
              borderRadius: 5,
              overflow: "hidden",
              boxShadow: "0 4px 14px rgba(0,0,0,0.08)",
            }}
          >
            <WorkThread mode="working" />
          </div>
        </div>
      </DetailTile>
      <DetailTile
        eyebrow="speak"
        title="The mic talks in magnetic tape"
        caption="Tap to record and the prompt lane becomes a tape transport — VU bars riding an amber centerline, a tape-head marking where you are. It reads as the machine hearing you, not a dead field waiting for keys."
      >
        <div
          style={{
            border: `0.5px solid ${T.inkRuleS}`,
            borderRadius: 5,
            overflow: "hidden",
          }}
        >
          <SpeakStripV2 mode="recording" placeholder="" examples={[]} />
        </div>
      </DetailTile>
    </div>
  );
}

// ─── Level-up vocabulary ─────────────────────────────────────────────

function LevelUpMarginalia() {
  const entries: [string, string][] = [
    ["Work Thread", "right rail · the agent's run, streamed log-style as it happens"],
    ["Thread Row", "one step · time · verb · detail · a node on the thread spine"],
    ["Thread Spine", "the vertical line + nodes · meta steps hollow · marks filled amber"],
    ["Live Node", "the pulsing head of the thread while the pass is in flight"],
    ["Pass", "one agent run · its rows are the steps it took"],
    ["Pass Summary", "thread footer when done · ‘pass 1 · 4 marks · 1.4s’"],
    ["Undo", "↶ / ⌘Z · walks back the whole pass · no accept/cancel gate"],
    ["Right Rail", "contextual · Work Thread during/after a run · Inspector on select"],
    ["Tape Waveform", "recording state of the prompt lane · VU bars + centerline + head"],
    ["Tape Head", "the marker on the waveform · where the recording is now"],
  ];
  return (
    <div
      style={{
        marginTop: 14,
        padding: "12px 16px",
        background: T.pane,
        border: `0.5px solid ${T.inkRuleS}`,
        borderRadius: 4,
      }}
    >
      <div className="flex items-baseline gap-3" style={{ marginBottom: 10 }}>
        <span
          className="font-mono font-semibold uppercase tracking-[0.24em]"
          style={{ fontSize: 9, color: T.amberDeep }}
        >
          · level up · names
        </span>
        <span className="font-display italic" style={{ fontSize: 11, color: T.inkFaint }}>
          the agent's run, streamed on the right · the mic speaks in tape — words for Swift + chat
        </span>
      </div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "150px 1fr",
          rowGap: 4,
          columnGap: 18,
        }}
      >
        {entries.map(([name, def]) => (
          <React.Fragment key={name}>
            <span
              className="font-mono font-semibold uppercase tracking-[0.16em]"
              style={{ fontSize: 10, color: T.amberDeep }}
            >
              {name}
            </span>
            <span
              className="font-display italic"
              style={{ fontSize: 12, color: T.inkMid, lineHeight: 1.45 }}
            >
              {def}
            </span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}
