import { describe, expect, test } from "bun:test";
import {
  CodexTaskMessageCoordinator,
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

  test("queue waits for the current Talkie turn and then starts another", async () => {
    const calls: string[] = [];
    let finishTurn: (() => void) | undefined;
    const turnGate = new Promise<void>((resolve) => {
      finishTurn = resolve;
    });
    let submitCount = 0;
    const coordinator = new CodexTaskMessageCoordinator(async (command) => {
      calls.push(command);
      submitCount += 1;
      if (submitCount === 1) await turnGate;
      return completed("started-turn", `response ${submitCount}`);
    });

    const activeTurn = coordinator.deliver("task-1", "first", "auto");
    await Promise.resolve();
    const queuedTurn = coordinator.deliver("task-1", "next", "queue");
    await Promise.resolve();

    expect(calls).toEqual(["submit"]);

    finishTurn?.();
    await activeTurn;
    const result = await queuedTurn;

    expect(calls).toEqual(["submit", "submit"]);
    expect(result.response).toBe("response 2");
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

function completed(delivery: string, response: string): BridgeEnvelope {
  return {
    ok: true,
    turnId: "turn-1",
    delivery,
    response,
  };
}
