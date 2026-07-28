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
import { existsSync } from "node:fs";
import { log } from "../../log";
import { badRequest } from "./responses";

/** Where the vendored Codex Desktop adapter lives (sibling of this routes dir). */
const BRIDGE_SCRIPT = path.join(import.meta.dir, "..", "codex-desktop-bridge.cjs");

/** `list`/`validate` are snapshot reads; `submit` waits for a full Codex turn. */
const SNAPSHOT_TIMEOUT_MS = 20_000;
const TURN_TIMEOUT_MS = 31 * 60_000;
// A queue command may wait for one full turn and then run another.
const QUEUED_TURN_TIMEOUT_MS = 61 * 60_000;

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

export interface BridgeEnvelope {
  ok: boolean;
  tasks?: CodexTaskSummary[];
  task?: { id: string; title?: string; cwd?: string };
  turnId?: string;
  response?: string;
  delivery?: string;
  error?: string;
  code?: string;
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
 * Recovery guidance keyed by adapter failure code. The article's contract is
 * that a lane which cannot be confirmed must explain how to recover, so the
 * hint travels with the error rather than being invented on the phone.
 */
const RECOVERY_HINTS: Record<string, string> = {
  "catalog-unavailable": "Open Codex Desktop at least once so its task catalog exists.",
  "desktop-unavailable": "Codex Desktop is not running. Launch it, then retry.",
  "desktop-timeout": "Codex Desktop did not respond. Bring it to the foreground, then retry.",
  "task-owner-unavailable": "Open this task in Codex Desktop so a window owns it, then retry.",
  "app-server-unavailable": "Install or update Codex on this Mac, then retry.",
  "app-server-request-failed": "Open this task in Codex Desktop and retry from the deck.",
  "approval-required": "Open this task in Codex Desktop to review the approval request.",
  "task-mismatch": "Codex Desktop returned a different task. Re-map this lane.",
  "protocol-mismatch": "Codex Desktop's task protocol changed. Update Talkie.",
  "turn-timeout": "Codex did not finish in time. Check the task in Codex Desktop.",
  "empty-response": "Codex finished without a final message.",
  "unsafe-socket": "Codex Desktop's IPC socket failed its ownership check.",
  "unsafe-rollout-path": "Codex Desktop returned an unsafe transcript path.",
};

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
  options: { stdin?: string; timeoutMs: number },
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
      new Response(proc.stdout).text(),
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
) => Promise<BridgeEnvelope>;

/**
 * Coordinates Talkie-originated messages per exact task.
 *
 * Completed turns are serialized because every adapter process tails one
 * rollout offset. Steering is a separate, ordered lane: it is acknowledged as
 * soon as Codex accepts the message and the already-running submit remains the
 * sole waiter for that turn's final response.
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
  ): Promise<BridgeEnvelope> {
    if (mode === "queue") {
      return this.enqueueTurn(taskId, text, "queue");
    }

    if (mode === "steer" || (mode === "auto" && this.activeTurns.has(taskId))) {
      return this.steer(taskId, text);
    }

    return this.enqueueTurn(taskId, text, "submit");
  }

  private enqueueTurn(
    taskId: string,
    text: string,
    firstCommand: "submit" | "queue",
  ): Promise<BridgeEnvelope> {
    const predecessor = this.turnTails.get(taskId);
    // Once another Talkie turn is ahead of us, ordinary submit is sufficient:
    // the predecessor guarantees Codex is idle before this operation starts.
    const command: "submit" | "queue" = predecessor ? "submit" : firstCommand;
    const ready = predecessor?.catch(() => undefined) ?? Promise.resolve();
    const result = ready.then(async () => {
      this.activeTurns.add(taskId);
      try {
        return await this.run(command, taskId, text);
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

  private steer(taskId: string, text: string): Promise<BridgeEnvelope> {
    const predecessor = this.steerTails.get(taskId);
    const ready = predecessor?.catch(() => undefined) ?? Promise.resolve();
    const result = ready
      .then(() => this.run("steer", taskId, text))
      .catch((error: unknown) => {
        // The current turn can finish between speech capture and delivery.
        // Preserve the user's message by making it the next turn.
        if (error instanceof CodexBridgeError && error.code === "turn-not-active") {
          return this.enqueueTurn(taskId, text, "submit");
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
): Promise<BridgeEnvelope> {
  const envelope = await runBridge([command, taskId], {
    stdin: text,
    timeoutMs: command === "queue" ? QUEUED_TURN_TIMEOUT_MS : TURN_TIMEOUT_MS,
  });
  if (!envelope.ok) throw envelopeError(envelope);
  return envelope;
}

const messageCoordinator = new CodexTaskMessageCoordinator(runCodexCommand);

/** Maps a bridge failure onto an HTTP response, preserving code + recovery hint. */
function bridgeFailureResponse(error: unknown): Response {
  const code = error instanceof CodexBridgeError ? error.code : "bridge-failed";
  const message = error instanceof Error ? error.message : String(error);
  const hint = RECOVERY_HINTS[code];

  log.warn(`[codex] ${code}: ${message}`);

  const body = JSON.stringify({ error: message, code, ...(hint && { hint }) });
  const status = UNAVAILABLE_CODES.has(code) ? 503 : 502;
  return new Response(body, { status, headers: { "Content-Type": "application/json" } });
}

/**
 * GET /codex/tasks — recent Codex Desktop tasks for the lane mapper.
 * Read-only snapshot of the catalog; never touches task ownership.
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
 * POST /codex/validate — confirm the Mac can resume this exact task.
 *
 * The deck calls this before showing a lane as locked. A success here means
 * either a live Desktop owner or Codex app-server resumed this exact task ID.
 */
export async function codexValidateRoute(body: unknown): Promise<Response> {
  const taskId = (body as { taskId?: unknown })?.taskId;
  if (typeof taskId !== "string" || !taskId.trim()) {
    return badRequest("taskId is required");
  }

  try {
    const envelope = await runBridge(["validate", taskId.trim()], { timeoutMs: SNAPSHOT_TIMEOUT_MS });
    if (!envelope.ok || !envelope.task) throw envelopeError(envelope);

    // Defense in depth: the adapter already rejects a mismatched task, but the
    // lock badge is only trustworthy if this layer refuses to relabel it too.
    if (envelope.task.id !== taskId.trim()) {
      throw new CodexBridgeError("Codex Desktop confirmed a different task.", "task-mismatch");
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
  const payload = body as { taskId?: unknown; text?: unknown; mode?: unknown };
  const taskId = typeof payload?.taskId === "string" ? payload.taskId.trim() : "";
  const text = typeof payload?.text === "string" ? payload.text.trim() : "";
  const mode = payload?.mode ?? "auto";

  if (!taskId) return badRequest("taskId is required");
  if (!text) return badRequest("text is required");
  if (mode !== "auto" && mode !== "queue" && mode !== "steer") {
    return badRequest("mode must be auto, queue, or steer");
  }

  try {
    const envelope = await messageCoordinator.deliver(taskId, text, mode);
    const response = envelope.response?.trim();
    const delivery = envelope.delivery;
    const isCompletedTurn = delivery === "started-turn" || delivery === "queued-turn";
    const isSteer = delivery === "steered-active-turn";
    if ((!isCompletedTurn && !isSteer) || (isCompletedTurn && !response)) {
      throw new CodexBridgeError("Codex Desktop returned an incomplete turn result.", "protocol-mismatch");
    }

    const responseDetail = response ? ` (${response.length} chars)` : "";
    log.info(`[codex] ${delivery} for task ${taskId}${responseDetail}`);
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
