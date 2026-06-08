"use client";

import { cn } from "@/lib/utils";

/**
 * Agent Tray artifact — the macOS menu-bar pop-out for TalkieAgent.
 *
 * Ships in `AgentMenuPopoverView.swift` (320pt wide). This studio
 * recreation explores two moves the current panel is missing:
 *
 *   1. Consolidate NOW (record action) + INPUT (mic picker) into one
 *      "capture composer" — the record action is the hero, the input
 *      device is quiet metadata about *where* the audio comes from, not
 *      its own labelled section. Three layouts: bar / segmented / footer.
 *
 *   2. Dress RECENT + TOOLS in the scope/instrument language — amber
 *      channel eyebrows, mono traces, hairline rules, warm tile material —
 *      so the panel reads as Talkie, not a generic dark menu.
 *
 * All material comes from the parent <SchemeCard> via `var(--scheme-*)`.
 * `AgentTrayCurrent` is a faithful render of today's shipping panel for
 * an honest before/after.
 */

export type CaptureLayout = "split" | "labeled" | "stacked";

export interface TrayTreatments {
  layout: CaptureLayout;
  recording: boolean;
  graticule: boolean;
  strips: boolean;
}

const RECENT = [
  { preview: "Alright, that's good. That's very…", time: "now" },
  { preview: "Yeah, your first instinct shoul…", time: "3m" },
  { preview: "Wait, why did you make any chan…", time: "6m" },
  { preview: "Okay, so now I'm interested in…", time: "6m" },
];

const TOOLS = [
  { title: "Home", glyph: "▦", primary: true },
  { title: "Settings", glyph: "✦" },
  { title: "Logs", glyph: "≣", badge: "2" },
  { title: "Permissions", glyph: "⛉" },
  { title: "Restart", glyph: "↻", warm: true },
  { title: "Quit", glyph: "⏻", danger: true },
];

// ── Shared primitives ───────────────────────────────────────────────

/** Monochrome mic glyph that tints with `currentColor`. */
function MicGlyph({ size = 13 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" aria-hidden>
      <rect
        x="5.4"
        y="1.6"
        width="5.2"
        height="8"
        rx="2.6"
        fill="currentColor"
      />
      <path
        d="M3.4 7.4a4.6 4.6 0 0 0 9.2 0"
        stroke="currentColor"
        strokeWidth="1.1"
        strokeLinecap="round"
      />
      <line
        x1="8"
        y1="12"
        x2="8"
        y2="14.4"
        stroke="currentColor"
        strokeWidth="1.1"
        strokeLinecap="round"
      />
    </svg>
  );
}

function ChannelEyebrow({
  label,
  trailing,
}: {
  label: string;
  trailing?: string;
}) {
  return (
    <div className="flex items-center gap-2 px-1.5 pb-1">
      <span
        aria-hidden
        className="h-[5px] w-[5px] rounded-full"
        style={{
          background: "var(--scheme-accent)",
          boxShadow: "0 0 4px var(--scheme-accent-glow)",
        }}
      />
      <span
        className="text-[8.5px] font-semibold uppercase tracking-eyebrow"
        style={{ color: "var(--scheme-ink-faint)" }}
      >
        {label}
      </span>
      {trailing ? (
        <span
          className="ml-auto flex items-center gap-1 text-[8.5px] font-semibold uppercase tracking-ch"
          style={{ color: "var(--scheme-accent)" }}
        >
          {trailing}
          <span className="text-[7px]">›</span>
        </span>
      ) : null}
    </div>
  );
}

function RecordDisc({ recording }: { recording: boolean }) {
  return (
    <div
      className="relative flex h-9 w-9 shrink-0 items-center justify-center rounded-full"
      style={{
        background: recording
          ? "color-mix(in srgb, var(--scheme-rec) 18%, transparent)"
          : "color-mix(in srgb, var(--scheme-accent) 10%, transparent)",
        border: `1px solid ${
          recording ? "var(--scheme-rec)" : "color-mix(in srgb, var(--scheme-accent) 45%, transparent)"
        }`,
        boxShadow: recording ? "0 0 10px var(--scheme-rec-glow)" : "none",
      }}
    >
      {recording ? (
        <span
          className="h-[10px] w-[10px] rounded-[2px]"
          style={{ background: "var(--scheme-rec)" }}
        />
      ) : (
        <span
          className="h-[11px] w-[11px] rounded-full"
          style={{
            background: "var(--scheme-rec)",
            boxShadow: "0 0 5px var(--scheme-rec-glow)",
          }}
        />
      )}
    </div>
  );
}

/** Live mini-waveform shown in the record subline while recording. */
function MiniWave() {
  const bars = [0.3, 0.7, 0.45, 0.9, 0.6, 0.85, 0.4, 0.7, 0.5, 0.8, 0.35, 0.65];
  return (
    <div className="flex h-3 items-center gap-[2px]">
      {bars.map((b, i) => (
        <span
          key={i}
          className="w-[2px] rounded-full"
          style={{
            height: `${(b * 100).toFixed(0)}%`,
            background: "var(--scheme-rec)",
            opacity: 0.5 + b * 0.5,
          }}
        />
      ))}
    </div>
  );
}

// ── Capture composer (consolidates NOW + INPUT) ─────────────────────
//
// One unit, split 50/50: record action on the left, mic picker on the
// right. No shortcut keycaps here — the chord already lives in the header
// ("Ready for ⌃⌥⇧⌘D").

/** Left half — the record action. `compact` uses the verb only so a
 *  50/50 split never truncates; otherwise the idle/live titles are used. */
function RecordHalf({
  recording,
  label,
  compact,
  idleTitle = "Start Recording",
  liveTitle = "Stop Recording",
}: {
  recording: boolean;
  label?: boolean;
  compact?: boolean;
  idleTitle?: string;
  liveTitle?: string;
}) {
  const title = compact
    ? recording
      ? "Stop"
      : "Record"
    : recording
      ? liveTitle
      : idleTitle;
  return (
    <div className="flex min-w-0 flex-1 items-center gap-2.5 px-3 py-2.5">
      <RecordDisc recording={recording} />
      <div className="flex min-w-0 flex-col gap-1">
        {label ? (
          <span
            className="text-[7.5px] font-semibold uppercase tracking-ch"
            style={{ color: "var(--scheme-ink-subtle)" }}
          >
            {recording ? "Capturing" : "Record"}
          </span>
        ) : null}
        <span
          className="truncate text-[13px] font-semibold leading-none"
          style={{ color: recording ? "var(--scheme-rec)" : "var(--scheme-ink)" }}
        >
          {title}
        </span>
      </div>
    </div>
  );
}

/** Right half — mic picker (idle) or live meter (recording). */
function InputHalf({ recording, label, meta }: { recording: boolean; label?: boolean; meta?: boolean }) {
  if (recording) {
    return (
      <div className="flex flex-1 items-center gap-2 px-3 py-2.5">
        <MiniWave />
        <span
          className="ml-auto text-[11px] font-medium tabular-nums"
          style={{ color: "var(--scheme-rec)" }}
        >
          0:08
        </span>
      </div>
    );
  }
  return (
    <button className="flex min-w-0 flex-1 items-center gap-2 px-3 py-2.5 text-left transition-colors hover:bg-[color-mix(in_srgb,var(--scheme-ink-faint)_7%,transparent)]">
      <span style={{ color: "var(--scheme-accent)" }}>
        <MicGlyph />
      </span>
      <div className="flex min-w-0 flex-col gap-1">
        {label ? (
          <span
            className="text-[7.5px] font-semibold uppercase tracking-ch"
            style={{ color: "var(--scheme-ink-subtle)" }}
          >
            Input
          </span>
        ) : null}
        <span
          className="truncate text-[11.5px] font-medium leading-none"
          style={{ color: "var(--scheme-ink-faint)" }}
        >
          Yeti Stereo Microphone
        </span>
        {meta ? (
          <span className="text-[8px]" style={{ color: "var(--scheme-ink-subtle)" }}>
            48 kHz · stereo
          </span>
        ) : null}
      </div>
      <span className="ml-auto text-[8px]" style={{ color: "var(--scheme-ink-subtle)" }}>
        ⌄
      </span>
    </button>
  );
}

/** Split 50/50 with a hairline divider. */
function CaptureSplit({ recording, label, meta }: { recording: boolean; label?: boolean; meta?: boolean }) {
  return (
    <div
      className="flex items-stretch overflow-hidden rounded-[9px]"
      style={{
        background: "color-mix(in srgb, var(--scheme-accent) 5%, transparent)",
        border: "0.5px solid var(--scheme-edge-strong)",
      }}
    >
      <RecordHalf recording={recording} label={label} compact />
      <span className="w-px shrink-0" style={{ background: "var(--scheme-edge-strong)" }} />
      <InputHalf recording={recording} label={label} meta={meta} />
    </div>
  );
}

/** Record hero on top, mic as an attached instrument footer. */
function CaptureStacked({ recording }: { recording: boolean }) {
  return (
    <div
      className="overflow-hidden rounded-[9px]"
      style={{ border: "0.5px solid var(--scheme-edge-strong)" }}
    >
      <div
        className="flex items-center"
        style={{ background: "color-mix(in srgb, var(--scheme-accent) 5%, transparent)" }}
      >
        <RecordHalf recording={recording} idleTitle="Start Talking" liveTitle="Stop" />
        {recording ? (
          <div className="flex items-center gap-2 px-3">
            <MiniWave />
            <span
              className="text-[11px] font-medium tabular-nums"
              style={{ color: "var(--scheme-rec)" }}
            >
              0:08
            </span>
          </div>
        ) : null}
      </div>
      <button
        className="flex w-full items-center gap-2 px-3 py-1.5 transition-colors hover:bg-[color-mix(in_srgb,var(--scheme-ink-faint)_8%,transparent)]"
        style={{
          borderTop: "0.5px solid var(--scheme-edge)",
          background: "color-mix(in srgb, var(--scheme-ink-faint) 4%, transparent)",
        }}
      >
        <span style={{ color: "var(--scheme-accent)" }}>
          <MicGlyph size={11} />
        </span>
        <span className="text-[10px] font-medium" style={{ color: "var(--scheme-ink-faint)" }}>
          Yeti Stereo Microphone
        </span>
        <span className="text-[9px]" style={{ color: "var(--scheme-ink-subtle)" }}>
          · 48 kHz
        </span>
        <span className="ml-auto text-[8px]" style={{ color: "var(--scheme-ink-subtle)" }}>
          ⌄
        </span>
      </button>
    </div>
  );
}

function Composer({ t }: { t: TrayTreatments }) {
  if (t.layout === "stacked") return <CaptureStacked recording={t.recording} />;
  if (t.layout === "labeled")
    return <CaptureSplit recording={t.recording} label meta />;
  return <CaptureSplit recording={t.recording} />;
}

// ── Recent + Tools (scope-dressed) ──────────────────────────────────

function RecentList() {
  return (
    <div>
      <ChannelEyebrow label="Recent" trailing="All" />
      <div
        className="overflow-hidden rounded-[7px]"
        style={{
          background: "color-mix(in srgb, var(--scheme-ink-faint) 4%, transparent)",
          border: "0.5px solid var(--scheme-edge)",
        }}
      >
        {RECENT.map((r, i) => (
          <button
            key={i}
            className="flex w-full items-center gap-2 px-2.5 py-[7px] text-left transition-colors hover:bg-[color-mix(in_srgb,var(--scheme-ink-faint)_7%,transparent)]"
            style={
              i < RECENT.length - 1
                ? { borderBottom: "0.5px solid var(--scheme-edge)" }
                : undefined
            }
          >
            <span
              aria-hidden
              className="h-[3px] w-[3px] shrink-0 rounded-full"
              style={{ background: "var(--scheme-accent)", opacity: 0.7 }}
            />
            <span
              className="flex-1 truncate text-[11px]"
              style={{ color: "var(--scheme-ink-faint)" }}
            >
              {r.preview}
            </span>
            <span
              className="shrink-0 text-[9px] tabular-nums"
              style={{ color: "var(--scheme-ink-subtle)" }}
            >
              {r.time}
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}

function ToolTile({
  title,
  glyph,
  primary,
  warm,
  danger,
  badge,
}: {
  title: string;
  glyph: string;
  primary?: boolean;
  warm?: boolean;
  danger?: boolean;
  badge?: string;
}) {
  const tint = danger
    ? "var(--scheme-rec)"
    : warm
      ? "var(--scheme-accent)"
      : primary
        ? "var(--scheme-accent)"
        : "var(--scheme-ink-faint)";
  return (
    <button
      className="relative flex h-[44px] flex-col items-center justify-center gap-1 rounded-[8px] transition-colors"
      style={{
        background:
          "linear-gradient(to bottom, color-mix(in srgb, var(--scheme-ink-faint) 6%, transparent), color-mix(in srgb, var(--scheme-ink-faint) 2%, transparent))",
        border: "0.5px solid var(--scheme-edge)",
      }}
    >
      <span className="text-[14px] leading-none" style={{ color: tint }}>
        {glyph}
      </span>
      <span
        className="text-[8.5px] font-medium"
        style={{ color: "var(--scheme-ink-subtle)" }}
      >
        {title}
      </span>
      {badge ? (
        <span
          className="absolute right-1 top-1 flex h-[13px] min-w-[13px] items-center justify-center rounded-full px-[3px] text-[8px] font-bold"
          style={{ background: "var(--scheme-accent)", color: "var(--scheme-bg)" }}
        >
          {badge}
        </span>
      ) : null}
    </button>
  );
}

function ToolsGrid() {
  return (
    <div>
      <ChannelEyebrow label="Tools" />
      <div className="grid grid-cols-3 gap-1.5">
        {TOOLS.map((tool) => (
          <ToolTile key={tool.title} {...tool} />
        ))}
      </div>
    </div>
  );
}

// ── Header ──────────────────────────────────────────────────────────

function TrayHeader({ t }: { t: TrayTreatments }) {
  return (
    <div
      className="relative flex items-center gap-2.5 px-3 py-2.5"
      style={t.strips ? { background: "var(--scheme-strip-top)" } : undefined}
    >
      <div
        className="flex h-[26px] w-[26px] items-center justify-center rounded-[7px]"
        style={{
          background: "color-mix(in srgb, var(--scheme-ink) 92%, transparent)",
          boxShadow: "0 1px 3px var(--scheme-bezel-shadow)",
        }}
      >
        <span
          className="font-display text-[15px] font-semibold leading-none"
          style={{ color: "var(--scheme-bg)" }}
        >
          t
        </span>
      </div>
      <div className="flex flex-col gap-0.5">
        <span
          className="text-[12.5px] font-semibold leading-none"
          style={{ color: "var(--scheme-ink)" }}
        >
          Talkie Agent
        </span>
        <span
          className="text-[9.5px] leading-none"
          style={{ color: "var(--scheme-ink-subtle)" }}
        >
          {t.recording ? "Listening for dictation" : "Ready for ⌃⌥⇧⌘D"}
        </span>
      </div>
      <div className="ml-auto">
        <StatusPill recording={t.recording} />
      </div>
      {t.strips ? (
        <span
          className="absolute bottom-0 left-3 right-3 h-px"
          style={{ background: "var(--scheme-edge)" }}
        />
      ) : null}
    </div>
  );
}

function StatusPill({ recording }: { recording: boolean }) {
  return (
    <span
      className="flex h-[18px] items-center rounded-full px-2 text-[8.5px] font-bold uppercase tracking-status"
      style={
        recording
          ? { background: "var(--scheme-rec)", color: "#fff" }
          : {
              color: "var(--scheme-accent)",
              background: "color-mix(in srgb, var(--scheme-accent) 12%, transparent)",
              border: "0.5px solid color-mix(in srgb, var(--scheme-accent) 34%, transparent)",
            }
      }
    >
      {recording ? "Rec" : "Ready"}
    </span>
  );
}

// ── Proposed tray ───────────────────────────────────────────────────

export function AgentTray({ treatments: t }: { treatments: TrayTreatments }) {
  return (
    <div
      className="relative w-[320px] overflow-hidden rounded-[14px] font-mono shadow-artifact"
      style={{
        background: "var(--scheme-bg)",
        border: "0.5px solid var(--scheme-edge-strong)",
      }}
    >
      {t.graticule ? (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 opacity-40"
          style={{
            backgroundImage:
              "linear-gradient(to right, var(--scheme-graticule) 0.5px, transparent 0.5px), linear-gradient(to bottom, var(--scheme-graticule) 0.5px, transparent 0.5px)",
            backgroundSize: "26px 26px",
          }}
        />
      ) : null}

      <div className="relative z-[2]">
        <TrayHeader t={t} />
        <div className="flex flex-col gap-2.5 px-2.5 pb-2.5 pt-1.5">
          <Composer t={t} />
          <RecentList />
          <ToolsGrid />
        </div>
      </div>
    </div>
  );
}

// ── Current tray (faithful before) ──────────────────────────────────

const CURRENT_BG = "#040405";
const CURRENT_AMBER = "#F29E47";
const CURRENT_REC = "#FF5346";

export function AgentTrayCurrent() {
  const sectionLabel = (s: string) => (
    <div
      className="px-1.5 pb-1 text-[8.5px] font-semibold uppercase tracking-eyebrow"
      style={{ color: "rgba(255,255,255,0.4)" }}
    >
      {s}
    </div>
  );

  const card = "rounded-[7px] border border-white/[0.055] bg-white/[0.024]";

  return (
    <div
      className="w-[320px] overflow-hidden rounded-[14px] font-mono"
      style={{ background: CURRENT_BG, border: "0.5px solid rgba(255,255,255,0.1)" }}
    >
      {/* header */}
      <div className="flex items-center gap-2.5 px-3 py-2.5">
        <div className="flex h-[26px] w-[26px] items-center justify-center rounded-[7px] bg-white/90">
          <span className="text-[14px] font-bold leading-none text-black/80">t</span>
        </div>
        <div className="flex flex-col gap-0.5">
          <span className="text-[12.5px] font-semibold leading-none text-white">
            Talkie Agent
          </span>
          <span className="text-[9.5px] leading-none text-white/50">Ready for ⌃⌥⇧⌘D</span>
        </div>
        <span className="ml-auto flex h-[18px] items-center rounded-full border border-white/20 px-2 text-[8.5px] font-bold uppercase tracking-status text-white/55">
          Ready
        </span>
      </div>

      <div className="flex flex-col gap-2 px-2 pb-2">
        {/* NOW */}
        <div>
          {sectionLabel("Now")}
          <div className={card}>
            <div className="flex h-10 items-center gap-2 px-1.5">
              <div className="flex h-6 w-6 items-center justify-center rounded-[5px] border border-white/[0.06] bg-white/[0.03]">
                <span className="text-[11px]" style={{ color: CURRENT_REC }}>
                  ◉
                </span>
              </div>
              <div className="flex flex-1 flex-col gap-0.5">
                <span className="text-[12px] font-medium text-white">Start Recording</span>
                <span className="text-[10px] text-white/55">Ready</span>
              </div>
              <span className="rounded-[4px] bg-white/[0.045] px-1.5 py-0.5 text-[10px] font-semibold text-white/55">
                ⌃⌥⇧⌘D
              </span>
            </div>
          </div>
        </div>

        {/* INPUT */}
        <div>
          {sectionLabel("Input")}
          <div className={card}>
            <div className="flex h-9 items-center gap-2 px-1.5">
              <div className="flex h-6 w-6 items-center justify-center rounded-[5px] border border-white/[0.06] bg-white/[0.03]">
                <span className="text-[11px] text-white/70">◓</span>
              </div>
              <span className="flex-1 text-[12px] font-medium text-white/80">
                Yeti Stereo Microphone
              </span>
              <span className="text-[9px] text-white/40">⌄</span>
            </div>
          </div>
        </div>

        {/* RECENT */}
        <div>
          <div className="flex items-center px-1.5 pb-1">
            <span className="text-[8.5px] font-semibold uppercase tracking-eyebrow text-white/40">
              Recent
            </span>
            <span className="ml-auto text-[8.5px] font-semibold uppercase tracking-ch text-white/50">
              All ›
            </span>
          </div>
          <div className={card}>
            {RECENT.map((r, i) => (
              <div
                key={i}
                className={cn(
                  "flex items-center gap-2 px-2 py-[6px]",
                  i < RECENT.length - 1 && "border-b border-white/[0.04]"
                )}
              >
                <span className="h-[3px] w-[3px] rounded-full bg-white/40" />
                <span className="flex-1 truncate text-[11px] text-white/75">{r.preview}</span>
                <span className="text-[9px] text-white/40">{r.time}</span>
              </div>
            ))}
          </div>
        </div>

        {/* TOOLS */}
        <div>
          {sectionLabel("Tools")}
          <div className="grid grid-cols-3 gap-1.5">
            {TOOLS.map((tool) => (
              <div
                key={tool.title}
                className="flex h-[42px] flex-col items-center justify-center gap-1 rounded-[8px] border border-white/[0.09] bg-white/[0.034]"
              >
                <span
                  className="text-[14px] leading-none"
                  style={{
                    color: tool.danger
                      ? "rgba(255,83,70,0.62)"
                      : tool.warm
                        ? CURRENT_AMBER
                        : tool.primary
                          ? "rgba(255,255,255,0.72)"
                          : "rgba(255,255,255,0.54)",
                  }}
                >
                  {tool.glyph}
                </span>
                <span className="text-[8.5px] font-medium text-white/50">{tool.title}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
