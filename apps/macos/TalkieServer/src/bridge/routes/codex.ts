/**
 * codex.ts - Exact-task Codex Desktop routing for the Command Deck.
 *
 * The phone selects a numbered lane; each lane is bound to one exact Codex
 * Desktop task. These routes are the Mac-side executor for that binding.
 *
 * All Codex access goes through the vendored `codex-desktop-bridge.cjs`
 * adapter. It prefers Codex Desktop's user-private follower IPC for tasks that
 * a Desktop client already owns, then uses Codex's supported app-server API to
 * resume the same exact thread when no Desktop window owns it. It never falls
 * back to global keystrokes or a frontmost-window guess.
 */

import path from "node:path";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { log } from "../../log";
import { CODEX_TURN_JOBS_FILE } from "../../paths";
import { talkieServerFetch } from "../talkie-local-client";
import { badRequest } from "./responses";

/** Where the vendored Codex Desktop adapter lives (sibling of this routes dir). */
const BRIDGE_SCRIPT = path.join(import.meta.dir, "..", "codex-desktop-bridge.cjs");

/** `list`/`validate` are snapshot reads; `submit` waits for a full Codex turn. */
const SNAPSHOT_TIMEOUT_MS = 20_000;
const TURN_TIMEOUT_MS = 31 * 60_000;
// A queue command may wait for one full turn and then run another.
const QUEUED_TURN_TIMEOUT_MS = 61 * 60_000;
const TALKIESERVER_PORT = 8766;
const TALKIESERVER_BASE_URL = `http://127.0.0.1:${TALKIESERVER_PORT}`;
const AGENT_REPORT_PATH = "/notifications/agent-report";
const AGENT_REPORT_URL = new URL(AGENT_REPORT_PATH, TALKIESERVER_BASE_URL).toString();

export interface CodexTaskSummary {
  id: string;
  title: string;
  preview: string;
  cwd: string;
  project: string;
  gitBranch?: string | null;
  gitOriginURL?: string | null;
  /** Seconds since epoch, matching the adapter's rollout timestamps. */
  updatedAt: number;
}

export type CodexMessageMode = "auto" | "queue" | "steer";
export type CodexTurnDelivery = "started-turn" | "queued-turn" | "steered-active-turn";
type CodexBridgeCommand = "submit" | "queue" | "steer";

function isCodexTurnDelivery(value: unknown): value is CodexTurnDelivery {
  return value === "started-turn" || value === "queued-turn" || value === "steered-active-turn";
}

export interface BridgeEnvelope {
  ok: boolean;
  phase?: "accepted";
  tasks?: CodexTaskSummary[];
  task?: { id: string; title?: string; cwd?: string };
  turnId?: string;
  response?: string;
  delivery?: string;
  requestedDelivery?: string;
  decision?: {
    snapshotRuntimeStatus?: string;
    rolloutActiveTurnId?: string | null;
  };
  active?: boolean;
  updates?: CodexProgressUpdate[];
  error?: string;
  code?: string;
}

export interface CodexProgressUpdate {
  id: string;
  kind: "commentary" | "tool";
  text: string;
  timestamp?: string | null;
}

/**
 * Bridge failure codes that mean "the Mac side is not currently able to own
 * this task" rather than "the caller sent something invalid". These become 503
 * so the deck can distinguish a recoverable environment problem (open Codex
 * Desktop, open the task) from a bad request.
 */
const UNAVAILABLE_CODES = new Set([
  "catalog-unavailable",
  "desktop-unavailable",
  "desktop-timeout",
  "task-owner-unavailable",
  "app-server-unavailable",
  "bridge-missing",
]);

/**
 * Recovery guidance keyed by adapter failure code. The hint travels with the
 * actual task operation error rather than being invented on the phone.
 */
const RECOVERY_HINTS: Record<string, string> = {
  "catalog-unavailable": "Open Codex Desktop at least once so its task catalog exists.",
  "desktop-unavailable": "Codex Desktop is not running. Launch it, then retry.",
  "desktop-timeout": "Codex Desktop did not respond. Bring it to the foreground, then retry.",
  "task-owner-unavailable": "Open this task in Codex Desktop, then retry.",
  "app-server-unavailable": "Install or update Codex on this Mac, then retry.",
  "app-server-request-failed": "Open this task in Codex Desktop and retry from the deck.",
  "approval-required": "Open this task in Codex Desktop to review the approval request.",
  "stale-thread": "This lane no longer points to a Codex task. Re-map it.",
  "submission-conflict": "Create a new Talkie submission before sending different text.",
  "invalid-submission-id": "Update Talkie and retry this instruction.",
  "turn-not-active": "The active turn ended before Talkie could steer it. Retry as a new turn.",
  "task-mismatch": "Codex Desktop returned a different task. Re-map this lane.",
  "protocol-mismatch": "Codex Desktop's task protocol changed. Update Talkie.",
  "turn-timeout": "Codex did not finish in time. Check the task in Codex Desktop.",
  "empty-response": "Codex finished without a final message.",
  "turn-queue-failed": "Open this task in Codex Desktop and retry the queued message.",
  "unsafe-socket": "Codex Desktop's IPC socket failed its security check.",
  "unsafe-global-state": "Codex Desktop's queued-message state failed its security check.",
  "unsafe-rollout-path": "Codex Desktop returned an unsafe transcript path.",
};

function parseSubmissionId(value: unknown): string {
  if (value === undefined || value === null) return crypto.randomUUID();
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new CodexBridgeError("submissionId must be a UUID.", "invalid-submission-id");
  }
  return value.toLowerCase();
}

class CodexBridgeError extends Error {
  constructor(message: string, readonly code: string) {
    super(message);
    this.name = "CodexBridgeError";
  }
}

/**
 * Runs the vendored adapter and decodes its single-line JSON envelope.
 * stdout carries the envelope; stderr is only used to explain a hard crash.
 */
async function runBridge(
  args: string[],
  options: {
    stdin?: string;
    timeoutMs: number;
    onEnvelope?: (envelope: BridgeEnvelope) => void;
  },
): Promise<BridgeEnvelope> {
  if (!existsSync(BRIDGE_SCRIPT)) {
    throw new CodexBridgeError(
      "The Codex Desktop bridge script is missing from this Talkie install.",
      "bridge-missing",
    );
  }

  const proc = Bun.spawn([process.execPath, BRIDGE_SCRIPT, ...args], {
    stdin: options.stdin === undefined ? "ignore" : new TextEncoder().encode(options.stdin),
    stdout: "pipe",
    stderr: "pipe",
  });

  const timer = setTimeout(() => proc.kill(), options.timeoutMs);
  let stdout: string;
  let stderr: string;
  try {
    [stdout, stderr] = await Promise.all([
      readBridgeOutput(proc.stdout, options.onEnvelope),
      new Response(proc.stderr).text(),
    ]);
    await proc.exited;
  } finally {
    clearTimeout(timer);
  }

  const line = stdout.trim().split("\n").filter(Boolean).pop();
  if (!line) {
    const detail = stderr.trim();
    throw new CodexBridgeError(
      detail || "The Codex Desktop bridge exited without a response.",
      "bridge-failed",
    );
  }

  try {
    return JSON.parse(line) as BridgeEnvelope;
  } catch {
    throw new CodexBridgeError("The Codex Desktop bridge returned unreadable output.", "bridge-failed");
  }
}

async function readBridgeOutput(
  stream: ReadableStream<Uint8Array>,
  onEnvelope?: (envelope: BridgeEnvelope) => void,
): Promise<string> {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let output = "";
  let pending = "";

  const observe = (line: string) => {
    if (!line.trim() || !onEnvelope) return;
    try {
      onEnvelope(JSON.parse(line) as BridgeEnvelope);
    } catch {
      // The final parser below owns protocol errors. Streaming observation is
      // best-effort and must not replace the adapter's authoritative envelope.
    }
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const text = decoder.decode(value, { stream: true });
    output += text;
    pending += text;
    const lines = pending.split("\n");
    pending = lines.pop() ?? "";
    for (const line of lines) observe(line);
  }
  const finalText = decoder.decode();
  output += finalText;
  pending += finalText;
  observe(pending);
  return output;
}

/** Turns a failed envelope into a typed error carrying the adapter's code. */
function envelopeError(envelope: BridgeEnvelope): CodexBridgeError {
  return new CodexBridgeError(
    envelope.error || "The Codex Desktop bridge failed.",
    envelope.code || "bridge-failed",
  );
}

type CodexCommandRunner = (
  command: CodexBridgeCommand,
  taskId: string,
  text: string,
  submissionId: string,
  onDisposition?: (envelope: BridgeEnvelope) => void,
  knownDelivery?: CodexTurnDelivery,
) => Promise<BridgeEnvelope>;

/**
 * Coordinates Talkie-originated messages per exact task.
 *
 * Talkie-started turns and explicit queue requests are serialized because
 * every adapter process tails one rollout offset. The first explicit queue
 * request still enters the exact task's owner-specific queue path; subsequent
 * requests wait on the per-task turn tail so an idle-to-active race cannot
 * start concurrent hidden turns. Steering remains a separate, ordered lane.
 */
export class CodexTaskMessageCoordinator {
  private readonly activeTurns = new Set<string>();
  private readonly turnTails = new Map<string, Promise<void>>();
  private readonly steerTails = new Map<string, Promise<void>>();

  constructor(private readonly run: CodexCommandRunner) {}

  deliver(
    taskId: string,
    text: string,
    mode: CodexMessageMode,
    submissionId: string,
    onStart?: () => void,
    onDisposition?: (envelope: BridgeEnvelope) => void,
    knownDelivery?: CodexTurnDelivery,
  ): Promise<BridgeEnvelope> {
    if (mode === "queue") {
      return this.queue(taskId, text, submissionId, onStart, onDisposition, knownDelivery);
    }

    if (mode === "steer") {
      // A Talkie-owned turn already has one long-lived observer responsible for
      // its final response. External active turns do not, so submit through the
      // observing path: the adapter will steer if still active or start the next
      // turn if the race has already completed.
      return this.activeTurns.has(taskId)
        ? this.steer(taskId, text, submissionId, onStart, onDisposition, knownDelivery)
        : this.enqueueTurn(
            taskId,
            text,
            "submit",
            submissionId,
            onStart,
            onDisposition,
            knownDelivery,
          );
    }

    if (mode === "auto" && this.activeTurns.has(taskId)) {
      return this.steer(taskId, text, submissionId, onStart, onDisposition, knownDelivery);
    }

    return this.enqueueTurn(
      taskId,
      text,
      "submit",
      submissionId,
      onStart,
      onDisposition,
      knownDelivery,
    );
  }

  private queue(
    taskId: string,
    text: string,
    submissionId: string,
    onStart?: () => void,
    onDisposition?: (envelope: BridgeEnvelope) => void,
    knownDelivery?: CodexTurnDelivery,
  ): Promise<BridgeEnvelope> {
    return this.enqueueTurn(
      taskId,
      text,
      "queue",
      submissionId,
      onStart,
      onDisposition,
      knownDelivery,
    );
  }

  private enqueueTurn(
    taskId: string,
    text: string,
    firstCommand: "submit" | "queue",
    submissionId: string,
    onStart?: () => void,
    onDisposition?: (envelope: BridgeEnvelope) => void,
    knownDelivery?: CodexTurnDelivery,
  ): Promise<BridgeEnvelope> {
    const predecessor = this.turnTails.get(taskId);
    // Once another Talkie turn is ahead of us, ordinary submit is sufficient:
    // the predecessor guarantees Codex is idle before this operation starts.
    const command: "submit" | "queue" = predecessor ? "submit" : firstCommand;
    const ready = predecessor?.catch(() => undefined) ?? Promise.resolve();
    const result = ready.then(async () => {
      onStart?.();
      this.activeTurns.add(taskId);
      try {
        return await this.run(
          command,
          taskId,
          text,
          submissionId,
          onDisposition,
          knownDelivery,
        );
      } finally {
        this.activeTurns.delete(taskId);
      }
    });
    const tail = result.then(() => undefined, () => undefined);
    this.turnTails.set(taskId, tail);
    void tail.then(() => {
      if (this.turnTails.get(taskId) === tail) {
        this.turnTails.delete(taskId);
      }
    });
    return result;
  }

  private steer(
    taskId: string,
    text: string,
    submissionId: string,
    onStart?: () => void,
    onDisposition?: (envelope: BridgeEnvelope) => void,
    knownDelivery?: CodexTurnDelivery,
  ): Promise<BridgeEnvelope> {
    const predecessor = this.steerTails.get(taskId);
    const ready = predecessor?.catch(() => undefined) ?? Promise.resolve();
    const result = ready
      .then(() => {
        onStart?.();
        return this.run("steer", taskId, text, submissionId, onDisposition, knownDelivery);
      })
      .catch((error: unknown) => {
        // The current turn can finish between speech capture and delivery.
        // Preserve the user's message by making it the next turn.
        if (error instanceof CodexBridgeError && error.code === "turn-not-active") {
          return this.enqueueTurn(
            taskId,
            text,
            "submit",
            submissionId,
            undefined,
            onDisposition,
          );
        }
        throw error;
      });
    const tail = result.then(() => undefined, () => undefined);
    this.steerTails.set(taskId, tail);
    void tail.then(() => {
      if (this.steerTails.get(taskId) === tail) {
        this.steerTails.delete(taskId);
      }
    });
    return result;
  }
}

async function runCodexCommand(
  command: CodexBridgeCommand,
  taskId: string,
  text: string,
  submissionId: string,
  onDisposition?: (envelope: BridgeEnvelope) => void,
  knownDelivery?: CodexTurnDelivery,
): Promise<BridgeEnvelope> {
  const envelope = await runBridge(
    [command, taskId, submissionId, ...(knownDelivery ? [knownDelivery] : [])],
    {
      stdin: text,
      timeoutMs: command === "queue" ? QUEUED_TURN_TIMEOUT_MS : TURN_TIMEOUT_MS,
      onEnvelope: (candidate) => {
        if (candidate.ok && candidate.phase === "accepted" && isCodexTurnDelivery(candidate.delivery)) {
          onDisposition?.(candidate);
        }
      },
    },
  );
  if (!envelope.ok) throw envelopeError(envelope);
  return envelope;
}

const messageCoordinator = new CodexTaskMessageCoordinator(runCodexCommand);

export type CodexTurnJobStatus =
  | "queued"
  | "running"
  | "blocked"
  | "completed"
  | "failed"
  | "unknown";

export interface CodexTurnJobSnapshot {
  id: string;
  submissionId: string;
  taskId: string;
  taskTitle: string;
  status: CodexTurnJobStatus;
  mode: CodexMessageMode;
  createdAt: string;
  updatedAt: string;
  turnId?: string;
  delivery?: string;
  response?: string;
  updates?: CodexProgressUpdate[];
  error?: string;
  code?: string;
  hint?: string;
  retryable?: boolean;
}

interface StoredCodexTurnJob {
  job: CodexTurnJobSnapshot;
  text: string;
}

type CodexActivityReader = (taskId: string) => Promise<BridgeEnvelope>;
type CodexCompletionNotifier = (job: CodexTurnJobSnapshot) => Promise<void>;

export class CodexTurnJobManager {
  private readonly jobs = new Map<string, StoredCodexTurnJob>();
  private readonly runningExecutions = new Set<string>();

  constructor(
    private readonly coordinator: CodexTaskMessageCoordinator,
    private readonly readActivity: CodexActivityReader,
    private readonly notifyCompletion: CodexCompletionNotifier,
    private readonly storagePath?: string,
  ) {
    const restoredPendingJobIDs = this.restore();
    if (restoredPendingJobIDs.length > 0) {
      queueMicrotask(() => this.resumePendingJobs(restoredPendingJobIDs));
    }
  }

  start(
    submissionId: string,
    taskId: string,
    taskTitle: string,
    text: string,
    mode: CodexMessageMode,
  ): CodexTurnJobSnapshot {
    const existing = this.jobs.get(submissionId);
    if (existing) {
      if (existing.job.taskId !== taskId || existing.text !== text || existing.job.mode !== mode) {
        throw new CodexBridgeError(
          "This Talkie submission id already belongs to another Codex instruction.",
          "submission-conflict",
        );
      }
      return { ...existing.job };
    }

    this.prune();
    const now = new Date().toISOString();
    const job: CodexTurnJobSnapshot = {
      id: submissionId,
      submissionId,
      taskId,
      taskTitle,
      status: "queued",
      mode,
      createdAt: now,
      updatedAt: now,
    };
    const stored = { job, text };
    this.jobs.set(job.id, stored);
    this.persist();
    log.info(
      `[codex] async job ${job.id} created task=${taskId} mode=${mode} chars=${text.length}`,
    );
    this.launch(stored);
    return { ...job };
  }

  private launch(stored: StoredCodexTurnJob): void {
    const { job, text } = stored;
    if (this.runningExecutions.has(job.id)) return;
    this.runningExecutions.add(job.id);

    const knownDelivery = isCodexTurnDelivery(job.delivery) ? job.delivery : undefined;
    void this.coordinator.deliver(job.taskId, text, job.mode, job.submissionId, () => {
      job.status = "running";
      job.updatedAt = new Date().toISOString();
      this.persist();
      log.info(`[codex] async job ${job.id} running task=${job.taskId} mode=${job.mode}`);
    }, (disposition) => {
      if (!isCodexTurnDelivery(disposition.delivery)) return;
      job.delivery = disposition.delivery;
      job.turnId = disposition.turnId ?? job.turnId;
      job.updatedAt = new Date().toISOString();
      this.persist();
      log.info(
        `[codex] async job ${job.id} accepted task=${job.taskId} delivery=${job.delivery}`,
      );
    }, knownDelivery).then(async (envelope) => {
      if (!isCodexTurnDelivery(envelope.delivery)) {
        throw new CodexBridgeError(
          "Codex Desktop returned an unknown turn delivery.",
          "protocol-mismatch",
        );
      }
      job.status = "completed";
      job.updatedAt = new Date().toISOString();
      job.turnId = envelope.turnId;
      job.delivery = envelope.delivery;
      job.response = envelope.response?.trim() || undefined;
      job.error = undefined;
      job.code = undefined;
      job.hint = undefined;
      job.retryable = undefined;
      this.persist();
      const decisionDetail = envelope.decision
        ? ` decision=${JSON.stringify(envelope.decision)}`
        : "";
      log.info(
        `[codex] async job ${job.id} completed task=${job.taskId} delivery=${job.delivery ?? "unknown"} `
          + `responseChars=${job.response?.length ?? 0}${decisionDetail}`,
      );
      if (job.response) {
        await this.notifyCompletion({ ...job });
      }
    }).catch((error: unknown) => {
      const code = error instanceof CodexBridgeError ? error.code : "bridge-failed";
      job.status = code === "approval-required" ? "blocked" : "failed";
      job.updatedAt = new Date().toISOString();
      job.error = error instanceof Error ? error.message : String(error);
      job.code = code;
      job.hint = RECOVERY_HINTS[code];
      job.retryable = UNAVAILABLE_CODES.has(code);
      this.persist();
      log.warn(`[codex] async job ${job.id} failed: ${job.code}: ${job.error}`);
    }).finally(() => {
      this.runningExecutions.delete(job.id);
    });
  }

  async snapshot(jobId: string): Promise<CodexTurnJobSnapshot | undefined> {
    const stored = this.jobs.get(jobId);
    if (!stored) return undefined;
    const { job } = stored;
    if (job.status !== "running") return { ...job };

    try {
      const activity = await this.readActivity(job.taskId);
      return {
        ...job,
        turnId: job.turnId ?? activity.turnId,
        updates: activity.updates ?? [],
      };
    } catch (error) {
      // Progress is best-effort. The owning delivery process remains the
      // authority for completion and failure.
      log.debug(`[codex] activity snapshot unavailable for ${job.id}: ${error}`);
      return { ...job };
    }
  }

  private prune() {
    const cutoff = Date.now() - 24 * 60 * 60 * 1_000;
    for (const [id, stored] of this.jobs) {
      if (this.isTerminal(stored.job) && Date.parse(stored.job.updatedAt) < cutoff) {
        this.jobs.delete(id);
      }
    }
    while (this.jobs.size >= 100) {
      const oldestTerminal = [...this.jobs.entries()].find(([, stored]) => this.isTerminal(stored.job));
      if (!oldestTerminal) break;
      this.jobs.delete(oldestTerminal[0]);
    }
  }

  private isTerminal(job: CodexTurnJobSnapshot): boolean {
    return job.status === "blocked" || job.status === "completed" || job.status === "failed";
  }

  private resumePendingJobs(jobIDs: string[]): void {
    for (const jobID of jobIDs) {
      const stored = this.jobs.get(jobID);
      if (!stored) continue;
      if (stored.job.status !== "queued" && stored.job.status !== "running") continue;
      stored.job.status = "queued";
      stored.job.updatedAt = new Date().toISOString();
      log.info(`[codex] resuming durable async job ${stored.job.id}`);
      this.launch(stored);
    }
    this.persist();
  }

  private restore(): string[] {
    if (!this.storagePath || !existsSync(this.storagePath)) return [];
    const pendingJobIDs: string[] = [];
    try {
      const decoded = JSON.parse(readFileSync(this.storagePath, "utf8")) as {
        version?: unknown;
        jobs?: unknown;
      };
      if (decoded.version !== 1 || !Array.isArray(decoded.jobs)) {
        throw new Error("unsupported receipt store");
      }
      for (const candidate of decoded.jobs) {
        const stored = candidate as StoredCodexTurnJob;
        if (
          !stored?.job ||
          typeof stored.job.id !== "string" ||
          typeof stored.job.submissionId !== "string" ||
          typeof stored.job.taskId !== "string" ||
          typeof stored.text !== "string"
        ) continue;
        this.jobs.set(stored.job.id, stored);
        if (stored.job.status === "queued" || stored.job.status === "running") {
          pendingJobIDs.push(stored.job.id);
        }
      }
    } catch (error) {
      log.warn(`[codex] durable receipt store is unreadable: ${error}`);
    }
    return pendingJobIDs;
  }

  private persist(): void {
    if (!this.storagePath) return;
    const directory = path.dirname(this.storagePath);
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    chmodSync(directory, 0o700);
    const temporaryPath = `${this.storagePath}.${process.pid}.${crypto.randomUUID()}.tmp`;
    try {
      const payload = JSON.stringify({ version: 1, jobs: [...this.jobs.values()] });
      writeFileSync(temporaryPath, payload, { encoding: "utf8", mode: 0o600 });
      renameSync(temporaryPath, this.storagePath);
      chmodSync(this.storagePath, 0o600);
    } catch (error) {
      try {
        unlinkSync(temporaryPath);
      } catch {
        // The temp path may already have been atomically renamed.
      }
      log.warn(`[codex] could not persist async turn receipts: ${error}`);
    }
  }
}

async function readCodexActivity(taskId: string): Promise<BridgeEnvelope> {
  const envelope = await runBridge(["activity", taskId], { timeoutMs: SNAPSHOT_TIMEOUT_MS });
  if (!envelope.ok) throw envelopeError(envelope);
  return envelope;
}

async function notifyCodexCompletion(job: CodexTurnJobSnapshot): Promise<void> {
  if (!job.response) return;
  const notificationBody = job.response.length > 280
    ? `${job.response.slice(0, 277).trimEnd()}...`
    : job.response;
  const body = JSON.stringify({
    title: `${job.taskTitle} is ready`,
    body: notificationBody,
    detail: job.response,
    sessionId: job.id,
    source: "codex",
  });
  try {
    const response = await talkieServerFetch(AGENT_REPORT_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      signal: AbortSignal.timeout(SNAPSHOT_TIMEOUT_MS),
    });
    if (!response.ok) {
      log.warn(`[codex] iPhone completion notification unavailable (${response.status})`);
    }
  } catch (error) {
    log.warn(`[codex] iPhone completion notification unavailable: ${error}`);
  }
}

const turnJobs = new CodexTurnJobManager(
  messageCoordinator,
  readCodexActivity,
  notifyCodexCompletion,
  // `bun test` imports this route module to exercise the coordinator and job
  // manager. Never let that import restore or mutate the live device receipts.
  process.env.NODE_ENV === "test" ? undefined : CODEX_TURN_JOBS_FILE,
);

/** Maps a bridge failure onto an HTTP response, preserving code + recovery hint. */
function bridgeFailureResponse(error: unknown): Response {
  const code = error instanceof CodexBridgeError ? error.code : "bridge-failed";
  const message = error instanceof Error ? error.message : String(error);
  const hint = RECOVERY_HINTS[code];

  log.warn(`[codex] ${code}: ${message}`);

  const body = JSON.stringify({ error: message, code, ...(hint && { hint }) });
  const status = code === "submission-conflict"
    ? 409
    : code === "stale-thread"
      ? 410
      : code === "invalid-submission-id"
        ? 400
        : UNAVAILABLE_CODES.has(code)
          ? 503
          : 502;
  return new Response(body, { status, headers: { "Content-Type": "application/json" } });
}

/**
 * GET /codex/tasks — recent Codex Desktop tasks for the lane mapper.
 * Read-only snapshot of the task catalog.
 */
export async function codexTasksRoute(limitParam?: string | null): Promise<Response> {
  const parsed = Number(limitParam);
  const limit = Number.isFinite(parsed) && parsed > 0 ? Math.min(Math.floor(parsed), 100) : 25;

  try {
    const envelope = await runBridge(["list", String(limit)], { timeoutMs: SNAPSHOT_TIMEOUT_MS });
    if (!envelope.ok || !envelope.tasks) throw envelopeError(envelope);

    return Response.json({ tasks: envelope.tasks });
  } catch (error) {
    return bridgeFailureResponse(error);
  }
}

/**
 * POST /codex/validate — compatibility probe for an exact task ID.
 *
 * Current deck clients submit directly. This remains available to older
 * clients and diagnostics without creating any user-visible lane state.
 */
export async function codexValidateRoute(body: unknown): Promise<Response> {
  const taskId = (body as { taskId?: unknown })?.taskId;
  if (typeof taskId !== "string" || !taskId.trim()) {
    return badRequest("taskId is required");
  }

  try {
    const envelope = await runBridge(["validate", taskId.trim()], { timeoutMs: SNAPSHOT_TIMEOUT_MS });
    if (!envelope.ok || !envelope.task) throw envelopeError(envelope);

    // Defense in depth: the adapter already rejects a mismatched task, but this
    // route must never relabel a different task as the requested one.
    if (envelope.task.id !== taskId.trim()) {
      throw new CodexBridgeError("Codex Desktop returned a different task.", "task-mismatch");
    }

    return Response.json({ task: envelope.task });
  } catch (error) {
    return bridgeFailureResponse(error);
  }
}

/**
 * POST /codex/submit — deliver an instruction into one exact Codex task.
 *
 * `auto` preserves the original start-or-steer behavior. `queue` waits for the
 * active turn before starting another; `steer` adds context to the active turn
 * immediately. The actual delivery is returned verbatim so the deck can report
 * what happened instead of hiding it.
 */
export async function codexSubmitRoute(body: unknown): Promise<Response> {
  const payload = body as {
    submissionId?: unknown;
    taskId?: unknown;
    text?: unknown;
    mode?: unknown;
  };
  const taskId = typeof payload?.taskId === "string" ? payload.taskId.trim() : "";
  const text = typeof payload?.text === "string" ? payload.text.trim() : "";
  const mode = payload?.mode ?? "auto";

  if (!taskId) return badRequest("taskId is required");
  if (!text) return badRequest("text is required");
  if (mode !== "auto" && mode !== "queue" && mode !== "steer") {
    return badRequest("mode must be auto, queue, or steer");
  }

  try {
    const submissionId = parseSubmissionId(payload.submissionId);
    const envelope = await messageCoordinator.deliver(taskId, text, mode, submissionId);
    const response = envelope.response?.trim();
    const delivery = envelope.delivery;
    const isCompletedTurn = delivery === "started-turn" || delivery === "queued-turn";
    const isSteer = delivery === "steered-active-turn";
    if ((!isCompletedTurn && !isSteer) || (isCompletedTurn && !response)) {
      throw new CodexBridgeError("Codex Desktop returned an incomplete turn result.", "protocol-mismatch");
    }

    const responseDetail = response ? ` (${response.length} chars)` : "";
    const decisionDetail = envelope.decision
      ? ` decision=${JSON.stringify(envelope.decision)}`
      : "";
    log.info(`[codex] ${delivery} for task ${taskId}${responseDetail}${decisionDetail}`);
    return Response.json({
      taskId,
      ...(envelope.turnId && { turnId: envelope.turnId }),
      ...(response && { response }),
      delivery,
    });
  } catch (error) {
    return bridgeFailureResponse(error);
  }
}

/** POST /codex/turns — hand a turn to the Mac and return immediately. */
export async function codexTurnStartRoute(body: unknown): Promise<Response> {
  const payload = body as {
    submissionId?: unknown;
    taskId?: unknown;
    taskTitle?: unknown;
    text?: unknown;
    mode?: unknown;
  };
  const taskId = typeof payload?.taskId === "string" ? payload.taskId.trim() : "";
  const taskTitle = typeof payload?.taskTitle === "string" ? payload.taskTitle.trim() : "";
  const text = typeof payload?.text === "string" ? payload.text.trim() : "";
  const mode = payload?.mode ?? "auto";

  if (!taskId) return badRequest("taskId is required");
  if (!text) return badRequest("text is required");
  if (mode !== "auto" && mode !== "queue" && mode !== "steer") {
    return badRequest("mode must be auto, queue, or steer");
  }

  try {
    const submissionId = parseSubmissionId(payload.submissionId);
    const job = turnJobs.start(submissionId, taskId, taskTitle || "Codex task", text, mode);
    log.info(`[codex] accepted async job ${job.id} for task ${taskId}`);
    return Response.json({ job }, { status: 202 });
  } catch (error) {
    return bridgeFailureResponse(error);
  }
}

/** GET /codex/turns/:id — current progress or durable result. */
export async function codexTurnStatusRoute(jobId: string): Promise<Response> {
  const id = jobId.trim();
  if (!id) return badRequest("job id is required");
  const job = await turnJobs.snapshot(id);
  if (!job) {
    return Response.json(
      { error: "This Codex turn receipt is no longer available.", code: "turn-job-not-found" },
      { status: 404 },
    );
  }
  return Response.json({ job });
}
