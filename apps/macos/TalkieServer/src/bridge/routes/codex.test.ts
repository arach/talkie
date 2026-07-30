import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  canonicalCodexProjectDirectory,
  CodexBridgeError,
  CodexTaskCreationManager,
  CodexTaskMessageCoordinator,
  CodexTurnJobManager,
  type BridgeEnvelope,
} from "./codex";

const submission1 = "019fae56-598a-70b0-83dd-539cda1c7704";
const submission2 = "019fae56-598a-70b0-83dd-539cda1c7705";
let receiptDirectory: string | undefined;

afterEach(() => {
  if (receiptDirectory) rmSync(receiptDirectory, { recursive: true, force: true });
  receiptDirectory = undefined;
});

describe("CodexTaskMessageCoordinator", () => {
  test("auto steers immediately while Talkie is waiting for the active turn", async () => {
    const calls: string[] = [];
    let finishTurn: (() => void) | undefined;
    const turnGate = new Promise<void>((resolve) => {
      finishTurn = resolve;
    });
    const coordinator = new CodexTaskMessageCoordinator(async (command) => {
      calls.push(command);
      if (command === "submit") {
        await turnGate;
        return completed("started-turn", "first response");
      }
      return {
        ok: true,
        turnId: "turn-1",
        delivery: "steered-active-turn",
      };
    });

    const activeTurn = coordinator.deliver("task-1", "first", "auto", submission1);
    await Promise.resolve();

    const steering = await coordinator.deliver("task-1", "more context", "auto", submission2);

    expect(steering.delivery).toBe("steered-active-turn");
    expect(calls).toEqual(["submit", "steer"]);

    finishTurn?.();
    await activeTurn;
  });

  test("reserves a newly scheduled turn before the first dispatch microtask", async () => {
    const calls: string[] = [];
    let finishTurn: (() => void) | undefined;
    const turnGate = new Promise<void>((resolve) => { finishTurn = resolve; });
    const coordinator = new CodexTaskMessageCoordinator(async (command) => {
      calls.push(command);
      if (command === "submit") {
        await turnGate;
        return completed("started-turn", "first response");
      }
      return {
        ok: true,
        phase: "accepted",
        turnId: "turn-1",
        delivery: "steered-active-turn",
      };
    });

    const activeTurn = coordinator.deliver("task-1", "first", "steer", submission1);
    const steering = coordinator.deliver("task-1", "more context", "steer", submission2);

    expect((await steering).delivery).toBe("steered-active-turn");
    expect(calls).toEqual(["submit", "steer"]);

    finishTurn?.();
    await activeTurn;
  });

  test("serializes queue publication only until Codex accepts the prior queue", async () => {
    const calls: string[] = [];
    let finishTurn: (() => void) | undefined;
    let acceptFirstQueue: ((envelope: BridgeEnvelope) => void) | undefined;
    const turnGate = new Promise<void>((resolve) => {
      finishTurn = resolve;
    });
    const coordinator = new CodexTaskMessageCoordinator(async (
      command,
      _taskId,
      _text,
      _submissionId,
      onDisposition,
    ) => {
      calls.push(command);
      if (calls.length === 1) {
        acceptFirstQueue = onDisposition;
        await turnGate;
        return completed("queued-turn", "first response");
      }
      return completed("queued-turn", "second response");
    });

    const activeTurn = coordinator.deliver("task-1", "first", "queue", submission1);
    await Promise.resolve();
    const queuedTurn = coordinator.deliver("task-1", "next", "queue", submission2);
    await Promise.resolve();

    expect(calls).toEqual(["queue"]);

    acceptFirstQueue?.({
      ok: true,
      phase: "accepted",
      delivery: "queued-turn",
    });
    await Promise.resolve();
    const result = await queuedTurn;

    expect(calls).toEqual(["queue", "queue"]);
    expect(result.response).toBe("second response");

    finishTurn?.();
    await activeTurn;
  });

  test("queue uses the adapter queue command when Codex may already be active externally", async () => {
    const calls: string[] = [];
    const coordinator = new CodexTaskMessageCoordinator(async (command) => {
      calls.push(command);
      return completed("queued-turn", "queued response");
    });

    const result = await coordinator.deliver("task-1", "next", "queue", submission1);

    expect(calls).toEqual(["queue"]);
    expect(result.delivery).toBe("queued-turn");
  });

  test("publishes queue to Codex after an active submission is accepted", async () => {
    const calls: string[] = [];
    let finishActiveTurn: (() => void) | undefined;
    let acceptedActiveTurn: (() => void) | undefined;
    const activeTurnGate = new Promise<void>((resolve) => {
      finishActiveTurn = resolve;
    });
    const acceptedGate = new Promise<void>((resolve) => {
      acceptedActiveTurn = resolve;
    });
    const coordinator = new CodexTaskMessageCoordinator(async (
      command,
      _taskId,
      _text,
      _submissionId,
      onDisposition,
    ) => {
      calls.push(command);
      if (command === "submit") {
        onDisposition?.({
          ok: true,
          phase: "accepted",
          turnId: "active-turn",
          delivery: "steered-active-turn",
        });
        acceptedActiveTurn?.();
        await activeTurnGate;
        return completed("steered-active-turn", "active response");
      }
      return completed("queued-turn", "queued response");
    });

    const activeTurn = coordinator.deliver("task-1", "context", "steer", submission1);
    await acceptedGate;
    const queuedTurn = coordinator.deliver("task-1", "next", "queue", submission2);
    await Promise.resolve();

    expect(calls).toEqual(["submit", "queue"]);

    finishActiveTurn?.();
    await activeTurn;
    expect((await queuedTurn).delivery).toBe("queued-turn");
  });

  test("explicit steer observes an externally owned active turn through completion", async () => {
    const calls: string[] = [];
    const coordinator = new CodexTaskMessageCoordinator(async (command) => {
      calls.push(command);
      return command === "submit"
        ? completed("steered-active-turn", "external turn response")
        : { ok: true, turnId: "turn-1", delivery: "steered-active-turn" };
    });

    const result = await coordinator.deliver("task-1", "more context", "steer", submission1);

    expect(calls).toEqual(["submit"]);
    expect(result.response).toBe("external turn response");
  });

  test("releases later steers when a raced steer fallback is accepted", async () => {
    const calls: string[] = [];
    let finishInitial: (() => void) | undefined;
    let finishFallback: (() => void) | undefined;
    let acceptFallback: (() => void) | undefined;
    const initialGate = new Promise<void>((resolve) => { finishInitial = resolve; });
    const fallbackGate = new Promise<void>((resolve) => { finishFallback = resolve; });
    const fallbackAccepted = new Promise<void>((resolve) => { acceptFallback = resolve; });
    const coordinator = new CodexTaskMessageCoordinator(async (
      command,
      _taskId,
      text,
      _submissionId,
      onDisposition,
    ) => {
      calls.push(`${command}:${text}`);
      if (text === "initial") {
        onDisposition?.({
          ok: true,
          phase: "accepted",
          turnId: "turn-initial",
          delivery: "started-turn",
        });
        await initialGate;
        return completed("started-turn", "initial response");
      }
      if (text === "fallback" && command === "steer") {
        throw new CodexBridgeError("turn ended", "turn-not-active");
      }
      if (text === "fallback") {
        onDisposition?.({
          ok: true,
          phase: "accepted",
          turnId: "turn-fallback",
          delivery: "started-turn",
        });
        acceptFallback?.();
        await fallbackGate;
        return completed("started-turn", "fallback response");
      }
      return {
        ok: true,
        phase: "accepted",
        turnId: "turn-fallback",
        delivery: "steered-active-turn",
      };
    });

    const initial = coordinator.deliver("task-1", "initial", "steer", submission1);
    await Promise.resolve();
    const fallback = coordinator.deliver("task-1", "fallback", "steer", submission2);
    await Promise.resolve();
    const latest = coordinator.deliver(
      "task-1",
      "latest",
      "steer",
      "019fae56-598a-70b0-83dd-539cda1c7706",
    );

    finishInitial?.();
    await fallbackAccepted;
    await latest;

    expect(calls).toEqual([
      "submit:initial",
      "steer:fallback",
      "submit:fallback",
      "steer:latest",
    ]);

    finishFallback?.();
    await fallback;
    await initial;
  });
});

describe("CodexTaskCreationManager", () => {
  test("coalesces repeated creation IDs and restores the durable task", async () => {
    receiptDirectory = mkdtempSync(path.join(tmpdir(), "talkie-codex-creations-"));
    const receiptPath = path.join(receiptDirectory, "creations.json");
    let invocations = 0;
    let releaseCreation: (() => void) | undefined;
    const creationGate = new Promise<void>((resolve) => { releaseCreation = resolve; });
    const creator = async (cwd: string) => {
      invocations += 1;
      await creationGate;
      return taskSummary("task-created-once", cwd);
    };
    const manager = new CodexTaskCreationManager(creator, receiptPath);

    const first = manager.create(submission1, receiptDirectory);
    const retry = manager.create(submission1, receiptDirectory);
    releaseCreation?.();

    expect(await first).toEqual(await retry);
    expect(invocations).toBe(1);
    expect(JSON.parse(readFileSync(receiptPath, "utf8")).creations[0].task.id)
      .toBe("task-created-once");

    const restored = new CodexTaskCreationManager(async () => {
      throw new Error("must not create twice");
    }, receiptPath);
    expect((await restored.create(submission1, receiptDirectory)).id).toBe("task-created-once");
  });

  test("rejects reuse of a creation ID for another working directory", async () => {
    receiptDirectory = mkdtempSync(path.join(tmpdir(), "talkie-codex-creations-"));
    const firstDirectory = path.join(receiptDirectory, "one");
    const secondDirectory = path.join(receiptDirectory, "two");
    const manager = new CodexTaskCreationManager(async (cwd) => taskSummary("task-1", cwd));

    await manager.create(submission1, firstDirectory);

    await expect(manager.create(submission1, secondDirectory)).rejects.toMatchObject({
      code: "creation-conflict",
    });
  });

  test("requires an existing absolute directory and resolves aliases", () => {
    receiptDirectory = mkdtempSync(path.join(tmpdir(), "talkie-codex-project-"));

    expect(canonicalCodexProjectDirectory(receiptDirectory)).toBe(realpathSync(receiptDirectory));
    expect(() => canonicalCodexProjectDirectory("relative/project")).toThrow(
      "cwd must be an absolute project directory",
    );
    expect(() => canonicalCodexProjectDirectory(path.join(receiptDirectory, "missing"))).toThrow(
      "cwd must refer to an existing project directory",
    );
  });
});

describe("CodexTurnJobManager", () => {
  test("atomically starts a fresh task, returns its accepted identity, and deduplicates retries", async () => {
    let invocations = 0;
    let finishTurn: (() => void) | undefined;
    const turnGate = new Promise<void>((resolve) => { finishTurn = resolve; });
    const projectDirectory = mkdtempSync(path.join(tmpdir(), "talkie-codex-fresh-job-"));
    const manager = new CodexTurnJobManager(
      new CodexTaskMessageCoordinator(async () => {
        throw new Error("fresh delivery must not use the existing-task coordinator");
      }),
      async () => ({ ok: true }),
      async () => {},
      undefined,
      async (cwd, _text, _submissionId, onDisposition) => {
        invocations += 1;
        const task = taskSummary("task-fresh", cwd);
        onDisposition({
          ok: true,
          phase: "accepted",
          task,
          turnId: "turn-fresh",
          delivery: "started-turn",
        });
        await turnGate;
        return {
          ok: true,
          task,
          turnId: "turn-fresh",
          delivery: "started-turn",
          response: "Fresh task finished",
        };
      },
    );

    const first = await manager.startFresh(submission1, projectDirectory, "start here");
    const retry = await manager.startFresh(submission1, projectDirectory, "start here");

    expect(first.taskId).toBe("task-fresh");
    expect(first.task?.cwd).toBe(projectDirectory);
    expect(retry.taskId).toBe(first.taskId);
    expect(invocations).toBe(1);

    finishTurn?.();
    await Bun.sleep(0);
    await Bun.sleep(0);
    expect((await manager.snapshot(first.id))?.status).toBe("completed");
  });

  test("resumes a retryable fresh task from its persisted task boundary", async () => {
    const projectDirectory = mkdtempSync(path.join(tmpdir(), "talkie-codex-fresh-retry-"));
    let freshInvocations = 0;
    let resumedInvocations = 0;
    const coordinator = new CodexTaskMessageCoordinator(async (
      _command,
      taskId,
      _text,
      submissionId,
    ) => {
      resumedInvocations += 1;
      expect(taskId).toBe("task-created-before-failure");
      expect(submissionId).toBe(submission1);
      return completed("started-turn", "Recovered without a duplicate task");
    });
    const manager = new CodexTurnJobManager(
      coordinator,
      async () => ({ ok: true }),
      async () => {},
      undefined,
      async (cwd, _text, _submissionId, onDisposition) => {
        freshInvocations += 1;
        const task = taskSummary("task-created-before-failure", cwd);
        onDisposition({ ok: true, phase: "created", task });
        throw new CodexBridgeError("Codex app-server disconnected.", "app-server-unavailable");
      },
    );

    const first = await manager.startFresh(submission1, projectDirectory, "keep this task");
    expect(first.taskId).toBe("task-created-before-failure");
    await Bun.sleep(0);
    await Bun.sleep(0);
    expect((await manager.snapshot(first.id))?.retryable).toBe(true);

    const resumed = await manager.startFresh(submission1, projectDirectory, "keep this task");
    expect(resumed.taskId).toBe(first.taskId);
    await Bun.sleep(0);
    await Bun.sleep(0);

    const completedJob = await manager.snapshot(first.id);
    expect(completedJob?.status).toBe("completed");
    expect(completedJob?.response).toBe("Recovered without a duplicate task");
    expect(freshInvocations).toBe(1);
    expect(resumedInvocations).toBe(1);
  });

  test("restores an accepted fresh task after restart without creating another task", async () => {
    receiptDirectory = mkdtempSync(path.join(tmpdir(), "talkie-codex-fresh-restore-"));
    const receiptPath = path.join(receiptDirectory, "jobs.json");
    const projectDirectory = realpathSync(receiptDirectory);
    const task = taskSummary("task-accepted-before-restart", projectDirectory);
    const now = new Date().toISOString();
    writeFileSync(receiptPath, JSON.stringify({
      version: 1,
      jobs: [{
        job: {
          id: submission1,
          submissionId: submission1,
          taskId: task.id,
          taskTitle: task.title,
          status: "running",
          mode: "steer",
          createdAt: now,
          updatedAt: now,
          task,
        },
        text: "continue after restart",
        freshCwd: projectDirectory,
      }],
    }));

    let resumedInvocations = 0;
    let freshInvocations = 0;
    const coordinator = new CodexTaskMessageCoordinator(async (
      _command,
      taskId,
      text,
      submissionId,
    ) => {
      resumedInvocations += 1;
      expect(taskId).toBe(task.id);
      expect(text).toBe("continue after restart");
      expect(submissionId).toBe(submission1);
      return completed("started-turn", "Restored after restart");
    });
    const restored = new CodexTurnJobManager(
      coordinator,
      async () => ({ ok: true }),
      async () => {},
      receiptPath,
      async () => {
        freshInvocations += 1;
        throw new Error("must not create a second fresh task");
      },
    );

    await Bun.sleep(0);
    await Bun.sleep(0);

    const completedJob = await restored.snapshot(submission1);
    expect(completedJob?.status).toBe("completed");
    expect(completedJob?.taskId).toBe(task.id);
    expect(completedJob?.response).toBe("Restored after restart");
    expect(freshInvocations).toBe(0);
    expect(resumedInvocations).toBe(1);
  });

  test("returns immediately, publishes public progress, and keeps the final response", async () => {
    let finishTurn: (() => void) | undefined;
    const turnGate = new Promise<void>((resolve) => {
      finishTurn = resolve;
    });
    const coordinator = new CodexTaskMessageCoordinator(async () => {
      await turnGate;
      return completed("started-turn", "Finished in the background");
    });
    const notified: string[] = [];
    const manager = new CodexTurnJobManager(
      coordinator,
      async () => ({
        ok: true,
        active: true,
        turnId: "turn-1",
        updates: [{ id: "u1", kind: "commentary", text: "Checking the host.", timestamp: null }],
      }),
      async (job) => { if (job.response) notified.push(job.response); },
    );

    const receipt = manager.start(submission1, "task-1", "Command Deck", "keep working", "steer");
    expect(receipt.status).toBe("queued");
    await Promise.resolve();

    const running = await manager.snapshot(receipt.id);
    expect(running?.status).toBe("running");
    expect(running?.updates?.[0]?.text).toBe("Checking the host.");

    finishTurn?.();
    await Bun.sleep(0);
    await Bun.sleep(0);
    const completedJob = await manager.snapshot(receipt.id);
    expect(completedJob?.status).toBe("completed");
    expect(completedJob?.response).toBe("Finished in the background");
    expect(notified).toEqual(["Finished in the background"]);
  });

  test("fails an async job when the adapter returns an unknown delivery", async () => {
    const coordinator = new CodexTaskMessageCoordinator(async () =>
      completed("adapter-internal-delivery", "Finished in the background"));
    const manager = new CodexTurnJobManager(
      coordinator,
      async () => ({ ok: true }),
      async () => {},
    );

    const receipt = manager.start(submission1, "task-1", "Command Deck", "keep working", "queue");
    await Bun.sleep(0);
    await Bun.sleep(0);

    const failedJob = await manager.snapshot(receipt.id);
    expect(failedJob?.status).toBe("failed");
    expect(failedJob?.code).toBe("protocol-mismatch");
  });

  test("deduplicates a repeated durable submission before invoking Codex twice", async () => {
    let invocations = 0;
    let finishTurn: (() => void) | undefined;
    const turnGate = new Promise<void>((resolve) => { finishTurn = resolve; });
    const coordinator = new CodexTaskMessageCoordinator(async () => {
      invocations += 1;
      await turnGate;
      return completed("started-turn", "Done once");
    });
    receiptDirectory = mkdtempSync(path.join(tmpdir(), "talkie-codex-receipts-"));
    const receiptPath = path.join(receiptDirectory, "jobs.json");
    const manager = new CodexTurnJobManager(
      coordinator,
      async () => ({ ok: true }),
      async () => {},
      receiptPath,
    );

    const first = manager.start(submission1, "task-1", "Command Deck", "same text", "queue");
    const retry = manager.start(submission1, "task-1", "Command Deck", "same text", "queue");
    await Bun.sleep(0);

    expect(retry.id).toBe(first.id);
    expect(invocations).toBe(1);
    expect(JSON.parse(readFileSync(receiptPath, "utf8")).jobs[0].job.submissionId).toBe(submission1);

    expect(() => manager.start(submission1, "task-1", "Command Deck", "different", "queue"))
      .toThrow("already belongs to another Codex instruction");
    finishTurn?.();
    await Bun.sleep(0);
  });

  test("retries one desktop timeout before Codex accepts the durable submission", async () => {
    let invocations = 0;
    const submissionIDs: string[] = [];
    const coordinator = new CodexTaskMessageCoordinator(async (
      _command,
      _taskId,
      _text,
      submissionId,
    ) => {
      invocations += 1;
      submissionIDs.push(submissionId);
      if (invocations === 1) {
        throw new CodexBridgeError("Timed out waiting for initialize.", "desktop-timeout");
      }
      return completed("started-turn", "Recovered on retry");
    });
    const manager = new CodexTurnJobManager(
      coordinator,
      async () => ({ ok: true }),
      async () => {},
    );

    const receipt = manager.start(submission1, "task-1", "Command Deck", "keep working", "steer");
    await Bun.sleep(0);
    await Bun.sleep(0);

    const completedJob = await manager.snapshot(receipt.id);
    expect(completedJob?.status).toBe("completed");
    expect(completedJob?.response).toBe("Recovered on retry");
    expect(invocations).toBe(2);
    expect(submissionIDs).toEqual([submission1, submission1]);
  });

  test("does not replay a timeout after Codex has accepted the submission", async () => {
    let invocations = 0;
    const coordinator = new CodexTaskMessageCoordinator(async (
      _command,
      _taskId,
      _text,
      _submissionId,
      onDisposition,
    ) => {
      invocations += 1;
      onDisposition?.({
        ok: true,
        phase: "accepted",
        turnId: "turn-1",
        delivery: "started-turn",
      });
      throw new CodexBridgeError("Timed out while observing the turn.", "desktop-timeout");
    });
    const manager = new CodexTurnJobManager(
      coordinator,
      async () => ({ ok: true }),
      async () => {},
    );

    const receipt = manager.start(submission1, "task-1", "Command Deck", "keep working", "steer");
    await Bun.sleep(0);
    await Bun.sleep(0);

    const failedJob = await manager.snapshot(receipt.id);
    expect(failedJob?.status).toBe("failed");
    expect(failedJob?.delivery).toBe("started-turn");
    expect(failedJob?.code).toBe("desktop-timeout");
    expect(invocations).toBe(1);
  });
});

function completed(delivery: string, response: string): BridgeEnvelope {
  return {
    ok: true,
    turnId: "turn-1",
    delivery,
    response,
  };
}

function taskSummary(id: string, cwd: string) {
  return {
    id,
    title: "New task",
    preview: "",
    cwd,
    project: path.basename(cwd),
    gitBranch: null,
    gitOriginURL: null,
    updatedAt: 1,
  };
}
