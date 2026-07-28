import { describe, expect, test } from "bun:test";
import {
  CodexTaskMessageCoordinator,
  CodexTurnJobManager,
  type BridgeEnvelope,
} from "./codex";

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

    const activeTurn = coordinator.deliver("task-1", "first", "auto");
    await Promise.resolve();

    const steering = await coordinator.deliver("task-1", "more context", "auto");

    expect(steering.delivery).toBe("steered-active-turn");
    expect(calls).toEqual(["submit", "steer"]);

    finishTurn?.();
    await activeTurn;
  });

  test("queue is published immediately while a Talkie turn is still running", async () => {
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
      return completed("queued-turn", "queued response");
    });

    const activeTurn = coordinator.deliver("task-1", "first", "auto");
    await Promise.resolve();
    const queuedTurn = coordinator.deliver("task-1", "next", "queue");
    await Promise.resolve();

    expect(calls).toEqual(["submit", "queue"]);

    const result = await queuedTurn;
    expect(result.response).toBe("queued response");

    finishTurn?.();
    await activeTurn;
  });

  test("queue uses the adapter queue command when Codex may already be active externally", async () => {
    const calls: string[] = [];
    const coordinator = new CodexTaskMessageCoordinator(async (command) => {
      calls.push(command);
      return completed("queued-turn", "queued response");
    });

    const result = await coordinator.deliver("task-1", "next", "queue");

    expect(calls).toEqual(["queue"]);
    expect(result.delivery).toBe("queued-turn");
  });
});

describe("CodexTurnJobManager", () => {
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

    const receipt = manager.start("task-1", "Command Deck", "keep working", "steer");
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

    const receipt = manager.start("task-1", "Command Deck", "keep working", "queue");
    await Bun.sleep(0);
    await Bun.sleep(0);

    const failedJob = await manager.snapshot(receipt.id);
    expect(failedJob?.status).toBe("failed");
    expect(failedJob?.code).toBe("protocol-mismatch");
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
