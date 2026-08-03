import Image from "next/image";

import styles from "./IPadDesignConsolidation.module.css";

type Concept = {
  index: string;
  name: string;
  shortName: string;
  status: string;
  score: string;
  ranks: string;
  thesis: string;
  keep: string;
  risk: string;
  layout: "desk" | "folio" | "tape" | "chronicle";
  tone: "advance" | "borrow" | "hold" | "reject";
};

const CONCEPTS: Concept[] = [
  {
    index: "01",
    name: "Fixed Command Desk",
    shortName: "Task Desk",
    status: "Advance",
    score: "8.68",
    ranks: "1 · 1 · 1",
    thesis: "A stable task rail beside one dominant selected conversation.",
    keep: "The two-column default, exact task selection, and fixed Talk shelf.",
    risk: "A permanent evidence column turns the surface into an IDE or dashboard.",
    layout: "desk",
    tone: "advance",
  },
  {
    index: "02",
    name: "Operational Folio",
    shortName: "Folio",
    status: "Borrow",
    score: "8.43",
    ranks: "3 · 2 · 3",
    thesis: "A readable task page paired with a generous result page.",
    keep: "The calm long-result reading model and honest recovery surface.",
    risk: "Two equally weighted pages weaken selection and make Talk move with focus.",
    layout: "folio",
    tone: "borrow",
  },
  {
    index: "03",
    name: "Selected-Task Tape",
    shortName: "Task Tape",
    status: "Conditional",
    score: "8.52",
    ranks: "2 · 3 · 2",
    thesis: "One task becomes a temporal record of request, activity, and result.",
    keep: "Pinned attention, terminal failure honesty, and quiet in-turn updates.",
    risk: "Chronology becomes log chrome unless real event density earns it.",
    layout: "tape",
    tone: "hold",
  },
  {
    index: "04",
    name: "Cross-Task Chronicle",
    shortName: "Chronicle",
    status: "Components only",
    score: "7.33",
    ranks: "4 · 4 · 4",
    thesis: "Several tasks share one time axis so attention can move across work.",
    keep: "Promote known attention above recency in the task list.",
    risk: "The shared timeline weakens voice ownership and recreates an operations console.",
    layout: "chronicle",
    tone: "reject",
  },
];

const PROBES = [
  {
    name: "Fixed Command Desk",
    role: "Closest starting point",
    image: "/studies/ios-deck-futures/ipad-probe-command-desk.png",
    note: "Stable and immediately legible. Remove the permanent right inspector before the next pass.",
  },
  {
    name: "Operational Folio",
    role: "Reading donor",
    image: "/studies/ios-deck-futures/ipad-probe-operational-folio.png",
    note: "The strongest treatment of a long result, but still reads as a polished three-column app.",
  },
  {
    name: "Selected-Task Tape",
    role: "Attention donor",
    image: "/studies/ios-deck-futures/ipad-probe-flight-recorder.png",
    note: "The clearest Needs you treatment. The temporal rail spends too much permanent space.",
  },
];

export function IPadDesignConsolidation() {
  return (
    <div className={styles.board}>
      <header className={styles.hero}>
        <div className={styles.heroCopy}>
          <span className={styles.kicker}>Consolidated design field</span>
          <h2>Four structures. One conversation instrument.</h2>
          <p>
            Kimi, Grok, and Claude Opus explored the same four iPad structures,
            challenged one another, and converged on a simpler Task Desk. The
            useful parts survive below without turning Talkie into a portable IDE.
          </p>
        </div>
        <dl className={styles.flightLedger}>
          <div>
            <dt>Models</dt>
            <dd>3</dd>
          </div>
          <div>
            <dt>Reviews</dt>
            <dd>9</dd>
          </div>
          <div>
            <dt>Structures</dt>
            <dd>4</dd>
          </div>
          <div>
            <dt>Probes</dt>
            <dd>3</dd>
          </div>
        </dl>
      </header>

      <div className={styles.lineage} aria-label="Design direction lineage">
        <div className={styles.lineageLabel}>
          <span>Direction lineage</span>
          <strong>From five spatial ideas to four tested structures</strong>
        </div>
        <div className={styles.lineageTrack}>
          <span><b>01 Bridge</b></span>
          <span><b>04 Ops Ledger</b></span>
          <span><b>05 Patch Bay</b></span>
          <i aria-hidden>→</i>
          <strong>Task Workbench</strong>
          <i aria-hidden>→</i>
          <em>Desk + Folio</em>
        </div>
        <div className={styles.lineageTrack}>
          <span><b>03 Flight Recorder</b></span>
          <i aria-hidden>→</i>
          <strong>Temporal wildcard</strong>
          <i aria-hidden>→</i>
          <em>Tape + Chronicle</em>
        </div>
        <div className={styles.archivedDirection}>
          <span>Archived</span>
          <p><b>02 Six-Bus Mixer</b> made every task an equal channel. Fleet visibility survived; the mixer structure did not.</p>
        </div>
      </div>

      <nav className={styles.jumpNav} aria-label="Consolidated study sections">
        <a href="#design-field">Design field</a>
        <a href="#visual-probes">Visual probes</a>
        <a href="#task-desk">Consolidated view</a>
        <a href="#product-boundary">Product boundary</a>
      </nav>

      <section className={styles.field} id="design-field" aria-labelledby="design-field-title">
        <SectionHeading
          label="The field"
          title="Every proposal, on the same terms"
          description="Round-one mean scores are diagnostic. The final model ranks and bridge-truth constraints decide what advances."
          id="design-field-title"
        />
        <div className={styles.conceptGrid}>
          {CONCEPTS.map((concept) => (
            <article className={styles.concept} data-tone={concept.tone} key={concept.index}>
              <header className={styles.conceptHeader}>
                <span className={styles.conceptIndex}>{concept.index}</span>
                <span className={styles.verdict}>{concept.status}</span>
              </header>
              <ConceptDiagram layout={concept.layout} />
              <div className={styles.conceptIdentity}>
                <h3>{concept.name}</h3>
                <span>{concept.shortName}</span>
              </div>
              <p className={styles.thesis}>{concept.thesis}</p>
              <dl className={styles.conceptMetrics}>
                <div>
                  <dt>Round 1 mean</dt>
                  <dd>{concept.score}</dd>
                </div>
                <div>
                  <dt>Final ranks · K G O</dt>
                  <dd>{concept.ranks}</dd>
                </div>
              </dl>
              <div className={styles.conceptNotes}>
                <p><strong>Carry forward</strong>{concept.keep}</p>
                <p><strong>Watch</strong>{concept.risk}</p>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className={styles.probes} id="visual-probes" aria-labelledby="visual-probes-title">
        <SectionHeading
          label="Agent probes"
          title="Three visual arguments"
          description="These are composition studies, not implementation specifications. Each exposes both a useful move and a failure mode."
          id="visual-probes-title"
        />
        <div className={styles.probeLayout}>
          {PROBES.map((probe, index) => (
            <figure className={styles.probe} data-featured={index === 0 || undefined} key={probe.name}>
              <div className={styles.imageFrame}>
                <Image
                  alt={`${probe.name} iPad design probe`}
                  height={1045}
                  priority={index === 0}
                  sizes={index === 0 ? "(max-width: 900px) 100vw, 66vw" : "(max-width: 900px) 100vw, 34vw"}
                  src={probe.image}
                  width={1505}
                />
              </div>
              <figcaption>
                <span>{probe.role}</span>
                <h3>{probe.name}</h3>
                <p>{probe.note}</p>
              </figcaption>
            </figure>
          ))}
        </div>
        <p className={styles.missingProbe}>
          <strong>Cross-Task Chronicle has no image probe by design.</strong> Its only
          surviving contribution is attention-aware task ordering; the shared time
          axis was rejected as the primary iPad surface.
        </p>
      </section>

      <section className={styles.resolution} id="task-desk" aria-labelledby="task-desk-title">
        <div className={styles.resolutionCopy}>
          <span className={styles.kicker}>Consolidated recommendation</span>
          <h2 id="task-desk-title">Talkie Task Desk</h2>
          <p className={styles.resolutionLead}>
            A narrow conversation list and one selected conversation. Talk stays
            attached to that task. Everything else earns temporary space.
          </p>
          <ol className={styles.readingOrder}>
            <li><span>1</span><div><strong>Select a conversation</strong><p>Named task first; Mac and project stay secondary.</p></div></li>
            <li><span>2</span><div><strong>Read the latest truth</strong><p>Request, current activity, and latest useful result share one flow.</p></div></li>
            <li><span>3</span><div><strong>Speak the next move</strong><p>The Talk control names its exact destination before capture.</p></div></li>
          </ol>
          <div className={styles.donorStrip} aria-label="Contribution from each proposal">
            <span><b>Desk</b> structure</span>
            <span><b>Folio</b> reading</span>
            <span><b>Tape</b> attention</span>
            <span><b>Chronicle</b> ordering</span>
          </div>
        </div>
        <TaskDeskSchematic />
      </section>

      <section className={styles.boundary} id="product-boundary" aria-labelledby="product-boundary-title">
        <SectionHeading
          label="Product boundary"
          title="Remote conversation, not remote development"
          description="The iPad should help a near-technical user understand and continue Codex work without exposing the machinery of an IDE."
          id="product-boundary-title"
        />
        <div className={styles.boundaryGrid}>
          <BoundaryColumn
            label="Always present"
            items={["Conversation list", "Latest request", "Current activity", "Latest result", "Talk destination"]}
            tone="keep"
          />
          <BoundaryColumn
            label="On demand"
            items={["History", "Evidence", "Branch and file context", "Connection recovery", "Readout controls"]}
            tone="temporary"
          />
          <BoundaryColumn
            label="Do not recreate"
            items={["File tree", "Editor", "Terminal", "Diff, logs, and telemetry", "Timeline", "Tabs or permanent inspector"]}
            tone="exclude"
          />
        </div>
        <div className={styles.truthBar}>
          <strong>Bridge-truth correction</strong>
          <p>
            Needs you is a pinned, read-only alert only for a turn this iPad dispatched.
            Talkie cannot stop that turn; show “Answer in Codex Desktop on &lt;Mac&gt;.”
            Do not draw Stop, Approve, Deny, or answer-by-voice controls. Unknown task
            state gets no chip—not a false Idle. “Last successful contact” is request
            bookkeeping, not a live heartbeat, and task selection stays locked throughout capture.
            Changed files and checkpoints in the visual probes are illustrative, not live bridge data.
          </p>
        </div>
      </section>
    </div>
  );
}

function SectionHeading({
  label,
  title,
  description,
  id,
}: {
  label: string;
  title: string;
  description: string;
  id: string;
}) {
  return (
    <header className={styles.sectionHeading}>
      <span className={styles.kicker}>{label}</span>
      <div>
        <h2 id={id}>{title}</h2>
        <p>{description}</p>
      </div>
    </header>
  );
}

function ConceptDiagram({ layout }: { layout: Concept["layout"] }) {
  return (
    <div className={styles.conceptDiagram} data-layout={layout} aria-hidden>
      {layout === "desk" ? (
        <><i /><b /><em /></>
      ) : null}
      {layout === "folio" ? (
        <><i /><span /><b /></>
      ) : null}
      {layout === "tape" ? (
        <><i /><i /><i /><b /><em /></>
      ) : null}
      {layout === "chronicle" ? (
        <><span /><span /><span /><span /><b /><em /></>
      ) : null}
    </div>
  );
}

function TaskDeskSchematic() {
  return (
    <div className={styles.schematicWrap}>
      <div className={styles.deviceLabel}><span>iPad · landscape</span><i /></div>
      <div className={styles.taskDesk} role="img" aria-label="Talkie Task Desk with a task list, selected conversation, and fixed Talk shelf">
        <aside className={styles.taskRail}>
          <header><span>Talkie</span><b>Mac connected</b></header>
          <div className={styles.taskSelected}>
            <i />
            <div><strong>Connection manager</strong><span>Talkie · 4m</span></div>
          </div>
          <div className={styles.taskNeeds}>
            <i />
            <div><strong>Ship the iOS deck</strong><span>Needs you</span></div>
          </div>
          <div>
            <i />
            <div><strong>Review bridge tests</strong><span>TalkieServer · 18m</span></div>
          </div>
        </aside>
        <section className={styles.conversationPane}>
          <header>
            <div><span>Selected conversation</span><strong>Connection manager</strong></div>
            <span className={styles.detailsControl}>Review details</span>
          </header>
          <div className={styles.exchange}>
            <div className={styles.requestBlock}>
              <span>You</span>
              <p>Make connection recovery clearer on iPad.</p>
            </div>
            <div className={styles.activityLine}>
              <i /><span>Codex is checking the bridge settings flow</span>
            </div>
            <div className={styles.resultBlock}>
              <span>Latest result</span>
              <p>The connection center now leads with the Mac that needs attention and keeps refresh and edit actions beside that connection.</p>
              <div><span>Hear</span><span>Copy</span></div>
            </div>
          </div>
          <div className={styles.talkShelf}>
            <div><span>Voice destination</span><strong>Connection manager</strong></div>
            <span className={styles.talkControl}><i />Hold to continue</span>
          </div>
        </section>
      </div>
      <p>Details open temporarily over the conversation; they never reserve a third pane.</p>
    </div>
  );
}

function BoundaryColumn({
  label,
  items,
  tone,
}: {
  label: string;
  items: string[];
  tone: "keep" | "temporary" | "exclude";
}) {
  return (
    <div className={styles.boundaryColumn} data-tone={tone}>
      <h3>{label}</h3>
      <ul>
        {items.map((item) => <li key={item}>{item}</li>)}
      </ul>
    </div>
  );
}
