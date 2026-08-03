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
import { hostname } from "node:os";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { log } from "../../log";
import {
  CODEX_APPROVAL_DECISIONS_DIR,
  CODEX_TASK_CREATIONS_FILE,
  CODEX_TURN_JOBS_FILE,
} from "../../paths";
import { talkieServerFetch } from "../talkie-local-client";
import { badRequest } from "./responses";
import {
  inspectCodexRepository,
  renderCodexStatusDocument,
  type CodexStatusHistoryTurn,
} from "./codex-status-document";

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
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
  phase?: "accepted" | "approval-required" | "approval-resolved";
  tasks?: CodexTaskSummary[];
  task?: Partial<CodexTaskSummary> & { id: string };
  nextCursor?: string | null;
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
  history?: CodexStatusHistoryTurn[];
  approval?: CodexApprovalRequest & { decision?: CodexApprovalDecision };
  error?: string;
  code?: string;
}

export type CodexApprovalDecision = "approve" | "decline";

export interface CodexApprovalRequest {
  id: string;
  method: string;
  title: string;
  detail: string;
  requestedAt: string;
}

export interface CodexTaskCreation {
  creationId: string;
  cwd: string;
  task: CodexTaskSummary;
  createdAt: string;
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
  "task-materialization-timeout",
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
  "task-materialization-timeout": "Codex did not finish creating the task. Retry the Watch instruction.",
  "turn-interrupted": "The task and prompt reached Codex, but the turn was interrupted before it answered. Open the task to inspect it, then speak again.",
  "approval-required": "Retry this action to receive the approval request in Talkie.",
  "approval-channel-unavailable": "Retry the turn after updating Talkie on the Mac.",
  "approval-timeout": "Retry the action and answer its approval request from Talkie.",
  "desktop-tool-required": "Open this task in Codex Desktop to run the requested desktop-only tool.",
  "operator-input-required": "Open this task in Codex Desktop to answer the agent's question.",
  "client-request-unsupported": "Update Talkie or open this task in Codex Desktop.",
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
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new CodexBridgeError("submissionId must be a UUID.", "invalid-submission-id");
  }
  return value.toLowerCase();
}

function parseCreationId(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new CodexBridgeError("creationId must be a UUID.", "invalid-creation-id");
  }
  return value.toLowerCase();
}

export function canonicalCodexProjectDirectory(value: unknown): string {
  const requested = typeof value === "string" ? value.trim() : "";
  if (!requested || !path.isAbsolute(requested)) {
    throw new CodexBridgeError(
      "cwd must be an absolute project directory.",
      "invalid-project-directory",
    );
  }
  try {
    const canonical = realpathSync(requested);
    if (!statSync(canonical).isDirectory()) throw new Error("not a directory");
    return canonical;
  } catch {
    throw new CodexBridgeError(
      "cwd must refer to an existing project directory.",
      "invalid-project-directory",
    );
  }
}

export class CodexBridgeError extends Error {
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
    env: {
      ...process.env,
      TALKIE_CODEX_APPROVAL_DIR: CODEX_APPROVAL_DECISIONS_DIR,
    },
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
 * request still enters the exact task's owner-specific queue path. Dispatches
 * wait only for the preceding message to be accepted—not for its turn to
 * complete—so explicit queue messages reach Codex's native queue immediately.
 * Steering remains a separate, ordered lane.
 */
export class CodexTaskMessageCoordinator {
  private readonly activeTurns = new Set<string>();
  private readonly turnTails = new Map<string, Promise<void>>();
  private readonly queueDispatchTails = new Map<string, Promise<void>>();
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
    log.info(
      `[codex] route task=${taskId} mode=${mode} `
        + `talkieActive=${this.activeTurns.has(taskId)} `
        + `waitingTurn=${this.turnTails.has(taskId)} `
        + `waitingQueueDispatch=${this.queueDispatchTails.has(taskId)}`,
    );
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
    const predecessor = this.queueDispatchTails.get(taskId);
    const ready = predecessor?.catch(() => undefined) ?? Promise.resolve();
    let releaseDispatch: (() => void) | undefined;
    const dispatched = new Promise<void>((resolve) => {
      releaseDispatch = resolve;
    });
    const result = ready.then(async () => {
      log.info(
        `[codex] dispatching task=${taskId} command=queue `
          + `waitedForPriorQueue=${Boolean(predecessor)}`,
      );
      onStart?.();
      try {
        return await this.run(
          "queue",
          taskId,
          text,
          submissionId,
          (disposition) => {
            onDisposition?.(disposition);
            releaseDispatch?.();
          },
          knownDelivery,
        );
      } finally {
        // Pre-acceptance errors must not strand later queue requests.
        releaseDispatch?.();
      }
    });
    this.queueDispatchTails.set(taskId, dispatched);
    void dispatched.then(() => {
      if (this.queueDispatchTails.get(taskId) === dispatched) {
        this.queueDispatchTails.delete(taskId);
      }
    });
    return result;
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
    log.info(
      `[codex] dispatch task=${taskId} requested=${firstCommand} command=${command} `
        + `waitingForCompletion=${Boolean(predecessor)}`,
    );
    const ready = predecessor?.catch(() => undefined) ?? Promise.resolve();
    // Reserve the task synchronously. Durable recovery launches every pending
    // receipt in one pass; waiting until the promise callback runs would let
    // later steer requests misclassify themselves as separate idle turns.
    this.activeTurns.add(taskId);
    const result = ready.then(async () => {
      log.info(`[codex] dispatching task=${taskId} command=${command}`);
      onStart?.();
      return await this.run(
        command,
        taskId,
        text,
        submissionId,
        onDisposition,
        knownDelivery,
      );
    });
    const tail = result.then(() => undefined, () => undefined);
    this.turnTails.set(taskId, tail);
    void tail.then(() => {
      if (this.turnTails.get(taskId) === tail) {
        this.turnTails.delete(taskId);
        this.activeTurns.delete(taskId);
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
    let releaseDispatch: (() => void) | undefined;
    const dispatched = new Promise<void>((resolve) => {
      releaseDispatch = resolve;
    });
    const recordDisposition = (disposition: BridgeEnvelope) => {
      onDisposition?.(disposition);
      releaseDispatch?.();
    };
    const result = ready
      .then(() => {
        onStart?.();
        return this.run("steer", taskId, text, submissionId, recordDisposition, knownDelivery);
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
            recordDisposition,
          );
        }
        throw error;
      })
      .finally(() => {
        // Pre-acceptance errors must not strand later steer requests. A
        // successful direct steer or fallback submit releases this lane as
        // soon as Codex acknowledges the message via recordDisposition.
        releaseDispatch?.();
      });
    this.steerTails.set(taskId, dispatched);
    void dispatched.then(() => {
      if (this.steerTails.get(taskId) === dispatched) {
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
        if (candidate.ok && candidate.approval && candidate.phase?.startsWith("approval-")) {
          turnJobs.observeBridgeEvent(submissionId, candidate);
        }
      },
    },
  );
  if (!envelope.ok) throw envelopeError(envelope);
  return envelope;
}

async function runFreshCodexTurn(
  cwd: string,
  text: string,
  submissionId: string,
  onDisposition: (envelope: BridgeEnvelope) => void,
): Promise<BridgeEnvelope> {
  const envelope = await runBridge(
    ["create-submit", cwd, submissionId],
    {
      stdin: text,
      timeoutMs: TURN_TIMEOUT_MS,
      onEnvelope: (candidate) => {
        if (candidate.ok && candidate.approval && candidate.phase?.startsWith("approval-")) {
          turnJobs.observeBridgeEvent(submissionId, candidate);
        }
        if (
          candidate.ok
          && candidate.phase === "accepted"
          && isCodexTurnDelivery(candidate.delivery)
          && candidate.task
          && isCodexTaskSummary(candidate.task)
        ) {
          onDisposition(candidate);
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
  | "awaiting-approval"
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
  task?: CodexTaskSummary;
  approval?: CodexApprovalRequest;
}

interface StoredCodexTurnJob {
  job: CodexTurnJobSnapshot;
  text: string;
  freshCwd?: string;
}

function writeApprovalDecision(
  jobId: string,
  approvalId: string,
  decision: CodexApprovalDecision,
): void {
  if (!UUID_PATTERN.test(jobId) || !UUID_PATTERN.test(approvalId)) {
    throw new CodexBridgeError("The approval identifier is invalid.", "approval-not-pending");
  }
  mkdirSync(CODEX_APPROVAL_DECISIONS_DIR, { recursive: true, mode: 0o700 });
  chmodSync(CODEX_APPROVAL_DECISIONS_DIR, 0o700);
  const destination = path.join(CODEX_APPROVAL_DECISIONS_DIR, `${jobId}.${approvalId}.json`);
  if (existsSync(destination)) {
    const existing = JSON.parse(readFileSync(destination, "utf8")) as { decision?: unknown };
    if (existing.decision === decision) return;
    throw new CodexBridgeError(
      "A different decision was already recorded for this approval.",
      "approval-conflict",
    );
  }
  const temporary = `${destination}.${process.pid}.${crypto.randomUUID()}.tmp`;
  try {
    writeFileSync(temporary, JSON.stringify({ decision }), { encoding: "utf8", mode: 0o600 });
    renameSync(temporary, destination);
    chmodSync(destination, 0o600);
  } catch (error) {
    try {
      unlinkSync(temporary);
    } catch {
      // The temp path may already have been atomically renamed.
    }
    throw error;
  }
}

type CodexActivityReader = (taskId: string) => Promise<BridgeEnvelope>;
type CodexCompletionNotifier = (job: CodexTurnJobSnapshot) => Promise<void>;
type CodexFreshTurnRunner = (
  cwd: string,
  text: string,
  submissionId: string,
  onDisposition: (envelope: BridgeEnvelope) => void,
) => Promise<BridgeEnvelope>;

export class CodexTurnJobManager {
  private readonly jobs = new Map<string, StoredCodexTurnJob>();
  private readonly runningExecutions = new Set<string>();

  constructor(
    private readonly coordinator: CodexTaskMessageCoordinator,
    private readonly readActivity: CodexActivityReader,
    private readonly notifyCompletion: CodexCompletionNotifier,
    private readonly storagePath?: string,
    private readonly runFreshTurn?: CodexFreshTurnRunner,
    private readonly recordApprovalDecision: (
      jobId: string,
      approvalId: string,
      decision: CodexApprovalDecision,
    ) => void = writeApprovalDecision,
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
      this.resumeRetryable(existing);
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

  observeBridgeEvent(jobId: string, envelope: BridgeEnvelope): void {
    const stored = this.jobs.get(jobId);
    if (!stored || !envelope.approval) return;
    const { job } = stored;
    if (envelope.phase === "approval-required") {
      job.status = "awaiting-approval";
      job.approval = {
        id: envelope.approval.id,
        method: envelope.approval.method,
        title: envelope.approval.title,
        detail: envelope.approval.detail,
        requestedAt: envelope.approval.requestedAt,
      };
      job.updatedAt = new Date().toISOString();
      job.error = undefined;
      job.code = undefined;
      job.hint = undefined;
      this.persist();
      log.info(`[codex] async job ${job.id} is awaiting remote approval ${job.approval.id}`);
      return;
    }
    if (envelope.phase === "approval-resolved" && job.approval?.id === envelope.approval.id) {
      job.status = "running";
      job.approval = undefined;
      job.updatedAt = new Date().toISOString();
      this.persist();
      log.info(`[codex] async job ${job.id} remote approval ${envelope.approval.id} resolved`);
    }
  }

  resolveApproval(
    jobId: string,
    approvalId: string,
    decision: CodexApprovalDecision,
  ): CodexTurnJobSnapshot {
    const stored = this.jobs.get(jobId);
    if (!stored) {
      throw new CodexBridgeError("This Codex turn receipt is no longer available.", "turn-job-not-found");
    }
    const { job } = stored;
    if (job.status !== "awaiting-approval" || job.approval?.id !== approvalId) {
      throw new CodexBridgeError("This Codex approval is no longer pending.", "approval-not-pending");
    }
    this.recordApprovalDecision(job.id, approvalId, decision);
    log.info(`[codex] recorded remote ${decision} decision for job ${job.id} approval ${approvalId}`);
    return { ...job };
  }

  async startFresh(
    submissionId: string,
    cwd: string,
    text: string,
  ): Promise<CodexTurnJobSnapshot> {
    if (!this.runFreshTurn) {
      throw new CodexBridgeError("Fresh Codex task dispatch is unavailable.", "bridge-failed");
    }
    const existing = this.jobs.get(submissionId);
    if (existing) {
      if (existing.freshCwd !== cwd || existing.text !== text || existing.job.mode !== "steer") {
        throw new CodexBridgeError(
          "This Talkie submission id already belongs to another Codex instruction.",
          "submission-conflict",
        );
      }
      this.resumeRetryable(existing);
      return this.waitForFreshTask(existing);
    }

    this.prune();
    const now = new Date().toISOString();
    const job: CodexTurnJobSnapshot = {
      id: submissionId,
      submissionId,
      taskId: "",
      taskTitle: "New task",
      status: "queued",
      mode: "steer",
      createdAt: now,
      updatedAt: now,
    };
    const stored: StoredCodexTurnJob = { job, text, freshCwd: cwd };
    this.jobs.set(job.id, stored);
    this.persist();
    log.info(`[codex] atomic fresh-task job ${job.id} created cwd=${cwd} chars=${text.length}`);
    this.launch(stored);
    return this.waitForFreshTask(stored);
  }

  private launch(stored: StoredCodexTurnJob): void {
    const { job, text } = stored;
    if (this.runningExecutions.has(job.id)) return;
    this.runningExecutions.add(job.id);

    const deliver = async (): Promise<BridgeEnvelope> => {
      if (stored.freshCwd && !job.taskId) {
        job.status = "running";
        job.updatedAt = new Date().toISOString();
        this.persist();
        return this.runFreshTurn!(
          stored.freshCwd,
          text,
          job.submissionId,
          (disposition) => {
            if (!disposition.task || !isCodexTaskSummary(disposition.task)) {
              throw new CodexBridgeError(
                "Codex app-server accepted an unreadable fresh task.",
                "protocol-mismatch",
              );
            }
            job.taskId = disposition.task.id;
            job.taskTitle = disposition.task.title;
            job.task = disposition.task;
            job.updatedAt = new Date().toISOString();
            if (!isCodexTurnDelivery(disposition.delivery)) {
              throw new CodexBridgeError(
                "Codex app-server accepted an unknown turn delivery.",
                "protocol-mismatch",
              );
            }
            job.delivery = disposition.delivery;
            job.turnId = disposition.turnId;
            this.persist();
            log.info(
              `[codex] atomic fresh-task job ${job.id} accepted task=${job.taskId} `
                + `delivery=${job.delivery}`,
            );
          },
        );
      }

      let preDeliveryTimeoutRetries = 0;
      while (true) {
        const knownDelivery = isCodexTurnDelivery(job.delivery) ? job.delivery : undefined;
        try {
          return await this.coordinator.deliver(
            job.taskId,
            text,
            job.mode,
            job.submissionId,
            () => {
              job.status = "running";
              job.updatedAt = new Date().toISOString();
              this.persist();
              log.info(`[codex] async job ${job.id} running task=${job.taskId} mode=${job.mode}`);
            },
            (disposition) => {
              if (!isCodexTurnDelivery(disposition.delivery)) return;
              job.delivery = disposition.delivery;
              job.turnId = disposition.turnId ?? job.turnId;
              job.updatedAt = new Date().toISOString();
              this.persist();
              log.info(
                `[codex] async job ${job.id} accepted task=${job.taskId} delivery=${job.delivery}`,
              );
            },
            knownDelivery,
          );
        } catch (error) {
          const code = error instanceof CodexBridgeError ? error.code : "bridge-failed";
          const canRetry = code === "desktop-timeout"
            && preDeliveryTimeoutRetries === 0
            && !isCodexTurnDelivery(job.delivery);
          if (!canRetry) throw error;

          preDeliveryTimeoutRetries += 1;
          job.status = "queued";
          job.updatedAt = new Date().toISOString();
          this.persist();
          log.warn(
            `[codex] async job ${job.id} timed out before acceptance; retrying once with the same submission`,
          );
        }
      }
    };

    void deliver().then(async (envelope) => {
      if (!isCodexTurnDelivery(envelope.delivery)) {
        throw new CodexBridgeError(
          "Codex Desktop returned an unknown turn delivery.",
          "protocol-mismatch",
        );
      }
      if (!job.taskId) {
        throw new CodexBridgeError(
          "Codex completed a fresh turn without identifying its task.",
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
      job.approval = undefined;
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
      job.approval = undefined;
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
    if (job.status !== "running" || !job.taskId) return { ...job };

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

  async snapshotForTask(
    taskId: string,
    preferredJobId?: string,
  ): Promise<CodexTurnJobSnapshot | undefined> {
    const preferred = preferredJobId ? this.jobs.get(preferredJobId) : undefined;
    if (preferred?.job.taskId === taskId) return this.snapshot(preferred.job.id);

    const candidates = [...this.jobs.values()]
      .map((stored) => stored.job)
      .filter((job) => job.taskId === taskId)
      .sort((left, right) => {
        const active = (status: CodexTurnJobStatus) => status === "running"
          || status === "queued"
          || status === "awaiting-approval"
          || status === "blocked";
        if (active(left.status) !== active(right.status)) return active(left.status) ? -1 : 1;
        return Date.parse(right.updatedAt) - Date.parse(left.updatedAt);
      });
    return candidates[0] ? this.snapshot(candidates[0].id) : undefined;
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

  private async waitForFreshTask(stored: StoredCodexTurnJob): Promise<CodexTurnJobSnapshot> {
    const deadline = Date.now() + SNAPSHOT_TIMEOUT_MS;
    while (Date.now() < deadline) {
      if (stored.job.taskId) return { ...stored.job };
      if (this.isTerminal(stored.job)) {
        throw new CodexBridgeError(
          stored.job.error || "Codex could not create the fresh task.",
          stored.job.code || "bridge-failed",
        );
      }
      await Bun.sleep(25);
    }
    throw new CodexBridgeError(
      "Timed out waiting for Codex to accept the fresh task.",
      "desktop-timeout",
    );
  }

  private isTerminal(job: CodexTurnJobSnapshot): boolean {
    return job.status === "blocked" || job.status === "completed" || job.status === "failed";
  }

  private resumeRetryable(stored: StoredCodexTurnJob): void {
    const { job } = stored;
    if (job.status !== "failed" || job.retryable !== true) return;
    job.status = "queued";
    job.updatedAt = new Date().toISOString();
    job.error = undefined;
    job.code = undefined;
    job.hint = undefined;
    job.retryable = undefined;
    this.persist();
    log.info(`[codex] retrying durable async job ${job.id} from its last accepted boundary`);
    this.launch(stored);
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
    let changed = false;
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
        if (stored.job.status === "awaiting-approval") {
          stored.job.status = "failed";
          stored.job.updatedAt = new Date().toISOString();
          stored.job.error = "The approval expired when the Talkie bridge restarted.";
          stored.job.code = "approval-channel-unavailable";
          stored.job.hint = RECOVERY_HINTS["approval-channel-unavailable"];
          stored.job.approval = undefined;
          changed = true;
        } else if (stored.job.status === "queued" || stored.job.status === "running") {
          pendingJobIDs.push(stored.job.id);
        }
      }
      if (changed) this.persist();
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

type CodexTaskCreator = (cwd: string) => Promise<CodexTaskSummary>;

/**
 * Owns durable, client-keyed task creation so transport retries cannot create
 * duplicate Codex threads. The same key is valid only for the same canonical
 * working directory.
 */
export class CodexTaskCreationManager {
  private readonly creations = new Map<string, CodexTaskCreation>();
  private readonly inFlight = new Map<string, { cwd: string; task: Promise<CodexTaskSummary> }>();

  constructor(
    private readonly createTask: CodexTaskCreator,
    private readonly storagePath?: string,
  ) {
    this.restore();
  }

  async create(creationId: string, cwd: string): Promise<CodexTaskSummary> {
    const existing = this.creations.get(creationId);
    if (existing) {
      this.assertMatchingDirectory(existing.cwd, cwd);
      return existing.task;
    }

    const active = this.inFlight.get(creationId);
    if (active) {
      this.assertMatchingDirectory(active.cwd, cwd);
      return active.task;
    }

    const task = this.createTask(cwd).then((created) => {
      if (!isCodexTaskSummary(created) || created.cwd !== cwd) {
        throw new CodexBridgeError(
          "Codex app-server returned an unreadable task.",
          "protocol-mismatch",
        );
      }
      this.creations.set(creationId, {
        creationId,
        cwd,
        task: created,
        createdAt: new Date().toISOString(),
      });
      this.persist();
      return created;
    }).finally(() => {
      this.inFlight.delete(creationId);
    });
    this.inFlight.set(creationId, { cwd, task });
    return task;
  }

  private assertMatchingDirectory(existing: string, requested: string): void {
    if (existing === requested) return;
    throw new CodexBridgeError(
      "creationId already belongs to another project directory.",
      "creation-conflict",
    );
  }

  private restore(): void {
    if (!this.storagePath || !existsSync(this.storagePath)) return;
    try {
      const decoded = JSON.parse(readFileSync(this.storagePath, "utf8")) as {
        version?: unknown;
        creations?: unknown;
      };
      if (decoded.version !== 1 || !Array.isArray(decoded.creations)) {
        throw new Error("unsupported creation store");
      }
      for (const candidate of decoded.creations) {
        const creation = candidate as CodexTaskCreation;
        if (
          typeof creation?.creationId !== "string" ||
          typeof creation.cwd !== "string" ||
          typeof creation.createdAt !== "string" ||
          !isCodexTaskSummary(creation.task)
        ) continue;
        this.creations.set(creation.creationId, creation);
      }
    } catch (error) {
      log.warn(`[codex] durable task creation store is unreadable: ${error}`);
    }
  }

  private persist(): void {
    if (!this.storagePath) return;
    const directory = path.dirname(this.storagePath);
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    chmodSync(directory, 0o700);
    const temporaryPath = `${this.storagePath}.${process.pid}.${crypto.randomUUID()}.tmp`;
    try {
      const payload = JSON.stringify({ version: 1, creations: [...this.creations.values()] });
      writeFileSync(temporaryPath, payload, { encoding: "utf8", mode: 0o600 });
      renameSync(temporaryPath, this.storagePath);
      chmodSync(this.storagePath, 0o600);
    } catch (error) {
      try {
        unlinkSync(temporaryPath);
      } catch {
        // The temp path may already have been atomically renamed.
      }
      log.warn(`[codex] could not persist task creations: ${error}`);
    }
  }
}

function isCodexTaskSummary(value: unknown): value is CodexTaskSummary {
  const task = value as Partial<CodexTaskSummary> | undefined;
  return typeof task?.id === "string" && task.id.length > 0
    && typeof task.title === "string"
    && typeof task.preview === "string"
    && typeof task.cwd === "string" && path.isAbsolute(task.cwd)
    && typeof task.project === "string"
    && typeof task.updatedAt === "number" && Number.isFinite(task.updatedAt);
}

async function validatedCodexTask(taskId: string): Promise<CodexTaskSummary> {
  const envelope = await runBridge(["validate", taskId], { timeoutMs: SNAPSHOT_TIMEOUT_MS });
  if (!envelope.ok || !envelope.task) throw envelopeError(envelope);
  if (!isCodexTaskSummary(envelope.task)) {
    throw new CodexBridgeError("Codex app-server returned an unreadable task.", "protocol-mismatch");
  }
  if (envelope.task.id !== taskId) {
    throw new CodexBridgeError("Codex Desktop returned a different task.", "task-mismatch");
  }
  return envelope.task;
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
  runFreshCodexTurn,
);

const taskCreations = new CodexTaskCreationManager(
  async (cwd) => {
    const envelope = await runBridge(["create", cwd], { timeoutMs: SNAPSHOT_TIMEOUT_MS });
    if (!envelope.ok) throw envelopeError(envelope);
    if (!envelope.task || !isCodexTaskSummary(envelope.task)) {
      throw new CodexBridgeError(
        "Codex app-server returned an unreadable task.",
        "protocol-mismatch",
      );
    }
    return envelope.task;
  },
  // Tests inject their own creator and isolated storage. Importing this module
  // must never read or mutate the live device's creation receipts.
  process.env.NODE_ENV === "test" ? undefined : CODEX_TASK_CREATIONS_FILE,
);

/** Maps a bridge failure onto an HTTP response, preserving code + recovery hint. */
function bridgeFailureResponse(error: unknown): Response {
  const code = error instanceof CodexBridgeError ? error.code : "bridge-failed";
  const message = error instanceof Error ? error.message : String(error);
  const hint = RECOVERY_HINTS[code];

  log.warn(`[codex] ${code}: ${message}`);

  const body = JSON.stringify({ error: message, code, ...(hint && { hint }) });
  let status = 502;
  if (
    code === "submission-conflict"
    || code === "creation-conflict"
    || code === "approval-conflict"
    || code === "approval-not-pending"
  ) {
    status = 409;
  } else if (code === "turn-job-not-found") {
    status = 404;
  } else if (code === "stale-thread") {
    status = 410;
  } else if (
    code === "invalid-submission-id"
    || code === "invalid-creation-id"
    || code === "invalid-project-directory"
  ) {
    status = 400;
  } else if (UNAVAILABLE_CODES.has(code)) {
    status = 503;
  }
  return new Response(body, { status, headers: { "Content-Type": "application/json" } });
}

/**
 * GET /codex/tasks — recent Codex Desktop tasks for the lane mapper.
 * Read-only snapshot of the task catalog.
 */
export async function codexTasksRoute(
  limitParam?: string | null,
  cursorParam?: string | null,
): Promise<Response> {
  const parsed = Number(limitParam);
  const limit = Number.isFinite(parsed) && parsed > 0 ? Math.min(Math.floor(parsed), 100) : 25;

  try {
    const args = ["list", String(limit)];
    if (cursorParam) args.push(cursorParam);
    const envelope = await runBridge(args, { timeoutMs: SNAPSHOT_TIMEOUT_MS });
    if (!envelope.ok || !envelope.tasks) throw envelopeError(envelope);
    if (!envelope.tasks.every(isCodexTaskSummary)) {
      throw new CodexBridgeError(
        "Codex app-server returned an unreadable task catalogue.",
        "protocol-mismatch",
      );
    }

    return Response.json({ tasks: envelope.tasks, nextCursor: envelope.nextCursor ?? null });
  } catch (error) {
    return bridgeFailureResponse(error);
  }
}

/** POST /codex/tasks — create one durable Codex task in an exact project. */
export async function codexTaskCreateRoute(body: unknown): Promise<Response> {
  const payload = body as { creationId?: unknown; cwd?: unknown };
  try {
    const creationId = parseCreationId(payload?.creationId);
    const cwd = canonicalCodexProjectDirectory(payload?.cwd);
    const task = await taskCreations.create(creationId, cwd);
    log.info(`[codex] resolved task creation ${creationId} as ${task.id} in ${cwd}`);
    return Response.json({ task }, { status: 201 });
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
    return Response.json({ task: await validatedCodexTask(taskId.trim()) });
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

/** POST /codex/task-turns — atomically create a task and start its first turn. */
export async function codexFreshTurnStartRoute(body: unknown): Promise<Response> {
  const payload = body as {
    submissionId?: unknown;
    cwd?: unknown;
    text?: unknown;
  };
  const text = typeof payload?.text === "string" ? payload.text.trim() : "";
  if (!text) return badRequest("text is required");

  try {
    const submissionId = parseSubmissionId(payload.submissionId);
    const cwd = canonicalCodexProjectDirectory(payload.cwd);
    const job = await turnJobs.startFresh(submissionId, cwd, text);
    log.info(`[codex] accepted atomic fresh-task job ${job.id} for task ${job.taskId}`);
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

/** POST /codex/turns/:id/approval — answer one still-live app-server approval. */
export async function codexApprovalDecisionRoute(jobIdValue: string, body: unknown): Promise<Response> {
  const jobId = jobIdValue.trim();
  const payload = body as { approvalId?: unknown; decision?: unknown };
  const approvalId = typeof payload?.approvalId === "string" ? payload.approvalId.trim() : "";
  const decision = payload?.decision;
  if (!jobId) return badRequest("job id is required");
  if (!approvalId) return badRequest("approvalId is required");
  if (decision !== "approve" && decision !== "decline") {
    return badRequest("decision must be approve or decline");
  }
  try {
    const job = turnJobs.resolveApproval(jobId, approvalId, decision);
    return Response.json({ job }, { status: 202 });
  } catch (error) {
    return bridgeFailureResponse(error);
  }
}

/** GET /codex/tasks/:id/history — bounded public turn history for one exact task. */
export async function codexTaskHistoryRoute(taskIdValue: string): Promise<Response> {
  const taskId = taskIdValue.trim();
  if (!taskId) return badRequest("task id is required");
  try {
    const [task, activity] = await Promise.all([
      validatedCodexTask(taskId),
      readCodexActivity(taskId),
    ]);
    return Response.json({
      task,
      turns: activity.history ?? [],
    }, {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    return bridgeFailureResponse(error);
  }
}

/** GET /codex/tasks/:id/status-document — trusted, read-only technical status surface. */
export async function codexStatusDocumentRoute(
  taskIdValue: string,
  jobIdValue?: string | null,
): Promise<Response> {
  const taskId = taskIdValue.trim();
  if (!taskId) return badRequest("task id is required");
  try {
    const task = await validatedCodexTask(taskId);
    const [repository, turn, activity] = await Promise.all([
      inspectCodexRepository(task.cwd),
      turnJobs.snapshotForTask(task.id, jobIdValue?.trim() || undefined),
      readCodexActivity(task.id).catch((error) => {
        log.debug(`[codex] status history unavailable for ${task.id}: ${error}`);
        return undefined;
      }),
    ]);
    const document = renderCodexStatusDocument({
      task,
      repository,
      ...(turn && { turn }),
      ...(activity?.history && { history: activity.history }),
      host: hostname(),
    });
    return new Response(document, {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
        "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; connect-src 'none'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch (error) {
    return bridgeFailureResponse(error);
  }
}
