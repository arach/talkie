"use client";

/**
 * Mac Capture Markup · Speak Strip · REDESIGN
 * ===========================================
 *
 * Bottom band of the capture-markup window (ships as
 * CaptureMarkupPanelChrome.swift · CaptureMarkupInputBarView).
 *
 * Critique of the shipped bar:
 *   · the mic is a small circle marooned in the far-right corner next to
 *     RUN, with a wide empty field beside it — "weird oval", leftover UI.
 *   · "RUN ⌘↵" puts a raw keycap on the primary button.
 *   · the top band fights itself: "· TRY" chips on the left, the AGENT
 *     picker + "GLOBAL · WHOLE IMAGE" scope on the right, and a SEPARATE
 *     "· ATTACHED" row when a layer is selected. Three context zones.
 *
 * Reference: openscout's Comms composer (apps/macos · CommsWindow.swift).
 * Its composer is a bottom-aligned row of squared rounded-rect buttons —
 * mic · field · paperplane-send — over a `canvasLift` fill with a hairline
 * border, and ONE status line below (dictation status / "⏎ to send").
 * No bar waveform; recording just swaps the mic glyph + shows the status
 * line. We adopt that vocabulary.
 *
 * The redesign — three zones, each with one job:
 *
 *   ┌ IDENTITY LINE ───────────────────────────────────────────────┐
 *   │  agent ▸ GPT-5.4 · openai      scope ▸ whole image · pass 1 · │
 *   ├ COMPOSER (bottom-aligned row) ────────────────────────────────┤
 *   │  [ tell the agent what to mark up…        ]  [mic]  [ ▸send ] │
 *   ├ STATUS / FOOTER (one adaptive line) ──────────────────────────┤
 *   │  try  circle the error · blur the email · arrow to line       │
 *   └───────────────────────────────────────────────────────────────┘
 *
 * IDENTITY LINE — the coding-agent "where am I running" header. Left =
 *   the agent (model · provider) picker. Right = the run target (scope,
 *   the "branch" analog) + pass / save freshness.
 * COMPOSER — field flexes; mic + send are squared buttons on the right
 *   (per direction: mic on the right, hugging the send).
 * STATUS — context-adaptive single line: try-examples (idle) / attachment
 *   (layer selected) / "listening…" (recording). Never stacked.
 *
 * Palette: canonical warm amber (SCOPE.amber #C47D1C). The shipped Swift
 * overrides its "amber" constants to BLUE (rgb 0.31,0.49,1.0) — that's
 * the "studio doesn't match the app" gap; the port brings Swift back.
 */

import React from "react";

import { SCOPE } from "@/lib/scope-tokens";

const T = {
  page:       SCOPE.canvas,
  pane:       SCOPE.pane,
  paneLift:   SCOPE.paneLifted,
  chrome:     SCOPE.chrome,
  canvasAlt:  SCOPE.canvasAlt,
  rail:       SCOPE.rail,
  ink:        SCOPE.ink,
  inkMid:     SCOPE.inkMid,
  inkFaint:   SCOPE.inkFaint,
  inkFainter: SCOPE.inkFainter,
  inkRule:    SCOPE.rule,
  inkRuleS:   SCOPE.ruleSubtle,
  edge:       SCOPE.edge,
  amber:      SCOPE.amber,
  amberDeep:  SCOPE.amberDeep,
  amberFaint: SCOPE.amberFaint,
  amberSoft:  SCOPE.amberSoft,
  alert:      SCOPE.alert,
  white:      SCOPE.white,
};

// ─── Glyphs ──────────────────────────────────────────────────────────
// Tight line-art SVGs (no emoji), stroke = currentColor. SF-symbol
// equivalents of openscout's mic.fill / stop.fill / paperplane.fill.

function MicGlyph() {
  return (
    <svg width="15" height="15" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth={1.4} strokeLinecap="round">
      <rect x="5" y="2" width="4" height="6.5" rx="2" />
      <path d="M3.5 7.5 A3.5 3.5 0 0 0 10.5 7.5" />
      <line x1="7" y1="10.5" x2="7" y2="12" />
    </svg>
  );
}

function StopGlyph() {
  return (
    <svg width="13" height="13" viewBox="0 0 14 14" fill="currentColor" aria-hidden>
      <rect x="3.5" y="3.5" width="7" height="7" rx="1.5" />
    </svg>
  );
}

function SendGlyph({ size = 15 }: { size?: number }) {
  // Solid right-pointing paper plane — nose at the right edge, tail notch
  // on the left so the send direction reads unambiguously.
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="currentColor" aria-hidden>
      <path d="M1.6 2 L12.5 7 L1.6 12 L3.6 7 Z" />
    </svg>
  );
}

function AttachGlyph() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth={1.4} strokeLinecap="round" strokeLinejoin="round">
      <path d="M9.5 4.5 L5 9 a1.8 1.8 0 0 0 2.5 2.5 L11.5 7 a3.2 3.2 0 0 0 -4.5 -4.5 L3 6.5" />
    </svg>
  );
}

// ─── Atoms ───────────────────────────────────────────────────────────

function Mono({
  children,
  color = T.inkFaint,
  size = 9,
  track = 0.18,
  weight = 600,
}: {
  children: React.ReactNode;
  color?: string;
  size?: number;
  track?: number;
  weight?: number;
}) {
  return (
    <span
      className="font-mono uppercase"
      style={{ fontSize: size, letterSpacing: `${track}em`, color, fontWeight: weight, lineHeight: 1 }}
    >
      {children}
    </span>
  );
}

/** the agent picker rendered as a coding-agent identity badge */
function AgentBadge() {
  return (
    <button
      className="flex items-center"
      style={{ gap: 7, background: "transparent", border: "none", padding: 0, cursor: "pointer" }}
    >
      <Mono color={T.inkFainter} track={0.2}>agent</Mono>
      <span style={{ color: T.inkFainter, fontSize: 9 }}>▸</span>
      <span style={{ width: 5, height: 5, borderRadius: 999, background: T.amber, boxShadow: `0 0 0 2px ${T.amberFaint}` }} />
      <Mono color={T.ink} track={0.04} size={10}>GPT-5.4</Mono>
      <Mono color={T.inkFaint} track={0.12} size={9} weight={500}>· openai</Mono>
      <span style={{ color: T.inkFainter, fontSize: 8, marginLeft: 1 }}>▾</span>
    </button>
  );
}

/** run-target / state cluster — scope is the "branch", pass/save is "where it's running" */
function RunState({ scope = "whole image", selected, pass = 1, saved = "saved 4s" }: {
  scope?: string;
  selected?: { id: string; label: string };
  pass?: number;
  saved?: string;
}) {
  return (
    <div className="flex items-center" style={{ gap: 8 }}>
      <Mono color={T.inkFainter} track={0.2}>scope</Mono>
      <span style={{ color: T.inkFainter, fontSize: 9 }}>▸</span>
      {selected ? (
        <span className="flex items-center" style={{ gap: 5 }}>
          <Mono color={T.amberDeep} track={0.06} size={9.5}>↳ {selected.id}</Mono>
          <span className="font-display italic" style={{ fontSize: 11, color: T.amberDeep }}>{selected.label}</span>
        </span>
      ) : (
        <Mono color={T.inkFaint} track={0.12} size={9.5} weight={500}>{scope}</Mono>
      )}
      <span style={{ width: 1, height: 9, background: T.inkRuleS }} />
      <Mono color={T.inkFainter} track={0.14}>pass {pass}</Mono>
      <span className="flex items-center" style={{ gap: 4 }}>
        <span style={{ width: 4, height: 4, borderRadius: 999, background: T.amber }} />
        <Mono color={T.inkFaint} track={0.12} weight={500}>{saved}</Mono>
      </span>
    </div>
  );
}

// ─── Composer parts ──────────────────────────────────────────────────
// Squared rounded-rect buttons (r8) over a canvasLift fill + hairline
// border, mirroring openscout's Comms composer.

const BTN = 38;
const RADIUS = 8;

/** ghost icon button that rides inside the field's trailing edge */
function InFieldIcon({ children, active, title }: { children: React.ReactNode; active?: boolean; title?: string }) {
  return (
    <button
      className="flex items-center justify-center"
      style={{
        width: 26,
        height: 26,
        flexShrink: 0,
        borderRadius: 6,
        background: active ? "rgba(196,58,28,0.12)" : "transparent",
        border: "none",
        color: active ? T.alert : T.inkFainter,
        cursor: "pointer",
      }}
      title={title}
    >
      {children}
    </button>
  );
}

/** field with attach + mic riding inside the trailing edge (openscout desktop) */
function FieldWithControls({ value, recording }: { value?: string; recording?: boolean }) {
  const placeholder = recording ? "listening…" : "tell the agent what to mark up…";
  return (
    <div
      className="flex items-center"
      style={{
        flex: 1,
        minWidth: 0,
        minHeight: BTN,
        padding: "0 6px 0 14px",
        gap: 2,
        borderRadius: RADIUS,
        background: T.white,
        border: `0.5px solid ${recording ? "rgba(196,58,28,0.45)" : value ? T.amberSoft : T.inkRule}`,
        boxShadow: "0 1px 0 rgba(255,255,255,0.55) inset",
      }}
    >
      <div style={{ flex: 1, minWidth: 0 }}>
        {value ? (
          <span className="font-display" style={{ fontSize: 13, color: T.ink }}>
            {value}
            <span style={{ display: "inline-block", width: 1, height: 14, marginLeft: 1, background: T.amber, verticalAlign: "text-bottom" }} />
          </span>
        ) : (
          <span className="font-display italic" style={{ fontSize: 13, color: recording ? T.alert : T.inkFainter }}>{placeholder}</span>
        )}
      </div>
      <InFieldIcon title="Attach reference">
        <AttachGlyph />
      </InFieldIcon>
      <InFieldIcon active={recording} title={recording ? "tap to stop" : "tap to record · tap again to stop"}>
        {recording ? <StopGlyph /> : <MicGlyph />}
      </InFieldIcon>
    </div>
  );
}

/** send button — squared, amber-filled paperplane; faint when empty */
function SendButton({ enabled }: { enabled?: boolean }) {
  return (
    <button
      className="flex items-center justify-center"
      style={{
        width: BTN,
        height: BTN,
        flexShrink: 0,
        borderRadius: RADIUS,
        background: enabled ? T.amber : T.pane,
        border: `0.5px solid ${enabled ? T.amber : T.inkRule}`,
        color: enabled ? T.white : T.inkFainter,
        boxShadow: enabled ? "0 1px 0 rgba(255,255,255,0.28) inset" : "none",
        cursor: enabled ? "pointer" : "default",
      }}
      title="Run · ⌘↵"
    >
      <SendGlyph size={15} />
    </button>
  );
}

// ─── Footer / status chips ───────────────────────────────────────────

function TryChip({ children }: { children: React.ReactNode }) {
  return (
    <span className="flex items-center" style={{ height: 20, padding: "0 9px", borderRadius: 999, border: `0.5px dashed ${T.inkRule}`, background: T.pane }}>
      <span className="font-display" style={{ fontSize: 11, color: T.inkFaint }}>{children}</span>
    </span>
  );
}

function AttachChip({ id, label }: { id: string; label: string }) {
  return (
    <span className="flex items-center" style={{ height: 22, padding: "0 6px 0 9px", gap: 6, borderRadius: 999, background: T.amberFaint, border: `0.5px solid ${T.amberSoft}` }}>
      <Mono color={T.amberDeep} size={9} track={0.08}>↳ {id}</Mono>
      <span className="font-display italic" style={{ fontSize: 11, color: T.amberDeep }}>{label}</span>
      <span style={{ color: T.amberDeep, opacity: 0.6, fontSize: 12, marginLeft: 1 }}>×</span>
    </span>
  );
}

// ─── Band ────────────────────────────────────────────────────────────

type BandState = "idle" | "selected" | "recording" | "drafting";

function Band({ state = "idle" }: { state?: BandState }) {
  const recording = state === "recording";
  const draftValue =
    state === "selected" ? "make the ring red" : state === "drafting" ? "circle the failed line and label it" : undefined;

  return (
    <div style={{ background: T.canvasAlt, borderTop: `0.5px solid ${T.inkRule}`, padding: "12px 16px 13px", display: "flex", flexDirection: "column", gap: 10 }}>
      {/* IDENTITY LINE */}
      <div className="flex items-center justify-between">
        <AgentBadge />
        <RunState selected={state === "selected" ? { id: "L2", label: "the ring" } : undefined} />
      </div>

      {/* COMPOSER — field flexes with attach + mic inside (right); amber send outside */}
      <div className="flex items-end" style={{ gap: 8 }}>
        <FieldWithControls value={recording ? undefined : draftValue} recording={recording} />
        <SendButton enabled={!recording && (state === "selected" || state === "drafting")} />
      </div>

      {/* STATUS / FOOTER — one adaptive line */}
      {recording ? (
        <div className="flex items-center" style={{ gap: 7, paddingTop: 1 }}>
          <span style={{ width: 6, height: 6, borderRadius: 999, background: T.alert }} />
          <Mono color={T.alert} track={0.16} weight={600}>listening · 0:07 · tap mic to stop</Mono>
        </div>
      ) : state === "selected" ? (
        <div className="flex items-center" style={{ gap: 9, paddingTop: 1 }}>
          <Mono color={T.inkFainter} track={0.2}>attached</Mono>
          <AttachChip id="L2" label="the ring" />
        </div>
      ) : state === "drafting" ? (
        <div className="flex items-center justify-end" style={{ paddingTop: 1 }}>
          <Mono color={T.inkFainter} track={0.12} weight={500}>⏎ send · ⇧⏎ newline</Mono>
        </div>
      ) : (
        <div className="flex items-center" style={{ gap: 8, paddingTop: 1 }}>
          <Mono color={T.inkFainter} track={0.2}>try</Mono>
          <TryChip>circle the error and label it</TryChip>
          <TryChip>blur the email</TryChip>
          <TryChip>arrow to the failed line</TryChip>
        </div>
      )}
    </div>
  );
}

// ─── Studio composition ──────────────────────────────────────────────

function Caption({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ padding: "0 2px 8px" }}>
      <Mono color={T.inkFainter} track={0.22}>{children}</Mono>
    </div>
  );
}

function Frame({ children, width = 720 }: { children: React.ReactNode; width?: number }) {
  return (
    <div style={{ width, borderRadius: 12, overflow: "hidden", border: `0.5px solid ${T.edge}`, boxShadow: "0 8px 28px rgba(0,0,0,0.10)", background: T.rail }}>
      <div style={{ height: 64, background: T.rail, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Mono color={T.inkFainter} track={0.24}>⋯ canvas ⋯</Mono>
      </div>
      {children}
    </div>
  );
}

export function MacCaptureMarkupStripRedesign() {
  return (
    <div className="flex flex-col" style={{ gap: 34, alignItems: "flex-start", padding: "8px 0" }}>
      <div>
        <Caption>1 · idle · try-examples footer · send dim (empty prompt)</Caption>
        <Frame><Band state="idle" /></Frame>
      </div>
      <div>
        <Caption>2 · drafting · field active · send lit · "⏎ send" hint</Caption>
        <Frame><Band state="drafting" /></Frame>
      </div>
      <div>
        <Caption>3 · layer selected · scope flips to ↳ L2 · footer becomes the attachment</Caption>
        <Frame><Band state="selected" /></Frame>
      </div>
      <div>
        <Caption>4 · recording · mic → stop · "listening…" in field · status line (openscout-simple, no VU bars)</Caption>
        <Frame><Band state="recording" /></Frame>
      </div>
      <NamesMarginalia />
    </div>
  );
}

// ─── Names · marginalia ──────────────────────────────────────────────

function NamesMarginalia() {
  const rows: [string, string][] = [
    ["Speak Strip", "bottom band · identity line + composer + status"],
    ["Identity Line", "coding-agent header · Agent Badge (left) · Run State (right)"],
    ["Agent Badge", "the model · provider picker · 'agent ▸ GPT-5.4 · openai'"],
    ["Run State", "what Run targets + freshness · 'scope ▸ … · pass N · saved Xs'"],
    ["Scope", "the run target — whole image, or ↳ L2 when a layer is selected (the 'branch' analog)"],
    ["Composer", "field flexes · attach + mic ride inside the trailing edge · amber send outside (openscout desktop)"],
    ["Attach", "paperclip · pull a reference image into the prompt"],
    ["Mic", "in-field tap-to-toggle · mic glyph / stop while recording"],
    ["Send", "amber paperplane square · dim when the prompt is empty · ⌘↵"],
    ["Status", "ONE adaptive line · try-examples / attachment / listening / ⏎-hint — never stacked"],
    ["Attachment", "the selected layer chip · lives in the status line, not the field"],
  ];
  return (
    <div style={{ width: 720, marginTop: 6 }}>
      <Caption>names · marginalia</Caption>
      <div style={{ border: `0.5px solid ${T.inkRuleS}`, borderRadius: 8, overflow: "hidden", background: T.pane }}>
        {rows.map(([name, desc], i) => (
          <div key={name} className="flex items-baseline" style={{ gap: 14, padding: "7px 12px", borderTop: i === 0 ? "none" : `0.5px solid ${T.inkRuleS}` }}>
            <div style={{ width: 116, flexShrink: 0 }}>
              <Mono color={T.amberDeep} track={0.08} size={9.5}>{name}</Mono>
            </div>
            <span className="font-display" style={{ fontSize: 12, color: T.inkFaint, lineHeight: 1.4 }}>{desc}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
