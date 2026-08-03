"use client";

/**
 * Standing Page — Round 2 full-size iPad at-bat.
 *
 * The premise: one task's latest useful work stands as a single lit
 * porcelain page on a live brass sill, and the sill is the voice.
 *
 * There is no sidebar, no card grid, and no toolbar. The left edge is a
 * spine — a binding you turn to, not a navigation list. The page is the
 * work. The sill under the page is simultaneously the address plate that
 * names where speech goes and the surface you press to speak, which is
 * why voice cannot read as an appended control: the work is physically
 * resting on it.
 */

import { useCallback, useEffect, useRef, useState } from "react";

import s from "./standing-page.module.css";
import { MAC, SCENARIOS, TASKS, WAVE, type ResultBlock, type Task } from "./content";

const ARTBOARD_W = 1366;
const ARTBOARD_H = 1024;

export function StandingPage({ scenarioKey }: { scenarioKey: string }) {
  const scenario = SCENARIOS.find((v) => v.key === scenarioKey) ?? SCENARIOS[0];

  // Scenario changes re-aim the spine at the task that scenario is about.
  const [seen, setSeen] = useState(scenario.key);
  const [taskId, setTaskId] = useState(scenario.taskId);
  const [detailOpen, setDetailOpen] = useState(false);
  const [listening, setListening] = useState(false);

  if (seen !== scenario.key) {
    setSeen(scenario.key);
    setTaskId(scenario.taskId);
    setDetailOpen(false);
    setListening(false);
  }

  const task = TASKS.find((t) => t.id === taskId) ?? TASKS[0];
  const online = scenario.online;
  const attention = online && task.state === "needs-you";

  const release = useCallback(() => setListening(false), []);

  useEffect(() => {
    if (!listening) return;
    window.addEventListener("pointerup", release);
    window.addEventListener("pointercancel", release);
    return () => {
      window.removeEventListener("pointerup", release);
      window.removeEventListener("pointercancel", release);
    };
  }, [listening, release]);

  return (
    <FitToWidth>
      <div className={s.deviceShell}>
        <div
          className={s.stage}
          data-online={online}
          data-listening={listening}
        >
          <div className={s.stageLight} aria-hidden />

          <Spine
            selectedId={task.id}
            online={online}
            onSelect={(id) => {
              setTaskId(id);
              setDetailOpen(false);
              setListening(false);
            }}
          />

          <Page
            task={task}
            online={online}
            detailOpen={detailOpen}
            onToggleDetail={() => setDetailOpen((v) => !v)}
          />

          <Marginalia task={task} online={online} />

          <Sill
            task={task}
            online={online}
            attention={attention}
            listening={listening}
            onHold={() => setListening(true)}
            onRelease={release}
          />

          <div className={s.homeBar} aria-hidden />
        </div>
      </div>
    </FitToWidth>
  );
}

/* ── Spine ───────────────────────────────────────────────────────────── */

function Spine({
  selectedId,
  online,
  onSelect,
}: {
  selectedId: string;
  online: boolean;
  onSelect: (id: string) => void;
}) {
  return (
    <nav className={s.spine} aria-label="Tasks">
      <div className={s.spineHead} aria-hidden>
        <WaveMark />
      </div>
      <div className={s.spineTicks}>
        {TASKS.map((t) => {
          const selected = t.id === selectedId;
          // Offline flattens every mark but the selection: Talkie cannot
          // observe any of these states while the Mac is unreachable.
          const mark = online && t.state !== "unknown" ? t.state : null;
          return (
            <button
              key={t.id}
              type="button"
              className={s.tick}
              data-selected={selected}
              aria-current={selected ? "true" : undefined}
              onClick={() => onSelect(t.id)}
            >
              {selected ? <span className={s.tickBar} aria-hidden /> : null}
              {mark ? (
                <span className={s.tickMark} data-state={mark} aria-hidden />
              ) : (
                <span className={s.tickSpacer} aria-hidden />
              )}
              <span className={s.tickLabel}>{t.name}</span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}

/* ── The standing page ───────────────────────────────────────────────── */

function Page({
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
  const showQuestion = online && task.question;
  const showActivity = online && task.activity;

  return (
    <article className={s.page}>
      {!online ? (
        <div className={s.staleBand}>
          <span className={s.staleBandKey}>Last heard {MAC.lastHeard}</span>
          <span>
            {task.result
              ? `Everything below is what ${MAC.name} last sent, at ${task.result.at}.`
              : `Nothing below has been confirmed since ${MAC.name} went quiet.`}
          </span>
        </div>
      ) : null}

      {showQuestion ? (
        <div className={s.attention}>
          <div className={s.attentionLabel}>Codex is waiting on you</div>
          <p className={s.attentionQuestion}>{task.question}</p>
        </div>
      ) : null}

      <div className={s.pageBody}>
        <header className={s.pageHead}>
          <h1 className={s.title}>{task.name}</h1>
          <div className={s.titleMeta}>
            {/* No state word at all when the state is not observable. */}
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
            <span className={s.instructionAt}>you · {task.instruction.at}</span>
          </div>
        ) : null}

        <div className={s.bodyRule} aria-hidden />

        {showActivity && task.activity ? (
          <div className={s.working}>
            <div className={s.activityLine}>
              <p className={s.activityText}>{task.activity.text}</p>
              <span className={s.activityStarted}>{task.activity.started}</span>
            </div>
            <div className={s.foldRule} aria-hidden>
              <div className={s.foldRuleBase} />
              <div className={s.foldRuleTravel} />
            </div>
            <div className={s.pending}>{task.emptyNote}</div>
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

      <button
        type="button"
        className={s.fold}
        data-open={detailOpen}
        aria-expanded={detailOpen}
        onClick={onToggleDetail}
      >
        <span className={s.foldText}>{detailOpen ? "Hide turn" : "Turn detail"}</span>
      </button>
    </article>
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

/* ── Marginalia ──────────────────────────────────────────────────────── */

function Marginalia({ task, online }: { task: Task; online: boolean }) {
  const stamp = task.result?.at ?? task.instruction?.at ?? "—";
  const turn = task.result?.turn ?? task.detail[0];
  const hasResult = Boolean(task.result);

  return (
    <aside className={s.margin}>
      <div>
        <div className={s.marginStamp}>{stamp}</div>
        <div className={s.marginTurn}>{turn}</div>
      </div>

      <div className={s.marginActions}>
        <button type="button" className={s.marginAction} disabled={!hasResult}>
          <EarMark />
          Hear this result
        </button>
        <button type="button" className={s.marginAction} disabled={!hasResult}>
          <CopyMark />
          Copy text
        </button>
      </div>

      <div className={s.marginRule} aria-hidden />

      <div className={s.marginBlock}>
        <div className={s.marginKey}>Mac</div>
        <div className={s.marginValue} data-alarm={!online}>
          <span className={s.healthDot} aria-hidden />
          {MAC.name}
        </div>
        <div className={s.marginValue} data-alarm={!online}>
          {online ? MAC.since : `last heard ${MAC.lastHeard}`}
        </div>
      </div>
    </aside>
  );
}

/* ── The sill ────────────────────────────────────────────────────────── */

function Sill({
  task,
  online,
  attention,
  listening,
  onHold,
  onRelease,
}: {
  task: Task;
  online: boolean;
  attention: boolean;
  listening: boolean;
  onHold: () => void;
  onRelease: () => void;
}) {
  const working = online && Boolean(task.activity);

  // Talkie can dispatch speech. It cannot cancel a turn or answer a
  // question on the user's behalf, so no control here claims to.
  const label = listening
    ? "Listening — release to send"
    : !online
      ? `Talk unavailable — ${MAC.name} is offline`
      : working
        ? "Hold to add a follow-up"
        : attention
          ? "Hold to queue a follow-up"
          : "Hold to continue this task";

  const note = !online
    ? null
    : attention
      ? `Answer the question in Codex Desktop on ${MAC.name}`
      : working
        ? "Saved with this task"
        : null;

  return (
    <div className={s.sill} data-attention={attention}>
      <div className={s.plate}>
        <div className={s.plateTop}>
          <WaveMark small />
          <span className={s.plateTo}>Talking to</span>
        </div>
        <div className={s.plateTask}>{task.name}</div>
        <div className={s.plateMac}>on {MAC.name}</div>
      </div>

      {online ? (
        <button
          type="button"
          className={s.lane}
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
          <div className={s.laneTop}>
            <span className={s.laneLabel}>{label}</span>
            {note ? (
              <span className={s.laneNote}>{note}</span>
            ) : null}
          </div>

          <div className={s.meniscus} aria-hidden>
            {listening ? (
              <div className={s.bars}>
                {WAVE.map((h, i) => (
                  <span
                    key={i}
                    className={s.bar}
                    style={{ height: `${h}px`, animationDelay: `${i * 7}ms` }}
                  />
                ))}
              </div>
            ) : (
              <span className={s.meniscusLine} data-breathing={working} />
            )}
          </div>
        </button>
      ) : (
        <div className={s.recovery}>
          <div className={s.recoveryText}>
            <span className={s.recoveryStrong}>{MAC.name} is unavailable</span>
            <span>Last heard {MAC.lastHeard}. Nothing you say can be delivered.</span>
          </div>
          <button type="button" className={s.recoveryBtn} data-primary="true">
            Reconnect
          </button>
          <button type="button" className={s.recoveryBtn}>
            Review connection
          </button>
          <button type="button" className={s.recoveryBtn}>
            Choose another Mac
          </button>
        </div>
      )}
    </div>
  );
}

/* ── Marks ───────────────────────────────────────────────────────────── */

function WaveMark({ small }: { small?: boolean }) {
  const h = small ? 12 : 20;
  const w = small ? 14 : 22;
  return (
    <svg width={w} height={h} viewBox="0 0 22 20" fill="none" aria-hidden>
      <g stroke="currentColor" strokeWidth="2" strokeLinecap="round">
        <path d="M2 8v4" />
        <path d="M7.33 3v14" />
        <path d="M12.66 6v8" />
        <path d="M18 1.5v17" />
      </g>
    </svg>
  );
}

function EarMark() {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" fill="none" aria-hidden>
      <g stroke="currentColor" strokeWidth="1.4" strokeLinecap="round">
        <path d="M8 14a3.4 3.4 0 0 0 3.4-3.4c0-1.5 1.6-2.2 1.6-4.6a5 5 0 1 0-10 0" />
        <path d="M6 6.6a2 2 0 1 1 3.2 1.6c-.8.6-1.2 1-1.2 2" />
      </g>
    </svg>
  );
}

function CopyMark() {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" fill="none" aria-hidden>
      <g stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round">
        <rect x="5.5" y="5.5" width="8" height="9" rx="1.2" />
        <path d="M10.5 3.2A1.2 1.2 0 0 0 9.3 2H3.7a1.2 1.2 0 0 0-1.2 1.2v7.1a1.2 1.2 0 0 0 1.2 1.2h.8" />
      </g>
    </svg>
  );
}

/* ── Studio-side scaler (not part of the iPad surface) ────────────────── */

function FitToWidth({ children }: { children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(([entry]) => {
      const w = entry.contentRect.width;
      setScale(w > 0 ? Math.min(1, w / ARTBOARD_W) : 1);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div ref={ref} className={s.scaler} style={{ height: ARTBOARD_H * scale }}>
      <div className={s.scalerInner} style={{ transform: `scale(${scale})` }}>
        <div className={s.root}>{children}</div>
      </div>
    </div>
  );
}
