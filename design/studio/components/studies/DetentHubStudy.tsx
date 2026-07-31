"use client";

import { useState, type CSSProperties, type ReactNode } from "react";

import styles from "./DetentHubStudy.module.css";

type OutputMode = "phone" | "watch" | "silent";
type StatusMode = "rdy" | "mic" | "run" | "play" | "err";
type Variant = "needle" | "carriage";

const OUTPUTS: { key: OutputMode; label: string }[] = [
  { key: "phone", label: "Phone" },
  { key: "watch", label: "Watch" },
  { key: "silent", label: "Silent" },
];

const STATUSES: { key: StatusMode; label: string }[] = [
  { key: "rdy", label: "RDY" },
  { key: "mic", label: "MIC" },
  { key: "run", label: "RUN" },
  { key: "play", label: "PLAY" },
  { key: "err", label: "ERR" },
];

const VARIANTS: {
  key: Variant;
  name: string;
  thesis: string;
  selector: string;
  status: string;
}[] = [
  {
    key: "needle",
    name: "A1 · Needle Ports",
    thesis: "A quieter, more exact version of Grok A. The needle makes contact with one enlarged port; the other stops remain visible but recede.",
    selector: "Long needle · three icon ports · selected port carries the brass",
    status: "Single LED capsule · code plus five stepped level bars",
  },
  {
    key: "carriage",
    name: "A2 · Detent Carriage",
    thesis: "The pointer ends in a small carriage that cups the selected output. More of the limited 60pt face is spent on destination, less on knob.",
    selector: "Forked carriage · open detent rail · smaller fixed hub",
    status: "Split LED lens · code held left · motion isolated right",
  },
];

const OUTPUT_ANGLE: Record<OutputMode, number> = {
  phone: 0,
  watch: -90,
  silent: 180,
};

export function DetentHubStudy() {
  const [output, setOutput] = useState<OutputMode>("phone");
  const [status, setStatus] = useState<StatusMode>("mic");

  return (
    <div className={styles.study} data-theme="scope">
      <header className={styles.brief}>
        <p className={styles.lede}>
          Two permutations of <strong>Grok A · Detent Hub</strong>. Both keep
          one round 60pt instrument seated inside the shared keytop, three
          discrete stops, and one moving indicator. The comparison changes
          where visual weight lands—not the interaction model or the Scope
          palette.
        </p>
        <div className={styles.invariants} aria-label="Study invariants">
          <Metric value="60pt" label="instrument" />
          <Metric value="3" label="detents" />
          <Metric value="44pt" label="minimum target" />
          <Metric value="0" label="green states" />
        </div>
      </header>

      <div className={styles.controlPanel}>
        <StateControl
          label="Output"
          value={output}
          options={OUTPUTS}
          onChange={setOutput}
        />
        <StateControl
          label="Status"
          value={status}
          options={STATUSES}
          onChange={setStatus}
        />
        <p className={styles.controlHint}>
          Change a state once; both permutations update together.
        </p>
      </div>

      <section className={styles.variantGrid} aria-label="Detent Hub permutations">
        {VARIANTS.map((variant) => (
          <VariantPanel
            key={variant.key}
            variant={variant}
            output={output}
            status={status}
            onCycleOutput={() => setOutput(nextOutput(output))}
            onCycleStatus={() => setStatus(nextStatus(status))}
          />
        ))}
      </section>

      <section className={styles.trueSizeSection}>
        <div className={styles.sectionHeading}>
          <div>
            <span className={styles.sectionKicker}>First-row fit</span>
            <h2>Judge the instruments at the size that matters.</h2>
          </div>
          <p>
            The enlarged views explain the mechanism. This strip decides
            whether it survives beside ordinary keys.
          </p>
        </div>

        <div className={styles.fitRows}>
          {VARIANTS.map((variant) => (
            <div className={styles.fitRow} key={variant.key}>
              <span className={styles.fitName}>{variant.name}</span>
              <DeckKey index="01" instrument>
                <OutputDial
                  variant={variant.key}
                  output={output}
                  size={60}
                  onCycle={() => setOutput(nextOutput(output))}
                />
              </DeckKey>
              <DeckKey index="02" label="MAPPER" icon={<MapperIcon />} />
              <DeckKey index="03" label="SPACES" icon={<SpacesIcon />} />
              <DeckKey index="04" instrument>
                <StatusDial
                  variant={variant.key}
                  status={status}
                  size={60}
                  onCycle={() => setStatus(nextStatus(status))}
                />
              </DeckKey>
            </div>
          ))}
        </div>
      </section>

      <footer className={styles.readout}>
        <div>
          <span className={styles.sectionKicker}>Read</span>
          <strong>A2 carriage + A1 capsule</strong>
        </div>
        <p>
          The carriage makes the selected destination fastest to parse. The
          simpler capsule keeps status from becoming a second selector. Seat
          both inside the shared keytop; that synthesis is the strongest next
          Swift pass.
        </p>
      </footer>
    </div>
  );
}

function VariantPanel({
  variant,
  output,
  status,
  onCycleOutput,
  onCycleStatus,
}: {
  variant: (typeof VARIANTS)[number];
  output: OutputMode;
  status: StatusMode;
  onCycleOutput: () => void;
  onCycleStatus: () => void;
}) {
  return (
    <article className={styles.variantPanel}>
      <div className={styles.variantHeader}>
        <div>
          <span className={styles.variantName}>{variant.name}</span>
          <h2>{variant.key === "needle" ? "Contact, then light." : "Carry the selection."}</h2>
        </div>
        <span className={styles.variantCode}>GROK A / {variant.key === "needle" ? "01" : "02"}</span>
      </div>

      <p className={styles.variantThesis}>{variant.thesis}</p>

      <div className={styles.instrumentStage}>
        <InstrumentStudy label="01 · response output" note={variant.selector}>
          <OutputDial
            variant={variant.key}
            output={output}
            size={148}
            onCycle={onCycleOutput}
          />
          <StateCaption value={output.toUpperCase()} detail={outputDetail(output)} />
        </InstrumentStudy>

        <div className={styles.pairRule} aria-hidden />

        <InstrumentStudy label="04 · status" note={variant.status}>
          <StatusDial
            variant={variant.key}
            status={status}
            size={148}
            onCycle={onCycleStatus}
          />
          <StateCaption value={status.toUpperCase()} detail={statusDetail(status)} />
        </InstrumentStudy>
      </div>
    </article>
  );
}

function InstrumentStudy({
  label,
  note,
  children,
}: {
  label: string;
  note: string;
  children: ReactNode;
}) {
  return (
    <div className={styles.instrumentStudy}>
      <span className={styles.instrumentLabel}>{label}</span>
      <div className={styles.instrumentBody}>{children}</div>
      <p className={styles.instrumentNote}>{note}</p>
    </div>
  );
}

function OutputDial({
  variant,
  output,
  size,
  onCycle,
}: {
  variant: Variant;
  output: OutputMode;
  size: number;
  onCycle: () => void;
}) {
  const style = {
    "--instrument-size": `${size}px`,
    "--instrument-scale": size / 148,
    "--selector-angle": `${OUTPUT_ANGLE[output]}deg`,
  } as CSSProperties;

  return (
    <button
      type="button"
      className={`${styles.outputDial} ${styles[variant]}`}
      style={style}
      onClick={onCycle}
      aria-label={`${output} response output. Tap to select the next output.`}
    >
      <span className={styles.instrumentIndex}>01</span>
      <span className={styles.detentTrack} aria-hidden />
      {OUTPUTS.map((item) => (
        <span
          key={item.key}
          className={`${styles.detent} ${styles[`detent_${item.key}`]} ${output === item.key ? styles.detentActive : ""}`}
          aria-hidden
        >
          <OutputIcon mode={item.key} />
        </span>
      ))}
      <span className={styles.selectorAssembly} aria-hidden>
        <span className={styles.pointer} />
        {variant === "carriage" ? <span className={styles.carriageShoe} /> : null}
      </span>
      <span className={styles.hub} aria-hidden>
        <span />
      </span>
    </button>
  );
}

function StatusDial({
  variant,
  status,
  size,
  onCycle,
}: {
  variant: Variant;
  status: StatusMode;
  size: number;
  onCycle: () => void;
}) {
  const style = {
    "--instrument-size": `${size}px`,
    "--instrument-scale": size / 148,
  } as CSSProperties;

  return (
    <button
      type="button"
      className={`${styles.statusDial} ${styles[variant]} ${styles[`status_${status}`]}`}
      style={style}
      onClick={onCycle}
      aria-label={`${status} status. Tap to show the next status.`}
    >
      <span className={styles.instrumentIndex}>04</span>
      <span className={styles.statusBezel} aria-hidden>
        <span className={styles.statusCode}>{status.toUpperCase()}</span>
        {variant === "needle" ? (
          <LevelBars status={status} />
        ) : (
          <StatusTrace status={status} />
        )}
      </span>
    </button>
  );
}

function LevelBars({ status }: { status: StatusMode }) {
  const levels: Record<StatusMode, number[]> = {
    rdy: [1, 1, 1, 1, 1],
    mic: [2, 4, 7, 5, 3],
    run: [2, 3, 3, 3, 2],
    play: [3, 6, 4, 7, 3],
    err: [2, 2, 2, 2, 2],
  };

  return (
    <span className={styles.levelBars} aria-hidden>
      {levels[status].map((level, index) => (
        <i
          key={index}
          style={{
            "--bar-height": `${level * 1.7}px`,
            "--bar-level": level,
          } as CSSProperties}
        />
      ))}
    </span>
  );
}

function StatusTrace({ status }: { status: StatusMode }) {
  return (
    <svg className={styles.statusTrace} viewBox="0 0 42 18" aria-hidden>
      <path className={styles.traceBaseline} d="M1 9H41" />
      <path className={styles.traceSignal} d={tracePath(status)} />
    </svg>
  );
}

function StateControl<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T;
  options: { key: T; label: string }[];
  onChange: (value: T) => void;
}) {
  return (
    <fieldset className={styles.stateControl}>
      <legend>{label}</legend>
      <div>
        {options.map((option) => (
          <button
            type="button"
            key={option.key}
            className={value === option.key ? styles.stateActive : ""}
            onClick={() => onChange(option.key)}
            aria-pressed={value === option.key}
          >
            {option.label}
          </button>
        ))}
      </div>
    </fieldset>
  );
}

function Metric({ value, label }: { value: string; label: string }) {
  return (
    <div className={styles.metric}>
      <strong>{value}</strong>
      <span>{label}</span>
    </div>
  );
}

function StateCaption({ value, detail }: { value: string; detail: string }) {
  return (
    <div className={styles.stateCaption}>
      <strong>{value}</strong>
      <span>{detail}</span>
    </div>
  );
}

function DeckKey({
  index,
  label,
  icon,
  instrument = false,
  children,
}: {
  index: string;
  label?: string;
  icon?: ReactNode;
  instrument?: boolean;
  children?: ReactNode;
}) {
  return (
    <div className={`${styles.deckKey} ${instrument ? styles.deckKeyInstrument : ""}`}>
      <span className={styles.deckIndex}>{index}</span>
      {children ?? (
        <>
          <span className={styles.deckIcon}>{icon}</span>
          <span className={styles.deckLabel}>{label}</span>
        </>
      )}
    </div>
  );
}

function OutputIcon({ mode }: { mode: OutputMode }) {
  if (mode === "phone") {
    return (
      <svg viewBox="0 0 20 20">
        <rect x="6.5" y="3" width="7" height="14" rx="1.5" />
        <path d="M9 14.8h2" />
      </svg>
    );
  }
  if (mode === "watch") {
    return (
      <svg viewBox="0 0 20 20">
        <path d="M8 2.5h4l.7 3H7.3l.7-3ZM8 17.5h4l.7-3H7.3l.7 3Z" />
        <rect x="5.7" y="5.4" width="8.6" height="9.2" rx="2" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 20 20">
      <path d="M4 8h3l3-3v10l-3-3H4V8Z" />
      <path d="m13 7 4 6M17 7l-4 6" />
    </svg>
  );
}

function MapperIcon() {
  return (
    <svg viewBox="0 0 24 24">
      <rect x="3.5" y="4" width="7" height="6" rx="1" />
      <rect x="13.5" y="14" width="7" height="6" rx="1" />
      <path d="M10.5 7h3v10h-3" />
    </svg>
  );
}

function SpacesIcon() {
  return (
    <svg viewBox="0 0 24 24">
      <rect x="4" y="4" width="6" height="6" rx="1" />
      <rect x="14" y="4" width="6" height="6" rx="1" />
      <rect x="4" y="14" width="6" height="6" rx="1" />
      <rect x="14" y="14" width="6" height="6" rx="1" />
    </svg>
  );
}

function nextOutput(current: OutputMode): OutputMode {
  const index = OUTPUTS.findIndex((output) => output.key === current);
  return OUTPUTS[(index + 1) % OUTPUTS.length].key;
}

function nextStatus(current: StatusMode): StatusMode {
  const index = STATUSES.findIndex((status) => status.key === current);
  return STATUSES[(index + 1) % STATUSES.length].key;
}

function outputDetail(output: OutputMode): string {
  switch (output) {
    case "phone": return "handset route";
    case "watch": return "wrist route";
    case "silent": return "audio suppressed";
  }
}

function statusDetail(status: StatusMode): string {
  switch (status) {
    case "rdy": return "quiet baseline";
    case "mic": return "capture level";
    case "run": return "agent working";
    case "play": return "speech output";
    case "err": return "failure only";
  }
}

function tracePath(status: StatusMode): string {
  switch (status) {
    case "rdy": return "M1 9H41";
    case "mic": return "M1 10L5 8l4 3 4-7 4 10 4-6 4 4 4-9 4 11 4-6 4 2";
    case "run": return "M1 9h5l2-3 3 6 3-6 3 6 3-6 3 6 3-6 3 6 3-3h5";
    case "play": return "M1 9c6-8 12 8 18 0s12-8 22 0";
    case "err": return "M1 9h13l3-5 5 10 4-5h15";
  }
}
