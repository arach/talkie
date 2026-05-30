"use client";

/**
 * Mac Command Palette — reimagined.
 *
 * Premise (commission 2026-05-24):
 *   The shipped palette is two surfaces fighting for the same job —
 *     · CommandPaletteView      (Raycast-style text palette, ⌘⇧K)
 *     · VoiceCommandOverlay     (separate particle modal, ⌘⇧V)
 *   Per the markup study just landed: voice and text are not modes,
 *   they're equal-weight affordances on the same input. Reimagining
 *   collapses them into ONE palette, where text and voice share the
 *   same row and target the same command list.
 *
 * Three reimagining moves —
 *   1. ONE SURFACE. The mic lives inside the palette input row. Hold
 *      to speak; release to commit. No second modal. The particle viz
 *      reduces to a thin waveform/bars strip that sits inside the row
 *      so it never steals the result list's space.
 *   2. GROUPED RESULTS. The current list is a flat ScrollView with
 *      every command jumbled (Navigation, Settings, View, Help, Debug
 *      interleaved). Group by section with small mono headers. The
 *      eye lands on the kind of command, then the command.
 *   3. SCOPE CHIP. When opened from a specific context (a Recording,
 *      a Note, the Canvas), a chip rides in the input next to the
 *      cursor — same shape as the markup study's selection chip.
 *      Top of the list pins a "Here" group with context-specific
 *      actions ("Open in editor", "Copy link", "Share…").
 *
 * Visual family: dark glass, but adopt Talkie's AMBER agent-bay
 * treatment (the same dark surface the agent transcript uses in
 * MacCaptureMarkup Framing B). Not generic Raycast — Talkie agent
 * voice. Amber accent replaces system .accentColor.
 *
 * Architecture: native SwiftUI sheet, same NSPanel pattern as today.
 * No webview here. The intent recognition + audio capture stays
 * VoiceCommandService.shared. The palette consumes an `inputMode`
 * (typing | speaking) and a `scope?` from whatever invoked it.
 */

import React from "react";

import { SCOPE } from "@/lib/scope-tokens";

// ─── Tokens — page (PEARL/FROST) and palette (AMBER glass) ───────────

const T = {
  page:        SCOPE.canvas,
  pane:        SCOPE.pane,
  chrome:      SCOPE.chrome,
  ink:         SCOPE.ink,
  inkMid:      SCOPE.inkMid,
  inkFaint:    SCOPE.inkFaint,
  inkFainter:  SCOPE.inkFainter,
  inkRule:     SCOPE.rule,
  inkRuleS:    SCOPE.ruleSubtle,
  amber:       SCOPE.amber,
  amberFaint:  SCOPE.amberFaint,
  amberSoft:   SCOPE.amberSoft,
  alert:       SCOPE.alert,
};

// Palette substrate — PORCELAIN family. Light cool gray with deep
// amber accents that carry against the light. Earlier draft was dark
// glass (AMBER scheme); operator pivot 2026-05-24 — "should feel
// sharper, lighter." Light reads as instrument panel, not modal void.
//
// One inset stays dark: the TapeWaveform substrate, where the
// magnetic-tape vibe wants a deck-black background to push the amber
// bars. That's a localized exception — every other surface is light.
const P = {
  bg:           "#EAEEF1",          // PORCELAIN base panel
  bgRaised:     "#F2F5F7",          // search field, footer, input bar
  bgSunk:       "#DFE3E8",          // section header strip
  ink:          "#232423",
  inkFaint:     "rgba(35,36,35,0.62)",
  inkFainter:   "rgba(35,36,35,0.40)",
  inkSubtle:    "rgba(35,36,35,0.24)",
  amber:        "#C47D1C",          // deeper amber for light substrate
  amberFaint:   "rgba(196,125,28,0.10)",
  amberSoft:    "rgba(196,125,28,0.28)",
  amberDeep:    "#7A521A",
  rec:          "#C43A1C",
  edge:         "rgba(35,36,35,0.10)",
  edgeStrong:   "rgba(35,36,35,0.22)",
  rule:         "rgba(35,36,35,0.10)",
  ruleStrong:   "rgba(35,36,35,0.18)",
  // VU-meter inset for the speaking-state waveform — explicitly dark
  // so the mag-tape readout reads as a deck window inside the panel.
  tapeBg:       "#1A1F22",
  tapeRule:     "rgba(255,255,255,0.06)",
};

// ─── Composition root ────────────────────────────────────────────────

export function MacCommandPalette() {
  return (
    <div style={{ width: 1180, background: T.page }} className="flex flex-col">
      <StudyHeader />
      <SectionBreak
        label="1 · resting"
        hint="palette open · grouped list · mic ready · text focused"
      />
      <RestingState />
      <SectionBreak
        label="2 · speaking"
        hint="mic held · transcript inline · intent highlighted in the list"
      />
      <SpeakingState />
      <SectionBreak
        label="3 · in context"
        hint="opened from a Recording · scope chip rides the input · Here pinned"
      />
      <ContextState />
      <SectionBreak
        label="donor · before"
        hint="two surfaces today · text palette + separate voice overlay"
      />
      <DonorStrip />
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
          · COMMAND PALETTE · voice + text · one surface
        </span>
        <span className="font-display italic" style={{ color: T.inkFaint, fontSize: 13 }}>
          collapses the Raycast palette + voice overlay into a single sheet
        </span>
        <div className="ml-auto flex items-center gap-3">
          <Chip label="REIMAGINE" tone="ink" />
          <span
            className="font-mono uppercase tracking-[0.18em]"
            style={{ color: T.inkFaint, fontSize: 10 }}
          >
            replaces · CommandPaletteView + VoiceCommandOverlay
          </span>
        </div>
      </div>
      <h2
        className="font-display tracking-tight"
        style={{ color: T.ink, fontSize: 30, fontWeight: 500, lineHeight: 1, marginTop: 8 }}
      >
        Command Palette
      </h2>
      <p
        className="font-display italic"
        style={{ color: T.inkFaint, fontSize: 13, lineHeight: 1.6, marginTop: 10, maxWidth: 820 }}
      >
        Today's palette is a Raycast clone and the voice overlay is its
        own modal — two surfaces for the same job. The reimagining puts
        the mic inside the palette row, groups the results, and lets a
        scope chip ride the input when you opened the palette from
        somewhere specific. Dark glass stays — but in Talkie's amber
        agent-bay treatment, not generic Raycast.
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
        Architecturally unchanged: native SwiftUI sheet, NSPanel overlay,
        VoiceCommandService.shared for audio + intent. The reimagining
        is composition, not infrastructure — collapse two surfaces into
        one, group the results, let context ride the input.
      </p>
    </div>
  );
}

// ─── State 1 · Resting ───────────────────────────────────────────────

function RestingState() {
  return (
    <Surface>
      <DesktopBackdrop height={580}>
        <PaletteWindow>
          <InputBar
            placeholder="Search commands · or hold ♪ to speak"
            text=""
          />
          <Divider />
          <CommandList highlightId={DEFAULT_HIGHLIGHT} />
          <KeyHintsFooter />
        </PaletteWindow>
      </DesktopBackdrop>
      <CaptionStrip
        text="The palette opens centered, upper third, with the text cursor focused and the mic primed. Results are grouped by section so the eye lands on the kind first; the first row of the first group is selected by default. ⌘⇧K toggles the surface; ⎋ closes."
      />
    </Surface>
  );
}

// ─── State 2 · Speaking ──────────────────────────────────────────────

function SpeakingState() {
  return (
    <Surface>
      <DesktopBackdrop height={580}>
        <PaletteWindow>
          <InputBar
            placeholder=""
            text="go to dictations"
            listening
          />
          <Divider />
          <VoiceIntentBanner
            intent="Go to Dictations"
            section="Navigation"
            confidence={0.91}
          />
          <CommandList highlightId="navigation-go-to-dictations" subdued />
          <KeyHintsFooter mode="speaking" />
        </PaletteWindow>
      </DesktopBackdrop>
      <CaptionStrip
        text="Mic held. The waveform strip drops into the row beneath the input; the transcript fills the field as you speak. Best-guess intent pins above the list as a banner with confidence — release the mic to auto-commit if confidence is high, or ↵ to confirm. No second modal — the same surface handles both modalities."
      />
    </Surface>
  );
}

// ─── State 3 · In context (scope chip) ───────────────────────────────

function ContextState() {
  return (
    <Surface>
      <DesktopBackdrop height={580}>
        <PaletteWindow>
          <InputBar
            placeholder="Search · or speak — scoped to this recording"
            text=""
            scope={{ kind: "Recording", label: "Q1 plan · 12:42" }}
          />
          <Divider />
          <ScopedHereGroup />
          <CommandList highlightId="here-open-editor" extraDimmed />
          <KeyHintsFooter />
        </PaletteWindow>
      </DesktopBackdrop>
      <CaptionStrip
        text="Opened with ⌘⇧K while viewing a recording. A scope chip rides the input — same shape as the markup study's selection chip — and a HERE group pins context-specific actions at the top: open in editor, copy link, share, delete. Below it, the rest of the palette is unchanged, dimmed slightly so the scoped actions read first."
      />
    </Surface>
  );
}

// ─── Donor strip · two surfaces today ────────────────────────────────

function DonorStrip() {
  return (
    <Surface>
      <div className="flex gap-4">
        <DonorTile
          eyebrow="CommandPaletteView.swift"
          title="The text palette today"
          caption="Raycast-style. Hero search; flat list; system .accentColor highlight; two-line rows with icon, title, subtitle, shortcut chip. Solid bones; the issue is family fit + flat grouping."
        >
          <DonorPalette />
        </DonorTile>
        <DonorTile
          eyebrow="VoiceCommandOverlay.swift"
          title="The voice overlay today"
          caption="Separate ⌘⇧V modal. Particle visualization, state machine (idle → recording → processing → result → navigating). Beautiful particles — but a second surface for a sibling job. Reimagining folds it into the palette row."
        >
          <DonorVoiceOverlay />
        </DonorTile>
      </div>
      <CaptionStrip
        text="Two surfaces, two ⌘shortcuts, two state machines. The donor is solid; the move is consolidation."
      />
    </Surface>
  );
}

// ─── The palette window shell ────────────────────────────────────────

function PaletteWindow({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="relative overflow-hidden"
      style={{
        width: 600,
        background: P.bg,
        borderRadius: 14,
        border: `0.5px solid ${P.ruleStrong}`,
        boxShadow:
          "0 18px 42px -8px rgba(0,0,0,0.22), 0 6px 14px -2px rgba(0,0,0,0.10)",
      }}
    >
      {/* Amber bay-tint strip across the very top — deeper amber on
          the porcelain substrate so it carries without the dark-glass
          assist it used to lean on. */}
      <div
        className="flex items-center gap-2 px-3"
        style={{
          height: 26,
          background: "rgba(196,125,28,0.10)",
          borderBottom: `0.5px solid ${P.rule}`,
        }}
      >
        <span
          aria-hidden
          className="inline-block h-1.5 w-1.5 rounded-full"
          style={{ background: P.amber, boxShadow: `0 0 4px ${P.amberSoft}` }}
        />
        <span
          className="font-mono font-semibold uppercase tracking-[0.22em]"
          style={{ fontSize: 9, color: P.amberDeep }}
        >
          · PALETTE · cmd ⇧ K
        </span>
        <span className="ml-auto font-mono uppercase tracking-[0.18em]" style={{ fontSize: 8.5, color: P.inkFainter }}>
          v2 · concept
        </span>
      </div>
      {children}
    </div>
  );
}

function Divider() {
  return <div style={{ height: 0.5, background: P.rule }} />;
}

// ─── Input bar (mic + scope chip + text + state) ─────────────────────

function InputBar({
  placeholder,
  text,
  listening,
  scope,
}: {
  placeholder: string;
  text: string;
  listening?: boolean;
  scope?: { kind: string; label: string };
}) {
  const hasText = text.length > 0;
  return (
    <div
      className="flex flex-col"
      style={{
        background: P.bgRaised,
      }}
    >
      {/* Voice command row — mic + scope/transcript + state. The
          waveform tape strip lives directly beneath, sharing this bg,
          so the two read as one zone: the "voice command area." */}
      <div className="flex items-stretch">
        <button
          className="flex items-center gap-1.5 px-3.5"
          title="Hold to speak"
          style={{
            background: listening ? P.amber : P.amberFaint,
            color: listening ? "#FFFFFF" : P.amberDeep,
            borderRight: `0.5px solid ${P.rule}`,
          }}
        >
          <span style={{ fontSize: 13, lineHeight: 1 }}>♪</span>
          <span
            className="font-mono font-semibold uppercase tracking-[0.16em]"
            style={{ fontSize: 9 }}
          >
            {listening ? "listening" : "hold"}
          </span>
        </button>
        <div className="flex items-center gap-3 flex-1 px-4" style={{ minHeight: 52 }}>
          {scope && <ScopeChip kind={scope.kind} label={scope.label} />}
          <span
            className="font-mono"
            style={{ fontSize: 13, color: P.inkFainter, lineHeight: 1 }}
          >
            ⌕
          </span>
          {hasText ? (
            <span
              className="font-display"
              style={{
                fontSize: 14,
                color: listening ? P.amberDeep : P.ink,
                fontWeight: 400,
                letterSpacing: "-0.005em",
              }}
            >
              {text}
            </span>
          ) : (
            <span
              className="font-display italic"
              style={{ fontSize: 13.5, color: P.inkFainter, fontWeight: 300 }}
            >
              {placeholder}
            </span>
          )}
          <span
            style={{
              display: "inline-block",
              width: 1,
              height: 14,
              background: P.amber,
              animation: "palettecaret 1s steps(2) infinite",
            }}
          />
        </div>
        <div className="flex items-center px-4">
          {listening ? (
            <span
              className="font-mono font-semibold uppercase tracking-[0.18em]"
              style={{ fontSize: 9, color: P.rec, lineHeight: 1 }}
            >
              REC · 0:03
            </span>
          ) : hasText ? (
            <span
              className="font-mono uppercase tracking-[0.18em]"
              style={{ fontSize: 9, color: P.inkFainter }}
            >
              7 results
            </span>
          ) : (
            <span
              className="font-mono uppercase tracking-[0.18em]"
              style={{ fontSize: 9, color: P.inkSubtle }}
            >
              all
            </span>
          )}
        </div>
      </div>
      {/* Mag-tape waveform — only visible when listening. Lives inside
          the InputBar shell so it reads as part of the voice command
          area, not a separate row. */}
      {listening && <TapeWaveform />}
      <style jsx>{`
        @keyframes palettecaret {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0; }
        }
      `}</style>
    </div>
  );
}

function ScopeChip({ kind, label }: { kind: string; label: string }) {
  return (
    <span
      className="flex items-center gap-1.5"
      style={{
        height: 22,
        padding: "0 7px",
        background: P.amberFaint,
        border: `0.5px solid ${P.amberSoft}`,
        borderRadius: 3,
        color: P.amberDeep,
      }}
    >
      <span className="font-mono" style={{ fontSize: 9.5 }}>↳</span>
      <span
        className="font-mono font-semibold uppercase tracking-[0.16em]"
        style={{ fontSize: 8.5 }}
      >
        {kind}
      </span>
      <span
        className="font-display italic"
        style={{ fontSize: 10.5, color: P.amberDeep, opacity: 0.85, fontWeight: 300 }}
      >
        {label}
      </span>
      <span style={{ fontSize: 10, opacity: 0.55, marginLeft: 1 }}>×</span>
    </span>
  );
}

// ─── Mag-tape waveform · lives inside the voice command area ─────────
//
// VU-style symmetric bars growing both up and down from an amber tape-
// track centerline; tape-head triangle on the right marks the current
// position. Shares the InputBar's bgRaised so it reads as part of the
// voice command zone, not a separate strip beneath it. A subtle
// reel-scroll animation gives the bars a slow rightward drift, like
// the head is reading tape that's spooling past it.

function TapeWaveform() {
  // Frozen waveform-ish data. In production this is audio-driven
  // (VoiceCommandService.audioLevel polled at 30fps, decimated into
  // ~50 bars over a ~3s window). Here we just paint a static rhythm
  // that reads as recorded voice.
  const bars = [
    0.18, 0.32, 0.51, 0.74, 0.92, 0.81, 0.62, 0.45, 0.38, 0.52,
    0.71, 0.88, 0.95, 0.79, 0.56, 0.34, 0.22, 0.31, 0.48, 0.66,
    0.82, 0.93, 0.85, 0.64, 0.42, 0.28, 0.36, 0.55, 0.74, 0.86,
    0.92, 0.78, 0.58, 0.38, 0.26, 0.34, 0.52, 0.71, 0.84, 0.69,
    0.48, 0.32, 0.24, 0.30, 0.46, 0.64, 0.78, 0.62, 0.42, 0.28,
  ];
  return (
    <div
      className="relative"
      style={{
        height: 44,
        background: P.tapeBg,
        borderTop: `0.5px solid ${P.rule}`,
        overflow: "hidden",
      }}
    >
      {/* Tape-track centerline — amber rule the bars grow from. */}
      <div
        className="absolute left-0 right-0 pointer-events-none"
        style={{
          top: "50%",
          height: 0.5,
          background: "rgba(232,154,60,0.40)",
          transform: "translateY(-0.5px)",
          opacity: 0.75,
        }}
      />
      {/* Bars — items-center makes them grow symmetrically up + down. */}
      <div
        className="absolute flex items-center"
        style={{
          left: 16,
          right: 56,
          top: 0,
          bottom: 0,
          gap: 2,
          animation: "tapescroll 3.2s linear infinite",
          willChange: "transform",
        }}
      >
        {bars.map((h, i) => (
          <span
            key={i}
            className="inline-block"
            style={{
              flex: "1 1 0%",
              minWidth: 2,
              maxWidth: 4,
              height: `${Math.max(4, h * 30)}px`,
              background: `rgba(232,154,60,${0.50 + h * 0.40})`,
              borderRadius: 1,
            }}
          />
        ))}
      </div>
      {/* Tape-head triangle — the read head, fixed at the right edge.
          Uses the brighter dark-substrate amber so it carries against
          the inset deck-black, not the porcelain deep-amber. */}
      <span
        className="absolute pointer-events-none"
        aria-hidden
        style={{
          right: 28,
          top: "50%",
          transform: "translateY(-50%)",
          width: 0,
          height: 0,
          borderTop: "5px solid transparent",
          borderBottom: "5px solid transparent",
          borderLeft: `7px solid #E89A3C`,
          filter: "drop-shadow(0 0 4px rgba(232,154,60,0.7))",
        }}
      />
      {/* Frame counter — tiny mono readout, reel position vibe. */}
      <span
        className="absolute font-mono font-semibold"
        style={{
          right: 10,
          top: "50%",
          transform: "translateY(-50%)",
          fontSize: 9,
          letterSpacing: "0.06em",
          color: "#E89A3C",
        }}
      >
        00:03
      </span>
      <style jsx>{`
        @keyframes tapescroll {
          0%   { transform: translateX(0); }
          100% { transform: translateX(-12px); }
        }
      `}</style>
    </div>
  );
}

// ─── Voice intent banner (best match + confidence) ───────────────────

function VoiceIntentBanner({
  intent,
  section,
  confidence,
}: {
  intent: string;
  section: string;
  confidence: number;
}) {
  const pct = Math.round(confidence * 100);
  return (
    <div
      className="flex items-center gap-3 px-4"
      style={{
        height: 44,
        background: P.amberFaint,
        borderBottom: `0.5px solid ${P.rule}`,
      }}
    >
      <span
        className="font-mono font-semibold uppercase tracking-[0.22em]"
        style={{ fontSize: 8.5, color: P.amberDeep }}
      >
        · INTENT
      </span>
      <span className="flex items-baseline gap-2">
        <span
          className="font-display"
          style={{ fontSize: 13, fontWeight: 500, color: P.ink, letterSpacing: "-0.005em" }}
        >
          {intent}
        </span>
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 9, color: P.inkFainter }}
        >
          · {section}
        </span>
      </span>
      <span className="flex-1" />
      {/* Confidence bar */}
      <span className="flex items-center gap-2">
        <span
          className="font-mono uppercase tracking-[0.16em]"
          style={{ fontSize: 8.5, color: P.inkFainter }}
        >
          confidence
        </span>
        <span
          className="relative inline-block"
          style={{
            width: 64,
            height: 3,
            background: "rgba(35,36,35,0.10)",
            borderRadius: 999,
            overflow: "hidden",
          }}
        >
          <span
            className="absolute left-0 top-0 bottom-0"
            style={{
              width: `${pct}%`,
              background: P.amber,
              borderRadius: 999,
            }}
          />
        </span>
        <span
          className="font-mono"
          style={{ fontSize: 9.5, color: P.amberDeep, fontWeight: 600 }}
        >
          {pct}%
        </span>
      </span>
      <span
        className="font-mono uppercase tracking-[0.20em]"
        style={{ fontSize: 9, color: P.amber, marginLeft: 6 }}
      >
        ↵ commit
      </span>
    </div>
  );
}

// ─── Command list ────────────────────────────────────────────────────

type CommandRow = {
  id: string;
  title: string;
  subtitle: string;
  icon: string;
  shortcut?: string;
};

const NAVIGATION: CommandRow[] = [
  { id: "navigation-go-to-home",       title: "Go to Home",       subtitle: "Dashboard, recent",         icon: "▸",  shortcut: "⌘1" },
  { id: "navigation-go-to-library",    title: "Go to Library",    subtitle: "All recordings",            icon: "▣" },
  { id: "navigation-go-to-dictations", title: "Go to Dictations", subtitle: "Speech, transcripts",       icon: "~",  shortcut: "⌘D" },
  { id: "navigation-go-to-notes",      title: "Go to Notes",      subtitle: "Snippets, screenshots",     icon: "✎" },
  { id: "navigation-go-to-compose",    title: "Go to Compose",    subtitle: "Drafts, editor",            icon: "✚" },
];

const SETTINGS: CommandRow[] = [
  { id: "settings-context",            title: "Context Settings", subtitle: "Apps, dictionary, actions", icon: "◇" },
  { id: "settings-api-keys",           title: "API Keys",         subtitle: "OpenAI, Anthropic …",       icon: "⚷" },
  { id: "settings-appearance",         title: "Appearance",       subtitle: "Theme, colors",             icon: "◐" },
];

const ACTIONS: CommandRow[] = [
  { id: "actions-toggle-sidebar",      title: "Toggle Sidebar",   subtitle: "View",                       icon: "▤",  shortcut: "⌃⌘S" },
  { id: "actions-keyboard-shortcuts",  title: "Keyboard Shortcuts", subtitle: "Help",                     icon: "⌨",  shortcut: "?"   },
  { id: "actions-submit-report",       title: "Submit Report",    subtitle: "Help & Feedback",            icon: "✉" },
];

const DEFAULT_HIGHLIGHT = "navigation-go-to-home";

function CommandList({
  highlightId,
  subdued,
  extraDimmed,
}: {
  highlightId?: string;
  subdued?: boolean;
  extraDimmed?: boolean;
}) {
  return (
    <div
      className="flex-1 overflow-hidden"
      style={{
        background: P.bg,
        opacity: extraDimmed ? 0.65 : 1,
      }}
    >
      <Group title="Navigation" rows={NAVIGATION} highlightId={highlightId} subdued={subdued} />
      <Group title="Settings"   rows={SETTINGS}   highlightId={highlightId} subdued={subdued} />
      <Group title="Actions"    rows={ACTIONS}    highlightId={highlightId} subdued={subdued} />
    </div>
  );
}

function Group({
  title,
  rows,
  highlightId,
  subdued,
}: {
  title: string;
  rows: CommandRow[];
  highlightId?: string;
  subdued?: boolean;
}) {
  return (
    <div>
      <div
        className="flex items-center px-4"
        style={{
          height: 24,
          background: "transparent",
          borderTop: `0.5px solid ${P.rule}`,
        }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.22em]"
          style={{ fontSize: 9, color: P.amberDeep }}
        >
          · {title}
        </span>
      </div>
      {rows.map((r) => (
        <Row
          key={r.id}
          row={r}
          selected={r.id === highlightId}
          subdued={subdued && r.id !== highlightId}
        />
      ))}
    </div>
  );
}

function Row({
  row,
  selected,
  subdued,
}: {
  row: CommandRow;
  selected?: boolean;
  subdued?: boolean;
}) {
  return (
    <div
      className="flex items-center gap-3 px-4"
      style={{
        height: 36,
        background: selected ? "rgba(196,125,28,0.18)" : "transparent",
        borderLeft: selected ? `3px solid ${P.amber}` : "3px solid transparent",
        opacity: subdued ? 0.55 : 1,
      }}
    >
      {/* Inline glyph — no tile, no border, just the mark. Color
          carries selection state. Fixed-width slot keeps titles
          left-aligned. */}
      <span
        className="flex items-center justify-center"
        style={{
          width: 16,
          color: selected ? P.amberDeep : P.inkFainter,
          fontSize: 13,
          fontWeight: selected ? 500 : 400,
          lineHeight: 1,
          textAlign: "center",
        }}
      >
        {row.icon}
      </span>
      {/* Title + subtitle — lighter, smaller. Subtitle drops down a
          half-step into footnote territory. */}
      <div className="flex flex-col" style={{ gap: 1, minWidth: 0 }}>
        <span
          className="font-display"
          style={{
            fontSize: 12,
            color: selected ? P.ink : P.ink,
            fontWeight: selected ? 500 : 400,
            lineHeight: 1.25,
            letterSpacing: "-0.005em",
          }}
        >
          {row.title}
        </span>
        <span
          className="font-mono"
          style={{
            fontSize: 9,
            color: P.inkFainter,
            letterSpacing: "0.04em",
            lineHeight: 1.2,
          }}
        >
          {row.subtitle}
        </span>
      </div>
      <span className="flex-1" />
      {row.shortcut && (
        <span
          className="font-mono"
          style={{
            fontSize: 9.5,
            fontWeight: 500,
            color: selected ? P.amberDeep : P.inkFainter,
            padding: "2px 6px",
            background: selected ? P.amberFaint : "transparent",
            border: `0.5px solid ${selected ? P.amberSoft : P.rule}`,
            borderRadius: 3,
            letterSpacing: "0.02em",
          }}
        >
          {row.shortcut}
        </span>
      )}
    </div>
  );
}

// ─── Scoped "Here" group (State 3) ───────────────────────────────────

const HERE_ROWS: CommandRow[] = [
  { id: "here-open-editor", title: "Open in editor",  subtitle: "Q1 plan",            icon: "▸", shortcut: "↵"   },
  { id: "here-copy-link",   title: "Copy link",       subtitle: "internal share",     icon: "⌘", shortcut: "⌘L" },
  { id: "here-share",       title: "Share…",          subtitle: "AirDrop, Mail, …",   icon: "↗"               },
  { id: "here-delete",      title: "Delete recording", subtitle: "moves to trash",    icon: "⌫", shortcut: "⌘⌫" },
];

function ScopedHereGroup() {
  return (
    <div>
      <div
        className="flex items-center px-4"
        style={{
          height: 26,
          background: P.amberFaint,
          borderBottom: `0.5px solid ${P.amberSoft}`,
        }}
      >
        <span
          className="font-mono font-semibold uppercase tracking-[0.20em]"
          style={{ fontSize: 9.5, color: P.amberDeep }}
        >
          · HERE · Q1 plan
        </span>
        <span className="ml-2 flex-1" style={{ height: 1, background: P.amberSoft }} />
        <span
          className="font-mono uppercase tracking-[0.18em]"
          style={{ fontSize: 8.5, color: P.inkFainter }}
        >
          context · 4
        </span>
      </div>
      {HERE_ROWS.map((r) => (
        <Row key={r.id} row={r} selected={r.id === "here-open-editor"} />
      ))}
    </div>
  );
}

// ─── Footer · key hints ──────────────────────────────────────────────

function KeyHintsFooter({ mode = "browse" }: { mode?: "browse" | "speaking" }) {
  return (
    <div
      className="flex items-center gap-3 px-3"
      style={{
        height: 32,
        background: P.bgSunk,
        borderTop: `0.5px solid ${P.rule}`,
      }}
    >
      {mode === "speaking" ? (
        <>
          <KeyHint keys="release" label="commit" />
          <KeyHint keys="↵" label="confirm" />
          <KeyHint keys="⎋" label="cancel" />
        </>
      ) : (
        <>
          <KeyHint keys="↑↓" label="navigate" />
          <KeyHint keys="↵" label="run" />
          <KeyHint keys="⎋" label="close" />
          <KeyHint keys="♪" label="hold to speak" />
        </>
      )}
      <span className="flex-1" />
      <span
        className="font-mono"
        style={{ fontSize: 10, color: P.inkFainter, letterSpacing: "0.04em" }}
      >
        ⌘ ⇧ K
      </span>
    </div>
  );
}

function KeyHint({ keys, label }: { keys: string; label: string }) {
  return (
    <span className="flex items-center gap-1.5">
      <span
        className="font-mono"
        style={{
          fontSize: 9.5,
          fontWeight: 500,
          color: P.inkFaint,
          padding: "2px 6px",
          background: "rgba(35,36,35,0.04)",
          border: `0.5px solid ${P.rule}`,
          borderRadius: 3,
        }}
      >
        {keys}
      </span>
      <span
        className="font-mono uppercase tracking-[0.16em]"
        style={{ fontSize: 9, color: P.inkFainter }}
      >
        {label}
      </span>
    </span>
  );
}

// ─── Desktop backdrop · faux dimmed app behind the palette ───────────

function DesktopBackdrop({
  height,
  children,
}: {
  height: number;
  children: React.ReactNode;
}) {
  return (
    <div
      className="relative overflow-hidden"
      style={{
        height,
        borderRadius: 10,
        border: `0.5px solid ${T.inkRule}`,
        background:
          "linear-gradient(135deg, #DEE3EA 0%, #C9CFD9 55%, #BCC3CD 100%)",
        boxShadow: "0 1px 0 rgba(0,0,0,0.04) inset, 0 18px 38px -8px rgba(0,0,0,0.10)",
      }}
    >
      {/* Faux menu bar */}
      <div
        className="absolute left-0 right-0 top-0 flex items-center px-3"
        style={{
          height: 22,
          background: "rgba(255,255,255,0.55)",
          backdropFilter: "blur(20px)",
          WebkitBackdropFilter: "blur(20px)",
          borderBottom: "0.5px solid rgba(0,0,0,0.10)",
        }}
      >
        <span style={{ fontSize: 10, fontWeight: 600, color: "rgba(35,36,35,0.85)" }}>
          Talkie
        </span>
        <span className="flex-1" />
        <span
          className="font-mono"
          style={{ fontSize: 9, color: "rgba(35,36,35,0.7)", letterSpacing: "0.06em" }}
        >
          Wed 3:42 PM
        </span>
      </div>
      {/* Modal scrim — palette is a focus mode, app behind is dimmed. */}
      <div
        className="absolute"
        style={{
          left: 0, right: 0, top: 22, bottom: 0,
          background: "rgba(8,10,14,0.30)",
          backdropFilter: "blur(2px)",
          WebkitBackdropFilter: "blur(2px)",
        }}
      />
      {/* Palette anchored upper third */}
      <div
        className="absolute"
        style={{ left: 0, right: 0, top: 70, display: "flex", justifyContent: "center" }}
      >
        {children}
      </div>
    </div>
  );
}

// ─── Donor tiles ─────────────────────────────────────────────────────

function DonorTile({
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
      <PaneHeader title={eyebrow} sub="donor" />
      <div
        style={{
          background: T.pane,
          border: `1px solid ${T.inkRuleS}`,
          borderRadius: 4,
          padding: 16,
          minHeight: 240,
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

// Tiny re-rendering of the Raycast-clone donor.
function DonorPalette() {
  const rows = [
    { icon: "▸", title: "Go to Home",       sub: "Navigation" },
    { icon: "▣", title: "Go to Library",    sub: "Navigation" },
    { icon: "~", title: "Go to Dictations", sub: "Navigation" },
    { icon: "⚷", title: "API Keys",         sub: "Settings"   },
    { icon: "♪", title: "Voice Command",    sub: "Actions"    },
  ];
  return (
    <div
      style={{
        background: "#15161B",
        borderRadius: 10,
        border: "0.5px solid rgba(255,255,255,0.12)",
        overflow: "hidden",
        boxShadow: "0 18px 44px -8px rgba(0,0,0,0.40)",
      }}
    >
      {/* search */}
      <div className="flex items-center gap-2 px-3" style={{ height: 40, borderBottom: "0.5px solid rgba(255,255,255,0.06)" }}>
        <span style={{ fontSize: 14, color: "rgba(255,255,255,0.55)" }}>⌕</span>
        <span className="font-display italic" style={{ fontSize: 12, color: "rgba(255,255,255,0.4)" }}>
          Search commands...
        </span>
      </div>
      {/* flat list, no grouping */}
      {rows.map((r, i) => (
        <div
          key={r.title}
          className="flex items-center gap-2 px-3"
          style={{
            height: 36,
            background: i === 0 ? "rgba(10,132,255,0.18)" : "transparent",
            borderBottom: "0.5px solid rgba(255,255,255,0.03)",
          }}
        >
          <span
            className="flex items-center justify-center"
            style={{
              width: 22, height: 22,
              background: i === 0 ? "#0A84FF" : "rgba(255,255,255,0.08)",
              color: i === 0 ? "#fff" : "rgba(255,255,255,0.65)",
              borderRadius: 3, fontSize: 11,
            }}
          >
            {r.icon}
          </span>
          <span style={{ fontSize: 11.5, color: "rgba(255,255,255,0.92)" }}>{r.title}</span>
          <span className="flex-1" />
          <span style={{ fontSize: 9.5, color: "rgba(255,255,255,0.4)" }}>{r.sub}</span>
        </div>
      ))}
      {/* footer */}
      <div className="flex items-center gap-3 px-3" style={{ height: 26, background: "rgba(255,255,255,0.03)" }}>
        <span style={{ fontSize: 9, color: "rgba(255,255,255,0.45)" }}>↑↓ navigate</span>
        <span style={{ fontSize: 9, color: "rgba(255,255,255,0.45)" }}>↵ select</span>
        <span className="flex-1" />
        <span className="font-mono" style={{ fontSize: 9, color: "rgba(255,255,255,0.25)" }}>⌘⇧K</span>
      </div>
    </div>
  );
}

// Tiny re-rendering of the VoiceCommandOverlay particle modal.
function DonorVoiceOverlay() {
  return (
    <div
      style={{
        background: "rgba(20,24,30,0.85)",
        backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        borderRadius: 14,
        border: "0.5px solid rgba(255,255,255,0.10)",
        boxShadow: "0 22px 48px -8px rgba(0,0,0,0.40)",
        overflow: "hidden",
      }}
    >
      {/* Particle stand-in */}
      <div
        className="relative"
        style={{ height: 110, padding: 12 }}
      >
        <div
          className="absolute"
          style={{
            left: "50%", top: "50%",
            transform: "translate(-50%,-50%)",
            width: 90, height: 90,
            borderRadius: "50%",
            background:
              "radial-gradient(circle at 50% 50%, rgba(10,132,255,0.55) 0%, rgba(10,132,255,0.18) 50%, transparent 75%)",
            filter: "blur(2px)",
          }}
        />
        {/* simulated particles */}
        {[...Array(18)].map((_, i) => (
          <span
            key={i}
            className="absolute rounded-full"
            style={{
              left: `${50 + Math.cos(i) * 28}%`,
              top: `${50 + Math.sin(i) * 28}%`,
              width: 4 + (i % 3),
              height: 4 + (i % 3),
              background: `rgba(120,170,255,${0.4 + (i % 5) * 0.1})`,
            }}
          />
        ))}
      </div>
      <div className="px-3 pb-3" style={{ display: "flex", flexDirection: "column", gap: 6, alignItems: "center" }}>
        <span className="font-mono uppercase tracking-[0.20em]" style={{ fontSize: 9, color: "rgba(255,255,255,0.7)" }}>
          Listening …
        </span>
        <span
          className="font-display italic"
          style={{ fontSize: 11, color: "rgba(255,255,255,0.45)" }}
        >
          Press Return when done · Esc to cancel
        </span>
      </div>
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
