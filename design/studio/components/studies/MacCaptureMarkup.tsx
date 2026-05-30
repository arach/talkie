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
  children,
}: {
  title: string;
  subtitle?: string;
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
        className="flex items-center gap-2 px-3"
        style={{
          height: 32,
          background: T.chrome,
          borderBottom: `0.5px solid ${T.inkRuleS}`,
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
