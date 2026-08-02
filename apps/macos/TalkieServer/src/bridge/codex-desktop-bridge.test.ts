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
  desktopSteerFailureCode,
  appendQueuedFollowUp,
  makeQueuedFollowUp,
  readQueuedFollowUps,
  readTurnActivity,
  remoteApprovalResponse,
  resolveDesktopTurnState,
  taskRolloutPath,
  withQueuedFollowUpMutationLock,
  waitForQueuedTurn,
} = require("./codex-desktop-bridge.cjs") as {
  desktopSteerFailureCode: (error: unknown) => string;
  appendQueuedFollowUp: (
    queued: Record<string, Array<Record<string, unknown>>>,
    taskId: string,
    message: Record<string, unknown>,
  ) => Record<string, Array<Record<string, unknown>>>;
  makeQueuedFollowUp: (text: string, state: Record<string, unknown>) => Record<string, any>;
  readQueuedFollowUps: () => Record<string, Array<Record<string, unknown>>>;
  readTurnActivity: (rolloutPath: string) => Record<string, unknown>;
  remoteApprovalResponse: (
    method: string,
    params: Record<string, any>,
    decision: "approve" | "decline",
  ) => Record<string, unknown>;
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

test("an ended Desktop steer is a recoverable inactive-turn race", () => {
  expect(desktopSteerFailureCode(
    "Cannot steer conversation because its active turn already ended",
  )).toBe("turn-not-active");
  expect(desktopSteerFailureCode("socket disconnected")).toBe("turn-steer-failed");
});

test("remote approval responses preserve Codex decision contracts", () => {
  expect(remoteApprovalResponse(
    "item/commandExecution/requestApproval",
    {},
    "approve",
  )).toEqual({ result: { decision: "accept" } });
  expect(remoteApprovalResponse(
    "item/fileChange/requestApproval",
    {},
    "decline",
  )).toEqual({ result: { decision: "decline" } });
  expect(remoteApprovalResponse(
    "item/permissions/requestApproval",
    { permissions: { network: { enabled: true }, fileSystem: null } },
    "approve",
  )).toEqual({
    result: {
      permissions: { network: { enabled: true } },
      scope: "turn",
    },
  });
  expect(remoteApprovalResponse(
    "execCommandApproval",
    {},
    "decline",
  )).toEqual({ result: { decision: "denied" } });
});

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

  test("ends a fresh submission when app-server reports an interrupted turn", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-app-server-interrupted-"));
    const threadId = "019fae56-598a-70b0-83dd-539cda1c7712";
    const submissionId = "019fae56-598a-70b0-83dd-539cda1c7713";
    const sessions = path.join(fixtureHome, "sessions", "2026", "07", "29");
    mkdirSync(sessions, { recursive: true });
    const rollout = path.join(sessions, `rollout-${threadId}.jsonl`);
    writeFileSync(rollout, "");
    const database = new Database(path.join(fixtureHome, "state_5.sqlite"));
    database.exec("CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL)");
    database.query("INSERT INTO threads (id, rollout_path) VALUES (?, ?)").run(threadId, rollout);
    database.close();

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
  if (message.method === 'thread/start') return send({ id: message.id, result: { thread: {
    id: process.env.FAKE_CODEX_THREAD_ID,
    cwd: message.params.cwd,
    preview: '',
    createdAt: 123,
  } } });
  if (message.method === 'turn/start') {
    send({ id: message.id, result: { turn: { id: 'interrupted-turn' } } });
    fs.appendFileSync(process.env.FAKE_CODEX_ROLLOUT,
      JSON.stringify({ type: 'event_msg', payload: { type: 'task_started', turn_id: 'interrupted-turn' } }) + '\\n' +
      JSON.stringify({ type: 'event_msg', payload: { type: 'user_message', message: message.params.input[0].text, client_id: message.params.clientUserMessageId } }) + '\\n');
    setTimeout(() => send({
      method: 'turn/completed',
      params: {
        threadId: process.env.FAKE_CODEX_THREAD_ID,
        turn: { id: 'interrupted-turn', status: 'interrupted', error: null },
      },
    }), 20);
  }
});
`);
    chmodSync(executable, 0o755);

    const bridge = Bun.spawn(
      [
        process.execPath,
        path.join(import.meta.dir, "codex-desktop-bridge.cjs"),
        "create-submit",
        fixtureHome,
        submissionId,
      ],
      {
        stdin: new TextEncoder().encode("Start, then interrupt this task"),
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...process.env,
          CODEX_HOME: fixtureHome,
          TALKIE_CODEX_EXECUTABLE: executable,
          TALKIE_CODEX_DISABLE_DESKTOP_REVEAL: "1",
          FAKE_CODEX_THREAD_ID: threadId,
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
    expect(exitCode).toBe(1);
    const envelopes = stdout.trim().split("\n").map((line) => JSON.parse(line));
    expect(envelopes[0]).toMatchObject({ ok: true, phase: "created", threadId });
    expect(envelopes[1]).toMatchObject({
      ok: true,
      phase: "accepted",
      threadId,
      turnId: "interrupted-turn",
    });
    expect(envelopes.at(-1)).toEqual({
      ok: false,
      code: "turn-interrupted",
      error: "The Codex turn was interrupted before it completed.",
    });
  });

  test("recovers an already interrupted durable submission without replaying it", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-app-server-recover-interrupted-"));
    const threadId = "019fae56-598a-70b0-83dd-539cda1c7714";
    const submissionId = "019fae56-598a-70b0-83dd-539cda1c7715";
    const sessions = path.join(fixtureHome, "sessions", "2026", "07", "29");
    mkdirSync(sessions, { recursive: true });
    const rollout = path.join(sessions, `rollout-${threadId}.jsonl`);
    const requestLog = path.join(fixtureHome, "requests.log");
    writeFileSync(
      rollout,
      [
        { type: "event_msg", payload: { type: "task_started", turn_id: "interrupted-turn" } },
        {
          type: "event_msg",
          payload: {
            type: "user_message",
            message: "Recover this interrupted task",
            client_id: submissionId,
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
    result: { thread: {
      id: message.params.threadId,
      path: process.env.FAKE_CODEX_ROLLOUT,
      status: { type: 'idle' },
      turns: [{ id: 'interrupted-turn', status: 'interrupted', error: null }],
    } },
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
        "submit",
        threadId,
        submissionId,
        "started-turn",
      ],
      {
        stdin: new TextEncoder().encode("Recover this interrupted task"),
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
    expect(exitCode).toBe(1);
    expect(existsSync(requestLog)).toBe(false);
    const envelopes = stdout.trim().split("\n").map((line) => JSON.parse(line));
    expect(envelopes[0]).toMatchObject({
      ok: true,
      phase: "accepted",
      threadId,
      turnId: "interrupted-turn",
    });
    expect(envelopes.at(-1)).toEqual({
      ok: false,
      code: "turn-interrupted",
      error: "The Codex turn was interrupted before it completed.",
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

describe.serial("Codex task creation and pagination", () => {
  test("creates the task and starts its first turn in one app-server lifetime", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-create-submit-"));
    const threadId = "019fae56-598a-70b0-83dd-539cda1c7710";
    const submissionId = "019fae56-598a-70b0-83dd-539cda1c7711";
    const sessions = path.join(fixtureHome, "sessions", "2026", "07", "29");
    mkdirSync(sessions, { recursive: true });
    const rollout = path.join(sessions, `rollout-${threadId}.jsonl`);
    const requestLog = path.join(fixtureHome, "requests.json");
    const openLog = path.join(fixtureHome, "open.json");
    writeFileSync(rollout, "");
    const database = new Database(path.join(fixtureHome, "state_5.sqlite"));
    database.exec("CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL)");
    database.query("INSERT INTO threads (id, rollout_path) VALUES (?, ?)").run(threadId, rollout);
    database.close();

    const executable = path.join(fixtureHome, "fake-codex.cjs");
    writeFileSync(executable, `#!/usr/bin/env node
const fs = require('node:fs');
const readline = require('node:readline');
const rl = readline.createInterface({ input: process.stdin });
const requests = [];
const send = (value) => process.stdout.write(JSON.stringify(value) + '\\n');
rl.on('line', (line) => {
  const message = JSON.parse(line);
  if (message.id === undefined) return;
  if (message.method === 'initialize') return send({ id: message.id, result: {} });
  requests.push({ method: message.method, params: message.params });
  fs.writeFileSync(process.env.FAKE_CODEX_REQUEST_LOG, JSON.stringify(requests));
  if (message.method === 'thread/start') return send({ id: message.id, result: { thread: {
    id: process.env.FAKE_CODEX_THREAD_ID,
    cwd: message.params.cwd,
    preview: '',
    createdAt: 123,
  } } });
  if (message.method === 'turn/start') {
    send({ id: message.id, result: { turn: { id: 'first-turn' } } });
    fs.appendFileSync(process.env.FAKE_CODEX_ROLLOUT,
      JSON.stringify({ type: 'event_msg', payload: { type: 'task_started', turn_id: 'first-turn' } }) + '\\n' +
      JSON.stringify({ type: 'event_msg', payload: { type: 'user_message', message: message.params.input[0].text, client_id: message.params.clientUserMessageId } }) + '\\n' +
      JSON.stringify({ type: 'event_msg', payload: { type: 'task_complete', turn_id: 'first-turn', last_agent_message: 'Fresh task completed' } }) + '\\n');
  }
});
`);
    chmodSync(executable, 0o755);

    const openExecutable = path.join(fixtureHome, "fake-open.cjs");
    writeFileSync(openExecutable, `#!/usr/bin/env node
const fs = require('node:fs');
fs.writeFileSync(process.env.FAKE_CODEX_OPEN_LOG, JSON.stringify(process.argv.slice(2)));
`);
    chmodSync(openExecutable, 0o755);

    const bridge = Bun.spawn(
      [
        process.execPath,
        path.join(import.meta.dir, "codex-desktop-bridge.cjs"),
        "create-submit",
        fixtureHome,
        submissionId,
      ],
      {
        stdin: new TextEncoder().encode("Start this fresh task"),
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...process.env,
          CODEX_HOME: fixtureHome,
          TALKIE_CODEX_EXECUTABLE: executable,
          FAKE_CODEX_THREAD_ID: threadId,
          FAKE_CODEX_ROLLOUT: rollout,
          FAKE_CODEX_REQUEST_LOG: requestLog,
          FAKE_CODEX_OPEN_LOG: openLog,
          TALKIE_CODEX_OPEN_EXECUTABLE: openExecutable,
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
    expect(envelopes[0]).toMatchObject({
      ok: true,
      phase: "created",
      threadId,
      task: { id: threadId, cwd: fixtureHome },
    });
    expect(envelopes[1]).toMatchObject({
      ok: true,
      phase: "accepted",
      threadId,
      turnId: "first-turn",
      delivery: "started-turn",
      task: { id: threadId, cwd: fixtureHome },
    });
    expect(envelopes.at(-1)).toMatchObject({
      ok: true,
      threadId,
      turnId: "first-turn",
      delivery: "started-turn",
      response: "Fresh task completed",
    });
    expect(JSON.parse(readFileSync(requestLog, "utf8"))).toEqual([
      { method: "thread/start", params: { cwd: fixtureHome } },
      {
        method: "turn/start",
        params: {
          threadId,
          input: [{ type: "text", text: "Start this fresh task" }],
          clientUserMessageId: submissionId,
        },
      },
    ]);
    for (let attempt = 0; attempt < 50 && !existsSync(openLog); attempt += 1) {
      await Bun.sleep(10);
    }
    expect(JSON.parse(readFileSync(openLog, "utf8"))).toEqual([
      "-g",
      `codex://threads/${threadId}`,
    ]);
  });

  test("creates a task with cwd and no Codex configuration overrides", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-create-"));
    const requestLog = path.join(fixtureHome, "request.json");
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
  if (message.method === 'thread/start') {
    fs.writeFileSync(process.env.FAKE_CODEX_REQUEST_LOG, JSON.stringify(message.params));
    return send({ id: message.id, result: { thread: {
      id: 'created-task',
      cwd: message.params.cwd,
      preview: '',
      createdAt: 123,
      gitInfo: { branch: 'master', originUrl: 'https://github.com/arach/talkie.git' },
    } } });
  }
});
`);
    chmodSync(executable, 0o755);

    const bridge = Bun.spawn(
      [process.execPath, path.join(import.meta.dir, "codex-desktop-bridge.cjs"), "create", fixtureHome],
      {
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...process.env,
          CODEX_HOME: fixtureHome,
          TALKIE_CODEX_EXECUTABLE: executable,
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
    expect(JSON.parse(readFileSync(requestLog, "utf8"))).toEqual({ cwd: fixtureHome });
    expect(JSON.parse(stdout.trim())).toEqual({
      ok: true,
      task: {
        id: "created-task",
        title: "New task",
        preview: "",
        cwd: fixtureHome,
        project: "talkie",
        gitBranch: "master",
        gitOriginURL: "https://github.com/arach/talkie.git",
        updatedAt: 123,
      },
    });
  });

  test("passes opaque cursors and skips internal-only pages without losing the next page", async () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-list-"));
    const requestLog = path.join(fixtureHome, "requests.jsonl");
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
  if (message.method !== 'thread/list') return;
  fs.appendFileSync(process.env.FAKE_CODEX_REQUEST_LOG, JSON.stringify(message.params) + '\\n');
  if (!message.params.cursor) return send({ id: message.id, result: {
    data: [{ id: 'delegated', preview: '<codex_delegation>internal</codex_delegation>', cwd: '/tmp' }],
    nextCursor: 'opaque-page-2',
  } });
  return send({ id: message.id, result: {
    data: [{
      id: 'user-task', name: 'Ship it', preview: 'Finish the feature',
      cwd: '/Users/arach/dev/talkie', updatedAt: 456,
      gitInfo: { branch: 'master', originUrl: 'https://github.com/arach/talkie.git' },
    }],
    nextCursor: 'opaque-page-3',
  } });
});
`);
    chmodSync(executable, 0o755);

    const bridge = Bun.spawn(
      [process.execPath, path.join(import.meta.dir, "codex-desktop-bridge.cjs"), "list", "2"],
      {
        stdout: "pipe",
        stderr: "pipe",
        env: {
          ...process.env,
          CODEX_HOME: fixtureHome,
          TALKIE_CODEX_EXECUTABLE: executable,
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
    const requests = readFileSync(requestLog, "utf8").trim().split("\n").map(JSON.parse);
    expect(requests).toEqual([
      {
        limit: 2,
        sortKey: "recency_at",
        sortDirection: "desc",
        sourceKinds: ["cli", "vscode", "appServer"],
      },
      {
        limit: 2,
        sortKey: "recency_at",
        sortDirection: "desc",
        sourceKinds: ["cli", "vscode", "appServer"],
        cursor: "opaque-page-2",
      },
    ]);
    expect(JSON.parse(stdout.trim())).toMatchObject({
      ok: true,
      tasks: [{ id: "user-task", title: "Ship it", project: "talkie" }],
      nextCursor: "opaque-page-3",
    });
  });
});

describe.serial("Codex task catalog", () => {
  test("returns only public commentary and technical completion signals", () => {
    fixtureHome = mkdtempSync(path.join(tmpdir(), "talkie-codex-activity-"));
    const taskId = "019fa94d-8b11-7030-a252-5debffd976ae";
    const sessions = path.join(fixtureHome, "sessions", "2026", "07", "28");
    mkdirSync(sessions, { recursive: true });
    process.env.CODEX_HOME = fixtureHome;
    const rollout = path.join(sessions, `rollout-${taskId}.jsonl`);
    writeFileSync(rollout, [
      { type: "event_msg", timestamp: "2026-07-28T10:00:00Z", payload: { type: "task_started", turn_id: "turn-1" } },
      { type: "response_item", timestamp: "2026-07-28T10:00:00Z", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "Please fix the host signal." }] } },
      { type: "response_item", timestamp: "2026-07-28T10:00:00Z", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "<environment_context>private metadata</environment_context>" }] } },
      { type: "response_item", payload: { type: "reasoning", summary: "private" } },
      { type: "event_msg", timestamp: "2026-07-28T10:00:01Z", payload: { type: "agent_reasoning", text: "private" } },
      { type: "event_msg", timestamp: "2026-07-28T10:00:02Z", payload: { type: "agent_message", phase: "commentary", message: "Tracing the host signal." } },
      { type: "event_msg", timestamp: "2026-07-28T10:00:03Z", payload: { type: "patch_apply_end", turn_id: "turn-1", success: true } },
      { type: "event_msg", timestamp: "2026-07-28T10:00:04Z", payload: { type: "agent_message", phase: "final_answer", message: "The host signal is fixed." } },
      { type: "event_msg", timestamp: "2026-07-28T10:00:05Z", payload: { type: "task_complete", turn_id: "turn-1", last_agent_message: "The host signal is fixed.", duration_ms: 5_000 } },
      { type: "event_msg", timestamp: "2026-07-28T10:01:00Z", payload: { type: "task_started", turn_id: "turn-2" } },
      { type: "event_msg", timestamp: "2026-07-28T10:01:01Z", payload: { type: "agent_message", phase: "commentary", message: "Verifying the phone." } },
    ].map(JSON.stringify).join("\n") + "\n");

    const database = new Database(path.join(fixtureHome, "state_5.sqlite"), { create: true });
    database.exec("CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL);");
    database.prepare("INSERT INTO threads VALUES (?, ?)").run(taskId, rollout);
    database.close();

    expect(taskRolloutPath(taskId)).toBe(rollout);
    expect(readTurnActivity(rollout)).toEqual({
      ok: true,
      active: true,
      turnId: "turn-2",
      updates: [
        {
          id: "2026-07-28T10:01:01Z-1",
          kind: "commentary",
          text: "Verifying the phone.",
          timestamp: "2026-07-28T10:01:01Z",
        },
      ],
      history: [
        {
          id: "turn-1",
          status: "completed",
          startedAt: "2026-07-28T10:00:00Z",
          completedAt: "2026-07-28T10:00:05Z",
          durationMs: 5_000,
          instructions: ["Please fix the host signal."],
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
          response: "The host signal is fixed.",
        },
      ],
    });
    expect(JSON.stringify(readTurnActivity(rollout))).not.toContain("private");
    expect(JSON.stringify(readTurnActivity(rollout))).not.toContain("environment_context");
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
