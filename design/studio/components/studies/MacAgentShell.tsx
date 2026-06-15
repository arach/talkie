"use client";

/**
 * Mac Agent Shell — navigation + IA study for the TalkieAgent window.
 *
 * Three problems, one window:
 *   1. The MAIN RAIL (far-left "main talkie agent bar") today carries 10
 *      destinations across 4 group headers. Simplify to a PRIMARY TRIO —
 *      Agents · History · Permissions — with the rest demoted under a
 *      "…" OVERFLOW (kept as a stop-gap; they were never carefully
 *      designed and will be removed), and Settings pinned in the FOOTER.
 *   2. The SETTINGS SECTION PICKER header (today a tiny "‹ SETTINGS"
 *      eyebrow) should read like a proper header.
 *   3. The AGENTS landing = a STATUS STRIP (runtime/adapters/jobs) over an
 *      ASSISTANT WELL (the conversation), per the picked direction.
 *
 * Everything here is a flat mock against the SCOPE light palette so we can
 * compare treatments before porting to AgentHomeShellView / SettingsView.
 */

import { SCOPE } from "@/lib/scope-tokens";

export type ShellSurface = "agents" | "logs" | "settings";
export type RailMode = "menu" | "group" | "tucked";
export type SettingsHeader = "titled" | "segmented" | "breadcrumb";

const RAIL_ICON = 40; // matches SidebarLayout.railWidth
const LABEL_W = 168;
const MONO = "var(--theme-font-mono)";

// ── Public component ──────────────────────────────────────────────────

export function MacAgentShell({
  surface = "agents",
  railMode = "menu",
  settingsHeader = "titled",
}: {
  surface?: ShellSurface;
  railMode?: RailMode;
  settingsHeader?: SettingsHeader;
}) {
  return (
    <section
      className="mx-auto overflow-hidden rounded-md"
      style={{
        width: "100%",
        maxWidth: 1180,
        background: SCOPE.canvas,
        color: SCOPE.ink,
        border: `0.5px solid ${SCOPE.edge}`,
        boxShadow: "0 8px 30px rgba(0,0,0,0.08), 0 2px 6px rgba(0,0,0,0.04)",
        fontFamily: MONO,
        WebkitFontSmoothing: "antialiased",
        MozOsxFontSmoothing: "grayscale",
      }}
    >
      <Titlebar />
      <div
        className="grid"
        style={{ gridTemplateColumns: `${RAIL_ICON + LABEL_W}px minmax(0,1fr)`, minHeight: 720 }}
      >
        <MainRail active={surface} mode={railMode} />
        {surface === "agents" ? (
          <AgentsLanding />
        ) : surface === "logs" ? (
          <LogsSurface />
        ) : (
          <SettingsSurface header={settingsHeader} />
        )}
      </div>
    </section>
  );
}

// ── Titlebar ──────────────────────────────────────────────────────────

function Titlebar() {
  return (
    <div
      className="flex items-center gap-2 px-4 py-2.5"
      style={{ borderBottom: `0.5px solid ${SCOPE.edge}`, background: SCOPE.chrome }}
    >
      <div className="flex gap-1.5">
        {[0, 1, 2].map((i) => (
          <span key={i} className="h-3 w-3 rounded-full" style={{ background: "#DEDEDD" }} />
        ))}
      </div>
      <div
        className="mx-auto text-[9px] uppercase"
        style={{ color: SCOPE.inkFaint, fontFamily: MONO, letterSpacing: "0.20em" }}
      >
        Talkie Agent
      </div>
      <div className="invisible flex gap-1.5">
        {[0, 1, 2].map((i) => (
          <span key={i} className="h-3 w-3 rounded-full" />
        ))}
      </div>
    </div>
  );
}

// ── Main rail ─────────────────────────────────────────────────────────

type RailId = "agents" | "history" | "permissions" | "logs";

const PRIMARY: { id: RailId; label: string; sub: string; icon: IconName }[] = [
  { id: "agents", label: "Agents", sub: "Runtime + assistant", icon: "agents" },
  { id: "history", label: "History", sub: "Memos + media", icon: "history" },
  { id: "permissions", label: "Permissions", sub: "macOS access", icon: "shield" },
  { id: "logs", label: "Logs", sub: "Live diagnostics", icon: "logs" },
];

const DEMOTED: { label: string; icon: IconName }[] = [
  { label: "Capture", icon: "capture" },
  { label: "Tray", icon: "tray" },
  { label: "Dictation", icon: "wave" },
  { label: "Overlays", icon: "overlay" },
  { label: "Server", icon: "server" },
];

function MainRail({ active, mode }: { active: ShellSurface; mode: RailMode }) {
  return (
    <aside
      className="flex flex-col"
      style={{ background: SCOPE.pane, borderRight: `0.5px solid ${SCOPE.edge}` }}
    >
      {/* Brand header — amber "t" tile + wordmark */}
      <div className="flex items-center gap-2.5 px-3" style={{ height: 52 }}>
        <div
          className="grid place-items-center rounded-[7px] text-[14px] font-bold"
          style={{ width: 24, height: 24, background: SCOPE.amber, color: SCOPE.white }}
        >
          t
        </div>
        <div className="leading-tight">
          <div className="text-[12px] font-semibold" style={{ color: SCOPE.ink }}>
            Talkie
          </div>
          <div
            className="text-[8px] uppercase"
            style={{ color: SCOPE.inkFainter, letterSpacing: "0.18em" }}
          >
            Agent
          </div>
        </div>
      </div>

      <div
        className="mx-3 mb-2"
        style={{ height: 0.5, background: SCOPE.rule }}
      />

      {/* Primary trio */}
      <nav className="flex flex-col gap-0.5 px-2">
        {PRIMARY.map((p) => (
          <RailRow
            key={p.id}
            icon={p.icon}
            label={p.label}
            sub={p.sub}
            selected={p.id === active}
          />
        ))}
      </nav>

      {/* Overflow — the "…" that holds the demoted, soon-to-go sections.
          The flyout is a hover artifact, so only pop it open on the Agents
          surface; on Settings it stays a collapsed row so it can't overlap
          the section picker. */}
      <Overflow mode={mode} showFlyout={active === "agents"} />

      <div className="flex-1" />

      {/* Footer — Settings pinned at the bottom, rail-slot gear */}
      <div className="mx-2 mb-1" style={{ height: 0.5, background: SCOPE.rule }} />
      <div className="px-2 pb-2">
        <RailRow icon="gear" label="Settings" sub="Preferences" selected={false} muted />
      </div>
    </aside>
  );
}

function Overflow({ mode, showFlyout = true }: { mode: RailMode; showFlyout?: boolean }) {
  if (mode === "group") {
    return (
      <div className="mt-3 px-2">
        <div
          className="px-2.5 pb-1 text-[8px] uppercase"
          style={{ color: SCOPE.inkFainter, letterSpacing: "0.2em" }}
        >
          More · stop-gap
        </div>
        <div className="flex flex-col gap-0.5">
          {DEMOTED.map((d) => (
            <RailRow key={d.label} icon={d.icon} label={d.label} selected={false} muted dense />
          ))}
        </div>
      </div>
    );
  }

  if (mode === "tucked") {
    return (
      <div className="mt-2 px-2">
        <RailRow icon="more" label="More" sub="Capture · Server · Logs…" selected={false} muted />
      </div>
    );
  }

  // mode === "menu" — a "More" row with a faux popover flyout
  return (
    <div className="relative mt-2 px-2">
      <RailRow icon="more" label="More" sub="6 sections" selected={false} muted hasFlyout />
      {!showFlyout ? null : (
      <div
        className="absolute left-[calc(100%-6px)] top-0 z-10 w-[176px] rounded-[10px] p-1.5"
        style={{
          background: SCOPE.white,
          border: `0.5px solid ${SCOPE.edge}`,
          boxShadow: "0 12px 30px rgba(0,0,0,0.14), 0 2px 6px rgba(0,0,0,0.06)",
        }}
      >
        <div
          className="px-2 pb-1 pt-0.5 text-[8px] uppercase"
          style={{ color: SCOPE.inkFainter, letterSpacing: "0.2em" }}
        >
          Stop-gap · retiring
        </div>
        {DEMOTED.map((d) => (
          <div
            key={d.label}
            className="flex items-center gap-2 rounded-[6px] px-2 py-1.5 text-[12px]"
            style={{ color: SCOPE.inkMid }}
          >
            <span style={{ color: SCOPE.inkFainter }}>
              <Icon name={d.icon} size={14} />
            </span>
            {d.label}
          </div>
        ))}
      </div>
      )}
    </div>
  );
}

function RailRow({
  icon,
  label,
  sub,
  selected,
  muted = false,
  dense = false,
  hasFlyout = false,
}: {
  icon: IconName;
  label: string;
  sub?: string;
  selected: boolean;
  muted?: boolean;
  dense?: boolean;
  hasFlyout?: boolean;
}) {
  const ink = selected ? SCOPE.ink : muted ? SCOPE.inkFaint : SCOPE.inkMid;
  return (
    <div
      className="relative flex items-center gap-2.5 rounded-[7px]"
      style={{
        padding: dense ? "5px 8px" : "7px 8px",
        background: selected ? SCOPE.amberFaint : "transparent",
      }}
    >
      {/* Armed leading stripe on selection (editorial indicator) */}
      {selected ? (
        <span
          className="absolute left-0 top-1/2 -translate-y-1/2 rounded-full"
          style={{ width: 2.5, height: dense ? 14 : 18, background: SCOPE.amber }}
        />
      ) : null}
      <span
        className="grid place-items-center"
        style={{ width: 20, color: selected ? SCOPE.amber : ink }}
      >
        <Icon name={icon} size={dense ? 14 : 16} />
      </span>
      <span className="min-w-0 flex-1 leading-tight">
        <span
          className="block truncate"
          style={{ fontSize: dense ? 11.5 : 12.5, fontWeight: selected ? 600 : 500, color: ink }}
        >
          {label}
        </span>
        {sub && !dense ? (
          <span className="block truncate text-[9px]" style={{ color: SCOPE.inkFainter }}>
            {sub}
          </span>
        ) : null}
      </span>
      {hasFlyout ? (
        <span className="text-[11px]" style={{ color: SCOPE.inkFainter }}>
          ›
        </span>
      ) : null}
    </div>
  );
}

// ── Agents landing — status strip + assistant well ────────────────────

function AgentsLanding() {
  return (
    <main className="flex min-w-0 flex-col" style={{ background: SCOPE.canvas }}>
      <SurfaceHeader title="Agents" subtitle="What's running, and the assistant you talk to." />

      <div className="flex flex-1 flex-col gap-5 overflow-auto px-7 py-6">
        {/* Status strip */}
        <div
          className="flex flex-wrap items-center gap-x-6 gap-y-3 rounded-[12px] px-5 py-4"
          style={{ background: SCOPE.white, border: `0.5px solid ${SCOPE.edge}` }}
        >
          <Stat dot={SCOPE.amber} label="Runtime" value="Ready" mono />
          <Divider />
          <Stat label="Adapters" value="3 / 4" />
          <Divider />
          <Stat label="Active work" value="1 job" />
          <Divider />
          <Stat label="Bridge" value="Running" dot="#3D9B6B" />
          <div className="ml-auto">
            <Chip>Agent-owned</Chip>
          </div>
        </div>

        {/* Assistant well */}
        <div
          className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[12px]"
          style={{ background: SCOPE.white, border: `0.5px solid ${SCOPE.edge}` }}
        >
          <div
            className="flex items-center justify-between px-4 py-2.5"
            style={{ borderBottom: `0.5px solid ${SCOPE.ruleSubtle}` }}
          >
            <span className="text-[11px] font-semibold" style={{ color: SCOPE.ink }}>
              Assistant
            </span>
            <span
              className="text-[9px] uppercase"
              style={{ color: SCOPE.inkFainter, letterSpacing: "0.16em" }}
            >
              · conversation
            </span>
          </div>

          <div className="flex flex-1 flex-col gap-4 px-5 py-5">
            <Bubble who="You" body="Summarize the three captures from this morning." />
            <Bubble
              who="Talkie"
              live
              body="Pulled the 3 captures from the live tray and drafted a summary — opening it in Library now."
            />
          </div>

          {/* Composer */}
          <div className="px-4 pb-4">
            <div
              className="flex items-center gap-3 rounded-[10px] px-3 py-2.5"
              style={{ background: SCOPE.canvas, border: `0.5px solid ${SCOPE.edge}` }}
            >
              <span style={{ color: SCOPE.amber }}>
                <Icon name="mic" size={16} />
              </span>
              <span className="flex-1 text-[12px]" style={{ color: SCOPE.inkFainter }}>
                Ask the agent, or hold ⌥Space to talk…
              </span>
              <span
                className="grid h-6 w-6 place-items-center rounded-full"
                style={{ background: SCOPE.amber, color: SCOPE.white }}
              >
                ↑
              </span>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}

function Stat({
  label,
  value,
  dot,
  mono,
}: {
  label: string;
  value: string;
  dot?: string;
  mono?: boolean;
}) {
  return (
    <div className="flex items-center gap-2">
      {dot ? <span className="h-2 w-2 rounded-full" style={{ background: dot }} /> : null}
      <span className="text-[10px] uppercase" style={{ color: SCOPE.inkFainter, letterSpacing: "0.12em" }}>
        {label}
      </span>
      <span
        className="text-[12px] font-semibold"
        style={{ color: SCOPE.ink, fontFamily: mono ? MONO : undefined }}
      >
        {value}
      </span>
    </div>
  );
}

function Divider() {
  return <span style={{ width: 0.5, height: 18, background: SCOPE.rule }} />;
}

function Bubble({ who, body, live }: { who: "You" | "Talkie"; body: string; live?: boolean }) {
  const isAgent = who === "Talkie";
  return (
    <div className="flex gap-3">
      <span
        className="grid h-6 w-6 shrink-0 place-items-center rounded-full text-[10px] font-bold"
        style={{
          background: isAgent ? SCOPE.amberFaint : SCOPE.selection,
          color: isAgent ? SCOPE.amberDeep : SCOPE.inkFaint,
        }}
      >
        {isAgent ? "t" : "Y"}
      </span>
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-[11px] font-semibold" style={{ color: SCOPE.ink }}>
            {who}
          </span>
          {live ? (
            <span className="flex items-center gap-1">
              <span className="h-1.5 w-1.5 rounded-full" style={{ background: SCOPE.amber }} />
              <span className="text-[9px] font-semibold" style={{ color: SCOPE.amberDeep }}>
                live
              </span>
            </span>
          ) : null}
        </div>
        <p className="mt-1 max-w-[560px] text-[12.5px] leading-relaxed" style={{ color: SCOPE.inkMid }}>
          {body}
        </p>
      </div>
    </div>
  );
}

// ── Logs surface — first-class live log viewer ────────────────────────

type LogLevel = "info" | "warn" | "error";
interface LogLine {
  t: string;
  level: LogLevel;
  channel: string;
  msg: string;
}

const LOG_LINES: LogLine[] = [
  { t: "12:45:07.214", level: "info", channel: "runtime", msg: "Bridge healthy · 3 adapters online · rtt 4ms" },
  { t: "12:45:06.880", level: "info", channel: "capture", msg: "Promoted 2 tray assets → durable media" },
  { t: "12:45:05.142", level: "warn", channel: "transcribe", msg: "Whisper warmup slow (1.8s) on first segment" },
  { t: "12:45:04.001", level: "info", channel: "server", msg: "Job a91f completed in 412ms" },
  { t: "12:45:01.770", level: "error", channel: "paste", msg: "Accessibility denied — fell back to clipboard" },
  { t: "12:45:00.330", level: "info", channel: "dictation", msg: "Segment committed · 14 words · model small.en" },
  { t: "12:44:58.912", level: "info", channel: "runtime", msg: "Ping ok · executor idle" },
  { t: "12:44:57.640", level: "warn", channel: "overlay", msg: "Island frame skipped — display reconfigured" },
  { t: "12:44:55.218", level: "info", channel: "tray", msg: "Screenshot ef59a8 captured · 812×855" },
  { t: "12:44:53.004", level: "info", channel: "server", msg: "Spawned bun bridge · pid 95492" },
  { t: "12:44:51.882", level: "error", channel: "transcribe", msg: "Model load retry 1/3 — checksum mismatch" },
  { t: "12:44:50.111", level: "info", channel: "runtime", msg: "Boot sequence complete in 1.42s" },
];

function levelTone(level: LogLevel): { dot: string; text: string; label: string } {
  switch (level) {
    case "warn":
      return { dot: SCOPE.amber, text: SCOPE.amberDeep, label: "WARN" };
    case "error":
      return { dot: SCOPE.alert, text: SCOPE.alert, label: "ERROR" };
    default:
      return { dot: SCOPE.inkFainter, text: SCOPE.inkFaint, label: "INFO" };
  }
}

function LogsSurface() {
  const errorCount = LOG_LINES.filter((l) => l.level === "error").length;
  return (
    <main className="flex min-w-0 flex-col" style={{ background: SCOPE.canvas }}>
      <SurfaceHeader
        title="Logs"
        subtitle="Live runtime diagnostics — agent, server, capture, and paste pipeline."
      />

      {/* Toolbar: level filter · channel · search · live tail */}
      <div
        className="flex items-center gap-3 px-7 py-3"
        style={{ borderBottom: `0.5px solid ${SCOPE.ruleSubtle}`, background: SCOPE.canvas }}
      >
        <div
          className="flex items-center gap-0.5 rounded-[7px] p-0.5"
          style={{ background: SCOPE.pane, border: `0.5px solid ${SCOPE.edgeSubtle}` }}
        >
          {["All", "Info", "Warn", "Error"].map((lvl, i) => (
            <button
              key={lvl}
              className="rounded-[5px] px-2.5 py-1 text-[10.5px] font-semibold"
              style={{
                background: i === 0 ? SCOPE.white : "transparent",
                color: i === 0 ? SCOPE.ink : SCOPE.inkFaint,
                boxShadow: i === 0 ? "0 0.5px 1px rgba(28,28,26,0.06)" : "none",
              }}
            >
              {lvl}
            </button>
          ))}
        </div>

        <div
          className="flex items-center gap-1.5 rounded-[7px] px-2.5 py-1.5 text-[11px]"
          style={{ background: SCOPE.white, border: `0.5px solid ${SCOPE.edgeSubtle}`, color: SCOPE.inkMid }}
        >
          All channels
          <span style={{ color: SCOPE.inkFainter }}>▾</span>
        </div>

        <div
          className="flex flex-1 items-center gap-2 rounded-[7px] px-2.5 py-1.5 text-[11px]"
          style={{ background: SCOPE.white, border: `0.5px solid ${SCOPE.edgeSubtle}`, color: SCOPE.inkFainter }}
        >
          <span>⌕</span>
          filter logs…
        </div>

        <div
          className="flex items-center gap-1.5 rounded-full px-2.5 py-1.5 text-[10.5px] font-semibold"
          style={{ background: "rgba(61,155,107,0.10)", color: "#2C7A53" }}
        >
          <span className="h-1.5 w-1.5 rounded-full" style={{ background: "#3D9B6B" }} />
          Live
        </div>
      </div>

      {/* Feed */}
      <div className="min-h-0 flex-1 overflow-auto px-7 py-4">
        <div
          className="overflow-hidden rounded-[10px]"
          style={{ background: SCOPE.white, border: `0.5px solid ${SCOPE.edge}` }}
        >
          {/* column header */}
          <div
            className="flex items-center gap-3 px-4 py-2 text-[8.5px] uppercase"
            style={{ borderBottom: `0.5px solid ${SCOPE.ruleSubtle}`, color: SCOPE.inkFainter, letterSpacing: "0.16em" }}
          >
            <span style={{ width: 88 }}>Time</span>
            <span style={{ width: 56 }}>Level</span>
            <span style={{ width: 84 }}>Channel</span>
            <span>Message</span>
          </div>

          {LOG_LINES.map((line, i) => {
            const tone = levelTone(line.level);
            return (
              <div
                key={i}
                className="flex items-center gap-3 px-4 py-[7px] text-[11.5px]"
                style={{
                  borderBottom: i === LOG_LINES.length - 1 ? "none" : `0.5px solid ${SCOPE.ruleSoft}`,
                  background: line.level === "error" ? "rgba(196,58,28,0.035)" : "transparent",
                }}
              >
                <span style={{ width: 88, color: SCOPE.inkFainter, fontFamily: MONO }}>{line.t}</span>
                <span className="flex items-center gap-1.5" style={{ width: 56 }}>
                  <span className="h-1.5 w-1.5 rounded-full" style={{ background: tone.dot }} />
                  <span className="text-[9px] font-bold" style={{ color: tone.text, letterSpacing: "0.04em" }}>
                    {tone.label}
                  </span>
                </span>
                <span
                  className="truncate text-[10px] font-semibold uppercase"
                  style={{ width: 84, color: SCOPE.inkFaint, letterSpacing: "0.06em" }}
                >
                  {line.channel}
                </span>
                <span className="min-w-0 flex-1 truncate" style={{ color: SCOPE.inkMid, fontFamily: MONO }}>
                  {line.msg}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      {/* Status footer */}
      <div
        className="flex items-center gap-4 px-7 py-2.5 text-[10px]"
        style={{ borderTop: `0.5px solid ${SCOPE.ruleSubtle}`, color: SCOPE.inkFaint, fontFamily: MONO }}
      >
        <span>tailing</span>
        <span>· 1,284 lines</span>
        <span style={{ color: errorCount ? SCOPE.alert : SCOPE.inkFaint }}>· {errorCount} errors</span>
        <span className="ml-auto flex items-center gap-1.5" style={{ color: SCOPE.inkMid }}>
          Open in Console <span aria-hidden>↗</span>
        </span>
      </div>
    </main>
  );
}

// ── Settings surface — secondary picker rail + content ────────────────

const SETTINGS_GROUPS: { title: string; items: { label: string; icon: IconName }[] }[] = [
  { title: "Appearance", items: [{ label: "Theme & Colors", icon: "brush" }] },
  {
    title: "Behavior",
    items: [
      { label: "Shortcuts", icon: "cmd" },
      { label: "Capture", icon: "capture" },
      { label: "Sounds", icon: "speaker" },
      { label: "Auto-Paste", icon: "paste" },
      { label: "Overlay", icon: "overlay" },
      { label: "Audio", icon: "mic" },
    ],
  },
  {
    title: "System",
    items: [
      { label: "Transcription", icon: "wave" },
      { label: "Files & Data", icon: "folder" },
      { label: "Permissions", icon: "shield" },
      { label: "About", icon: "info" },
    ],
  },
];

function SettingsSurface({ header }: { header: SettingsHeader }) {
  return (
    <div className="grid min-w-0" style={{ gridTemplateColumns: "190px minmax(0,1fr)" }}>
      {/* Secondary picker rail */}
      <aside className="flex flex-col" style={{ background: SCOPE.chrome, borderRight: `0.5px solid ${SCOPE.edge}` }}>
        <SettingsPickerHeader variant={header} />
        <nav className="flex flex-col gap-4 overflow-auto px-2.5 pb-4">
          {SETTINGS_GROUPS.map((g, gi) => (
            <div key={g.title} className="flex flex-col gap-1">
              <div
                className="px-2 text-[8.5px] uppercase"
                style={{
                  color: gi === 0 ? SCOPE.amber : SCOPE.inkFaint,
                  letterSpacing: "0.18em",
                  fontWeight: 700,
                }}
              >
                {g.title}
              </div>
              {g.items.map((it, ii) => {
                const selected = gi === 0 && ii === 0;
                return (
                  <div
                    key={it.label}
                    className="relative flex items-center gap-2 rounded-[6px] px-2 py-[6px]"
                    style={{ background: selected ? SCOPE.white : "transparent" }}
                  >
                    {selected ? (
                      <span
                        className="absolute left-0 top-1/2 -translate-y-1/2 rounded-full"
                        style={{ width: 2, height: 16, background: SCOPE.amber }}
                      />
                    ) : null}
                    <span style={{ color: selected ? SCOPE.ink : SCOPE.inkFaint, width: 16 }}>
                      <Icon name={it.icon} size={13} />
                    </span>
                    <span
                      className="text-[10.5px] uppercase"
                      style={{
                        color: selected ? SCOPE.ink : SCOPE.inkMid,
                        letterSpacing: "0.04em",
                        fontWeight: selected ? 600 : 500,
                      }}
                    >
                      {it.label}
                    </span>
                  </div>
                );
              })}
            </div>
          ))}
        </nav>
      </aside>

      {/* Content — appearance page stub for context */}
      <main className="min-w-0 overflow-auto" style={{ background: SCOPE.canvas }}>
        <SurfaceHeader title="Appearance" subtitle="Customize how Talkie Agent looks." eyebrow="Appearance" />
        <div className="flex flex-col gap-6 px-7 py-6">
          <FieldBlock label="Color Theme">
            <div className="flex gap-3">
              {["Pro", "Pro", "Terminal", "Dark Matte", "Light"].map((name, i) => (
                <div key={i} className="flex flex-col items-center gap-1.5">
                  <div
                    className="grid place-items-center rounded-[8px]"
                    style={{
                      width: 76,
                      height: 50,
                      background: i === 4 ? "#EFEFEE" : "#101010",
                      border: i === 0 ? `1.5px solid ${SCOPE.amber}` : `0.5px solid ${SCOPE.edge}`,
                    }}
                  >
                    <span
                      className="h-3 w-3 rounded-full"
                      style={{ background: i === 4 ? SCOPE.amber : i === 2 ? "#9aa" : "#4d7bf3" }}
                    />
                  </div>
                  <span className="text-[9px]" style={{ color: SCOPE.inkFaint }}>
                    {name}
                  </span>
                </div>
              ))}
            </div>
          </FieldBlock>

          <FieldBlock label="Accent Color">
            <div className="flex gap-3">
              {["#4d7bf3", "#2f6bd6", "#9b59b6", "#e8568f", "#e0483a", "#e08a2a", "#e8c43a", "#3fae6e", "#3aa6a6", "#8a8a8a"].map(
                (c, i) => (
                  <span
                    key={i}
                    className="h-6 w-6 rounded-full"
                    style={{ background: c, outline: i === 0 ? `2px solid ${SCOPE.amber}` : "none", outlineOffset: 2 }}
                  />
                )
              )}
            </div>
          </FieldBlock>
        </div>
      </main>
    </div>
  );
}

/** The thing the user wants "nicer" — three header treatments to compare. */
function SettingsPickerHeader({ variant }: { variant: SettingsHeader }) {
  if (variant === "segmented") {
    return (
      <div className="px-2.5 pb-3 pt-4">
        <div
          className="flex items-center gap-1.5 rounded-[8px] px-1.5 py-1"
          style={{ background: SCOPE.pane, border: `0.5px solid ${SCOPE.edgeSubtle}` }}
        >
          <button
            className="grid h-6 w-6 place-items-center rounded-[6px]"
            style={{ background: SCOPE.white, border: `0.5px solid ${SCOPE.edgeSubtle}`, color: SCOPE.inkFaint }}
          >
            <Icon name="back" size={12} />
          </button>
          <span
            className="text-[10px] font-bold uppercase"
            style={{ color: SCOPE.ink, letterSpacing: "0.16em" }}
          >
            Settings
          </span>
        </div>
      </div>
    );
  }

  if (variant === "breadcrumb") {
    return (
      <div className="px-3 pb-3 pt-4">
        <button className="flex items-center gap-1.5" style={{ color: SCOPE.inkFaint }}>
          <Icon name="back" size={12} />
          <span className="text-[9px] uppercase" style={{ letterSpacing: "0.18em" }}>
            Agent Home
          </span>
        </button>
        <div className="mt-2 flex items-center gap-1.5">
          <span style={{ color: SCOPE.amber }}>
            <Icon name="gear" size={13} />
          </span>
          <span className="text-[14px] font-semibold" style={{ color: SCOPE.ink, fontFamily: "var(--theme-font-display)" }}>
            Settings
          </span>
          <span className="text-[11px]" style={{ color: SCOPE.inkFainter }}>
            › Appearance
          </span>
        </div>
        <div className="mt-2.5" style={{ height: 0.5, background: SCOPE.rule }} />
      </div>
    );
  }

  // "titled" — back chip + display title + rule
  return (
    <div className="px-3 pb-3 pt-4">
      <div className="flex items-center gap-2">
        <button
          className="grid h-[22px] w-[22px] place-items-center rounded-[6px]"
          style={{ background: SCOPE.white, border: `0.5px solid ${SCOPE.edgeSubtle}`, color: SCOPE.inkFaint }}
        >
          <Icon name="back" size={12} />
        </button>
        <span
          className="text-[18px] font-semibold leading-none"
          style={{ color: SCOPE.ink, fontFamily: "var(--theme-font-display)" }}
        >
          Settings
        </span>
      </div>
      <div className="mt-3" style={{ height: 0.5, background: SCOPE.rule }} />
    </div>
  );
}

// ── Shared bits ───────────────────────────────────────────────────────

function SurfaceHeader({
  title,
  subtitle,
  eyebrow,
}: {
  title: string;
  subtitle: string;
  eyebrow?: string;
}) {
  return (
    <div className="px-7 pb-4 pt-6" style={{ background: SCOPE.canvas, borderBottom: `0.5px solid ${SCOPE.ruleSubtle}` }}>
      {eyebrow ? (
        <div
          className="mb-1 text-[9px] font-bold uppercase"
          style={{ color: SCOPE.amber, letterSpacing: "0.18em" }}
        >
          {eyebrow}
        </div>
      ) : null}
      <h2
        className="m-0 text-[24px] font-semibold leading-none"
        style={{ color: SCOPE.ink, fontFamily: "var(--theme-font-display)" }}
      >
        {title}
      </h2>
      <p className="mt-2 text-[12px]" style={{ color: SCOPE.inkFaint }}>
        {subtitle}
      </p>
    </div>
  );
}

function FieldBlock({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-3">
      <div className="text-[9px] font-bold uppercase" style={{ color: SCOPE.inkFaint, letterSpacing: "0.16em" }}>
        {label}
      </div>
      <div
        className="rounded-[12px] px-5 py-4"
        style={{ background: SCOPE.white, border: `0.5px solid ${SCOPE.edge}` }}
      >
        {children}
      </div>
    </div>
  );
}

function Chip({ children }: { children: React.ReactNode }) {
  return (
    <span
      className="rounded-full px-2.5 py-1 text-[9px] font-semibold uppercase"
      style={{ background: SCOPE.amberFaint, color: SCOPE.amberDeep, letterSpacing: "0.1em" }}
    >
      {children}
    </span>
  );
}

// ── Icons — minimal inline SVG set (stroke = currentColor) ────────────

type IconName =
  | "agents"
  | "history"
  | "shield"
  | "more"
  | "gear"
  | "capture"
  | "tray"
  | "wave"
  | "overlay"
  | "server"
  | "logs"
  | "mic"
  | "brush"
  | "cmd"
  | "speaker"
  | "paste"
  | "folder"
  | "info"
  | "back";

function Icon({ name, size = 16 }: { name: IconName; size?: number }) {
  const s = size;
  const p = { fill: "none", stroke: "currentColor", strokeWidth: 1.4, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  switch (name) {
    case "agents":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <circle cx="8" cy="8" r="2.2" {...p} />
          <circle cx="8" cy="2.3" r="1" {...p} />
          <circle cx="13" cy="11" r="1" {...p} />
          <circle cx="3" cy="11" r="1" {...p} />
          <path d="M8 4.5v1.3M11.3 9.6 9.7 8.9M4.7 9.6l1.6-.7" {...p} />
        </svg>
      );
    case "history":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <circle cx="8" cy="8" r="5.6" {...p} />
          <path d="M8 5v3l2 1.4" {...p} />
        </svg>
      );
    case "shield":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M8 1.8 13 3.6v3.7c0 3-2.1 5.3-5 6.9-2.9-1.6-5-3.9-5-6.9V3.6z" {...p} />
          <path d="m5.8 8 1.6 1.6L10.4 6.6" {...p} />
        </svg>
      );
    case "more":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <circle cx="3.5" cy="8" r="1.1" fill="currentColor" stroke="none" />
          <circle cx="8" cy="8" r="1.1" fill="currentColor" stroke="none" />
          <circle cx="12.5" cy="8" r="1.1" fill="currentColor" stroke="none" />
        </svg>
      );
    case "gear":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <circle cx="8" cy="8" r="2.1" {...p} />
          <path d="M8 1.6v1.7M8 12.7v1.7M14.4 8h-1.7M3.3 8H1.6M12.5 3.5l-1.2 1.2M4.7 11.3l-1.2 1.2M12.5 12.5l-1.2-1.2M4.7 4.7 3.5 3.5" {...p} />
        </svg>
      );
    case "capture":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M2.5 5V3.2A.7.7 0 0 1 3.2 2.5H5M11 2.5h1.8a.7.7 0 0 1 .7.7V5M13.5 11v1.8a.7.7 0 0 1-.7.7H11M5 13.5H3.2a.7.7 0 0 1-.7-.7V11" {...p} />
          <circle cx="8" cy="8" r="1.6" {...p} />
        </svg>
      );
    case "tray":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M2.4 9.5 3.8 4a1 1 0 0 1 1-.8h6.4a1 1 0 0 1 1 .8l1.4 5.5" {...p} />
          <path d="M2.4 9.5h3.2l.8 1.4h3.2l.8-1.4h3.2v2.4a.9.9 0 0 1-.9.9H3.3a.9.9 0 0 1-.9-.9z" {...p} />
        </svg>
      );
    case "wave":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M3 8v0M5.5 5.5v5M8 3.5v9M10.5 5.5v5M13 8v0" {...p} />
        </svg>
      );
    case "overlay":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <rect x="2.4" y="3.2" width="11.2" height="9.6" rx="1.4" {...p} />
          <rect x="8.4" y="4.6" width="3.8" height="2.2" rx="0.8" fill="currentColor" stroke="none" opacity="0.6" />
        </svg>
      );
    case "server":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <rect x="2.5" y="3" width="11" height="4" rx="1" {...p} />
          <rect x="2.5" y="9" width="11" height="4" rx="1" {...p} />
          <path d="M4.6 5h0M4.6 11h0" {...p} />
        </svg>
      );
    case "logs":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M4 2.6h6l2.5 2.5v8.3H4z" {...p} />
          <path d="M9.7 2.6V5h2.6M5.8 8h4.4M5.8 10.4h4.4" {...p} />
        </svg>
      );
    case "mic":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <rect x="6" y="2" width="4" height="7" rx="2" {...p} />
          <path d="M4 7.5a4 4 0 0 0 8 0M8 11.5V14M5.8 14h4.4" {...p} />
        </svg>
      );
    case "brush":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M11.5 2.5 13.5 4.5 7.8 10.2 5.8 8.2z" {...p} />
          <path d="M5.8 8.2c-1.6.6-1.8 2.4-2.8 3.4 1.6.5 3.8.2 4.5-1.4z" {...p} />
        </svg>
      );
    case "cmd":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M6 4.5A1.5 1.5 0 1 0 4.5 6H11A1.5 1.5 0 1 0 9.5 4.5v7A1.5 1.5 0 1 0 11 10H5A1.5 1.5 0 1 0 6.5 11.5z" {...p} />
        </svg>
      );
    case "speaker":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M3 6v4h2l3 2.5v-9L5 6z" {...p} />
          <path d="M10.5 6a3 3 0 0 1 0 4" {...p} />
        </svg>
      );
    case "paste":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <rect x="3.5" y="3" width="9" height="10" rx="1.2" {...p} />
          <path d="M6 3V2.2h4V3M6.2 7h3.6M6.2 9.4h3.6" {...p} />
        </svg>
      );
    case "folder":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M2.5 4.5a1 1 0 0 1 1-1h2.3l1.2 1.3h4.5a1 1 0 0 1 1 1v5.4a1 1 0 0 1-1 1h-8a1 1 0 0 1-1-1z" {...p} />
        </svg>
      );
    case "info":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <circle cx="8" cy="8" r="5.6" {...p} />
          <path d="M8 7.2v3.2M8 5.2v0" {...p} />
        </svg>
      );
    case "back":
      return (
        <svg width={s} height={s} viewBox="0 0 16 16">
          <path d="M9.5 3.5 5 8l4.5 4.5" {...p} />
        </svg>
      );
  }
}
