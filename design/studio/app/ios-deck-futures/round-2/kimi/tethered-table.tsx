"use client";

/**
 * The Tethered Table — Round 2 iPad at-bat (Kimi).
 *
 * SPATIAL PREMISE
 *   One task lies open on the table as a full sheet of paper. The other
 *   tasks wait as a fanned deck of slips at the left thumb. Talkie's voice
 *   disc sits at the right thumb, tied to the open task by a thread —
 *   voice travels along the thread, and the thread is the targeting.
 *
 *   No sidebar. Selection is direct manipulation: tap a slip and it comes
 *   to the table while the current sheet returns to the fan. Voice
 *   targeting is physical: the thread runs from the disc to a brass tie
 *   ring on the sheet, so "which task am I about to speak to" is answered
 *   by a line you can trace, in every state, with the text blurred.
 *
 * STATES
 *   working    Codex is on Studio Mac; the sheet shows your ask and the
 *              latest plain-language update. No percentages, no telemetry.
 *   result     The sheet becomes reading matter: headline, two short
 *              paragraphs, a facts rule, Hear result / Copy, byline.
 *   offline    The bridge owns the header, the thread goes slack and
 *              cools, the disc keeps recording locally ("kept on this
 *              iPad · delivers on reconnect"), and one Reconnect path
 *              leads. Technical evidence stays behind Connection details.
 *
 * VOICE OBJECT
 *   The amber disc + thread. Hold the disc: the thread carries a current
 *   (dash flow) while you speak; release and a droplet of voice rides the
 *   thread into the sheet's tie ring. Offline, the thread sags and the
 *   same gesture records a memo that waits for the bridge.
 *
 * Canvas is a fixed 1180×885 (12.9-inch iPad landscape, 4:3) so the
 * thread geometry can be authored, not derived.
 */

import React from "react";

// ─── Tokens (cream paper editorial, shared with Mac Compose) ─────────

const TABLE       = "#E0DFDA";
const PAPER       = "#FAFAF8";
const INK         = "#232423";
const INK_FAINT   = "rgba(35,36,35,0.55)";
const INK_FAINTER = "rgba(35,36,35,0.34)";
const INK_RULE    = "rgba(35,36,35,0.18)";
const INK_RULE_S  = "rgba(35,36,35,0.10)";
const AMBER       = "#C47D1C";
const BRASS       = "#9A6A22";
const COLD        = "#9E3B30";
const GRAPHITE    = "#5A5B5E";

// ─── Content (illustrative, shared task set with Round 1) ────────────

type TaskNature = "working" | "result" | "needsyou" | "idle";

type Task = {
  id: string;
  name: string;
  project: string;
  sentAt: string;
  nature: TaskNature;
  natureNote: string;
  ask: string;
  workingLine: string;
  lastUpdate: string;
  resultHeadline: string;
  resultBody: string[];
  facts: [string, string][];
  byline: string;
};

const TASKS: Task[] = [
  {
    id: "repair",
    name: "Repair Studio Mac connection",
    project: "Talkie",
    sentAt: "11:34",
    nature: "result",
    natureNote: "2m ago",
    ask: "The Studio Mac stopped connecting after we changed the bridge port. Make recovery obvious on iPad, then build it directly on both devices.",
    workingLine: "Checking the connection flow on Studio Mac",
    lastUpdate: "11:38",
    resultHeadline: "Recovery now starts with the Mac that needs attention.",
    resultBody: [
      "The connection screen no longer makes you hunt through settings. When a saved bridge stops responding, its recovery actions stay together and explain what Talkie knows.",
      "The discovered endpoint is offered beside the previous value — you confirm the change, nothing moves silently.",
    ],
    facts: [
      ["Changed", "Connection Center"],
      ["Verified", "iPhone + iPad"],
      ["Next", "Review on device"],
    ],
    byline: "Worked on Studio Mac in Talkie, verified for iPhone and iPad.",
  },
  {
    id: "launch-notes",
    name: "Prepare the launch notes",
    project: "usetalkie.com",
    sentAt: "10:58",
    nature: "working",
    natureNote: "7m in",
    ask: "Pull the launch notes for the site refresh into shape. Lead with what changed for people who dictate all day, and keep it under a page.",
    workingLine: "Drafting from the release branch",
    lastUpdate: "11:31",
    resultHeadline: "The launch notes fit on one page and open with dictation.",
    resultBody: [
      "The draft leads with hold-to-talk on Mac and the iPad supervision work, cuts the internal roadmap section, and keeps every claim checkable against the release branch.",
    ],
    facts: [
      ["Worked in", "usetalkie.com"],
      ["Length", "One page"],
      ["Next", "Your read-through"],
    ],
    byline: "Drafted on Studio Mac from the release branch, ready for your pass.",
  },
  {
    id: "bridge-tests",
    name: "Review bridge protocol tests",
    project: "Talkie",
    sentAt: "09:40",
    nature: "needsyou",
    natureNote: "waiting",
    ask: "The bridge protocol tests are flaky on the retry suite. Tell me which ones are worth keeping before you rewrite anything.",
    workingLine: "Waiting on your answer in Codex Desktop",
    lastUpdate: "11:12",
    resultHeadline: "Three retry tests are worth keeping; the rest were testing the mock, not the bridge.",
    resultBody: [
      "The keep list covers reconnect, out-of-order delivery, and token expiry. The remaining nine asserted mock timing and masked real failures.",
    ],
    facts: [
      ["Keep", "3 tests"],
      ["Retire", "9 tests"],
      ["Next", "Answer in Codex Desktop"],
    ],
    byline: "Analysis only — Codex is waiting for your call in Codex Desktop on Studio Mac.",
  },
  {
    id: "sync-audit",
    name: "Audit transcript sync",
    project: "Talkie",
    sentAt: "Thu",
    nature: "idle",
    natureNote: "quiet",
    ask: "Check whether transcript edits on iPhone reach the Mac before the readout runs. Quiet audit, no changes.",
    workingLine: "Re-checking the sync window since Thursday",
    lastUpdate: "11:20",
    resultHeadline: "Every edit landed before readout; the slow path is the first library load.",
    resultBody: [
      "Across the captured week, transcript edits synced ahead of playback. The only lag appears on first open after a reinstall, and it resolves itself within a minute.",
    ],
    facts: [
      ["Window", "Last 7 days"],
      ["Changes", "None"],
      ["Next", "Nothing needed"],
    ],
    byline: "Read-only audit on Studio Mac. No files were touched.",
  },
];

type Scene = "working" | "result" | "offline";

const SCENES: { key: Scene; label: string }[] = [
  { key: "working", label: "Working" },
  { key: "result", label: "Result ready" },
  { key: "offline", label: "Mac unreachable" },
];

// ─── Thread geometry (authored against the fixed canvas) ─────────────

const THREAD_LIVE = "M 1088 736 Q 1112 440 984 134";
const THREAD_SLACK = "M 1088 736 Q 1156 520 996 148";
const TIE = { x: 984, y: 134 };

// ─── Root study ──────────────────────────────────────────────────────

export function TetheredTable() {
  const [scene, setScene] = React.useState<Scene>("result");
  const [taskId, setTaskId] = React.useState("repair");
  const [voice, setVoice] = React.useState<"idle" | "listening" | "sent" | "kept">("idle");
  const [showDetails, setShowDetails] = React.useState(false);
  const settleTimer = React.useRef<ReturnType<typeof setTimeout> | null>(null);

  const task = TASKS.find((t) => t.id === taskId) ?? TASKS[0];
  const waiting = TASKS.filter((t) => t.id !== task.id);
  const offline = scene === "offline";
  const listening = voice === "listening";

  function pressVoice() {
    if (settleTimer.current) clearTimeout(settleTimer.current);
    setVoice("listening");
  }

  function releaseVoice() {
    if (!listening) return;
    setVoice(offline ? "kept" : "sent");
    settleTimer.current = setTimeout(() => setVoice("idle"), 2400);
  }

  return (
    <div className="py-2">
      <KeyframeStyles />

      {/* Studio chrome: scene switcher. Not part of the proposal. */}
      <div className="mx-auto mb-4 flex max-w-[1232px] items-baseline justify-between px-1">
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em] text-studio-ink-faint">
          Round 2 · Kimi — The Tethered Table
        </span>
        <div
          role="group"
          aria-label="Scenario"
          className="flex overflow-hidden rounded-[4px] border border-studio-edge bg-white"
        >
          {SCENES.map((s) => (
            <button
              key={s.key}
              type="button"
              aria-pressed={scene === s.key}
              onClick={() => setScene(s.key)}
              className="px-3.5 py-2 font-mono text-[10px] font-semibold uppercase tracking-[0.18em] transition-colors"
              style={
                scene === s.key
                  ? { background: INK, color: PAPER }
                  : { background: "transparent", color: INK_FAINT }
              }
            >
              {s.label}
            </button>
          ))}
        </div>
      </div>

      {/* Device */}
      <div className="overflow-x-auto pb-4">
        <div
          className="mx-auto w-fit rounded-[38px] p-[14px]"
          style={{
            background: "#1B1B1A",
            boxShadow: "0 30px 60px -18px rgba(35,36,35,0.35)",
          }}
        >
          <div className="relative">
            <span
              aria-hidden
              className="absolute left-1/2 top-[5px] h-[6px] w-[6px] -translate-x-1/2 rounded-full"
              style={{ background: "#3A3A38" }}
            />
            <div
              className="relative overflow-hidden rounded-[24px]"
              style={{ width: 1180, height: 885, background: TABLE }}
            >
              <Screen
                scene={scene}
                task={task}
                waiting={waiting}
                offline={offline}
                listening={listening}
                voice={voice}
                showDetails={showDetails}
                onToggleDetails={() => setShowDetails((v) => !v)}
                onPickTask={(id) => {
                  setTaskId(id);
                  setShowDetails(false);
                }}
                onPressVoice={pressVoice}
                onReleaseVoice={releaseVoice}
              />
            </div>
          </div>
        </div>
      </div>

      <p className="mx-auto mt-1 max-w-[1232px] px-1 font-mono text-[9px] uppercase tracking-[0.22em] text-studio-ink-faint">
        Hold the disc to talk · tap a slip to bring it to the table · 1180×885 · illustrative task state
      </p>
    </div>
  );
}

// ─── The iPad screen ─────────────────────────────────────────────────

function Screen({
  scene,
  task,
  waiting,
  offline,
  listening,
  voice,
  showDetails,
  onToggleDetails,
  onPickTask,
  onPressVoice,
  onReleaseVoice,
}: {
  scene: Scene;
  task: Task;
  waiting: Task[];
  offline: boolean;
  listening: boolean;
  voice: "idle" | "listening" | "sent" | "kept";
  showDetails: boolean;
  onToggleDetails: () => void;
  onPickTask: (id: string) => void;
  onPressVoice: () => void;
  onReleaseVoice: () => void;
}) {
  return (
    <div className="relative h-full w-full">
      <Header offline={offline} />

      {/* Waiting slips, tucked at the sheet's left edge */}
      <Fan waiting={waiting} onPick={onPickTask} />

      {/* The sheet on the table */}
      <div
        key={`${task.id}-${scene}`}
        className="talkie-sheet-in absolute"
        style={{
          left: 272,
          top: 88,
          width: 756,
          height: 716,
          background: PAPER,
          boxShadow: "0 14px 34px -10px rgba(35,36,35,0.28)",
          zIndex: 10,
        }}
      >
        <Sheet
          scene={scene}
          task={task}
          offline={offline}
          showDetails={showDetails}
          onToggleDetails={onToggleDetails}
        />
      </div>

      {/* The thread, over the sheet's right margin, under the disc */}
      <svg
        aria-hidden
        className="pointer-events-none absolute inset-0"
        width={1180}
        height={885}
        viewBox="0 0 1180 885"
      >
        <path
          d={offline ? THREAD_SLACK : THREAD_LIVE}
          fill="none"
          stroke={offline ? GRAPHITE : AMBER}
          strokeWidth={listening ? 2 : 1.4}
          strokeDasharray={offline ? "5 7" : listening ? "7 7" : "none"}
          className={listening && !offline ? "talkie-thread-flow" : undefined}
          opacity={offline ? 0.55 : 0.9}
          style={{ transition: "stroke 300ms, stroke-width 200ms, opacity 300ms" }}
        />
        {/* Tie ring on the sheet */}
        <circle
          cx={TIE.x}
          cy={TIE.y}
          r={7.5}
          fill={PAPER}
          stroke={offline ? GRAPHITE : BRASS}
          strokeWidth={1.6}
        />
        {!offline && <circle cx={TIE.x} cy={TIE.y} r={2.4} fill={AMBER} />}
        <text
          x={TIE.x}
          y={TIE.y - 16}
          textAnchor="middle"
          fill={offline ? GRAPHITE : INK_FAINTER}
          fontSize={8}
          letterSpacing={2.4}
          style={{ fontFamily: "var(--theme-font-mono)" }}
        >
          VOICE
        </text>
      </svg>

      {/* Droplet of voice riding the thread into the sheet */}
      {voice === "sent" && (
        <span
          aria-hidden
          className="talkie-droplet absolute h-[10px] w-[10px] rounded-full"
          style={{ background: AMBER, boxShadow: `0 0 10px 2px ${AMBER}55`, zIndex: 30 }}
        />
      )}

      <VoiceCluster
        task={task}
        offline={offline}
        listening={listening}
        voice={voice}
        onPress={onPressVoice}
        onRelease={onReleaseVoice}
      />
    </div>
  );
}

// ─── Header: sparse chrome; failure owns it when the bridge drops ────

function Header({ offline }: { offline: boolean }) {
  return (
    <div
      className="absolute left-0 right-0 top-0 flex items-center gap-3 px-7"
      style={{ height: 64 }}
    >
      <span aria-hidden style={{ color: offline ? GRAPHITE : AMBER }}>
        <svg viewBox="0 0 24 24" width={17} height={17} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round">
          <path d="M3 13v-2m4 6V7m4 13V7m4 6v-2" />
        </svg>
      </span>
      <span className="font-display text-[16px] font-medium" style={{ color: INK }}>
        Talkie
      </span>
      <span className="font-mono text-[9px] uppercase tracking-[0.32em]" style={{ color: INK_FAINTER }}>
        · iPad
      </span>

      <div className="ml-auto flex items-center gap-4">
        <div className="flex items-baseline gap-2.5">
          <span
            aria-hidden
            className="inline-block h-[7px] w-[7px] self-center rounded-full"
            style={{ background: offline ? COLD : AMBER }}
          />
          <span className="font-sans text-[13px] font-semibold" style={{ color: INK }}>
            Studio Mac
          </span>
          <span
            className="font-mono text-[9.5px] uppercase tracking-[0.18em]"
            style={{ color: offline ? COLD : INK_FAINT }}
          >
            {offline ? "Unreachable · last contact 11:42" : "Connected"}
          </span>
        </div>
      </div>

      <span
        aria-hidden
        className="absolute bottom-0 left-7 right-7"
        style={{ height: 0.5, background: offline ? `${COLD}66` : INK_RULE }}
      />
    </div>
  );
}

// ─── The sheet: selected task + its artifact ─────────────────────────

function Sheet({
  scene,
  task,
  offline,
  showDetails,
  onToggleDetails,
}: {
  scene: Scene;
  task: Task;
  offline: boolean;
  showDetails: boolean;
  onToggleDetails: () => void;
}) {
  return (
    <div className="flex h-full flex-col" style={{ padding: "34px 44px 30px 40px" }}>
      {/* Header: identity + status. Right edge stays clear for the tie ring. */}
      <div className="flex items-baseline gap-3" style={{ paddingRight: 92 }}>
        <span className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: BRASS }}>
          · On the table
        </span>
        <span className="font-mono text-[9px] uppercase tracking-[0.22em]" style={{ color: INK_FAINTER }}>
          {task.project} · sent from this iPad · {task.sentAt}
        </span>
      </div>

      <h2
        className="m-0 mt-3 font-display font-medium"
        style={{ color: INK, fontSize: 31, lineHeight: 1.15, letterSpacing: "-0.012em", maxWidth: 480 }}
      >
        {task.name}
      </h2>

      <div className="mt-3.5 flex items-center gap-2.5">
        <StatusDisc scene={scene} />
        <span
          className="font-mono text-[10px] uppercase tracking-[0.2em]"
          style={{ color: offline ? COLD : scene === "working" ? AMBER : INK_FAINT, fontWeight: 600 }}
        >
          {scene === "working" && `Working on Studio Mac · last update ${task.lastUpdate}`}
          {scene === "result" && "Result ready · completed 11:42"}
          {scene === "offline" && "Paused · Studio Mac unreachable"}
        </span>
      </div>

      <div className="mt-5" style={{ height: 0.5, background: INK_RULE }} />

      {/* Body */}
      <div className="relative mt-0 flex-1">
        {offline ? (
          <RecoveryBody task={task} showDetails={showDetails} onToggleDetails={onToggleDetails} />
        ) : scene === "working" ? (
          <WorkingBody task={task} />
        ) : (
          <ResultBody task={task} />
        )}
      </div>
    </div>
  );
}

function StatusDisc({ scene }: { scene: Scene }) {
  if (scene === "result") {
    return <span aria-hidden className="inline-block rounded-full" style={{ width: 9, height: 9, background: AMBER }} />;
  }
  if (scene === "working") {
    return (
      <svg width={9} height={9} viewBox="0 0 9 9" aria-hidden className="talkie-status-pulse">
        <circle cx="4.5" cy="4.5" r="3.6" fill="none" stroke={AMBER} strokeWidth="1.2" />
        <path d="M 4.5 0.9 A 3.6 3.6 0 0 1 4.5 8.1 Z" fill={AMBER} />
      </svg>
    );
  }
  return (
    <span
      aria-hidden
      className="inline-block rounded-full"
      style={{ width: 9, height: 9, border: `1.2px solid ${COLD}`, background: "transparent" }}
    />
  );
}

function WorkingBody({ task }: { task: Task }) {
  return (
    <div className="flex pt-6">
      <span aria-hidden className="self-stretch" style={{ width: 0.5, background: `${BRASS}55`, marginRight: 20 }} />
      <div style={{ maxWidth: 520 }}>
        <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: INK_FAINT }}>
          · Your ask · {task.sentAt}
        </div>
        <p
          className="m-0 mt-2.5 font-display italic"
          style={{ color: INK, fontSize: 17, lineHeight: 1.55 }}
        >
          “{task.ask}”
        </p>

        <div className="mt-8 font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: INK_FAINT }}>
          · Latest from Codex
        </div>
        <p className="m-0 mt-2.5 font-display" style={{ color: INK, fontSize: 17, lineHeight: 1.55 }}>
          {task.workingLine}. Nothing is needed from you right now.
        </p>
        <p className="m-0 mt-3 font-sans text-[12.5px] leading-[1.6]" style={{ color: INK_FAINT }}>
          Keep talking if something changes — what you say joins this task, and
          Codex picks it up as it works. You&apos;ll see the result here when it lands.
        </p>
      </div>
    </div>
  );
}

function ResultBody({ task }: { task: Task }) {
  return (
    <div className="flex h-full flex-col pt-6">
      <div className="flex">
        <span aria-hidden className="self-stretch" style={{ width: 0.5, background: `${BRASS}55`, marginRight: 20 }} />
        <div style={{ maxWidth: 540 }}>
          <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: BRASS }}>
            · Latest result · 11:42
          </div>
          <h3
            className="m-0 mt-3 font-display font-medium"
            style={{ color: INK, fontSize: 22, lineHeight: 1.3, letterSpacing: "-0.008em" }}
          >
            {task.resultHeadline}
          </h3>
          {task.resultBody.map((p, i) => (
            <p key={i} className="m-0 mt-3.5 font-display" style={{ color: INK, fontSize: 15, lineHeight: 1.65 }}>
              {p}
            </p>
          ))}

          {/* Facts rule */}
          <div
            className="mt-6 grid"
            style={{
              gridTemplateColumns: `repeat(${task.facts.length}, 1fr)`,
              borderTop: `0.5px solid ${INK_RULE}`,
              borderBottom: `0.5px solid ${INK_RULE}`,
              padding: "10px 0",
              columnGap: 20,
            }}
          >
            {task.facts.map(([k, v]) => (
              <div key={k}>
                <div className="font-mono text-[8.5px] uppercase tracking-[0.26em]" style={{ color: INK_FAINTER }}>
                  {k}
                </div>
                <div className="mt-1 font-sans text-[13px] font-semibold" style={{ color: INK }}>
                  {v}
                </div>
              </div>
            ))}
          </div>

          {/* Actions */}
          <div className="mt-5 flex items-center gap-3">
            <button
              type="button"
              className="flex items-center gap-2 rounded-[3px] px-3.5 py-2.5 font-mono text-[10px] font-semibold uppercase tracking-[0.2em]"
              style={{ border: `0.5px solid ${AMBER}`, color: BRASS, background: "rgba(196,125,28,0.05)" }}
            >
              <svg viewBox="0 0 24 24" width={13} height={13} fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round">
                <path d="M11 5 6 9H3v6h3l5 4V5Z" />
                <path d="M15 9a4 4 0 0 1 0 6M17.5 6.5a8 8 0 0 1 0 11" />
              </svg>
              Hear result
            </button>
            <button
              type="button"
              className="px-2 py-2.5 font-mono text-[10px] font-semibold uppercase tracking-[0.2em]"
              style={{ color: INK_FAINT }}
            >
              Copy
            </button>
          </div>
        </div>
      </div>

      {/* Byline */}
      <div className="mt-auto border-t pt-3" style={{ borderColor: INK_RULE_S }}>
        <p className="m-0 font-display italic" style={{ color: INK_FAINT, fontSize: 13.5, lineHeight: 1.5 }}>
          {task.byline}
        </p>
      </div>
    </div>
  );
}

function RecoveryBody({
  task,
  showDetails,
  onToggleDetails,
}: {
  task: Task;
  showDetails: boolean;
  onToggleDetails: () => void;
}) {
  return (
    <div className="flex h-full flex-col pt-6">
      {/* Recovery leads; last known state is kept underneath, quieted. */}
      <div style={{ border: `0.5px solid ${INK_RULE}`, padding: "18px 20px" }}>
        <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: COLD }}>
          · Connection recovery
        </div>
        <p className="m-0 mt-2.5 font-display" style={{ color: INK, fontSize: 17, lineHeight: 1.55, maxWidth: 500 }}>
          Studio Mac stopped answering. Voice and delivery are paused —
          everything on the table is kept exactly as it was.
        </p>
        <div className="mt-4 flex items-center gap-3">
          <button
            type="button"
            className="rounded-[3px] px-4 py-2.5 font-mono text-[10px] font-semibold uppercase tracking-[0.2em]"
            style={{ background: INK, color: PAPER }}
          >
            Reconnect
          </button>
          <button
            type="button"
            aria-expanded={showDetails}
            onClick={onToggleDetails}
            className="px-2 py-2.5 font-mono text-[10px] font-semibold uppercase tracking-[0.2em]"
            style={{ color: INK_FAINT }}
          >
            Connection details {showDetails ? "▴" : "▾"}
          </button>
        </div>
        {showDetails && (
          <div className="mt-4 space-y-1.5 border-t pt-3.5" style={{ borderColor: INK_RULE_S }}>
            {[
              ["Saved endpoint", "studio-mac.tailnet · port 7749"],
              ["Last successful contact", "11:42 · result delivered"],
              ["Transport", "Tailscale"],
            ].map(([k, v]) => (
              <div key={k} className="flex items-baseline gap-3 font-mono text-[10px]">
                <span className="uppercase tracking-[0.18em]" style={{ color: INK_FAINTER, width: 180 }}>{k}</span>
                <span style={{ color: INK_FAINT }}>{v}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="mt-7 flex" style={{ opacity: 0.42 }}>
        <span aria-hidden className="self-stretch" style={{ width: 0.5, background: `${BRASS}55`, marginRight: 20 }} />
        <div style={{ maxWidth: 500 }}>
          <div className="font-mono text-[9px] font-semibold uppercase tracking-[0.32em]" style={{ color: INK_FAINT }}>
            · Kept on the table — last heard 11:42
          </div>
          <p className="m-0 mt-2.5 font-display italic" style={{ color: INK, fontSize: 15.5, lineHeight: 1.55 }}>
            “{task.ask}”
          </p>
        </div>
      </div>
    </div>
  );
}

// ─── The fan: waiting tasks at the left thumb ────────────────────────

function Fan({ waiting, onPick }: { waiting: Task[]; onPick: (id: string) => void }) {
  const n = waiting.length;
  return (
    <div className="absolute" style={{ left: 0, bottom: 0, width: 272, height: 560 }}>
      <div
        className="absolute font-mono text-[9px] font-semibold uppercase tracking-[0.32em]"
        style={{ left: 28, top: 330, color: INK_FAINT }}
      >
        · Around the table · {n}
      </div>

      <div className="absolute" style={{ left: 0, right: 0, bottom: 56, height: 300 }}>
        {waiting.map((t, i) => {
          const mid = (n - 1) / 2;
          const rot = (i - mid) * 9;
          const x = 182 + (i - mid) * 72; // pivot near bottom-center of the zone
          return (
            <button
              key={t.id}
              type="button"
              onClick={() => onPick(t.id)}
              aria-label={`Bring ${t.name} to the table`}
              className="talkie-slip absolute text-left"
              style={{
                width: 160,
                height: 126,
                left: x - 80,
                bottom: 0,
                transform: `rotate(${rot}deg)`,
                transformOrigin: "50% 135%",
                zIndex: i === Math.ceil(mid) ? 3 : i,
                background: PAPER,
                boxShadow: "0 8px 20px -6px rgba(35,36,35,0.30)",
                padding: "12px 14px",
              }}
            >
              <span className="flex items-center gap-1.5">
                <SlipDot nature={t.nature} />
                <span
                  className="font-mono text-[8px] font-semibold uppercase tracking-[0.22em]"
                  style={{ color: t.nature === "needsyou" ? COLD : t.nature === "idle" ? INK_FAINTER : BRASS }}
                >
                  {t.nature === "needsyou" ? "Needs you" : t.nature === "working" ? "Working" : t.nature === "result" ? "Result ready" : "Idle"}
                </span>
              </span>
              <span
                className="mt-1.5 block font-display font-medium"
                style={{ color: INK, fontSize: 13.5, lineHeight: 1.25, letterSpacing: "-0.005em" }}
              >
                {t.name}
              </span>
              <span
                className="mt-1 block font-mono text-[8px] uppercase tracking-[0.2em]"
                style={{ color: INK_FAINTER }}
              >
                {t.project}
              </span>
            </button>
          );
        })}
      </div>

      <div
        className="absolute font-mono text-[8.5px] uppercase tracking-[0.2em]"
        style={{ left: 28, bottom: 18, color: INK_FAINTER }}
      >
        Tap a slip to bring it to the table
      </div>
    </div>
  );
}

function SlipDot({ nature }: { nature: TaskNature }) {
  if (nature === "result") {
    return <span aria-hidden className="inline-block h-[7px] w-[7px] rounded-full" style={{ background: AMBER }} />;
  }
  if (nature === "working") {
    return (
      <svg width={7} height={7} viewBox="0 0 9 9" aria-hidden>
        <circle cx="4.5" cy="4.5" r="3.6" fill="none" stroke={AMBER} strokeWidth="1.4" />
        <path d="M 4.5 0.9 A 3.6 3.6 0 0 1 4.5 8.1 Z" fill={AMBER} />
      </svg>
    );
  }
  return (
    <span
      aria-hidden
      className="inline-block h-[7px] w-[7px] rounded-full"
      style={{ border: `1.2px solid ${nature === "needsyou" ? COLD : INK_FAINTER}`, background: "transparent" }}
    />
  );
}

// ─── The voice cluster: disc + destination at the right thumb ────────

function VoiceCluster({
  task,
  offline,
  listening,
  voice,
  onPress,
  onRelease,
}: {
  task: Task;
  offline: boolean;
  listening: boolean;
  voice: "idle" | "listening" | "sent" | "kept";
  onPress: () => void;
  onRelease: () => void;
}) {
  const label =
    voice === "sent"
      ? ["Sent", "Codex picks it up on Studio Mac"]
      : voice === "kept"
      ? ["Kept on this iPad", "Delivers when Studio Mac returns"]
      : listening
      ? ["Listening…", "Release to send"]
      : offline
      ? ["Record anyway", "Talkie delivers on reconnect"]
      : ["Hold to talk", "Release to send"];

  return (
    <div className="absolute" style={{ right: 34, bottom: 40, zIndex: 20 }}>
      <div className="flex items-center gap-4">
        {/* Destination — explicit in every state */}
        <div className="text-right" style={{ maxWidth: 230 }}>
          <div
            className="font-mono text-[10px] font-semibold uppercase tracking-[0.22em]"
            style={{ color: listening ? AMBER : offline ? GRAPHITE : INK }}
          >
            {label[0]}
          </div>
          <div
            className="mt-1 font-mono text-[9.5px] uppercase tracking-[0.14em]"
            style={{ color: offline ? GRAPHITE : BRASS }}
          >
            → {task.name}
          </div>
          <div className="mt-1 font-mono text-[8.5px] uppercase tracking-[0.16em]" style={{ color: INK_FAINTER }}>
            {label[1]}
          </div>
        </div>

        {/* The disc */}
        <button
          type="button"
          aria-label={offline ? `Record a memo for ${task.name}, delivered on reconnect` : `Hold to talk to ${task.name}`}
          onPointerDown={onPress}
          onPointerUp={onRelease}
          onPointerLeave={onRelease}
          onContextMenu={(e) => e.preventDefault()}
          className={listening && !offline ? "talkie-disc-live" : undefined}
          style={{
            width: 94,
            height: 94,
            borderRadius: "50%",
            background: offline ? PAPER : AMBER,
            border: offline ? `1.5px solid ${GRAPHITE}` : "none",
            boxShadow: offline
              ? "0 8px 18px -6px rgba(35,36,35,0.25)"
              : `0 10px 24px -6px rgba(196,125,28,0.55)`,
            transform: listening ? "scale(1.06)" : "scale(1)",
            transition: "transform 180ms cubic-bezier(0.2,0,0.2,1), background 300ms, box-shadow 300ms",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            cursor: "pointer",
            touchAction: "none",
          }}
        >
          <svg
            viewBox="0 0 24 24"
            width={30}
            height={30}
            fill="none"
            stroke={offline ? GRAPHITE : PAPER}
            strokeWidth={1.8}
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <rect x="9" y="3" width="6" height="12" rx="3" />
            <path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
          </svg>
        </button>
      </div>
    </div>
  );
}

// ─── Keyframes ───────────────────────────────────────────────────────

function KeyframeStyles() {
  return (
    <style>{`
      @keyframes talkie-thread-flow {
        from { stroke-dashoffset: 0; }
        to   { stroke-dashoffset: -28; }
      }
      .talkie-thread-flow { animation: talkie-thread-flow 0.9s linear infinite; }

      @keyframes talkie-disc-breathe {
        0%, 100% { box-shadow: 0 10px 24px -6px rgba(196,125,28,0.55), 0 0 0 0 rgba(196,125,28,0.35); }
        50%      { box-shadow: 0 10px 24px -6px rgba(196,125,28,0.55), 0 0 0 12px rgba(196,125,28,0); }
      }
      .talkie-disc-live { animation: talkie-disc-breathe 1.4s ease-in-out infinite; }

      @keyframes talkie-status-pulse-k {
        0%, 100% { opacity: 1; }
        50%      { opacity: 0.45; }
      }
      .talkie-status-pulse { animation: talkie-status-pulse-k 2.2s ease-in-out infinite; transform-origin: center; }

      @keyframes talkie-sheet-in-k {
        from { opacity: 0; transform: translateY(6px); }
        to   { opacity: 1; transform: translateY(0); }
      }
      .talkie-sheet-in { animation: talkie-sheet-in-k 260ms cubic-bezier(0.2,0,0.2,1); }

      @keyframes talkie-droplet-k {
        0%   { offset-distance: 0%;   opacity: 0; }
        12%  { opacity: 1; }
        82%  { opacity: 1; }
        100% { offset-distance: 100%; opacity: 0; }
      }
      .talkie-droplet {
        offset-path: path("${THREAD_LIVE}");
        animation: talkie-droplet-k 950ms cubic-bezier(0.35,0,0.25,1) forwards;
      }

      .talkie-slip { transition: transform 200ms cubic-bezier(0.2,0,0.2,1), box-shadow 200ms; cursor: pointer; }
      .talkie-slip:hover { box-shadow: 0 14px 28px -8px rgba(35,36,35,0.38); }
    `}</style>
  );
}
