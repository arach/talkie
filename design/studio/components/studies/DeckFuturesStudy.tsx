"use client";

import { useState, type ReactNode } from "react";

import styles from "./DeckFuturesStudy.module.css";

type Source = "all" | "kimi" | "grok" | "opus";
type Effort = "Quick Win" | "Medium" | "Deeper Concept";
type IPadLayout = "bridge" | "mixer" | "recorder" | "ledger" | "patchbay";

const FILTERS: { key: Source; label: string; count: number }[] = [
  { key: "all", label: "All reviews", count: 20 },
  { key: "kimi", label: "Kimi", count: 10 },
  { key: "grok", label: "Grok", count: 5 },
  { key: "opus", label: "Opus", count: 5 },
];

const KIMI_IDEAS: {
  rank: number;
  title: string;
  effort: Effort;
  benefit: string;
  change: string;
}[] = [
  {
    rank: 1,
    title: "Porcelain by default",
    effort: "Quick Win",
    benefit: "The blue/off-white deck appears reliably instead of depending on a setting or falling back to brown Scope.",
    change: "Default new users to Porcelain, soften the brushed texture, keep cobalt for live or selected state, and preserve explicit theme choices.",
  },
  {
    rank: 2,
    title: "One canonical dossier",
    effort: "Medium",
    benefit: "Details and History stop feeling like competing versions of the same task truth.",
    change: "Use one document with Now, Repository, Timeline, Responses, and Files anchors. Details opens Now; History deep-links to Timeline.",
  },
  {
    rank: 3,
    title: "A strict console glance model",
    effort: "Quick Win",
    benefit: "Task, request, current work, and result become readable in one second.",
    change: "Hold the console to four stable bands and collapse older activity into one count that opens the dossier.",
  },
  {
    rank: 4,
    title: "Delivery belongs in the keybed",
    effort: "Medium",
    benefit: "Steer versus Queue is chosen in thumb reach before speaking, with less chance of a wrong send.",
    change: "Replace tiny console controls with passive mode text, add a two-state Deliver key, and echo TALK · STEER or TALK · QUEUE on capture.",
  },
  {
    rank: 5,
    title: "Direct-select the route",
    effort: "Medium",
    benefit: "Phone, Watch, or Silent becomes a one-gesture choice instead of a cyclic guessing game.",
    change: "Give all three detents generous hit wedges, add rotary dragging and haptics, and let the selected destination glyph own the center.",
  },
  {
    rank: 6,
    title: "Split lifecycle from audio activity",
    effort: "Medium",
    benefit: "Ready, Working, microphone input, and playback no longer masquerade as equivalent states.",
    change: "Put durable lifecycle on the outer ring, transient audio in the center, and print the plain status word beneath the dial.",
  },
  {
    rank: 7,
    title: "Swipe the console between lanes",
    effort: "Medium",
    benefit: "Lane switching becomes a large one-handed gesture rather than precision work on tiny numbers.",
    change: "Add horizontal glass swipe with a target preview and haptics, retain tappable lane marks, and lock switching during capture.",
  },
  {
    rank: 8,
    title: "Trace the recording signal",
    effort: "Medium",
    benefit: "Voice still feels alive without washing the whole console in a distracting halo.",
    change: "Use a restrained amplitude-reactive edge plus a cobalt trace from Talk into the console; reveal a clear slide-to-cancel track when needed.",
  },
  {
    rank: 9,
    title: "Contextual, persistent readouts",
    effort: "Deeper Concept",
    benefit: "Every spoken answer stays attached to its task and remains controllable while the user moves around.",
    change: "Add task identity and heard state, open the exact response, and replace isolated Hear buttons with a persistent seekable player.",
  },
  {
    rank: 10,
    title: "An accessibility deck layout",
    effort: "Medium",
    benefit: "Operational state remains usable in motion, bright light, and larger Dynamic Type settings.",
    change: "Promote actionable text out of microtype and switch accessibility sizes to one focused lane plus a two-row primary control bed.",
  },
];

const GROK_IDEAS: {
  rank: number;
  title: string;
  effort: Effort;
  benefit: string;
  firstVersion: string;
}[] = [
  {
    rank: 1,
    title: "Grounded voice recall",
    effort: "Medium",
    benefit: "Questions answer from the user’s real memos and captures rather than generic model knowledge.",
    firstVersion: "Attach the three strongest local excerpts to Ask AI, show removable source chips, and let each citation reopen its item.",
  },
  {
    rank: 2,
    title: "Speak to Scope",
    effort: "Medium",
    benefit: "A spoken thought joins an enduring project context that later agents and workflows can inherit.",
    firstVersion: "Route a capture into one of three recent Scopes, persist the Scope chip, and add Scope filtering in Library.",
  },
  {
    rank: 3,
    title: "Approve-to-act proposals",
    effort: "Deeper Concept",
    benefit: "Voice conversations can finish work while the human remains in charge of every consequential action.",
    firstVersion: "Return typed proposals for a reminder, pinned workflow, or Codex brief, each with an exact target and payload before approval.",
  },
  {
    rank: 4,
    title: "Speak follow-up from notifications",
    effort: "Quick Win",
    benefit: "An asynchronous result can become a conversation without navigating back through the deck.",
    firstVersion: "Place Speak follow-up beside Hear response and reopen the exact originating task directly into push-to-talk.",
  },
  {
    rank: 5,
    title: "Voice patch mode",
    effort: "Medium",
    benefit: "Users can reshape a memo with speech while retaining a reversible transcript history.",
    firstVersion: "Support rename, remove filler, and bullet commands with a before/after patch and explicit Apply or Cancel.",
  },
];

const OPUS_DIRECTIONS: {
  rank: number;
  title: string;
  layout: IPadLayout;
  model: string;
  use: string;
  landscape: string;
  portrait: string;
}[] = [
  {
    rank: 1,
    title: "The Bridge",
    layout: "bridge",
    model: "A three-zone command desk: lane rail, dominant live console, and persistent inspector over a full-width command shelf.",
    use: "Promotes Details, History, and Readouts out of sheets while preserving exact-task selection and press-to-talk.",
    landscape: "All three zones stay visible.",
    portrait: "Lane rail becomes a strip; inspector becomes a resizable lower drawer.",
  },
  {
    rank: 2,
    title: "Six-Bus Mixer",
    layout: "mixer",
    model: "Six equal task channels plus one master strip, borrowing the comparison grammar of a mixing desk without fake faders.",
    use: "Makes every lane’s task, status, mode, and last turn scannable before the user solos one lane and speaks through the master rail.",
    landscape: "Six strips sit side by side.",
    portrait: "A 2×3 bank expands the selected lane across two columns.",
  },
  {
    rank: 3,
    title: "Flight Recorder",
    layout: "recorder",
    model: "Six lane swimlanes plotted against real event time, with activity becoming the primary canvas.",
    use: "Turns commands, system transitions, responses, readouts, and failures into a selectable temporal record with one master capture rail.",
    landscape: "All timelines and the event inspector remain visible.",
    portrait: "The active lane becomes a full timeline above a compact five-lane overview.",
  },
  {
    rank: 4,
    title: "Ops Ledger",
    layout: "ledger",
    model: "A two-page operational folio: live task and command on the left, evidence and history on the right.",
    use: "Keeps current work visible while the user consults History, Readouts, or Dossier without modal interruption.",
    landscape: "Live and evidence pages appear together.",
    portrait: "A single-page Live / History / Dossier pager keeps capture anchored below.",
  },
  {
    rank: 5,
    title: "Patch Bay",
    layout: "patchbay",
    model: "A modular 2×2 operations board for Console, Lane Bank, Status/Dossier, and History/Readouts.",
    use: "Supports pointer-heavy work through focusable panels while keeping lane selection and capture persistent.",
    landscape: "The complete board is visible.",
    portrait: "One focused panel fills the width above a thumbnail rail for the other three.",
  },
];

export function DeckFuturesStudy() {
  const [source, setSource] = useState<Source>("all");

  return (
    <div className={styles.study}>
      <header className={styles.brief}>
        <div>
          <span className={styles.kicker}>Three independent lenses</span>
          <h2>One deck, seen at three distances.</h2>
          <p>
            Kimi tightens the instrument already in hand. Grok carries voice
            beyond capture into context and trusted action. Opus asks what the
            command deck becomes when iPad space is treated as capability—not
            empty room around a phone layout.
          </p>
        </div>
        <div className={styles.sourceLedger} aria-label="Review sources">
          <SourceMetric name="Kimi" count="10" label="deck improvements" />
          <SourceMetric name="Grok" count="5" label="iOS ideas" />
          <SourceMetric name="Opus" count="5" label="iPad directions" />
        </div>
      </header>

      <nav className={styles.filters} aria-label="Filter reviews">
        <div role="tablist" aria-label="Review source">
          {FILTERS.map((filter) => (
            <button
              key={filter.key}
              type="button"
              role="tab"
              aria-selected={source === filter.key}
              className={source === filter.key ? styles.filterActive : undefined}
              onClick={() => setSource(filter.key)}
            >
              <span>{filter.label}</span>
              <strong>{filter.count}</strong>
            </button>
          ))}
        </div>
        <p aria-live="polite">
          {source === "all" ? "Showing the complete board." : `Showing ${FILTERS.find((item) => item.key === source)?.label}.`}
        </p>
      </nav>

      {(source === "all" || source === "kimi") && <KimiSection />}
      {(source === "all" || source === "grok") && <GrokSection />}
      {(source === "all" || source === "opus") && <OpusSection />}

      <footer className={styles.readout}>
        <div>
          <span className={styles.kicker}>Recommended first sequence</span>
          <strong>Porcelain → glance model → delivery → lane swipe → dossier</strong>
        </div>
        <p>
          For iPad, prototype <strong>The Bridge</strong> first. Pair it with
          <strong> Flight Recorder</strong> as the strongest opposing thesis:
          persistent task instrumentation versus time-based cross-lane awareness.
        </p>
      </footer>
    </div>
  );
}

function KimiSection() {
  return (
    <ReviewSection
      source="Kimi"
      title="Tighten the instrument"
      summary="Ten ranked changes to make the existing iPhone deck faster to parse, easier to reach, and more internally consistent."
      meta="Current working tree · source and Studio studies reviewed"
    >
      <div className={styles.sequence} aria-label="Kimi recommended sequence">
        {[1, 3, 4, 7, 2].map((rank, index) => {
          const idea = KIMI_IDEAS.find((item) => item.rank === rank);
          return (
            <div key={rank}>
              <span>{index + 1}</span>
              <strong>{idea?.title}</strong>
            </div>
          );
        })}
      </div>
      <ol className={styles.ideaGrid}>
        {KIMI_IDEAS.map((idea) => (
          <li key={idea.rank} className={styles.ideaCard}>
            <div className={styles.ideaHeader}>
              <span className={styles.rank}>{String(idea.rank).padStart(2, "0")}</span>
              <EffortBadge effort={idea.effort} />
            </div>
            <h3>{idea.title}</h3>
            <p>{idea.benefit}</p>
            <div className={styles.change}>
              <span>UI move</span>
              <p>{idea.change}</p>
            </div>
          </li>
        ))}
      </ol>
    </ReviewSection>
  );
}

function GrokSection() {
  return (
    <ReviewSection
      source="Grok"
      title="Carry voice into context and action"
      summary="Five product moves beyond deck chrome, built around grounded recall, durable context, and explicit human approval."
      meta="Existing feed, Ask AI, Scope, notification, workflow, and transcript seams reviewed"
    >
      <ol className={styles.trajectory}>
        {GROK_IDEAS.map((idea) => (
          <li key={idea.rank}>
            <div className={styles.trajectoryRail} aria-hidden>
              <span>{String(idea.rank).padStart(2, "0")}</span>
              <i />
            </div>
            <div className={styles.trajectoryBody}>
              <div className={styles.trajectoryTitle}>
                <h3>{idea.title}</h3>
                <EffortBadge effort={idea.effort} />
              </div>
              <p>{idea.benefit}</p>
              <div className={styles.firstVersion}>
                <span>First version</span>
                <p>{idea.firstVersion}</p>
              </div>
            </div>
          </li>
        ))}
      </ol>
    </ReviewSection>
  );
}

function OpusSection() {
  return (
    <ReviewSection
      source="Opus"
      title="Let iPad change the composition"
      summary="Five spatial models that reorganize lanes, console, status, history, readouts, and capture instead of stretching the phone stack."
      meta="Landscape 1366×1024 · portrait 1024×1366 · Porcelain first"
    >
      <div className={styles.directionList}>
        {OPUS_DIRECTIONS.map((direction) => (
          <article className={styles.direction} key={direction.rank}>
            <div className={styles.directionCopy}>
              <div className={styles.directionIndex}>
                <span>{String(direction.rank).padStart(2, "0")}</span>
                {direction.rank === 1 && <strong>Prototype first</strong>}
                {direction.rank === 3 && <strong>Contrast study</strong>}
              </div>
              <h3>{direction.title}</h3>
              <p className={styles.model}>{direction.model}</p>
              <p>{direction.use}</p>
              <dl>
                <div>
                  <dt>Landscape</dt>
                  <dd>{direction.landscape}</dd>
                </div>
                <div>
                  <dt>Portrait</dt>
                  <dd>{direction.portrait}</dd>
                </div>
              </dl>
            </div>
            <IPadDiagram layout={direction.layout} title={direction.title} />
          </article>
        ))}
      </div>
    </ReviewSection>
  );
}

function ReviewSection({
  source,
  title,
  summary,
  meta,
  children,
}: {
  source: string;
  title: string;
  summary: string;
  meta: string;
  children: ReactNode;
}) {
  return (
    <section className={styles.reviewSection}>
      <header className={styles.sectionHeader}>
        <div>
          <span className={styles.source}>{source}</span>
          <h2>{title}</h2>
          <p>{summary}</p>
        </div>
        <span className={styles.meta}>{meta}</span>
      </header>
      {children}
    </section>
  );
}

function SourceMetric({ name, count, label }: { name: string; count: string; label: string }) {
  return (
    <div>
      <span>{name}</span>
      <strong>{count}</strong>
      <small>{label}</small>
    </div>
  );
}

function EffortBadge({ effort }: { effort: Effort }) {
  return (
    <span className={styles.effort} data-effort={effort}>
      {effort}
    </span>
  );
}

function IPadDiagram({ layout, title }: { layout: IPadLayout; title: string }) {
  return (
    <div className={styles.diagramWrap}>
      <div className={styles.deviceTop}>
        <span>Landscape map</span>
        <i aria-hidden />
      </div>
      <div className={styles.ipadFrame} data-layout={layout} role="img" aria-label={`${title} landscape layout diagram`}>
        {layout === "bridge" && (
          <>
            <DiagramBlock className={styles.lanes} label="Lanes" />
            <DiagramBlock className={styles.console} label="Live console" dark />
            <DiagramBlock className={styles.inspector} label="Details · History · Readouts" />
            <DiagramBlock className={styles.shelf} label="Route · Status · Command shelf" accent />
          </>
        )}
        {layout === "mixer" && (
          <>
            <DiagramBlock className={styles.mixerConsole} label="Selected console" dark />
            <div className={styles.channelBank}>
              {[1, 2, 3, 4, 5, 6].map((lane) => (
                <DiagramBlock key={lane} label={`0${lane}`} accent={lane === 3} />
              ))}
            </div>
            <DiagramBlock className={styles.master} label="Master" />
            <DiagramBlock className={styles.captureRail} label="Press + hold capture" accent />
          </>
        )}
        {layout === "recorder" && (
          <>
            <div className={styles.timelineBank}>
              {[1, 2, 3, 4, 5, 6].map((lane) => (
                <div key={lane} className={styles.timeline}>
                  <span>0{lane}</span>
                  <i />
                  <b style={{ left: `${20 + lane * 7}%` }} />
                  {lane === 3 && <em />}
                </div>
              ))}
            </div>
            <DiagramBlock className={styles.eventInspector} label="Event inspector" />
            <DiagramBlock className={styles.timelineRail} label="12 min · output · status · capture" dark />
          </>
        )}
        {layout === "ledger" && (
          <>
            <DiagramBlock className={styles.leftPage} label="Live task · command" dark />
            <span className={styles.spine} aria-hidden />
            <DiagramBlock className={styles.rightPage} label="History · readouts · dossier" />
            <DiagramBlock className={styles.ledgerShelf} label="Command shelf" accent />
          </>
        )}
        {layout === "patchbay" && (
          <>
            <DiagramBlock className={styles.panelConsole} label="Console" dark />
            <DiagramBlock className={styles.panelLanes} label="Lane bank" />
            <DiagramBlock className={styles.panelStatus} label="Status · dossier" />
            <DiagramBlock className={styles.panelHistory} label="History · readouts" accent />
            <DiagramBlock className={styles.patchDock} label="Persistent command dock" dark />
          </>
        )}
      </div>
    </div>
  );
}

function DiagramBlock({
  label,
  className,
  dark = false,
  accent = false,
}: {
  label: string;
  className?: string;
  dark?: boolean;
  accent?: boolean;
}) {
  return (
    <div
      className={`${styles.diagramBlock} ${className ?? ""}`}
      data-dark={dark || undefined}
      data-accent={accent || undefined}
    >
      <span>{label}</span>
    </div>
  );
}
