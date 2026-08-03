"use client";

/**
 * The Aperture — Round 2 full-size iPad at-bat (Grok).
 *
 * PREMISE
 *   One Codex task fills a single framed reading aperture under hanging
 *   task tags. The brass voice sill under the plate is both the destination
 *   address and the hold-to-talk surface. Speaking sends a rising amber
 *   breath into the plate — targeting you can still see with the copy blurred.
 *
 *   No sidebar. No card grid. No toolbar. No IDE. Three objects: tags on
 *   the lintel, the plate, and the sill.
 *
 * STATES
 *   active        Codex is working on the selected Mac; plate shows the ask
 *                 and a plain-language activity line. No fake progress.
 *   result        The plate becomes reading matter: prose + quoted facts.
 *   unavailable   Recovery owns the top of the plate; tags flatten; breath
 *                 cools; voice still records locally ("kept on this iPad").
 *
 * VOICE OBJECT
 *   Hold the talk control: an amber breath rises from the sill into the
 *   plate, and the address plate glows. Offline, the same gesture keeps a
 *   memo on-device for delivery on reconnect.
 */

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";

import s from "./aperture.module.css";
import {
  MAC,
  SCENARIOS,
  TASKS,
  type ResultBlock,
  type Task,
} from "./content";

const ARTBOARD_W = 1366;
const ARTBOARD_H = 1024;

export function Aperture({ scenarioKey }: { scenarioKey: string }) {
  const scenario = SCENARIOS.find((v) => v.key === scenarioKey) ?? SCENARIOS[0];

  const [seen, setSeen] = useState(scenario.key);
  const [taskId, setTaskId] = useState(scenario.taskId);
  const [detailOpen, setDetailOpen] = useState(false);
  const [listening, setListening] = useState(false);
  const [voiceFlash, setVoiceFlash] = useState<"sent" | "kept" | null>(null);
  const flashTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  if (seen !== scenario.key) {
    setSeen(scenario.key);
    setTaskId(scenario.taskId);
    setDetailOpen(false);
    setListening(false);
    setVoiceFlash(null);
  }

  const task = TASKS.find((t) => t.id === taskId) ?? TASKS[0];
  const online = scenario.online;
  const attention = online && task.state === "needs-you";
  const working = online && Boolean(task.activity);

  const release = useCallback(() => {
    setListening((was) => {
      if (!was) return false;
      if (flashTimer.current) clearTimeout(flashTimer.current);
      setVoiceFlash(online ? "sent" : "kept");
      flashTimer.current = setTimeout(() => setVoiceFlash(null), 2200);
      return false;
    });
  }, [online]);

  useEffect(() => {
    if (!listening) return;
    window.addEventListener("pointerup", release);
    window.addEventListener("pointercancel", release);
    return () => {
      window.removeEventListener("pointerup", release);
      window.removeEventListener("pointercancel", release);
    };
  }, [listening, release]);

  useEffect(
    () => () => {
      if (flashTimer.current) clearTimeout(flashTimer.current);
    },
    []
  );

  return (
    <FitToWidth>
      <div className={`${s.root} ${s.deviceShell}`}>
        <div
          className={s.stage}
          data-online={online}
          data-listening={listening}
        >
          <div className={s.stageLight} aria-hidden />

          <div className={s.statusBar} aria-hidden>
            <span>Talkie</span>
            <span className={s.statusBarTime}>2:41</span>
          </div>

          <Lintel
            selectedId={task.id}
            online={online}
            onSelect={(id) => {
              setTaskId(id);
              setDetailOpen(false);
              setListening(false);
            }}
          />

          <Frame
            task={task}
            online={online}
            detailOpen={detailOpen}
            onToggleDetail={() => setDetailOpen((v) => !v)}
          />

          <Sill
            task={task}
            online={online}
            attention={attention}
            working={working}
            listening={listening}
            voiceFlash={voiceFlash}
            onHold={() => setListening(true)}
            onRelease={release}
          />

          <div className={s.homeBar} aria-hidden />
        </div>
      </div>
    </FitToWidth>
  );
}

/* ── Fit artboard to available width ─────────────────────────────────── */

function FitToWidth({ children }: { children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const el = outer.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      const w = entry.contentRect.width;
      setScale(Math.min(1, w / ARTBOARD_W));
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div
      ref={outer}
      className={s.scaler}
      style={{ height: ARTBOARD_H * scale }}
    >
      <div
        className={s.scalerInner}
        style={{
          width: ARTBOARD_W,
          height: ARTBOARD_H,
          transform: `scale(${scale})`,
        }}
      >
        {children}
      </div>
    </div>
  );
}

/* ── Lintel: hanging tags ────────────────────────────────────────────── */

function Lintel({
  selectedId,
  online,
  onSelect,
}: {
  selectedId: string;
  online: boolean;
  onSelect: (id: string) => void;
}) {
  return (
    <nav className={s.lintel} aria-label="Tasks">
      {TASKS.map((t) => {
        const selected = t.id === selectedId;
        const mark = online && t.state !== "unknown" ? t.state : "unknown";
        return (
          <button
            key={t.id}
            type="button"
            className={s.tag}
            data-selected={selected}
            aria-current={selected ? "true" : undefined}
            onClick={() => onSelect(t.id)}
          >
            <span className={s.tagClip} aria-hidden />
            <span className={s.tagBody}>
              <span className={s.tagName}>{t.name}</span>
              <span className={s.tagMeta}>
                <span className={s.tagDot} data-state={mark} aria-hidden />
                {online && t.stateWord ? t.stateWord : t.project}
              </span>
            </span>
          </button>
        );
      })}
    </nav>
  );
}

/* ── Frame + plate ───────────────────────────────────────────────────── */

function Frame({
  task,
  online,
  detailOpen,
  onToggleDetail,
}: {
  task: Task;
  online: boolean;
  detailOpen: boolean;
  onToggleDetail: () => void;
}) {
  return (
    <div className={s.frame}>
      <div className={s.frameBezel}>
        <article className={s.aperture} aria-label={`${task.name} on ${MAC.name}`}>
          <div className={s.breath} aria-hidden>
            <div className={s.breathWave}>
              {Array.from({ length: 24 }, (_, i) => (
                <span
                  key={i}
                  className={s.breathWaveBar}
                  style={{
                    left: `${(i + 0.5) * (100 / 24)}%`,
                    height: `${10 + ((i * 17) % 14)}px`,
                    animationDelay: `${(i % 7) * 0.08}s`,
                  }}
                />
              ))}
            </div>
          </div>

          <div key={task.id} className={`${s.plateScroll} ${s.plateIn}`}>
            {!online ? <Recovery /> : null}

            {!online ? (
              <div className={s.staleNote}>
                Last confirmed from {MAC.name} · {MAC.lastHeard}
              </div>
            ) : null}

            {online && task.question ? (
              <div className={s.attention}>
                <div className={s.attentionLabel}>Codex is waiting on you</div>
                <p className={s.attentionQuestion}>{task.question}</p>
                <div className={s.attentionWhere}>
                  Answer in Codex Desktop on {MAC.name}
                </div>
              </div>
            ) : null}

            <header className={s.pageHead}>
              <h1 className={s.title}>{task.name}</h1>
              <div className={s.titleMeta}>
                {online && task.stateWord ? (
                  <span className={s.stateWord} data-state={task.state}>
                    {task.stateWord}
                  </span>
                ) : null}
                <span className={s.provenance}>
                  {task.branch} · {task.project}
                </span>
              </div>
            </header>

            <div className={s.headRule} aria-hidden />

            {task.instruction ? (
              <div className={s.instruction}>
                <span className={s.instructionTick} aria-hidden />
                <p className={s.instructionText}>{task.instruction.text}</p>
                <span className={s.instructionAt}>
                  you · {task.instruction.at}
                </span>
              </div>
            ) : null}

            <div className={s.bodyRule} aria-hidden />

            {online && task.activity ? (
              <div className={s.workingScaffold}>
                <div className={s.workingBody}>
                  <p className={s.activityText}>{task.activity.text}</p>
                  <div className={s.activityStarted}>{task.activity.started}</div>
                  <div className={s.foldRule} aria-hidden>
                    <div className={s.foldRuleBase} />
                    <div className={s.foldRuleTravel} />
                  </div>
                  {task.emptyNote ? (
                    <div className={s.pending}>{task.emptyNote}</div>
                  ) : null}
                </div>
              </div>
            ) : task.result ? (
              <div className={s.result}>
                {task.result.blocks.map((block, i) => (
                  <ResultPiece key={i} block={block} />
                ))}
              </div>
            ) : (
              <div className={s.result}>
                <p className={s.emptyNote}>{task.emptyNote}</p>
              </div>
            )}
          </div>

          {detailOpen ? (
            <div className={s.foldOpen}>
              {task.detail.map((row) => (
                <div key={row} className={s.foldOpenRow}>
                  {row}
                </div>
              ))}
            </div>
          ) : null}

          <div className={s.plateFoot}>
            <div className={s.footActions}>
              <button
                type="button"
                className={s.footAction}
                disabled={!task.result}
              >
                <EarMark />
                Hear result
              </button>
              <button
                type="button"
                className={s.footAction}
                disabled={!task.result}
              >
                <CopyMark />
                Copy
              </button>
            </div>
            <button
              type="button"
              className={s.fold}
              data-open={detailOpen}
              aria-expanded={detailOpen}
              onClick={onToggleDetail}
            >
              {detailOpen ? "Hide detail" : "Turn detail"}
            </button>
          </div>
        </article>
      </div>
    </div>
  );
}

function Recovery() {
  return (
    <div className={s.recovery}>
      <div className={s.recoveryHead}>
        <div className={s.recoveryTitle}>{MAC.name} is unreachable</div>
        <div className={s.recoveryHeard}>last heard {MAC.lastHeard}</div>
      </div>
      <p className={s.recoveryBody}>
        Talkie cannot observe live Codex state on this Mac. Anything already
        returned still reads below. Speech you record here stays on this iPad
        and delivers when the bridge returns.
      </p>
      <div className={s.recoveryActions}>
        <button type="button" className={s.recoveryPrimary}>
          Try reconnect
        </button>
        <button type="button" className={s.recoveryGhost}>
          Connection details
        </button>
      </div>
      <div className={s.recoveryNote}>
        Prefer another Mac? Switch destination after reconnect — tasks stay
        addressed to the selected work.
      </div>
    </div>
  );
}

function ResultPiece({ block }: { block: ResultBlock }) {
  if (block.kind === "quoted") {
    return (
      <div className={s.quoted}>
        <div className={s.quotedCaption}>{block.caption}</div>
        {block.lines.map((line) => (
          <div key={line} className={s.quotedLine}>
            {line}
          </div>
        ))}
      </div>
    );
  }
  return <p className={s.resultProse}>{block.text}</p>;
}

/* ── Voice sill ──────────────────────────────────────────────────────── */

function Sill({
  task,
  online,
  attention,
  working,
  listening,
  voiceFlash,
  onHold,
  onRelease,
}: {
  task: Task;
  online: boolean;
  attention: boolean;
  working: boolean;
  listening: boolean;
  voiceFlash: "sent" | "kept" | null;
  onHold: () => void;
  onRelease: () => void;
}) {
  // Talkie can dispatch speech. It cannot cancel a turn or answer a
  // question on the user's behalf, so no control here claims to.
  const label = listening
    ? online
      ? "Listening — release to send"
      : "Recording on this iPad — release to keep"
    : !online
      ? "Hold to keep a follow-up on this iPad"
      : working
        ? "Hold to add a follow-up"
        : attention
          ? "Hold to queue a follow-up"
          : "Hold to continue this task";

  const hint = listening
    ? `to ${task.name}`
    : !online
      ? "delivers on reconnect"
      : working
        ? "saved with this task"
        : attention
          ? `answer also needed in Codex Desktop`
          : `on ${MAC.name}`;

  return (
    <div className={s.sill}>
      <div className={s.address} aria-live="polite">
        <div className={s.addressEyebrow}>
          <WaveMark />
          {voiceFlash ? (
            <span className={s.voiceFlash}>
              {voiceFlash === "kept" ? "Kept on iPad" : "Sent to task"}
            </span>
          ) : (
            <span>Talking to</span>
          )}
        </div>
        <div className={s.addressTask}>{task.name}</div>
        <div className={s.addressMac} data-alarm={!online}>
          {online ? `on ${MAC.name}` : `${MAC.name} · offline`}
        </div>
      </div>

      <div className={s.talkCluster}>
        <button
          type="button"
          className={s.talk}
          aria-label={`${label}. Destination: ${task.name} on ${MAC.name}.`}
          onPointerDown={(e) => {
            e.currentTarget.setPointerCapture?.(e.pointerId);
            onHold();
          }}
          onPointerUp={onRelease}
          onKeyDown={(e) => {
            if (e.key === " " || e.key === "Enter") {
              e.preventDefault();
              onHold();
            }
          }}
          onKeyUp={(e) => {
            if (e.key === " " || e.key === "Enter") onRelease();
          }}
        >
          <span className={s.talkDisc} aria-hidden>
            <MicMark />
          </span>
          <span className={s.talkLabel}>{label}</span>
          <span className={s.talkHint}>{hint}</span>
        </button>

        <div className={s.talkMode}>
          {online && working ? (
            <span className={s.talkModeLabel}>Follow-up</span>
          ) : online ? (
            <span className={s.talkModeLabel}>Ready</span>
          ) : (
            <span className={s.talkModeLabel}>Local</span>
          )}
        </div>
      </div>
    </div>
  );
}

/* ── Marks ───────────────────────────────────────────────────────────── */

function WaveMark() {
  return (
    <svg width="14" height="8" viewBox="0 0 14 8" fill="none" aria-hidden>
      <path
        d="M1 4c1.2-2.2 2.4-2.2 3.6 0s2.4 2.2 3.6 0 2.4-2.2 3.6 0"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  );
}

function MicMark() {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden>
      <rect
        x="7.5"
        y="2.5"
        width="5"
        height="9"
        rx="2.5"
        stroke="currentColor"
        strokeWidth="1.4"
      />
      <path
        d="M4.5 9.5a5.5 5.5 0 0 0 11 0"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
      <path
        d="M10 15v2.5"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeLinecap="round"
      />
    </svg>
  );
}

function EarMark() {
  return (
    <svg viewBox="0 0 16 16" fill="none" aria-hidden>
      <path
        d="M3 8c0-2.8 2.2-5 5-5s5 2.2 5 5c0 1.6-.8 3-2 3.9V13H7.5"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M6.2 8.2c0-.9.7-1.6 1.6-1.6"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
      />
    </svg>
  );
}

function CopyMark() {
  return (
    <svg viewBox="0 0 16 16" fill="none" aria-hidden>
      <rect
        x="5.5"
        y="5.5"
        width="7"
        height="8"
        rx="1.2"
        stroke="currentColor"
        strokeWidth="1.3"
      />
      <path
        d="M3.5 10.5V3.8c0-.7.6-1.3 1.3-1.3H10"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
      />
    </svg>
  );
}
