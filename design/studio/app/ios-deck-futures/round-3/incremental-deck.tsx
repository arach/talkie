"use client";

import { useState } from "react";
import styles from "./incremental-deck.module.css";

type Take = "stack" | "split" | "wide" | "impeccable" | "dock" | "ledger";
type Scene = "ready" | "working" | "result" | "offline";
type Delivery = "steer" | "queue";

const TAKES: { id: Take; number: string; label: string; note: string }[] = [
  { id: "stack", number: "01", label: "Direct scale", note: "Today, opened up" },
  { id: "split", number: "02", label: "Calmer margins", note: "Same stack, less spread" },
  { id: "wide", number: "03", label: "More console", note: "Same stack, reading bias" },
  { id: "impeccable", number: "04", label: "Operational polish", note: "State and reach, preserved" },
  { id: "dock", number: "05", label: "Live dock", note: "Mechanics find a home" },
  { id: "ledger", number: "06", label: "Console ledger", note: "Context, permanently balanced" },
];

const SCENES: { id: Scene; label: string }[] = [
  { id: "ready", label: "Ready" },
  { id: "working", label: "Working" },
  { id: "result", label: "Result" },
  { id: "offline", label: "Offline" },
];

const COMMANDS = [
  { mark: "↗", label: "Output" },
  { mark: "⌁", label: "Mapper" },
  { mark: "▦", label: "Spaces" },
  { mark: "···", label: "Details" },
  { mark: "↶", label: "History" },
  { mark: "◉", label: "Read" },
  { mark: "⧉", label: "Copy" },
  { mark: "↻", label: "Refresh" },
  { mark: "←", label: "Prev lane" },
  { mark: "▶", label: "Replay" },
  { mark: "■", label: "Stop" },
  { mark: "→", label: "Next lane" },
  { mark: "+", label: "Task" },
  { mark: "⌁", label: "Readout" },
];

const DOCK_COMMANDS = COMMANDS.filter(
  (command) => !["Details", "History", "Readout"].includes(command.label),
);

const LEDGER_COMMANDS = COMMANDS.filter(
  (command) => !["Details", "History"].includes(command.label),
);

const LANE_NAMES = ["Release", "Bridge", "IPC", "Tests", "Docs", "Inbox"];

const SCENE_COPY: Record<Scene, { code: string; kicker: string; title: string }> = {
  ready: { code: "RDY", kicker: "WAITING ON YOU", title: "Ready for a direction." },
  working: { code: "RUN", kicker: "CODEX IS WORKING", title: "Tracing the follower ownership boundary" },
  result: { code: "RX", kicker: "RESPONSE RECEIVED", title: "Follower ownership is now explicit" },
  offline: { code: "ERR", kicker: "CONNECTION LOST", title: "Mac Mini unavailable" },
};

export function IncrementalDeckStudy() {
  const [take, setTake] = useState<Take>("dock");
  const [scene, setScene] = useState<Scene>("working");
  const [delivery, setDelivery] = useState<Delivery>("steer");

  const currentTake = TAKES.find((item) => item.id === take) ?? TAKES[1];

  return (
    <div className={styles.study}>
      <div className={styles.studyBar}>
        <div className={styles.takeTabs} role="tablist" aria-label="iPad layout take">
          {TAKES.map((item) => (
            <button
              key={item.id}
              type="button"
              role="tab"
              aria-selected={take === item.id}
              className={styles.takeTab}
              onClick={() => setTake(item.id)}
            >
              <span className={styles.takeNumber}>{item.number}</span>
              <span>
                <strong>{item.label}</strong>
                <small>{item.note}</small>
              </span>
            </button>
          ))}
        </div>

        <div className={styles.sceneTabs} role="group" aria-label="Preview state">
          {SCENES.map((item) => (
            <button
              key={item.id}
              type="button"
              aria-pressed={scene === item.id}
              className={styles.sceneTab}
              onClick={() => setScene(item.id)}
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>

      <div className={styles.renderLabel}>
        <span>{currentTake.number} · {currentTake.label}</span>
        <span>iPad Air landscape · 1180 × 820 pt</span>
      </div>

      <div className={styles.artboardShell}>
        <article className={styles.deck} data-take={take} data-scene={scene}>
          {take === "dock" || take === "ledger" ? null : <DeckHeader scene={scene} />}

          <div className={styles.instrument}>
            <div className={styles.consoleAssembly}>
              <LaneRail scene={scene} />
              <TaskConsole
                take={take}
                scene={scene}
                delivery={delivery}
                onDeliveryChange={setDelivery}
              />
            </div>
            <CommandKeybed take={take} scene={scene} />
          </div>
        </article>
      </div>

      <div className={styles.designNote}>
        <span>What changes</span>
        <p>{takeDescription(take)}</p>
        <span>What does not</span>
        <p>Six lanes, exact task, host state, delivery mode, command vocabulary, and voice control.</p>
      </div>
    </div>
  );
}

function DeckHeader({ scene }: { scene: Scene }) {
  return (
    <header className={styles.deckHeader}>
      <div className={styles.brandLockup}>
        <span className={styles.brandMark}>T</span>
        <span>
          <strong>TALKIE</strong>
          <small>COMMAND DECK</small>
        </span>
      </div>

      <div className={styles.headerCenter}>CODEX <i /> CMD</div>

      <button type="button" className={styles.hostStatus}>
        <span className={styles.hostPulse} data-offline={scene === "offline"} />
        <span>
          <strong>Mac Mini</strong>
          <small>{scene === "offline" ? "REVIEW CONNECTION" : "LIVE · CONNECTED"}</small>
        </span>
        <b>›</b>
      </button>
    </header>
  );
}

function LaneRail({ scene }: { scene: Scene }) {
  const selectedCode = SCENE_COPY[scene].code;
  return (
    <nav className={styles.laneRail} aria-label="Task lanes">
      <div className={styles.lanes}>
        {LANE_NAMES.map((name, index) => {
          const selected = index === 2;
          return (
            <button key={name} type="button" className={styles.lane} data-selected={selected}>
              <span>{String(index + 1).padStart(2, "0")}</span>
              <strong>{name}</strong>
              <small>{selected ? selectedCode : index === 1 ? "QUE" : "RDY"}</small>
            </button>
          );
        })}
      </div>
    </nav>
  );
}

function TaskConsole({
  take,
  scene,
  delivery,
  onDeliveryChange,
}: {
  take: Take;
  scene: Scene;
  delivery: Delivery;
  onDeliveryChange: (delivery: Delivery) => void;
}) {
  const copy = SCENE_COPY[scene];

  if (take === "ledger") {
    return (
      <LedgerTaskConsole
        scene={scene}
        delivery={delivery}
        onDeliveryChange={onDeliveryChange}
      />
    );
  }

  return (
    <section className={styles.console} aria-label="Active Codex task">
      <div className={styles.consoleTopline}>
        <div>
          <span className={styles.consoleIndex}>03</span>
          <span>IPC · FOLLOWER OWNERSHIP</span>
        </div>
        {take === "dock" ? (
          <ConsoleMechanics scene={scene} />
        ) : (
          <DeliveryModes delivery={delivery} onDeliveryChange={onDeliveryChange} />
        )}
      </div>

      <div className={styles.consoleBody}>
        <div className={styles.consoleStatus} data-code={copy.code}>
          <span>{copy.code}</span>
          <i />
          <small>{copy.kicker}</small>
        </div>
        <h2>{copy.title}</h2>
        <SceneBody scene={scene} />
      </div>

      {take === "dock" ? (
        <TaskDock
          scene={scene}
          delivery={delivery}
          onDeliveryChange={onDeliveryChange}
        />
      ) : (
        <div className={styles.consoleFooter}>
          <span>talkie-codex-command-deck</span>
          <span>~/dev/talkie</span>
        </div>
      )}
    </section>
  );
}

function DeliveryModes({
  delivery,
  onDeliveryChange,
}: {
  delivery: Delivery;
  onDeliveryChange: (delivery: Delivery) => void;
}) {
  return (
    <div className={styles.deliveryModes}>
      <span>SEND AS</span>
      {(["steer", "queue"] as Delivery[]).map((mode) => (
        <button
          key={mode}
          type="button"
          aria-pressed={delivery === mode}
          onClick={() => onDeliveryChange(mode)}
        >
          {mode.toUpperCase()}
        </button>
      ))}
    </div>
  );
}

function ConsoleMechanics({ scene }: { scene: Scene }) {
  return (
    <div className={styles.consoleMechanics}>
      <div className={styles.mechanicsNav} role="group" aria-label="Task context">
        <button type="button" aria-pressed="true">Thread <small>4</small></button>
        <button type="button">Details</button>
        <button type="button">History</button>
      </div>
      <button type="button" className={styles.consoleHost}>
        <span className={styles.hostPulse} data-offline={scene === "offline"} />
        <span>Mac Mini</span>
        <small>{scene === "offline" ? "Review" : "Live"}</small>
      </button>
    </div>
  );
}

function LedgerTaskConsole({
  scene,
  delivery,
  onDeliveryChange,
}: {
  scene: Scene;
  delivery: Delivery;
  onDeliveryChange: (delivery: Delivery) => void;
}) {
  const copy = SCENE_COPY[scene];

  return (
    <section className={styles.console} aria-label="Active Codex task">
      <div className={styles.ledgerBody}>
        <div className={styles.ledgerStage}>
          <div className={styles.ledgerIdentity}>
            <span>03</span>
            <strong>IPC · FOLLOWER OWNERSHIP</strong>
            <small>EXACT TASK</small>
          </div>

          <div className={styles.ledgerReading}>
            <div className={styles.consoleStatus} data-code={copy.code}>
              <span>{copy.code}</span>
              <i />
              <small>{copy.kicker}</small>
            </div>
            <h2>{copy.title}</h2>
            <SceneBody scene={scene} />
          </div>
        </div>

        <aside className={styles.ledgerRail} aria-label="Permanent task context">
          <section className={styles.ledgerDetails} aria-label="Task details">
            <LedgerHeading label="Details" meta="Exact task" />
            <dl>
              <div><dt>Task</dt><dd>03 · IPC</dd></div>
              <div><dt>Repo</dt><dd>talkie</dd></div>
              <div>
                <dt>Host</dt>
                <dd data-offline={scene === "offline"}>
                  <i /> Mac Mini · {scene === "offline" ? "Offline" : "Live"}
                </dd>
              </div>
            </dl>
          </section>

          <section className={styles.ledgerHistory} aria-label="Task history">
            <LedgerHeading label="History" meta="4 turns" />
            <div className={styles.ledgerMessages}>
              <article>
                <small>You · 23:18</small>
                <p>Trace the follower ownership boundary.</p>
              </article>
              <article>
                <small>Codex · now</small>
                <p>Checking listener teardown across bridge replacement.</p>
              </article>
            </div>
          </section>
        </aside>
      </div>

      <TaskDock
        scene={scene}
        delivery={delivery}
        onDeliveryChange={onDeliveryChange}
      />
    </section>
  );
}

function LedgerHeading({ label, meta }: { label: string; meta: string }) {
  return (
    <div className={styles.ledgerHeading}>
      <strong>{label}</strong>
      <span>{meta}</span>
    </div>
  );
}

function TaskDock({
  scene,
  delivery,
  onDeliveryChange,
}: {
  scene: Scene;
  delivery: Delivery;
  onDeliveryChange: (delivery: Delivery) => void;
}) {
  const copy = SCENE_COPY[scene];
  const placeholder = {
    ready: "Add a direction…",
    working: "Steer the current turn…",
    result: "Continue this task…",
    offline: "Reconnect to send a direction",
  }[scene];

  return (
    <div className={styles.taskDock} aria-label="Live status and direction dock">
      <div className={styles.directionField} data-offline={scene === "offline"}>
        <span className={styles.dockActivity} data-code={copy.code}>{copy.code}</span>
        <input
          type="text"
          aria-label="Direction"
          disabled={scene === "offline"}
          placeholder={placeholder}
        />
        <button type="button" aria-label="Speak direction" disabled={scene === "offline"}>
          <span><i /><i /><i /></span>
        </button>
      </div>

      <DeliveryModes delivery={delivery} onDeliveryChange={onDeliveryChange} />
    </div>
  );
}

function SceneBody({ scene }: { scene: Scene }) {
  if (scene === "ready") {
    return (
      <p className={styles.readingCopy}>
        Hold TALK to give Codex a direction. Use STEER to interrupt the current turn or QUEUE to send the next instruction.
      </p>
    );
  }

  if (scene === "result") {
    return (
      <div className={styles.resultCopy}>
        <p>The follower now owns its IPC listener for the lifetime of the active bridge.</p>
        <p>The adapter suite passes. The stale listener is released before a replacement bridge starts.</p>
      </div>
    );
  }

  if (scene === "offline") {
    return (
      <div className={styles.offlineCopy}>
        <p>Your active task is still visible on this iPad. Reconnect to continue.</p>
        <button type="button">Review connection</button>
      </div>
    );
  }

  return (
    <ol className={styles.activityList}>
      <li data-done="true"><span>01</span>Located the follower IPC owner</li>
      <li data-active="true"><span>02</span>Checking listener teardown across bridge replacement</li>
      <li><span>03</span>Re-run the focused adapter suite</li>
    </ol>
  );
}

function CommandKeybed({ take, scene }: { take: Take; scene: Scene }) {
  const commands = take === "dock"
    ? DOCK_COMMANDS
    : take === "ledger"
      ? LEDGER_COMMANDS
      : COMMANDS;
  return (
    <section className={styles.keybed} aria-label="Deck commands" data-layout={take}>
      <div className={styles.keybedLabel}>
        <span>COMMANDS</span>
        <span>{scene === "working" ? "ACTIVE TASK · 03" : "SELECTED LANE · 03"}</span>
      </div>
      <div className={styles.keyGrid}>
        {commands.map((command) => (
          <button key={command.label} type="button" className={styles.commandKey}>
            <span>{command.mark}</span>
            <small>{command.label}</small>
          </button>
        ))}
        <button type="button" className={styles.talkKey}>
          <span className={styles.talkGlyph}><i /><i /><i /><i /><i /></span>
          <strong>TALK</strong>
          <small>HOLD TO SPEAK</small>
        </button>
      </div>
    </section>
  );
}

function takeDescription(take: Take) {
  if (take === "stack") {
    return "The current console-over-keybed composition simply opens to the iPad width. Nothing moves and the 4×4 field stays intact.";
  }
  if (take === "wide") {
    return "The same stack gives the black-glass console a little more height, while the unchanged 4×4 keybed remains below it.";
  }
  if (take === "impeccable") {
    return "More Console remains intact. This pass only exposes each lane’s truthful state and brings the small delivery and recovery controls to a full 44-point touch target.";
  }
  if (take === "dock") {
    return "The ceremonial header disappears. Thread, Details, History, and host state fill the console utility rail; the lower dock is reserved for live direction and STEER / QUEUE. Their old key slots give TALK the full lower row of a quieter 5 × 3 keybed.";
  }
  if (take === "ledger") {
    return "The exact task remains primary while Details and prior messages gain a permanent, compact right-hand ledger. The live direction dock stays attached to the task, and the remaining commands settle into a balanced 4 × 3 key field above a full-width TALK plinth.";
  }
  return "The same proportions sit in a calmer 900-point instrument column. Only the iPad margins change.";
}
