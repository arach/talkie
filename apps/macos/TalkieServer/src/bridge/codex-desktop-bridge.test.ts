import { afterEach, describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
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
    clientUserMessageId?: string,
  ) => Promise<{ turnId: string; response: string }>;
};

const originalCodexHome = process.env.CODEX_HOME;
const originalCodexExecutable = process.env.TALKIE_CODEX_EXECUTABLE;
let fixtureHome: string | undefined;

afterEach(() => {
  if (originalCodexHome === undefined) delete process.env.CODEX_HOME;
  else process.env.CODEX_HOME = originalCodexHome;
  if (originalCodexExecutable === undefined) delete process.env.TALKIE_CODEX_EXECUTABLE;
  else process.env.TALKIE_CODEX_EXECUTABLE = originalCodexExecutable;
  if (fixtureHome) rmSync(fixtureHome, { recursive: true, force: true });
  fixtureHome = undefined;
});

describe.serial("Codex app-server fallback", () => {
  test("reports a missing exact thread as stale instead of an owner failure", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-app-server-stale-"));
    const threadId = "019fae56-598a-70b0-83dd-539cda1c7703";
    const submissionId = "019fae56-598a-70b0-83dd-539cda1c7704";
    const executable = path.join(fixtureHome, "fake-codex.cjs");
    writeFileSync(executable, `#!/usr/bin/env node
const readline = require('node:readline');
const rl = readline.createInterface({ input: process.stdin });
const send = (value) => process.stdout.write(JSON.stringify(value) + '\\n');
rl.on('line', (line) => {
  const message = JSON.parse(line);
  if (message.id === undefined) return;
  if (message.method === 'initialize') return send({ id: message.id, result: {} });
  if (message.method === 'thread/resume') return send({
    id: message.id,
    error: { code: 'thread_not_found', message: 'Thread not found' },
  });
});
`);
    chmodSync(executable, 0o755);

    const bridge = Bun.spawn(
      [process.execPath, path.join(import.meta.dir, "codex-desktop-bridge.cjs"), "submit", threadId, submissionId],
      {
        stdin: new TextEncoder().encode("This lane is stale"),
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...process.env,
          CODEX_HOME: fixtureHome,
          TALKIE_CODEX_EXECUTABLE: executable,
        },
      },
    );
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(bridge.stdout).text(),
      new Response(bridge.stderr).text(),
      bridge.exited,
    ]);

    expect(stderr).toBe("");
    expect(exitCode).toBe(1);
    expect(JSON.parse(stdout.trim())).toMatchObject({
      ok: false,
      code: "stale-thread",
      error: "Thread not found",
    });
  });

  test("starts an idle turn in the exact task with the caller submission id", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-app-server-"));
    const threadId = "019fae56-598a-70b0-83dd-539cda1c7704";
    const submissionId = "019fae56-598a-70b0-83dd-539cda1c7705";
    const sessions = path.join(fixtureHome, "sessions", "2026", "07", "29");
    mkdirSync(sessions, { recursive: true });
    const rollout = path.join(sessions, `rollout-${threadId}.jsonl`);
    const requestLog = path.join(fixtureHome, "request.json");
    writeFileSync(rollout, "");

    const executable = path.join(fixtureHome, "fake-codex.cjs");
    writeFileSync(executable, `#!/usr/bin/env node
const fs = require('node:fs');
const readline = require('node:readline');
const rl = readline.createInterface({ input: process.stdin });
const send = (value) => process.stdout.write(JSON.stringify(value) + '\\n');
rl.on('line', (line) => {
  const message = JSON.parse(line);
  if (message.id === undefined) return;
  if (message.method === 'initialize') return send({ id: message.id, result: {} });
  if (message.method === 'thread/resume') return send({
    id: message.id,
    result: { thread: { id: message.params.threadId, path: process.env.FAKE_CODEX_ROLLOUT, status: { type: 'idle' }, turns: [] } },
  });
  if (message.method === 'turn/start') {
    fs.writeFileSync(process.env.FAKE_CODEX_REQUEST_LOG, JSON.stringify(message.params));
    send({ id: message.id, result: { turn: { id: 'turn-from-talkie' } } });
    fs.appendFileSync(process.env.FAKE_CODEX_ROLLOUT,
      JSON.stringify({ type: 'event_msg', payload: { type: 'task_started', turn_id: 'turn-from-talkie' } }) + '\\n' +
      JSON.stringify({ type: 'event_msg', payload: { type: 'user_message', message: message.params.input[0].text, client_id: message.params.clientUserMessageId } }) + '\\n' +
      JSON.stringify({ type: 'event_msg', payload: { type: 'task_complete', turn_id: 'turn-from-talkie', last_agent_message: 'Exact task completed' } }) + '\\n');
  }
});
`);
    chmodSync(executable, 0o755);

    const bridge = Bun.spawn(
      [process.execPath, path.join(import.meta.dir, "codex-desktop-bridge.cjs"), "submit", threadId, submissionId],
      {
        stdin: new TextEncoder().encode("Run this exact task"),
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...process.env,
          CODEX_HOME: fixtureHome,
          TALKIE_CODEX_EXECUTABLE: executable,
          FAKE_CODEX_ROLLOUT: rollout,
          FAKE_CODEX_REQUEST_LOG: requestLog,
        },
      },
    );
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(bridge.stdout).text(),
      new Response(bridge.stderr).text(),
      bridge.exited,
    ]);

    expect(stderr).toBe("");
    expect(exitCode).toBe(0);
    const envelopes = stdout.trim().split("\n").map((line) => JSON.parse(line));
    expect(envelopes[0]).toMatchObject({ ok: true, phase: "accepted", delivery: "started-turn" });
    expect(envelopes.at(-1)).toMatchObject({
      ok: true,
      threadId,
      turnId: "turn-from-talkie",
      delivery: "started-turn",
      response: "Exact task completed",
    });
    expect(JSON.parse(readFileSync(requestLog, "utf8"))).toMatchObject({
      threadId,
      clientUserMessageId: submissionId,
    });
  });

  test("reconciles a durable submission already completed by Codex without replaying it", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-app-server-reconcile-"));
    const threadId = "019fae56-598a-70b0-83dd-539cda1c7708";
    const submissionId = "019fae56-598a-70b0-83dd-539cda1c7709";
    const sessions = path.join(fixtureHome, "sessions", "2026", "07", "29");
    mkdirSync(sessions, { recursive: true });
    const rollout = path.join(sessions, `rollout-${threadId}.jsonl`);
    const requestLog = path.join(fixtureHome, "requests.log");
    writeFileSync(
      rollout,
      [
        { type: "event_msg", payload: { type: "task_started", turn_id: "existing-talkie-turn" } },
        {
          type: "event_msg",
          payload: {
            type: "user_message",
            message: "Do not replay this",
            client_id: "desktop-generated-client-id",
          },
        },
        {
          type: "event_msg",
          payload: {
            type: "task_complete",
            turn_id: "existing-talkie-turn",
            last_agent_message: "Recovered exactly once",
          },
        },
      ].map((record) => JSON.stringify(record)).join("\n") + "\n",
    );

    const executable = path.join(fixtureHome, "fake-codex.cjs");
    writeFileSync(executable, `#!/usr/bin/env node
const fs = require('node:fs');
const readline = require('node:readline');
const rl = readline.createInterface({ input: process.stdin });
const send = (value) => process.stdout.write(JSON.stringify(value) + '\\n');
rl.on('line', (line) => {
  const message = JSON.parse(line);
  if (message.id === undefined) return;
  if (message.method === 'initialize') return send({ id: message.id, result: {} });
  if (message.method === 'thread/resume') return send({
    id: message.id,
    result: { thread: { id: message.params.threadId, path: process.env.FAKE_CODEX_ROLLOUT, status: { type: 'idle' }, turns: [] } },
  });
  fs.appendFileSync(process.env.FAKE_CODEX_REQUEST_LOG, message.method + '\\n');
  send({ id: message.id, error: { message: 'unexpected replay' } });
});
`);
    chmodSync(executable, 0o755);

    const bridge = Bun.spawn(
      [
        process.execPath,
        path.join(import.meta.dir, "codex-desktop-bridge.cjs"),
        "queue",
        threadId,
        submissionId,
        "queued-turn",
      ],
      {
        stdin: new TextEncoder().encode("Do not replay this"),
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...process.env,
          CODEX_HOME: fixtureHome,
          TALKIE_CODEX_EXECUTABLE: executable,
          FAKE_CODEX_ROLLOUT: rollout,
          FAKE_CODEX_REQUEST_LOG: requestLog,
        },
      },
    );
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(bridge.stdout).text(),
      new Response(bridge.stderr).text(),
      bridge.exited,
    ]);

    expect(stderr).toBe("");
    expect(exitCode).toBe(0);
    expect(existsSync(requestLog)).toBe(false);
    const envelopes = stdout.trim().split("\n").map((line) => JSON.parse(line));
    expect(envelopes[0]).toMatchObject({
      ok: true,
      phase: "accepted",
      turnId: "existing-talkie-turn",
      delivery: "queued-turn",
    });
    expect(envelopes.at(-1)).toMatchObject({
      ok: true,
      turnId: "existing-talkie-turn",
      delivery: "queued-turn",
      response: "Recovered exactly once",
    });
  });

  test("queues behind an active app-server turn and then starts the same task", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-app-server-queue-"));
    const threadId = "019fae56-598a-70b0-83dd-539cda1c7706";
    const submissionId = "019fae56-598a-70b0-83dd-539cda1c7707";
    const sessions = path.join(fixtureHome, "sessions", "2026", "07", "29");
    mkdirSync(sessions, { recursive: true });
    const rollout = path.join(sessions, `rollout-${threadId}.jsonl`);
    writeFileSync(
      rollout,
      JSON.stringify({ type: "event_msg", payload: { type: "task_started", turn_id: "existing-turn" } }) + "\n",
    );

    const executable = path.join(fixtureHome, "fake-codex.cjs");
    writeFileSync(executable, `#!/usr/bin/env node
const fs = require('node:fs');
const readline = require('node:readline');
const rl = readline.createInterface({ input: process.stdin });
const send = (value) => process.stdout.write(JSON.stringify(value) + '\\n');
let resumeCount = 0;
rl.on('line', (line) => {
  const message = JSON.parse(line);
  if (message.id === undefined) return;
  if (message.method === 'initialize') return send({ id: message.id, result: {} });
  if (message.method === 'thread/resume') {
    resumeCount += 1;
    const active = resumeCount === 1;
    send({ id: message.id, result: { thread: {
      id: message.params.threadId,
      path: process.env.FAKE_CODEX_ROLLOUT,
      status: { type: active ? 'active' : 'idle' },
      turns: active ? [{ id: 'existing-turn', status: 'inProgress' }] : [],
    } } });
    if (active) setTimeout(() => fs.appendFileSync(process.env.FAKE_CODEX_ROLLOUT,
      JSON.stringify({ type: 'event_msg', payload: { type: 'task_complete', turn_id: 'existing-turn', last_agent_message: 'Existing done' } }) + '\\n'), 20);
    return;
  }
  if (message.method === 'turn/start') {
    send({ id: message.id, result: { turn: { id: 'queued-turn-id' } } });
    fs.appendFileSync(process.env.FAKE_CODEX_ROLLOUT,
      JSON.stringify({ type: 'event_msg', payload: { type: 'task_started', turn_id: 'queued-turn-id' } }) + '\\n' +
      JSON.stringify({ type: 'event_msg', payload: { type: 'user_message', message: message.params.input[0].text, client_id: message.params.clientUserMessageId } }) + '\\n' +
      JSON.stringify({ type: 'event_msg', payload: { type: 'task_complete', turn_id: 'queued-turn-id', last_agent_message: 'Queued task completed' } }) + '\\n');
  }
});
`);
    chmodSync(executable, 0o755);

    const bridge = Bun.spawn(
      [process.execPath, path.join(import.meta.dir, "codex-desktop-bridge.cjs"), "queue", threadId, submissionId],
      {
        stdin: new TextEncoder().encode("Wait, then run here"),
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...process.env,
          CODEX_HOME: fixtureHome,
          TALKIE_CODEX_EXECUTABLE: executable,
          FAKE_CODEX_ROLLOUT: rollout,
        },
      },
    );
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(bridge.stdout).text(),
      new Response(bridge.stderr).text(),
      bridge.exited,
    ]);

    expect(stderr).toBe("");
    expect(exitCode).toBe(0);
    const envelopes = stdout.trim().split("\n").map((line) => JSON.parse(line));
    expect(envelopes[0]).toMatchObject({ ok: true, phase: "accepted", delivery: "queued-turn" });
    expect(envelopes.at(-1)).toMatchObject({
      ok: true,
      threadId,
      turnId: "queued-turn-id",
      delivery: "queued-turn",
      response: "Queued task completed",
    });
  });
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

  test("observes a queued instruction when Desktop replaces its client id", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-queued-turn-"));
    const rollout = path.join(fixtureHome, "rollout.jsonl");
    writeFileSync(rollout, [
      { type: "event_msg", payload: { type: "task_started", turn_id: "unrelated-turn" } },
      { type: "event_msg", payload: { type: "user_message", message: "Desktop message" } },
      { type: "event_msg", payload: { type: "task_complete", turn_id: "unrelated-turn", last_agent_message: "Unrelated" } },
      { type: "event_msg", payload: { type: "task_started", turn_id: "talkie-turn" } },
      {
        type: "event_msg",
        payload: {
          type: "user_message",
          message: "Talkie queued message",
          client_id: "desktop-generated-client-id",
        },
      },
      { type: "event_msg", payload: { type: "task_complete", turn_id: "talkie-turn", last_agent_message: "Talkie response" } },
    ].map(JSON.stringify).join("\n") + "\n");

    await expect(waitForQueuedTurn(
      rollout,
      0,
      "Talkie queued message",
      0,
      "talkie-submission-id",
    )).resolves.toEqual({
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
