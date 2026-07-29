import { afterEach, describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const {
  appendQueuedFollowUp,
  listTasks,
  makeQueuedFollowUp,
  readQueuedFollowUps,
  readTurnActivity,
  resolveDesktopTurnState,
  taskRolloutPath,
  withQueuedFollowUpMutationLock,
  waitForQueuedTurn,
} = require("./codex-desktop-bridge.cjs") as {
  appendQueuedFollowUp: (
    queued: Record<string, Array<Record<string, unknown>>>,
    taskId: string,
    message: Record<string, unknown>,
  ) => Record<string, Array<Record<string, unknown>>>;
  listTasks: (limit: number) => Array<Record<string, unknown>>;
  makeQueuedFollowUp: (text: string, state: Record<string, unknown>) => Record<string, any>;
  readQueuedFollowUps: () => Record<string, Array<Record<string, unknown>>>;
  readTurnActivity: (rolloutPath: string) => Record<string, unknown>;
  resolveDesktopTurnState: (
    rolloutPath: string,
    snapshotRuntimeStatus?: string,
  ) => {
    activeTurnId: string | null;
    decision: { snapshotRuntimeStatus: string; rolloutActiveTurnId: string | null };
  };
  taskRolloutPath: (taskId: string) => string;
  withQueuedFollowUpMutationLock: <T>(taskId: string, action: () => Promise<T>) => Promise<T>;
  waitForQueuedTurn: (
    rolloutPath: string,
    offset: number,
    text: string,
    matchingPredecessors?: number,
  ) => Promise<{ turnId: string; response: string }>;
};

const originalCodexHome = process.env.CODEX_HOME;
let fixtureHome: string | undefined;

afterEach(() => {
  if (originalCodexHome === undefined) delete process.env.CODEX_HOME;
  else process.env.CODEX_HOME = originalCodexHome;
  if (fixtureHome) rmSync(fixtureHome, { recursive: true, force: true });
  fixtureHome = undefined;
});

describe.serial("Codex task catalog", () => {
  test("returns recognizable user task identity and hides internal tasks", () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-catalog-"));
    mkdirSync(fixtureHome, { recursive: true });
    process.env.CODEX_HOME = fixtureHome;

    const database = new Database(path.join(fixtureHome, "state_5.sqlite"), { create: true });
    database.exec(`
      CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        archived INTEGER NOT NULL,
        name TEXT,
        title TEXT NOT NULL,
        first_user_message TEXT NOT NULL,
        preview TEXT NOT NULL,
        cwd TEXT NOT NULL,
        git_branch TEXT,
        git_origin_url TEXT,
        agent_role TEXT,
        thread_source TEXT,
        recency_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        rollout_path TEXT NOT NULL DEFAULT ''
      );
    `);
    const insert = database.prepare(`
      INSERT INTO threads (
        id, archived, name, title, first_user_message, preview, cwd,
        git_branch, git_origin_url, agent_role, thread_source,
        recency_at_ms, updated_at_ms, updated_at
      ) VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    insert.run(
      "user-task", "Add steer and queue support", "fallback title", "original request",
      "original request", "/Users/arach/.codex/worktrees/1234/talkie", "codex/deck",
      "https://github.com/arach/talkie.git", null, "user", 3000, 3000, 3,
    );
    insert.run(
      "subagent-task", "Background critique", "Background critique", "delegated work",
      "delegated work", "/Users/arach/dev/talkie", "codex/deck",
      "https://github.com/arach/talkie.git", "subagent", "subagent", 2000, 2000, 2,
    );
    insert.run(
      "empty-task", null, "Untitled", "", "", "/Users/arach/dev/talkie", null,
      null, null, "user", 1000, 1000, 1,
    );
    insert.run(
      "managed-agent", null, "[Base]\nYou are a managed agent", "[Base]\nYou are a managed agent",
      "[Base]\nYou are a managed agent", "/Users/arach/.buzz", null, null, null, null,
      500, 500, 1,
    );
    database.close();

    expect(listTasks(25)).toEqual([
      {
        id: "user-task",
        title: "Add steer and queue support",
        preview: "original request",
        cwd: "/Users/arach/.codex/worktrees/1234/talkie",
        gitBranch: "codex/deck",
        gitOriginURL: "https://github.com/arach/talkie.git",
        updatedAt: 3,
        project: "talkie",
      },
    ]);
  });

  test("returns only public commentary and technical completion signals", () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-activity-"));
    const taskId = "019fa94d-8b11-7030-a252-5debffd976ae";
    const sessions = path.join(fixtureHome, "sessions", "2026", "07", "28");
    mkdirSync(sessions, { recursive: true });
    process.env.CODEX_HOME = fixtureHome;
    const rollout = path.join(sessions, `rollout-${taskId}.jsonl`);
    writeFileSync(rollout, [
      { type: "event_msg", timestamp: "2026-07-28T10:00:00Z", payload: { type: "task_started", turn_id: "turn-1" } },
      { type: "response_item", payload: { type: "reasoning", summary: "private" } },
      { type: "event_msg", timestamp: "2026-07-28T10:00:01Z", payload: { type: "agent_reasoning", text: "private" } },
      { type: "event_msg", timestamp: "2026-07-28T10:00:02Z", payload: { type: "agent_message", phase: "commentary", message: "Tracing the host signal." } },
      { type: "event_msg", timestamp: "2026-07-28T10:00:03Z", payload: { type: "patch_apply_end", turn_id: "turn-1", success: true } },
    ].map(JSON.stringify).join("\n") + "\n");

    const database = new Database(path.join(fixtureHome, "state_5.sqlite"), { create: true });
    database.exec("CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL);");
    database.prepare("INSERT INTO threads VALUES (?, ?)").run(taskId, rollout);
    database.close();

    expect(taskRolloutPath(taskId)).toBe(rollout);
    expect(readTurnActivity(rollout)).toEqual({
      ok: true,
      active: true,
      turnId: "turn-1",
      updates: [
        {
          id: "2026-07-28T10:00:02Z-1",
          kind: "commentary",
          text: "Tracing the host signal.",
          timestamp: "2026-07-28T10:00:02Z",
        },
        {
          id: "2026-07-28T10:00:03Z-2",
          kind: "tool",
          text: "PATCH APPLIED",
          timestamp: "2026-07-28T10:00:03Z",
        },
      ],
    });
  });
});

describe.serial("Codex Desktop queued follow-ups", () => {
  test("serializes native queue state mutations for one task", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-queue-lock-"));
    process.env.CODEX_HOME = fixtureHome;
    const order: string[] = [];

    await Promise.all([
      withQueuedFollowUpMutationLock("task-1", async () => {
        order.push("first-start");
        await Bun.sleep(20);
        order.push("first-end");
      }),
      withQueuedFollowUpMutationLock("task-1", async () => {
        order.push("second-start");
        order.push("second-end");
      }),
    ]);

    expect(order).toEqual(["first-start", "first-end", "second-start", "second-end"]);
  });

  test("trusts rollout activity when a Desktop snapshot still says idle", () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-active-turn-"));
    const rollout = path.join(fixtureHome, "rollout.jsonl");
    writeFileSync(rollout, [
      { type: "event_msg", payload: { type: "task_started", turn_id: "visible-turn" } },
      { type: "event_msg", payload: { type: "user_message", message: "Desktop request" } },
    ].map(JSON.stringify).join("\n") + "\n");

    expect(resolveDesktopTurnState(rollout, "idle")).toEqual({
      activeTurnId: "visible-turn",
      decision: {
        snapshotRuntimeStatus: "idle",
        rolloutActiveTurnId: "visible-turn",
      },
    });
  });

  test("keeps the original active turn when a concurrent turn completes", () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-concurrent-turn-"));
    const rollout = path.join(fixtureHome, "rollout.jsonl");
    writeFileSync(rollout, [
      { type: "event_msg", payload: { type: "task_started", turn_id: "visible-turn" } },
      { type: "event_msg", payload: { type: "task_started", turn_id: "hidden-turn" } },
      { type: "event_msg", payload: { type: "task_complete", turn_id: "hidden-turn" } },
    ].map(JSON.stringify).join("\n") + "\n");

    expect(resolveDesktopTurnState(rollout, "active").activeTurnId).toBe("visible-turn");
  });

  test("preserves queues for other tasks when appending a Talkie message", () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-queue-"));
    process.env.CODEX_HOME = fixtureHome;
    const existing = {
      "other-task": [{ id: "existing", text: "Keep me" }],
    };
    writeFileSync(
      path.join(fixtureHome, ".codex-global-state.json"),
      JSON.stringify({ "queued-follow-ups": existing }),
    );

    const queued = appendQueuedFollowUp(readQueuedFollowUps(), "talkie-task", {
      id: "talkie-message",
      text: "Queue me",
    });

    expect(queued).toEqual({
      "other-task": [{ id: "existing", text: "Keep me" }],
      "talkie-task": [{ id: "talkie-message", text: "Queue me" }],
    });
  });

  test("builds a native Desktop follow-up with the selected task context", () => {
    const message = makeQueuedFollowUp("Visible from Talkie", {
      cwd: "/Users/arach/dev/talkie",
      latestCollaborationMode: { mode: "default" },
    });

    expect(message).toMatchObject({
      text: "Visible from Talkie",
      cwd: "/Users/arach/dev/talkie",
      context: {
        prompt: "Visible from Talkie",
        workspaceRoots: ["/Users/arach/dev/talkie"],
        collaborationMode: { mode: "default" },
      },
    });
    expect(message.id).toBeString();
    expect(message.createdAt).toBeNumber();
  });

  test("observes the exact queued instruction through its completed turn", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-queued-turn-"));
    const rollout = path.join(fixtureHome, "rollout.jsonl");
    writeFileSync(rollout, [
      { type: "event_msg", payload: { type: "task_started", turn_id: "unrelated-turn" } },
      { type: "event_msg", payload: { type: "user_message", message: "Desktop message" } },
      { type: "event_msg", payload: { type: "task_complete", turn_id: "unrelated-turn", last_agent_message: "Unrelated" } },
      { type: "event_msg", payload: { type: "task_started", turn_id: "talkie-turn" } },
      { type: "event_msg", payload: { type: "user_message", message: "Talkie queued message" } },
      { type: "event_msg", payload: { type: "task_complete", turn_id: "talkie-turn", last_agent_message: "Talkie response" } },
    ].map(JSON.stringify).join("\n") + "\n");

    await expect(waitForQueuedTurn(rollout, 0, "Talkie queued message")).resolves.toEqual({
      turnId: "talkie-turn",
      response: "Talkie response",
    });
  });

  test("distinguishes identical queued instructions by their queue position", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-duplicate-queue-"));
    const rollout = path.join(fixtureHome, "rollout.jsonl");
    writeFileSync(rollout, [
      { type: "event_msg", payload: { type: "task_started", turn_id: "first-turn" } },
      { type: "event_msg", payload: { type: "user_message", message: "Same spoken message" } },
      { type: "event_msg", payload: { type: "task_complete", turn_id: "first-turn", last_agent_message: "First response" } },
      { type: "event_msg", payload: { type: "task_started", turn_id: "second-turn" } },
      { type: "event_msg", payload: { type: "user_message", message: "Same spoken message" } },
      { type: "event_msg", payload: { type: "task_complete", turn_id: "second-turn", last_agent_message: "Second response" } },
    ].map(JSON.stringify).join("\n") + "\n");

    await expect(waitForQueuedTurn(rollout, 0, "Same spoken message", 1)).resolves.toEqual({
      turnId: "second-turn",
      response: "Second response",
    });
  });
});
