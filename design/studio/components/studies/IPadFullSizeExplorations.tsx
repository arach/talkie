/**
 * THESIS: Show Talkie as a conversation instrument at real iPad scale; refuse the IDE dashboard.
 * OWN-WORLD: Command Desk uses graphite, blue signal, and tightly machined controls. Operational Folio uses mineral paper, green ink, and generous editorial rhythm.
 * STORY: Select one Codex conversation, understand its latest result, and speak the next turn with the destination always explicit.
 * FIRST VIEWPORT: Two landscape iPad screens appear as complete products, not thumbnails or comparison cards. Each carries the same authored connection-recovery task.
 * FORM: Two precisely requested at-bats—fixed desk and horizontal folio. No concept seed; the user explicitly asked to see the shortlisted structures executed.
 */

import styles from "./IPadFullSizeExplorations.module.css";

type GlyphName =
  | "arrow"
  | "check"
  | "chevron"
  | "copy"
  | "details"
  | "mic"
  | "more"
  | "plus"
  | "speaker"
  | "wave";

export function IPadFullSizeExplorations() {
  return (
    <div className={styles.explorations} id="at-bats">
      <header className={styles.intro}>
        <div>
          <p className={styles.introLabel}>Full-size iPad explorations</p>
          <h2>Two actual at-bats.</h2>
        </div>
        <div className={styles.introCopy}>
          <p>
            Same task. Same bridge truth. Two materially different ways to make
            Talkie useful when Codex is working somewhere else.
          </p>
          <nav aria-label="Jump to a design proposal">
            <a href="#command-desk">Command Desk</a>
            <a href="#operational-folio">Operational Folio</a>
          </nav>
        </div>
      </header>

      <DesignAtBat
        id="command-desk"
        name="Command Desk"
        number="A"
        summary="Fastest to scan. A permanent conversation rail, one focused result, and a voice shelf that never loses its target."
        traits={["Dark-room instrument", "Stable selection", "Conversation first"]}
      >
        <CommandDesk />
      </DesignAtBat>

      <DesignAtBat
        id="operational-folio"
        name="Operational Folio"
        number="B"
        summary="Calmer to read. Conversations move into a horizontal work shelf so the selected task can become a generous two-page briefing."
        traits={["Daylight reading", "Horizontal selection", "Result first"]}
      >
        <OperationalFolio />
      </DesignAtBat>

      <footer className={styles.sharedTruth}>
        <strong>Shared product truth</strong>
        <p>
          These screens use illustrative task data. Neither proposal exposes a file
          tree, editor, terminal, timeline, or permanent inspector. “Needs you” is
          read-only and only appears for a turn dispatched from this iPad; its recovery
          remains “Answer in Codex Desktop on Studio Mac.”
        </p>
      </footer>
    </div>
  );
}

function DesignAtBat({
  children,
  id,
  name,
  number,
  summary,
  traits,
}: {
  children: React.ReactNode;
  id: string;
  name: string;
  number: string;
  summary: string;
  traits: string[];
}) {
  return (
    <section className={styles.atBat} id={id} aria-labelledby={`${id}-title`}>
      <header className={styles.atBatHeader}>
        <span className={styles.atBatNumber}>{number}</span>
        <div className={styles.atBatTitle}>
          <h3 id={`${id}-title`}>{name}</h3>
          <p>{summary}</p>
        </div>
        <ul aria-label={`${name} qualities`}>
          {traits.map((trait) => <li key={trait}>{trait}</li>)}
        </ul>
      </header>
      <div className={styles.artboardScroller}>
        {children}
      </div>
      <p className={styles.mockNote}>Illustrative task state · UI proposal only</p>
    </section>
  );
}

function CommandDesk() {
  return (
    <div className={`${styles.ipad} ${styles.commandDevice}`}>
      <div className={styles.camera} aria-hidden />
      <div className={styles.commandScreen}>
        <header className={styles.commandTopbar}>
          <div className={styles.commandBrand}>
            <span className={styles.waveMark}><Glyph name="wave" /></span>
            <strong>Talkie</strong>
          </div>
          <div className={styles.commandConnection}>
            <i aria-hidden />
            <div>
              <strong>Studio Mac</strong>
              <span>Last successful contact 11:42</span>
            </div>
          </div>
          <button className={styles.iconButtonDark} type="button" aria-label="More connection options">
            <Glyph name="more" />
          </button>
        </header>

        <div className={styles.commandBody}>
          <aside className={styles.commandRail}>
            <div className={styles.railHeading}>
              <div>
                <span>Conversations</span>
                <strong>4 active</strong>
              </div>
              <button type="button" aria-label="Start a new conversation"><Glyph name="plus" /></button>
            </div>

            <div className={styles.taskList}>
              <button className={styles.taskActive} type="button">
                <span className={styles.taskState} data-state="ready"><i />Result ready</span>
                <strong>Repair Studio Mac connection</strong>
                <span className={styles.taskMeta}>Talkie · sent from this iPad</span>
                <span className={styles.taskTime}>2m</span>
              </button>
              <button type="button">
                <span className={styles.taskState} data-state="working"><i />Working</span>
                <strong>Prepare the launch notes</strong>
                <span className={styles.taskMeta}>usetalkie.com</span>
                <span className={styles.taskTime}>7m</span>
              </button>
              <button className={styles.taskNeedsYou} type="button">
                <span className={styles.taskState} data-state="attention"><i />Needs you</span>
                <strong>Review bridge protocol tests</strong>
                <span className={styles.taskMeta}>Sent from this iPad</span>
                <span className={styles.taskTime}>18m</span>
              </button>
              <button type="button">
                <span className={styles.taskState}><i /></span>
                <strong>Audit transcript sync</strong>
                <span className={styles.taskMeta}>Talkie</span>
                <span className={styles.taskTime}>Thu</span>
              </button>
            </div>

            <div className={styles.needsYouNote}>
              <span><i />One task needs you</span>
              <strong>Answer in Codex Desktop on Studio Mac</strong>
              <button type="button">Dismiss</button>
            </div>
          </aside>

          <main className={styles.commandConversation}>
            <header className={styles.conversationHeader}>
              <div>
                <span>Selected conversation</span>
                <h4>Repair Studio Mac connection</h4>
                <p>Talkie · Studio Mac · sent from this iPad at 11:34</p>
              </div>
              <button type="button"><Glyph name="details" />Review details</button>
            </header>

            <div className={styles.conversationScroll}>
              <div className={styles.timeRule}><span>Today · 11:34</span></div>
              <section className={styles.userTurn} aria-label="Your request">
                <span>You</span>
                <p>
                  The Studio Mac stopped connecting after we changed the bridge
                  port. Make recovery obvious on iPad, then build it directly on
                  both devices.
                </p>
              </section>

              <div className={styles.completedActivity}>
                <span className={styles.completionIcon}><Glyph name="check" /></span>
                <div>
                  <strong>Completed on Studio Mac</strong>
                  <span>Connection flow updated and device builds verified · 8m</span>
                </div>
                <time>11:42</time>
              </div>

              <section className={styles.resultTurn} aria-label="Latest Codex result">
                <header>
                  <span>Latest result</span>
                  <time>11:42</time>
                </header>
                <h5>The failing Mac now opens directly into recovery.</h5>
                <p>
                  Talkie keeps the old port visible for comparison, offers the
                  discovered endpoint as the clear update, and leaves Refresh beside
                  the connection that needs attention.
                </p>
                <div className={styles.resultFacts}>
                  <div><span>Changed</span><strong>Connection Center</strong></div>
                  <div><span>Verified</span><strong>iPhone + iPad</strong></div>
                  <div><span>Next</span><strong>Review on device</strong></div>
                </div>
                <footer>
                  <button type="button"><Glyph name="speaker" />Hear result</button>
                  <button type="button"><Glyph name="copy" />Copy</button>
                </footer>
              </section>
            </div>

            <div className={styles.commandVoiceShelf}>
              <div className={styles.voiceDestination}>
                <span>Continue this conversation</span>
                <strong>Repair Studio Mac connection</strong>
              </div>
              <div className={styles.miniWave} aria-hidden>
                <i /><i /><i /><i /><i /><i /><i />
              </div>
              <button className={styles.holdButtonDark} type="button">
                <span><Glyph name="mic" /></span>
                <div><strong>Hold to talk</strong><small>Release to send</small></div>
              </button>
            </div>
          </main>
        </div>
      </div>
    </div>
  );
}

function OperationalFolio() {
  return (
    <div className={`${styles.ipad} ${styles.folioDevice}`}>
      <div className={styles.camera} aria-hidden />
      <div className={styles.folioScreen}>
        <header className={styles.folioTopbar}>
          <div className={styles.folioBrand}>
            <span><Glyph name="wave" /></span>
            <strong>Talkie</strong>
          </div>
          <div className={styles.folioTitle}>
            <span>Work with Codex</span>
            <strong>Saturday, August 1</strong>
          </div>
          <div className={styles.folioConnection}>
            <i aria-hidden />
            <div><strong>Studio Mac</strong><span>Last contact 11:42</span></div>
            <button type="button" aria-label="Open connection settings"><Glyph name="chevron" /></button>
          </div>
        </header>

        <nav className={styles.workShelf} aria-label="Conversations">
          <div className={styles.shelfLead}>
            <span>Conversations</span>
            <strong>Choose where Talk sends next</strong>
          </div>
          <button className={styles.shelfActive} type="button">
            <span>Result ready · 2m</span>
            <strong>Repair Studio Mac connection</strong>
            <small>Talkie</small>
          </button>
          <button type="button">
            <span>Working · 7m</span>
            <strong>Prepare launch notes</strong>
            <small>usetalkie.com</small>
          </button>
          <button className={styles.shelfAttention} type="button">
            <span>Needs you · 18m</span>
            <strong>Review bridge tests</strong>
            <small>Answer on Studio Mac</small>
          </button>
          <button className={styles.shelfMore} type="button" aria-label="Show another conversation">
            <Glyph name="arrow" />
          </button>
        </nav>

        <main className={styles.folioSpread}>
          <section className={styles.briefPage}>
            <div className={styles.pageFurniture}>
              <span>Selected brief</span>
              <span>Sent from this iPad · 11:34</span>
            </div>
            <h4>Repair Studio Mac connection</h4>
            <blockquote>
              “The Studio Mac stopped connecting after we changed the bridge port.
              Make recovery obvious on iPad.”
            </blockquote>
            <div className={styles.briefStatus}>
              <span className={styles.folioCheck}><Glyph name="check" /></span>
              <div>
                <span>Result ready</span>
                <strong>Completed on Studio Mac at 11:42</strong>
              </div>
            </div>
            <dl className={styles.briefFacts}>
              <div><dt>Worked in</dt><dd>Talkie</dd></div>
              <div><dt>Focused on</dt><dd>Connection Center</dd></div>
              <div><dt>Verified for</dt><dd>iPhone and iPad</dd></div>
            </dl>
            <button className={styles.reviewDetailsLight} type="button">
              Review implementation details <Glyph name="arrow" />
            </button>
          </section>

          <section className={styles.resultPage}>
            <header className={styles.resultPageHeader}>
              <span>Latest result</span>
              <div>
                <button type="button"><Glyph name="speaker" />Hear</button>
                <button type="button"><Glyph name="copy" />Copy</button>
              </div>
            </header>
            <div className={styles.resultPageBody}>
              <span className={styles.resultOrdinal}>Result 03</span>
              <h5>Recovery now starts with the Mac that needs attention.</h5>
              <p>
                The connection screen no longer makes you hunt through settings.
                When a saved bridge stops responding, its recovery actions stay
                together and explain what Talkie knows.
              </p>
              <ol>
                <li><span>1</span><div><strong>See the failing connection</strong><p>The last successful contact and saved endpoint stay visible.</p></div></li>
                <li><span>2</span><div><strong>Refresh beside the problem</strong><p>Discovery no longer lives in a separate settings path.</p></div></li>
                <li><span>3</span><div><strong>Update the changed port</strong><p>The discovered endpoint is offered without hiding the previous value.</p></div></li>
              </ol>
            </div>
            <footer className={styles.resultPageFooter}>
              <span><Glyph name="check" />Device builds passed</span>
              <button type="button">Open Connection Center <Glyph name="arrow" /></button>
            </footer>
          </section>
        </main>

        <div className={styles.folioVoiceShelf}>
          <div>
            <span>Voice destination</span>
            <strong>Repair Studio Mac connection</strong>
          </div>
          <p>Selection stays locked while you speak.</p>
          <button type="button">
            <span className={styles.folioMic}><Glyph name="mic" /></span>
            <span><strong>Hold to continue</strong><small>Release to send</small></span>
          </button>
        </div>
      </div>
    </div>
  );
}

function Glyph({ name }: { name: GlyphName }) {
  const path = {
    arrow: <><path d="M5 12h14" /><path d="m14 7 5 5-5 5" /></>,
    check: <path d="m5 12 4 4L19 6" />,
    chevron: <path d="m9 6 6 6-6 6" />,
    copy: <><rect x="8" y="8" width="11" height="11" rx="2" /><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3" /></>,
    details: <><path d="M4 6h16M4 12h16M4 18h10" /><circle cx="18" cy="18" r="2" /></>,
    mic: <><rect x="9" y="3" width="6" height="12" rx="3" /><path d="M5 11a7 7 0 0 0 14 0M12 18v3" /></>,
    more: <><circle cx="5" cy="12" r="1" /><circle cx="12" cy="12" r="1" /><circle cx="19" cy="12" r="1" /></>,
    plus: <path d="M12 5v14M5 12h14" />,
    speaker: <><path d="M11 5 6 9H3v6h3l5 4V5Z" /><path d="M15 9a4 4 0 0 1 0 6M17.5 6.5a8 8 0 0 1 0 11" /></>,
    wave: <path d="M3 13v-2m4 6V7m4 13V4m4 13V7m4 6v-2" />,
  }[name];

  return (
    <svg aria-hidden viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.7">
      {path}
    </svg>
  );
}
