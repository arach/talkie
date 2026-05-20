"use client";

import React, { useState } from "react";
import { StudioPage } from "@/components/StudioPage";

/**
 * Mac Talkie — Onboarding flow.
 *
 * First-launch experience. Today the Swift onboarding (`Views/Onboarding/`)
 * is a multi-step modal sequence — functional but not editorial. This
 * study proposes a 4-step flow on cream paper, treated like chapter
 * openings rather than wizard pages.
 *
 *   1. Frontispiece — "Talkie." in monumental serif, italic byline,
 *      "Press ↵ to begin." Stands as a single ceremonial page.
 *   2. Permissions — microphone, accessibility, screen recording.
 *      One row per permission with grant button + italic explanation.
 *   3. Models — ASR model (Parakeet) + LLM (provider + model) in one
 *      page. Download progress lives inline. Skip-for-now is allowed
 *      for the LLM.
 *   4. First memo — "You're ready." with a callout to the chrome bar
 *      TALKIE pill and the ⌘N shortcut.
 *
 * Each step shares the same editorial chrome: hairline at top with a
 * step indicator (`I · II · III · IV`), the page content, and a bottom
 * row with Skip / Back / Continue.
 */

const CREAM       = "#FBFBFA";
const PAPER       = "#F4F1EA";
const INK         = "#2A2620";
const INK_FAINT   = "rgba(42,38,32,0.55)";
const INK_FAINTER = "rgba(42,38,32,0.32)";
const INK_RULE    = "rgba(42,38,32,0.18)";
const INK_RULE_S  = "rgba(42,38,32,0.10)";
const AMBER       = "#C47D1C";
const AMBER_TINT  = "rgba(196,125,28,0.08)";
const BRASS       = "#9A6A22";
const EDGE        = "#E0DCD3";

const STEPS = ["I", "II", "III", "IV"] as const;
type StepIndex = 0 | 1 | 2 | 3;

// ─── Page ────────────────────────────────────────────────────────────

export default function MacOnboardingStudy() {
  return (
    <StudioPage
      eyebrow="Onboarding · macOS · 4-step sequence"
      title="Talkie onboarding · first launch"
      help="Each step renders at 880 × 600. Click the step numbers below to preview each chapter."
    >
      <div className="flex flex-col gap-12 py-6">
        <InteractiveStepper />

        <div className="flex flex-col gap-9">
          <Chapter eyebrow="· I · Frontispiece" title="Welcome">
            <StepWelcome />
          </Chapter>

          <Chapter eyebrow="· II · Permissions" title="What Talkie needs to work">
            <StepPermissions />
          </Chapter>

          <Chapter eyebrow="· III · Models" title="Voice + AI commands">
            <StepModels />
          </Chapter>

          <Chapter eyebrow="· IV · Ready" title="Your first memo">
            <StepReady />
          </Chapter>
        </div>
      </div>
    </StudioPage>
  );
}

// ─── Interactive stepper preview ─────────────────────────────────────

function InteractiveStepper() {
  const [step, setStep] = useState<StepIndex>(0);

  return (
    <section>
      <div className="mb-4 flex items-baseline justify-between border-b border-studio-edge pb-3">
        <div>
          <div className="text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
            · interactive preview
          </div>
          <h2 className="m-0 font-display text-[19px] font-medium leading-none tracking-tight text-studio-ink">
            Step through the flow
          </h2>
        </div>
        <div className="flex items-center gap-1.5">
          {STEPS.map((label, i) => (
            <button
              key={i}
              onClick={() => setStep(i as StepIndex)}
              className="rounded-[2px] px-2.5 py-1 font-mono text-[10px] font-semibold uppercase tracking-[0.22em] transition-colors"
              style={{
                color: step === i ? CREAM : INK_FAINT,
                background: step === i ? INK : "transparent",
                border: step === i ? "none" : `0.5px solid ${EDGE}`,
              }}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      <FrameWrap>
        {step === 0 && <StepWelcome />}
        {step === 1 && <StepPermissions />}
        {step === 2 && <StepModels />}
        {step === 3 && <StepReady />}
      </FrameWrap>
    </section>
  );
}

// ─── Chapter wrapper ─────────────────────────────────────────────────

function Chapter({
  eyebrow,
  title,
  children,
}: {
  eyebrow: string;
  title: string;
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
      </div>
      <FrameWrap>{children}</FrameWrap>
    </section>
  );
}

function FrameWrap({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="overflow-hidden rounded-md"
      style={{
        background: CREAM,
        border: `0.5px solid ${INK_RULE_S}`,
        width: 880,
        maxWidth: "100%",
        height: 600,
      }}
    >
      <div className="flex h-full flex-col">
        {children}
      </div>
    </div>
  );
}

// ─── Step indicator row (top of each step) ───────────────────────────

function StepBar({ active }: { active: StepIndex }) {
  return (
    <div
      className="flex items-center justify-between px-9 py-4"
      style={{ borderBottom: `0.5px solid ${INK_RULE_S}` }}
    >
      <div className="flex items-center gap-3 font-mono text-[10px] font-semibold uppercase tracking-[0.32em]">
        {STEPS.map((label, i) => (
          <React.Fragment key={i}>
            <span
              style={{
                color: i === active ? AMBER : i < active ? INK : INK_FAINTER,
                fontWeight: i === active ? 700 : 500,
              }}
            >
              {label}
            </span>
            {i < STEPS.length - 1 && (
              <span style={{ width: 14, height: 0.5, background: i < active ? AMBER : INK_FAINTER, opacity: i < active ? 0.55 : 0.4 }} />
            )}
          </React.Fragment>
        ))}
      </div>

      <span
        className="font-display italic"
        style={{ color: INK_FAINT, fontSize: 13 }}
      >
        Setting up Talkie
      </span>
    </div>
  );
}

// ─── Step footer (continue / skip / back) ────────────────────────────

function StepFooter({
  active,
  onBack,
  onContinue,
  skipLabel,
  continueLabel = "CONTINUE",
}: {
  active: StepIndex;
  onBack?: boolean;
  onContinue?: boolean;
  skipLabel?: string;
  continueLabel?: string;
}) {
  return (
    <div
      className="mt-auto flex items-center justify-between px-9 py-4"
      style={{ borderTop: `0.5px solid ${INK_RULE_S}` }}
    >
      {onBack && active > 0 ? (
        <button
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em] hover:text-studio-ink"
          style={{ color: INK_FAINT }}
        >
          ← BACK
        </button>
      ) : (
        <span />
      )}

      <div className="flex items-baseline gap-4">
        {skipLabel && (
          <button
            className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em] hover:text-studio-ink"
            style={{ color: INK_FAINT }}
          >
            {skipLabel}
          </button>
        )}
        {onContinue && (
          <button
            className="rounded-[3px] px-4 py-2 font-mono text-[10px] font-semibold uppercase tracking-[0.22em]"
            style={{ background: INK, color: CREAM }}
          >
            {continueLabel} →
          </button>
        )}
      </div>
    </div>
  );
}

// ─── Step I · Frontispiece ───────────────────────────────────────────

function StepWelcome() {
  return (
    <div className="flex h-full flex-col">
      <StepBar active={0} />

      <div className="flex flex-1 flex-col items-center justify-center px-9">
        <div
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.42em]"
          style={{ color: INK_FAINT }}
        >
          · TALKIE ·
        </div>

        <h1
          className="m-0 mt-8 font-display"
          style={{
            color: INK,
            fontSize: 110,
            lineHeight: 0.92,
            letterSpacing: "-0.045em",
            fontWeight: 400,
          }}
        >
          Talkie.
        </h1>

        <p
          className="m-0 mt-6 font-display italic"
          style={{
            color: INK_FAINT,
            fontSize: 19,
            letterSpacing: "0.005em",
            lineHeight: 1.4,
            textAlign: "center",
            maxWidth: 520,
          }}
        >
          A quiet desk for memos, dictations, and notes. Voice in,
          editorial out.
        </p>

        <div className="mt-12 flex items-center gap-3 font-mono text-[10px] uppercase tracking-[0.28em]" style={{ color: INK_FAINTER }}>
          <span>press</span>
          <span
            className="rounded-[2px] px-2 py-1"
            style={{ border: `0.5px solid ${EDGE}`, background: PAPER, color: INK }}
          >
            ↵
          </span>
          <span>to begin</span>
        </div>
      </div>

      <StepFooter active={0} onContinue continueLabel="BEGIN" />
    </div>
  );
}

// ─── Step II · Permissions ───────────────────────────────────────────

const PERMISSIONS = [
  {
    key: "mic",
    title: "Microphone",
    why: "to record your voice for memos and dictations.",
    state: "needs grant" as const,
  },
  {
    key: "accessibility",
    title: "Accessibility",
    why: "to type dictation into the focused app and listen for global shortcuts.",
    state: "needs grant" as const,
  },
  {
    key: "screen",
    title: "Screen Recording",
    why: "to capture screenshots when you press ⇧⌃⌥⌘ S. Optional — Talkie works without it.",
    state: "optional" as const,
  },
];

function StepPermissions() {
  return (
    <div className="flex h-full flex-col">
      <StepBar active={1} />

      <div className="flex flex-1 flex-col px-9 py-9">
        <div className="font-mono text-[10px] font-semibold uppercase tracking-[0.36em]" style={{ color: INK_FAINT }}>
          · PERMISSIONS
        </div>

        <h2
          className="m-0 mt-3 font-display"
          style={{
            color: INK,
            fontSize: 32,
            lineHeight: 1.15,
            letterSpacing: "-0.015em",
            fontWeight: 400,
          }}
        >
          What Talkie needs to work
        </h2>

        <p
          className="m-0 mt-2 font-display italic"
          style={{ color: INK_FAINT, fontSize: 15 }}
        >
          Two required, one optional. Grant them now and we're done.
        </p>

        <div className="mt-8 flex flex-col">
          {PERMISSIONS.map((p, i) => (
            <PermissionRow key={p.key} permission={p} isLast={i === PERMISSIONS.length - 1} />
          ))}
        </div>
      </div>

      <StepFooter active={1} onBack onContinue skipLabel="DO LATER" />
    </div>
  );
}

function PermissionRow({
  permission,
  isLast,
}: {
  permission: (typeof PERMISSIONS)[number];
  isLast: boolean;
}) {
  return (
    <div
      className="flex items-baseline gap-6 py-5"
      style={{ borderBottom: isLast ? "none" : `0.5px solid ${INK_RULE_S}` }}
    >
      <div className="flex flex-1 flex-col gap-1.5">
        <div className="flex items-baseline gap-3">
          <h3
            className="m-0 font-display"
            style={{
              color: INK,
              fontSize: 18,
              letterSpacing: "-0.005em",
              fontWeight: 500,
            }}
          >
            {permission.title}
          </h3>
          {permission.state === "optional" && (
            <span
              className="font-mono text-[9px] font-semibold uppercase tracking-[0.22em]"
              style={{ color: INK_FAINTER }}
            >
              · OPTIONAL
            </span>
          )}
        </div>
        <p
          className="m-0 font-display italic"
          style={{ color: INK_FAINT, fontSize: 14, lineHeight: 1.5 }}
        >
          {permission.why}
        </p>
      </div>

      <button
        className="rounded-[3px] px-4 py-2 font-mono text-[9.5px] font-semibold uppercase tracking-[0.24em]"
        style={{
          color: permission.state === "optional" ? INK_FAINT : AMBER,
          background: permission.state === "optional" ? "transparent" : AMBER_TINT,
          border: `1px solid ${permission.state === "optional" ? EDGE : AMBER}`,
        }}
      >
        {permission.state === "optional" ? "SKIP" : "GRANT →"}
      </button>
    </div>
  );
}

// ─── Step III · Models ───────────────────────────────────────────────

function StepModels() {
  return (
    <div className="flex h-full flex-col">
      <StepBar active={2} />

      <div className="flex flex-1 flex-col px-9 py-9">
        <div className="font-mono text-[10px] font-semibold uppercase tracking-[0.36em]" style={{ color: INK_FAINT }}>
          · MODELS
        </div>

        <h2
          className="m-0 mt-3 font-display"
          style={{
            color: INK,
            fontSize: 32,
            lineHeight: 1.15,
            letterSpacing: "-0.015em",
            fontWeight: 400,
          }}
        >
          Voice in, AI commands optional
        </h2>

        <p
          className="m-0 mt-2 font-display italic"
          style={{ color: INK_FAINT, fontSize: 15 }}
        >
          Talkie needs a speech-to-text model to hear you. An LLM is
          only required for AI commands in Compose.
        </p>

        <div className="mt-8 flex flex-col gap-7">
          {/* ASR */}
          <ModelBlock
            eyebrow="· VOICE · REQUIRED"
            title="Parakeet v3"
            byline="0.6 GB · runs locally · no network"
            statusLabel="DOWNLOADING · 42%"
            statusKind="downloading"
            footnote="Fast, accurate, never leaves your Mac. Apple Speech is available as a fallback if you'd rather not download."
          />

          {/* LLM */}
          <ModelBlock
            eyebrow="· AI COMMANDS · OPTIONAL"
            title="Anthropic · Claude Sonnet 4.6"
            byline="API key required · paid usage"
            statusLabel="NEEDS API KEY"
            statusKind="needsKey"
            footnote="Used for revise / refine / summarize / etc. in Compose. You can skip and add later from Settings."
          />
        </div>
      </div>

      <StepFooter active={2} onBack onContinue skipLabel="SKIP LLM" />
    </div>
  );
}

function ModelBlock({
  eyebrow,
  title,
  byline,
  statusLabel,
  statusKind,
  footnote,
}: {
  eyebrow: string;
  title: string;
  byline: string;
  statusLabel: string;
  statusKind: "downloading" | "needsKey" | "ready";
  footnote: string;
}) {
  const statusColor =
    statusKind === "ready" ? AMBER : statusKind === "downloading" ? BRASS : INK_FAINT;

  return (
    <div>
      <div className="flex items-baseline gap-3">
        <span
          className="font-mono text-[9.5px] font-semibold uppercase tracking-[0.32em]"
          style={{ color: BRASS }}
        >
          {eyebrow}
        </span>
        <span style={{ flex: 1, height: 0.5, background: INK_RULE_S }} />
        <span
          className="font-mono text-[9.5px] font-semibold uppercase tracking-[0.24em]"
          style={{ color: statusColor }}
        >
          {statusLabel}
        </span>
      </div>

      <div className="mt-3 flex items-baseline gap-4">
        <h3
          className="m-0 font-display"
          style={{
            color: INK,
            fontSize: 22,
            letterSpacing: "-0.012em",
            fontWeight: 500,
          }}
        >
          {title}
        </h3>
        <span
          className="font-display italic"
          style={{ color: INK_FAINT, fontSize: 14 }}
        >
          {byline}
        </span>
      </div>

      {/* Progress bar for downloading state */}
      {statusKind === "downloading" && (
        <div
          className="mt-3"
          style={{ height: 2, background: INK_RULE_S, borderRadius: 1, overflow: "hidden" }}
        >
          <div
            style={{
              width: "42%",
              height: "100%",
              background: AMBER,
            }}
          />
        </div>
      )}

      <p
        className="m-0 mt-3"
        style={{ color: INK_FAINT, fontSize: 13, lineHeight: 1.6, maxWidth: 620 }}
      >
        {footnote}
      </p>
    </div>
  );
}

// ─── Step IV · Ready ─────────────────────────────────────────────────

function StepReady() {
  return (
    <div className="flex h-full flex-col">
      <StepBar active={3} />

      <div className="flex flex-1 flex-col items-center justify-center px-9">
        <div
          className="font-mono text-[10px] font-semibold uppercase tracking-[0.42em]"
          style={{ color: BRASS }}
        >
          · READY ·
        </div>

        <h1
          className="m-0 mt-7 font-display"
          style={{
            color: INK,
            fontSize: 72,
            lineHeight: 0.96,
            letterSpacing: "-0.03em",
            fontWeight: 400,
            textAlign: "center",
          }}
        >
          Press <span style={{ color: AMBER }}>TALKIE</span> to record
          your first memo.
        </h1>

        <p
          className="m-0 mt-7 font-display italic"
          style={{
            color: INK_FAINT,
            fontSize: 16,
            textAlign: "center",
            maxWidth: 540,
          }}
        >
          The pill at the top center of every window is the recording
          anchor. Tap it once to start, again to stop. Talkie does the
          rest.
        </p>

        {/* Inline pill preview */}
        <div className="mt-9">
          <div
            className="flex items-center gap-2 rounded-full px-3.5 py-1.5"
            style={{ background: INK }}
          >
            <span
              className="inline-block h-2 w-2 rounded-full"
              style={{ background: AMBER, boxShadow: `0 0 4px ${AMBER}55` }}
            />
            <span
              className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em]"
              style={{ color: CREAM }}
            >
              TALKIE
            </span>
          </div>
        </div>

        <div
          className="mt-7 flex items-center gap-3 font-mono text-[10px] uppercase tracking-[0.24em]"
          style={{ color: INK_FAINTER }}
        >
          <span>or press</span>
          <span
            className="rounded-[2px] px-2 py-1"
            style={{ border: `0.5px solid ${EDGE}`, background: PAPER, color: INK }}
          >
            ⌘N
          </span>
          <span>any time</span>
        </div>
      </div>

      <StepFooter active={3} onBack onContinue continueLabel="OPEN TALKIE" />
    </div>
  );
}
