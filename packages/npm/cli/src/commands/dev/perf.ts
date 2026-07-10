import type { Command } from "../../gunshi-command";
import { readLogEntries, type LogEntry } from "../../log-parser";
import { getFormatOptions, output } from "../../format";

// ── Stats helpers ──────────────────────────────────────────

interface Stats {
  avg: number;
  p50: number;
  p95: number;
  min: number;
  max: number;
  count: number;
}

function computeStats(values: number[]): Stats | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const sum = sorted.reduce((a, b) => a + b, 0);
  return {
    avg: Math.round(sum / sorted.length),
    p50: sorted[Math.floor(sorted.length * 0.5)],
    p95: sorted[Math.floor(sorted.length * 0.95)],
    min: sorted[0],
    max: sorted[sorted.length - 1],
    count: sorted.length,
  };
}

function fmtMs(ms: number): string {
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`;
}

function fmtBytes(bytes: number): string {
  if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)}MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(0)}KB`;
  return `${bytes}B`;
}

function fmtTime(d: Date): string {
  return d.toTimeString().slice(0, 8);
}

function statLine(label: string, stats: Stats): string {
  return `  ${label.padEnd(10)} avg ${fmtMs(stats.avg).padStart(6)}  p50 ${fmtMs(stats.p50).padStart(6)}  p95 ${fmtMs(stats.p95).padStart(6)}`;
}

// ── ANSI helpers ───────────────────────────────────────────

const DIM = "\x1b[90m";      // grey — use sparingly
const SUBTLE = "\x1b[37m";  // white — readable secondary text
const BOLD = "\x1b[1m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";
const RESET = "\x1b[0m";

// ── Parsers ────────────────────────────────────────────────

interface RecordingStart {
  timestamp: Date;
  sampleRate: number;
  channels: number;
  startupMs: number;
}

interface RecordingComplete {
  timestamp: Date;
  buffers: number;
  bytes: number;
  finalizeMs: number;
}

interface SlowHAL {
  timestamp: Date;
  durationMs: number;
  totalMs: number;
  attempts: number;
}

interface TraceEntry {
  timestamp: Date;
  traceId: string;
  source: string;
  totalMs: number;
  steps: Record<string, number>;
}

function parseRecordingStart(entry: LogEntry): RecordingStart | null {
  if (!entry.message.includes("Recording started")) return null;
  const m = entry.detail.match(/(\d+)Hz,\s*(\d+)ch\s+in\s+(\d+)ms/);
  if (!m) return null;
  return {
    timestamp: entry.timestamp,
    sampleRate: parseInt(m[1]),
    channels: parseInt(m[2]),
    startupMs: parseInt(m[3]),
  };
}

function parseRecordingComplete(entry: LogEntry): RecordingComplete | null {
  if (!entry.message.includes("Recording complete")) return null;
  const m = entry.detail.match(/(\d+)\s+buffers,\s+(\d+)\s+bytes\s+in\s+(\d+)ms/);
  if (!m) return null;
  return {
    timestamp: entry.timestamp,
    buffers: parseInt(m[1]),
    bytes: parseInt(m[2]),
    finalizeMs: parseInt(m[3]),
  };
}

function parseSlowHAL(entry: LogEntry): SlowHAL | null {
  if (!entry.message.includes("SLOW HAL INIT")) return null;
  const msgMatch = entry.message.match(/(\d+)ms/);
  const detailMatch = entry.detail.match(/total_hal_time=(\d+)ms\s+across\s+(\d+)/);
  if (!msgMatch) return null;
  return {
    timestamp: entry.timestamp,
    durationMs: parseInt(msgMatch[1]),
    totalMs: detailMatch ? parseInt(detailMatch[1]) : parseInt(msgMatch[1]),
    attempts: detailMatch ? parseInt(detailMatch[2]) : 1,
  };
}

function parseTraceComplete(entry: LogEntry): TraceEntry | null {
  if (!entry.message.includes("Trace complete")) return null;

  let detail = entry.detail;
  let traceId = "unknown";
  let source = "unknown";

  // Extract [traceId]
  const idMatch = detail.match(/^\[([^\]]+)\]\s*/);
  if (idMatch) {
    traceId = idMatch[1];
    detail = detail.slice(idMatch[0].length);
  }

  // Use entry.process as source (e.g. "TalkieAgent", "Engine")
  source = entry.process;

  // Format A: "9822ms total: step=Xms, ..." (Agent traces)
  // Format B: "Engine 399ms: step=Xms, ..." (with source prefix)
  let totalMs = 0;
  const headerA = detail.match(/^(\d+)ms\s+total\s*:\s*/);
  const headerB = detail.match(/^(\w+)\s+(\d+)ms\s*:\s*/);
  if (headerA) {
    totalMs = parseInt(headerA[1]);
    detail = detail.slice(headerA[0].length);
  } else if (headerB) {
    source = headerB[1];
    totalMs = parseInt(headerB[2]);
    detail = detail.slice(headerB[0].length);
  }

  // Parse steps: "step1=Xms, step2=Xms"
  const steps: Record<string, number> = {};
  const stepRe = /(\w+)=(\d+)ms/g;
  let sm: RegExpExecArray | null;
  while ((sm = stepRe.exec(detail)) !== null) {
    steps[sm[1]] = parseInt(sm[2]);
  }

  // If no header totalMs, sum the steps
  if (totalMs === 0) {
    totalMs = Object.values(steps).reduce((a, b) => a + b, 0);
  }

  if (totalMs === 0) return null;

  return { timestamp: entry.timestamp, traceId, source, totalMs, steps };
}

// ── Recording session correlation ──────────────────────────

interface RecordingSession {
  timestamp: Date;
  startupMs: number;
  buffers: number | null;
  bytes: number | null;
  finalizeMs: number | null;
  durationSec: number | null;
  halMs: number | null;
}

function correlateRecordings(starts: RecordingStart[], completes: RecordingComplete[], hals: SlowHAL[]): RecordingSession[] {
  const sessions: RecordingSession[] = [];

  for (const start of starts) {
    // Find the closest complete that follows this start (within 5 minutes)
    const complete = completes.find(
      (c) => c.timestamp >= start.timestamp &&
             c.timestamp.getTime() - start.timestamp.getTime() < 300000
    );

    // Find any slow HAL within 2s before the start
    const hal = hals.find(
      (h) => Math.abs(h.timestamp.getTime() - start.timestamp.getTime()) < 2000
    );

    const durationSec = complete
      ? (complete.timestamp.getTime() - start.timestamp.getTime()) / 1000
      : null;

    sessions.push({
      timestamp: start.timestamp,
      startupMs: start.startupMs,
      buffers: complete?.buffers ?? null,
      bytes: complete?.bytes ?? null,
      finalizeMs: complete?.finalizeMs ?? null,
      durationSec,
      halMs: hal?.durationMs ?? null,
    });
  }

  return sessions;
}

// ── Output modes ───────────────────────────────────────────

function printSummary(since: string, last: number | undefined): void {
  const agentEntries = readLogEntries("TalkieAgent", { since });

  const starts = agentEntries.map(parseRecordingStart).filter(Boolean) as RecordingStart[];
  const completes = agentEntries.map(parseRecordingComplete).filter(Boolean) as RecordingComplete[];
  const hals = agentEntries.map(parseSlowHAL).filter(Boolean) as SlowHAL[];
  const traces = agentEntries.map(parseTraceComplete).filter(Boolean) as TraceEntry[];

  const startupStats = computeStats(starts.map((s) => s.startupMs));
  const traceStats = computeStats(traces.map((t) => t.totalMs));
  const inferStats = computeStats(
    traces.map((t) => t.steps.inference ?? t.steps.infer ?? 0).filter((v) => v > 0)
  );

  const sinceLabel = since === "1d" ? "today" : `last ${since}`;

  console.log(`\n${BOLD}Performance Summary${RESET} ${SUBTLE}(${sinceLabel})${RESET}`);
  console.log("═".repeat(45));

  console.log(`\n${BOLD}Recordings${RESET} ${SUBTLE}(TalkieAgent)${RESET}`);
  if (starts.length === 0) {
    console.log(`  ${DIM}No recordings found${RESET}`);
  } else {
    console.log(`  Sessions: ${starts.length}`);
    if (startupStats) console.log(statLine("Startup:", startupStats));
    const slowHalCount = hals.length;
    if (slowHalCount > 0) {
      console.log(`  ${YELLOW}HAL init: ${slowHalCount} slow (>100ms)${RESET}`);
    } else {
      console.log(`  HAL init: ${DIM}all ok${RESET}`);
    }
  }

  console.log(`\n${BOLD}Transcriptions${RESET} ${SUBTLE}(TalkieAgent)${RESET}`);
  if (traces.length === 0) {
    console.log(`  ${DIM}No traces found${RESET}`);
  } else {
    console.log(`  Traces:    ${traces.length}`);
    if (traceStats) console.log(statLine("Total:", traceStats));
    if (inferStats) console.log(statLine("Inference:", inferStats));
  }

  console.log("");
}

function printDictations(since: string, last: number | undefined): void {
  const entries = readLogEntries("TalkieAgent", { since });
  const starts = entries.map(parseRecordingStart).filter(Boolean) as RecordingStart[];
  const completes = entries.map(parseRecordingComplete).filter(Boolean) as RecordingComplete[];
  const hals = entries.map(parseSlowHAL).filter(Boolean) as SlowHAL[];

  let sessions = correlateRecordings(starts, completes, hals);
  if (last) sessions = sessions.slice(0, last);

  if (sessions.length === 0) {
    console.log(`\n${DIM}No recording sessions found${RESET}\n`);
    return;
  }

  console.log(`\n${BOLD}Recording Sessions${RESET} ${SUBTLE}(TalkieAgent)${RESET}`);
  console.log("");

  // Header
  const hdr = [
    "Time".padEnd(10),
    "Startup".padEnd(9),
    "Duration".padEnd(10),
    "Buffers".padEnd(9),
    "Bytes".padEnd(10),
    "HAL",
  ].join("  ");
  console.log(`  ${SUBTLE}${hdr}${RESET}`);
  console.log(`  ${"─".repeat(hdr.length)}`);

  for (const s of sessions) {
    const time = `${CYAN}${fmtTime(s.timestamp)}${RESET}`;
    const startup = fmtMs(s.startupMs).padEnd(9);
    const dur = s.durationSec !== null ? `${s.durationSec.toFixed(1)}s`.padEnd(10) : `${SUBTLE}—${RESET}`.padEnd(10);
    const bufs = s.buffers !== null ? String(s.buffers).padEnd(9) : `${SUBTLE}—${RESET}`.padEnd(9);
    const bytes = s.bytes !== null ? fmtBytes(s.bytes).padEnd(10) : `${SUBTLE}—${RESET}`.padEnd(10);
    const hal = s.halMs !== null ? `${YELLOW}🐢 ${s.halMs}ms${RESET}` : `${SUBTLE}ok${RESET}`;

    console.log(`  ${time}  ${startup}  ${dur}  ${bufs}  ${bytes}  ${hal}`);
  }

  console.log(`\n  ${sessions.length} session${sessions.length === 1 ? "" : "s"}\n`);
}

function printEngine(since: string, last: number | undefined): void {
  const agentEntries = readLogEntries("TalkieAgent", { since });

  let traces = agentEntries.map(parseTraceComplete).filter(Boolean) as TraceEntry[];
  traces.sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime());

  if (last) traces = traces.slice(0, last);

  if (traces.length === 0) {
    console.log(`\n${DIM}No transcription traces found${RESET}\n`);
    return;
  }

  console.log(`\n${BOLD}Transcription Traces${RESET} ${SUBTLE}(TalkieAgent)${RESET}`);
  console.log("");

  // Discover common step names across all traces for dynamic columns
  const commonSteps = ["inference", "audio_load", "audio_pad", "postprocess"];
  const stepLabels: Record<string, string> = {
    inference: "Infer",
    audio_load: "Load",
    audio_pad: "Pad",
    postprocess: "Post",
    model_check: "Model",
    file_check: "File",
    start: "Start",
    complete: "Done",
  };

  // Filter to steps that actually appear
  const activeSteps = commonSteps.filter((step) =>
    traces.some((t) => (t.steps[step] ?? 0) > 0)
  );

  const hdr = [
    "Time".padEnd(10),
    "Total".padEnd(8),
    ...activeSteps.map((s) => (stepLabels[s] ?? s).padEnd(7)),
    "Source",
  ].join("  ");
  console.log(`  ${SUBTLE}${hdr}${RESET}`);
  console.log(`  ${"─".repeat(hdr.length)}`);

  for (const t of traces) {
    const time = `${CYAN}${fmtTime(t.timestamp)}${RESET}`;
    const total = `${BOLD}${fmtMs(t.totalMs).padEnd(8)}${RESET}`;
    const stepCols = activeSteps.map((s) => {
      const v = t.steps[s];
      return v !== undefined ? fmtMs(v).padEnd(7) : `${SUBTLE}—${RESET}`.padEnd(7);
    });
    const src = `${SUBTLE}${t.source}${RESET}`;

    console.log(`  ${time}  ${total}  ${stepCols.join("  ")}  ${src}`);
  }

  console.log(`\n  ${traces.length} trace${traces.length === 1 ? "" : "s"}\n`);
}

// ── JSON output helpers ────────────────────────────────────

function collectJsonData(area: string | undefined, since: string, last: number | undefined) {
  const agentEntries = readLogEntries("TalkieAgent", { since });

  const starts = agentEntries.map(parseRecordingStart).filter(Boolean) as RecordingStart[];
  const completes = agentEntries.map(parseRecordingComplete).filter(Boolean) as RecordingComplete[];
  const hals = agentEntries.map(parseSlowHAL).filter(Boolean) as SlowHAL[];
  const traces = agentEntries.map(parseTraceComplete).filter(Boolean) as TraceEntry[];

  const sessions = correlateRecordings(starts, completes, hals);

  const data: Record<string, unknown> = {};

  if (!area || area === "dictations") {
    data.recordings = {
      sessions: last ? sessions.slice(0, last) : sessions,
      stats: {
        startup: computeStats(starts.map((s) => s.startupMs)),
        slowHAL: hals.length,
      },
    };
  }

  if (!area || area === "engine") {
    const limitedTraces = last ? traces.slice(0, last) : traces;
    data.transcriptions = {
      traces: limitedTraces,
      stats: {
        total: computeStats(traces.map((t) => t.totalMs)),
        inference: computeStats(
          traces.map((t) => t.steps.inference ?? 0).filter((v) => v > 0)
        ),
      },
    };
  }

  return data;
}

// ── Command registration ───────────────────────────────────

export function registerPerfCommand(devCmd: Command): void {
  devCmd
    .command("perf [area]")
    .description(
      "Performance dashboard from log file analysis.\n\n" +
      "Parses TalkieAgent log files for latency data.\n" +
      "Areas: dictations (recording sessions), engine (transcription traces)\n\n" +
      "Example: talkie-dev perf                  (summary)\n" +
      "         talkie-dev perf dictations        (recording table)\n" +
      "         talkie-dev perf engine            (transcription table)\n" +
      "         talkie-dev perf --since 2d        (last 2 days)\n" +
      "         talkie-dev perf --last 20         (last 20 events)"
    )
    .option("--since <duration>", "time window (e.g. 1h, 2d, 30m)", "1d")
    .option("--last <n>", "last N events", parseInt)
    .action((area: string | undefined, opts, cmd) => {
      const globalOpts = cmd.optsWithGlobals();
      const fmt = getFormatOptions(globalOpts);
      const { since, last } = opts;

      if (fmt.json || !fmt.pretty) {
        const data = collectJsonData(area, since, last);
        output(data, { pretty: false, json: true });
        return;
      }

      switch (area) {
        case "dictations":
        case "recordings":
          printDictations(since, last);
          break;
        case "engine":
        case "transcription":
        case "transcriptions":
          printEngine(since, last);
          break;
        case undefined:
          printSummary(since, last);
          break;
        default:
          console.error(`Unknown area: ${area}`);
          console.error("Available: dictations, engine");
          process.exit(1);
      }
    });
}
