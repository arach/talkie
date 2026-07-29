"use client";

/**
 * THESIS: A selected Codex task should read as one inspectable run dossier, not
 * a settings list or a miniature IDE. The server document owns technical truth;
 * the native sheet owns trust, navigation, and failure recovery.
 *
 * OWN-WORLD: Flat graphite or paper material, hairline rules, one amber state
 * channel, red only for failure, and mono only for identifiers, measurements,
 * git data, and code. No card grid.
 *
 * STORY: Identify the exact task, verify repository state, inspect the useful
 * change, understand the live turn, then recover the latest delivery.
 *
 * FIRST VIEWPORT: Native dismissal and title stay fixed above the task name,
 * lifecycle, identity, branch, HEAD, and change count.
 *
 * FORM: Three treatments share one dossier IA. Directed brief; no concept seed.
 */

import { useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import styles from "./CodexStatusDocument.module.css";

type Treatment = "ledger" | "instrument" | "trace";
type Appearance = "dark" | "light";

interface ChangedFile {
  status: "M" | "A" | "R";
  path: string;
  additions: number;
  deletions: number;
}

interface StatusFixture {
  task: {
    title: string;
    project: string;
    repository: string;
    host: string;
    route: string;
    adapter: string;
    harness: string;
    taskID: string;
  };
  repository: {
    branch: string;
    base: string;
    upstream: string;
    clean: boolean;
    aheadBase: number;
    behindBase: number;
    aheadUpstream: number;
    behindUpstream: number;
    head: string;
    subject: string;
    files: number;
    additions: number;
    deletions: number;
    changedFiles: ChangedFile[];
  };
  turn: {
    status: "running";
    mode: "steer";
    elapsed: string;
    startedAt: string;
    updatedAt: string;
    latestUpdate: string;
    updateSource: string;
  };
  bridge: {
    state: "healthy";
    transport: string;
    lastContact: string;
    renderedAt: string;
  };
  delivery: {
    kind: string;
    completedAt: string;
    response: string;
  };
}

const FIXTURE: StatusFixture = {
  task: {
    title: "Explore a technical, server-rendered Codex status display",
    project: "talkie",
    repository: "arach/talkie",
    host: "Arach’s Mac mini",
    route: "LAN",
    adapter: "Desktop follower · app-server fallback",
    harness: "Codex",
    taskID: "019fa5d3-1cc5-7fc1-a422-c9c3945a94d4",
  },
  repository: {
    branch: "codex/codex-deck-premium-device",
    base: "origin/master",
    upstream: "origin/codex/codex-deck-premium-device",
    clean: true,
    aheadBase: 31,
    behindBase: 0,
    aheadUpstream: 1,
    behindUpstream: 0,
    head: "7e2c14d8",
    subject: "✨ Add narration playback rail",
    files: 41,
    additions: 15_335,
    deletions: 100,
    changedFiles: [
      {
        status: "A",
        path: "apps/ios/Talkie iOS/Codex/CodexCommandDeckSurface.swift",
        additions: 1_658,
        deletions: 0,
      },
      {
        status: "A",
        path: "apps/macos/TalkieServer/src/bridge/routes/codex.ts",
        additions: 891,
        deletions: 0,
      },
      {
        status: "M",
        path: "apps/ios/Talkie iOS/Bridge/BridgeClient.swift",
        additions: 144,
        deletions: 3,
      },
      {
        status: "A",
        path: "design/studio/components/studies/CodexDeckKimi.tsx",
        additions: 1_360,
        deletions: 0,
      },
    ],
  },
  turn: {
    status: "running",
    mode: "steer",
    elapsed: "18:42",
    startedAt: "13:16:04",
    updatedAt: "13:34:46",
    latestUpdate:
      "The audit shows task identity and turn progress already exist. Repository truth and the rendered document need one narrow endpoint.",
    updateSource: "COMMENTARY · 22s ago",
  },
  bridge: {
    state: "healthy",
    transport: "SIGNED · SEALED V2",
    lastContact: "13:34:46.218",
    renderedAt: "13:34:46.311",
  },
  delivery: {
    kind: "STARTED TURN",
    completedAt: "12:52:42",
    response:
      "Narration playback now has a dedicated rail with truthful preparation, playback, stopped, suppressed, and failure states.",
  },
};

const TREATMENTS: Array<{
  key: Treatment;
  label: string;
  note: string;
}> = [
  {
    key: "ledger",
    label: "Run ledger",
    note: "Recommended · one ruled technical document with the least chrome.",
  },
  {
    key: "instrument",
    label: "Instrument",
    note: "Stronger live readout; repository evidence remains document-like.",
  },
  {
    key: "trace",
    label: "Trace",
    note: "A chronological spine emphasizes what changed and what happened.",
  },
];

const HUNK_LINES: Array<{
  kind: "meta" | "context" | "add";
  old?: string;
  next?: string;
  text: string;
}> = [
  { kind: "meta", text: "@@ -0,0 +1,1658 @@" },
  { kind: "context", text: "⋮ 1,545 added lines omitted" },
  { kind: "add", next: "1546", text: "private struct CodexDeckStatusSheet: View {" },
  { kind: "add", next: "1547", text: "    @ObservedObject private var store = CodexLaneStore.shared" },
  { kind: "add", next: "1548", text: "    @ObservedObject private var theme = ThemeManager.shared" },
  { kind: "add", next: "1549", text: "    @Environment(\\.dismiss) private var dismiss" },
  { kind: "add", next: "1551", text: "    var body: some View {" },
  { kind: "add", next: "1552", text: "        NavigationStack {" },
  { kind: "add", next: "1556", text: "                List {" },
  { kind: "add", next: "1557", text: "                    Section(\"Active task\") {" },
  { kind: "context", text: "⋮ 39 added lines omitted" },
  { kind: "add", next: "1597", text: "}" },
];

export function CodexStatusDocumentStudy() {
  const searchParams = useSearchParams();
  const initialTreatment = parseTreatment(searchParams.get("t"));
  const initialAppearance = parseAppearance(searchParams.get("a"));
  const phoneReview = searchParams.get("review") === "phone";
  const [treatment, setTreatment] = useState<Treatment>(initialTreatment);
  const [appearance, setAppearance] = useState<Appearance>(initialAppearance);

  const treatmentNote = useMemo(
    () => TREATMENTS.find((candidate) => candidate.key === treatment)?.note ?? "",
    [treatment],
  );

  return (
    <section className={`${styles.study} ${phoneReview ? styles.phoneReview : ""}`}>
      {!phoneReview ? (
        <div className={styles.controls} aria-label="Study controls">
          <div className={styles.controlGroup}>
            <span className={styles.controlLabel}>Treatment</span>
            <div className={styles.segmented}>
              {TREATMENTS.map((candidate) => (
                <button
                  key={candidate.key}
                  type="button"
                  aria-pressed={treatment === candidate.key}
                  className={styles.segment}
                  onClick={() => setTreatment(candidate.key)}
                >
                  {candidate.label}
                </button>
              ))}
            </div>
          </div>

          <div className={styles.controlGroup}>
            <span className={styles.controlLabel}>Material</span>
            <div className={styles.segmented}>
              {(["dark", "light"] as Appearance[]).map((value) => (
                <button
                  key={value}
                  type="button"
                  aria-pressed={appearance === value}
                  className={styles.segment}
                  onClick={() => setAppearance(value)}
                >
                  {value}
                </button>
              ))}
            </div>
          </div>

          <p className={styles.treatmentNote}>{treatmentNote}</p>
          <p className={styles.fixtureNote}>
            Repository values are captured from <code>7e2c14d8</code>. Runtime timestamps
            and progress copy are illustrative.
          </p>
        </div>
      ) : null}

      <div className={styles.previewColumn}>
        <div
          className={`${styles.phone} ${phoneReview ? styles.reviewShell : ""}`}
          data-appearance={appearance}
        >
          <NativeStatusBar />
          <NativeNavigation />
          <main
            className={`${styles.document} ${styles[treatment]}`}
            aria-label={`${TREATMENTS.find((candidate) => candidate.key === treatment)?.label} Codex task status prototype`}
          >
            <TaskIdentity fixture={FIXTURE} />
            <RepositoryState fixture={FIXTURE} />
            <ChangeSet fixture={FIXTURE} />
            <LiveTurn fixture={FIXTURE} />
            <RecentDelivery fixture={FIXTURE} />
            <DocumentFooter fixture={FIXTURE} />
          </main>
        </div>
        {!phoneReview ? (
          <div className={styles.ownershipKey}>
            <span><i className={styles.nativeMark} />Native shell</span>
            <span><i className={styles.serverMark} />Server document</span>
          </div>
        ) : null}
      </div>
    </section>
  );
}

function NativeStatusBar() {
  return (
    <div className={styles.statusBar} aria-label="Native iOS status bar">
      <span>9:41</span>
      <span className={styles.dynamicIsland} aria-hidden />
      <span className={styles.systemMarks} aria-hidden>● ◔ ▰</span>
    </div>
  );
}

function NativeNavigation() {
  return (
    <header className={styles.nativeNavigation}>
      <button type="button" className={styles.doneButton}>Done</button>
      <strong>Task status</strong>
      <button type="button" className={styles.reloadButton} aria-label="Reload status">
        ↻
      </button>
    </header>
  );
}

function TaskIdentity({ fixture }: { fixture: StatusFixture }) {
  return (
    <header className={styles.taskIdentity}>
      <div className={styles.stateLine}>
        <span className={styles.liveLamp} aria-hidden />
        <strong>{fixture.turn.status.toUpperCase()}</strong>
        <span>{fixture.turn.mode.toUpperCase()}</span>
        <time>{fixture.turn.elapsed}</time>
      </div>
      <h2>{fixture.task.title}</h2>
      <p className={styles.contextLine}>
        <span>{fixture.task.repository}</span>
        <span>{fixture.task.host}</span>
      </p>
      <dl className={styles.identityGrid}>
        <Metric label="Task / thread" value={fixture.task.taskID} wide />
        <Metric label="Harness" value={fixture.task.harness} />
        <Metric label="Adapter" value={fixture.task.adapter} wide />
        <Metric label="Route" value={`${fixture.task.route} · ${fixture.bridge.transport}`} wide />
      </dl>
    </header>
  );
}

function RepositoryState({ fixture }: { fixture: StatusFixture }) {
  const repository = fixture.repository;
  return (
    <DocumentSection kicker="Repository" title="Working state">
      <div className={styles.branchBlock}>
        <div>
          <span className={styles.fieldLabel}>Branch</span>
          <code>{repository.branch}</code>
        </div>
        <span className={repository.clean ? styles.cleanState : styles.dirtyState}>
          {repository.clean ? "CLEAN" : "DIRTY"}
        </span>
      </div>

      <dl className={styles.repoGrid}>
        <Metric label="Base" value={repository.base} />
        <Metric label="Base delta" value={`+${repository.aheadBase} / −${repository.behindBase}`} />
        <Metric label="Upstream" value={repository.upstream} wide />
        <Metric
          label="Upstream delta"
          value={`+${repository.aheadUpstream} / −${repository.behindUpstream}`}
        />
        <Metric label="HEAD" value={repository.head} />
      </dl>

      <p className={styles.commitSubject}>{repository.subject}</p>
    </DocumentSection>
  );
}

function ChangeSet({ fixture }: { fixture: StatusFixture }) {
  const repository = fixture.repository;
  return (
    <DocumentSection kicker="Changes" title="Branch diff">
      <div className={styles.diffSummary} aria-label="Diff summary">
        <strong>{repository.files}</strong>
        <span>files</span>
        <strong className={styles.additions}>+{formatNumber(repository.additions)}</strong>
        <span className={styles.deletions}>−{formatNumber(repository.deletions)}</span>
      </div>

      <div className={styles.fileList}>
        {repository.changedFiles.map((file) => (
          <div className={styles.fileRow} key={file.path}>
            <span className={styles.fileStatus}>{file.status}</span>
            <code title={file.path}>{file.path}</code>
            <span className={styles.fileDelta}>
              <b>+{formatNumber(file.additions)}</b>
              {file.deletions > 0 ? <i>−{formatNumber(file.deletions)}</i> : null}
            </span>
          </div>
        ))}
        <div className={`${styles.fileRow} ${styles.moreFiles}`}>
          <span className={styles.fileStatus}>…</span>
          <span>37 more changed files</span>
          <span />
        </div>
      </div>

      <details className={styles.hunk} open>
        <summary>
          <span>
            <strong>Added-file excerpt</strong>
            <code>CodexCommandDeckSurface.swift</code>
          </span>
          <span className={styles.disclosure}>⌄</span>
        </summary>
        <div className={styles.codeViewport}>
          {HUNK_LINES.map((line, index) => (
            <div className={`${styles.codeLine} ${styles[line.kind]}`} key={`${line.text}-${index}`}>
              <span className={styles.lineNumber}>{line.old ?? ""}</span>
              <span className={styles.lineNumber}>{line.next ?? ""}</span>
              <span className={styles.diffMark}>{line.kind === "add" ? "+" : " "}</span>
              <code>{line.text}</code>
            </div>
          ))}
        </div>
      </details>
    </DocumentSection>
  );
}

function LiveTurn({ fixture }: { fixture: StatusFixture }) {
  return (
    <DocumentSection kicker="Turn" title="Live activity">
      <div className={styles.turnRail}>
        <div className={styles.turnEvent}>
          <time>{fixture.turn.startedAt}</time>
          <div>
            <strong>Turn accepted</strong>
            <p>Delivery mode · {fixture.turn.mode.toUpperCase()}</p>
          </div>
        </div>
        <div className={`${styles.turnEvent} ${styles.currentEvent}`}>
          <time>{fixture.turn.updatedAt}</time>
          <div>
            <strong>{fixture.turn.updateSource}</strong>
            <p>{fixture.turn.latestUpdate}</p>
          </div>
        </div>
      </div>

      <dl className={styles.healthLine}>
        <Metric label="Bridge" value={fixture.bridge.state.toUpperCase()} />
        <Metric label="Last contact" value={fixture.bridge.lastContact} />
      </dl>
    </DocumentSection>
  );
}

function RecentDelivery({ fixture }: { fixture: StatusFixture }) {
  return (
    <DocumentSection kicker="Delivery" title="Previous response">
      <div className={styles.deliveryMeta}>
        <span>{fixture.delivery.kind}</span>
        <time>{fixture.delivery.completedAt}</time>
      </div>
      <blockquote>{fixture.delivery.response}</blockquote>
    </DocumentSection>
  );
}

function DocumentFooter({ fixture }: { fixture: StatusFixture }) {
  return (
    <footer className={styles.documentFooter}>
      <span>Rendered {fixture.bridge.renderedAt}</span>
      <span>Task scoped · read only</span>
    </footer>
  );
}

function DocumentSection({
  kicker,
  title,
  children,
}: {
  kicker: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className={styles.documentSection}>
      <header className={styles.sectionHeader}>
        <span>{kicker}</span>
        <h3>{title}</h3>
      </header>
      {children}
    </section>
  );
}

function Metric({
  label,
  value,
  wide = false,
}: {
  label: string;
  value: string;
  wide?: boolean;
}) {
  return (
    <div className={wide ? styles.wideMetric : undefined}>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function parseTreatment(value: string | null): Treatment {
  return value === "instrument" || value === "trace" ? value : "ledger";
}

function parseAppearance(value: string | null): Appearance {
  return value === "light" ? "light" : "dark";
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("en-CA").format(value);
}
