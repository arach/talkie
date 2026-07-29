#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const { execFileSync, spawn } = require('node:child_process');

const MAX_FRAME_BYTES = 256 * 1024 * 1024;
const FOLLOW_VERSION = 1;
const STREAM_VERSION = 11;
const START_TURN_VERSION = 1;
const STEER_TURN_VERSION = 1;
const QUEUED_FOLLOW_UPS_VERSION = 1;
const SNAPSHOT_TIMEOUT_MS = 5_000;
const QUEUE_MUTATION_LOCK_TIMEOUT_MS = 10_000;
const TURN_TIMEOUT_MS = 30 * 60_000;
const QUEUED_TURN_TIMEOUT_MS = 60 * 60_000;
const APP_SERVER_REQUEST_TIMEOUT_MS = 30_000;

const CODEX_EXECUTABLE_CANDIDATES = [
  process.env.TALKIE_CODEX_EXECUTABLE,
  '/Applications/ChatGPT.app/Contents/Resources/codex',
  '/Applications/Codex.app/Contents/Resources/codex',
  path.join(os.homedir(), 'Applications', 'ChatGPT.app', 'Contents', 'Resources', 'codex'),
  '/opt/homebrew/bin/codex',
  '/usr/local/bin/codex',
].filter(Boolean);

function codexHome() {
  return process.env.CODEX_HOME || path.join(os.homedir(), '.codex');
}

function writeResult(result) {
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

function fail(message, code = 'bridge-failed') {
  const error = new Error(message);
  error.code = code;
  throw error;
}

function listTasks(limit) {
  const database = path.join(codexHome(), 'state_5.sqlite');
  if (!fs.existsSync(database)) {
    fail('Codex task catalog is unavailable.', 'catalog-unavailable');
  }
  const boundedLimit = Math.max(1, Math.min(Number(limit) || 50, 100));
  const query = `
    SELECT
      state.id AS id,
      COALESCE(
        NULLIF(SUBSTR(REPLACE(state.name, CHAR(10), ' '), 1, 120), ''),
        NULLIF(SUBSTR(REPLACE(state.title, CHAR(10), ' '), 1, 120), ''),
        NULLIF(SUBSTR(REPLACE(state.first_user_message, CHAR(10), ' '), 1, 96), ''),
        NULLIF(SUBSTR(REPLACE(state.preview, CHAR(10), ' '), 1, 96), ''),
        'Untitled task'
      ) AS title,
      SUBSTR(REPLACE(COALESCE(state.preview, ''), CHAR(10), ' '), 1, 280) AS preview,
      state.cwd AS cwd,
      state.git_branch AS gitBranch,
      state.git_origin_url AS gitOriginURL,
      CASE WHEN state.updated_at_ms > 0 THEN state.updated_at_ms / 1000.0 ELSE state.updated_at END AS updatedAt
    FROM threads AS state
    WHERE
      state.archived = 0
      AND COALESCE(state.preview, '') <> ''
      AND COALESCE(state.agent_role, '') <> 'subagent'
      AND COALESCE(state.thread_source, 'user') IN ('', 'user')
      AND COALESCE(state.first_user_message, '') NOT LIKE '<codex_delegation>%'
      AND COALESCE(state.first_user_message, '') NOT LIKE '<realtime_delegation>%'
      AND COALESCE(state.first_user_message, '') NOT LIKE '[Base]%'
    ORDER BY state.recency_at_ms DESC, state.updated_at_ms DESC
    LIMIT ${boundedLimit};
  `;
  const output = execFileSync('/usr/bin/sqlite3', ['-readonly', '-json', database, query], {
    encoding: 'utf8',
    maxBuffer: 8 * 1024 * 1024,
  });
  return JSON.parse(output || '[]').map((task) => ({
    ...task,
    project: projectName(task.gitOriginURL, task.cwd),
  }));
}

/** A stable, human project label. Git origin wins over generated worktree names. */
function projectName(gitOriginURL, cwd) {
  if (typeof gitOriginURL === 'string' && gitOriginURL.trim()) {
    const withoutSuffix = gitOriginURL.trim().replace(/\/+$/, '').replace(/\.git$/, '');
    const repository = withoutSuffix.split(/[/:]/).pop();
    if (repository) return repository;
  }
  return path.basename(cwd || '') || cwd || 'Unknown project';
}

function assertPrivateCodexSocket(socketPath) {
  const socket = fs.lstatSync(socketPath);
  const directory = fs.lstatSync(path.dirname(socketPath));
  if (!socket.isSocket() || socket.uid !== process.getuid()) {
    fail('Codex Desktop IPC socket is not owned by this user.', 'unsafe-socket');
  }
  if (!directory.isDirectory() || directory.uid !== process.getuid() || (directory.mode & 0o022) !== 0) {
    fail('Codex Desktop IPC directory is not private.', 'unsafe-socket');
  }
}

function assertRolloutPath(rolloutPath, threadId) {
  const sessionsRoot = path.resolve(codexHome(), 'sessions');
  const resolved = path.resolve(rolloutPath);
  if (!resolved.startsWith(`${sessionsRoot}${path.sep}`) || !path.basename(resolved).includes(threadId)) {
    fail('Codex Desktop returned an unsafe task transcript path.', 'unsafe-rollout-path');
  }
  const info = fs.lstatSync(resolved);
  if (!info.isFile() || info.isSymbolicLink() || info.uid !== process.getuid()) {
    fail('Codex task transcript is not a private user-owned file.', 'unsafe-rollout-path');
  }
  return resolved;
}

function readQueuedFollowUps() {
  const statePath = path.join(codexHome(), '.codex-global-state.json');
  let info;
  try {
    info = fs.lstatSync(statePath);
  } catch (error) {
    if (error?.code === 'ENOENT') return {};
    throw error;
  }
  if (
    !info.isFile() ||
    info.isSymbolicLink() ||
    info.uid !== process.getuid() ||
    (info.mode & 0o022) !== 0
  ) {
    fail('Codex Desktop global state is not a private user-owned file.', 'unsafe-global-state');
  }
  if (info.size > 32 * 1024 * 1024) {
    fail('Codex Desktop global state is unexpectedly large.', 'unsafe-global-state');
  }

  let state;
  try {
    state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  } catch {
    fail('Codex Desktop global state is unreadable.', 'protocol-mismatch');
  }
  const queued = state?.['queued-follow-ups'] ?? {};
  if (!queued || typeof queued !== 'object' || Array.isArray(queued)) {
    fail('Codex Desktop queued follow-ups state is unreadable.', 'protocol-mismatch');
  }
  for (const messages of Object.values(queued)) {
    if (!Array.isArray(messages)) {
      fail('Codex Desktop queued follow-ups state is unreadable.', 'protocol-mismatch');
    }
  }
  return queued;
}

function appendQueuedFollowUp(queued, threadId, message) {
  const existing = queued[threadId] ?? [];
  if (!Array.isArray(existing)) {
    fail('Codex Desktop queued follow-ups state is unreadable.', 'protocol-mismatch');
  }
  return {
    ...queued,
    [threadId]: [...existing, message],
  };
}

function queuedTextPredecessorCount(queued, threadId, text) {
  const normalizedText = text.trim();
  return (queued[threadId] || []).filter(
    (message) => String(message?.text || '').trim() === normalizedText,
  ).length;
}

async function withQueuedFollowUpMutationLock(threadId, action) {
  const lockDirectory = path.join(codexHome(), '.talkie-queue-locks');
  fs.mkdirSync(lockDirectory, { recursive: true, mode: 0o700 });
  const directoryInfo = fs.lstatSync(lockDirectory);
  if (
    !directoryInfo.isDirectory() ||
    directoryInfo.isSymbolicLink() ||
    directoryInfo.uid !== process.getuid() ||
    (directoryInfo.mode & 0o077) !== 0
  ) {
    fail('Talkie queue lock storage is not private.', 'unsafe-queue-lock');
  }

  const digest = createHash('sha256').update(threadId).digest('hex');
  const lockPath = path.join(lockDirectory, `${digest}.lock`);
  const deadline = Date.now() + QUEUE_MUTATION_LOCK_TIMEOUT_MS;
  let descriptor;
  while (Date.now() < deadline) {
    try {
      descriptor = fs.openSync(lockPath, 'wx', 0o600);
      fs.writeFileSync(descriptor, `${process.pid}\n`, 'utf8');
      break;
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      await sleep(25);
    }
  }
  if (descriptor === undefined) {
    fail('Timed out while another Talkie message updated this Codex queue.', 'queue-lock-timeout');
  }

  try {
    return await action();
  } finally {
    fs.closeSync(descriptor);
    try {
      fs.unlinkSync(lockPath);
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
  }
}

function makeQueuedFollowUp(text, state, clientUserMessageId = randomUUID()) {
  return {
    id: clientUserMessageId,
    text,
    context: {
      addedFiles: [],
      prompt: text,
      ideContext: null,
      imageAttachments: [],
      fileAttachments: [],
      commentAttachments: [],
      pullRequestChecks: [],
      reviewFindings: [],
      workspaceRoots: state.cwd ? [state.cwd] : [],
      collaborationMode: state.latestCollaborationMode || null,
      pastedTextAttachments: [],
      appshotContexts: [],
      mcpAppModelContextAttachments: [],
    },
    cwd: state.cwd || '/',
    createdAt: Date.now(),
  };
}

function normalizeClientUserMessageId(value) {
  if (value === undefined || value === null || value === '') return randomUUID();
  const normalized = String(value).trim();
  if (!/^[0-9a-f-]{36}$/i.test(normalized)) {
    fail('The Talkie submission id is invalid.', 'invalid-submission-id');
  }
  return normalized;
}

function normalizeKnownDelivery(value) {
  if (value === undefined || value === null || value === '') return null;
  if (!['started-turn', 'queued-turn', 'steered-active-turn'].includes(value)) {
    fail('The prior Talkie delivery is invalid.', 'protocol-mismatch');
  }
  return value;
}

function existingQueuedFollowUp(queued, threadId, clientUserMessageId) {
  const messages = queued[threadId] || [];
  const index = messages.findIndex((message) => message?.id === clientUserMessageId);
  if (index < 0) return null;
  const message = messages[index];
  const matchingPredecessors = messages
    .slice(0, index)
    .filter((candidate) => String(candidate?.text || '').trim() === String(message?.text || '').trim())
    .length;
  return { message, matchingPredecessors };
}

function codexExecutable() {
  for (const candidate of CODEX_EXECUTABLE_CANDIDATES) {
    try {
      const resolved = fs.realpathSync(candidate);
      const info = fs.lstatSync(resolved);
      if (!info.isFile() || ![0, process.getuid()].includes(info.uid) || (info.mode & 0o022) !== 0) {
        continue;
      }
      fs.accessSync(resolved, fs.constants.X_OK);
      return resolved;
    } catch {
      // Keep looking. A standalone Codex install is optional when Desktop owns
      // the selected task, so missing candidates are expected.
    }
  }
  fail('Codex app-server is unavailable. Install or update Codex, then retry.', 'app-server-unavailable');
}

function latestActiveTurnId(rolloutPath) {
  const size = fs.statSync(rolloutPath).size;
  const maximumScan = 32 * 1024 * 1024;
  const start = Math.max(0, size - maximumScan);
  const descriptor = fs.openSync(rolloutPath, 'r');
  let text;
  try {
    const data = Buffer.allocUnsafe(size - start);
    fs.readSync(descriptor, data, 0, data.length, start);
    text = data.toString('utf8');
  } finally {
    fs.closeSync(descriptor);
  }
  if (start > 0) text = text.slice(text.indexOf('\n') + 1);

  const activeTurnIds = [];
  for (const line of text.split('\n')) {
    if (!line) continue;
    let record;
    try { record = JSON.parse(line); } catch { continue; }
    const payload = record?.type === 'event_msg' ? record.payload : null;
    if (payload?.type === 'task_started' && typeof payload.turn_id === 'string') {
      const existingIndex = activeTurnIds.indexOf(payload.turn_id);
      if (existingIndex >= 0) activeTurnIds.splice(existingIndex, 1);
      activeTurnIds.push(payload.turn_id);
    } else if (
      ['task_complete', 'task_failed', 'turn_aborted'].includes(payload?.type) &&
      typeof payload?.turn_id === 'string'
    ) {
      const completedIndex = activeTurnIds.indexOf(payload.turn_id);
      if (completedIndex >= 0) activeTurnIds.splice(completedIndex, 1);
    }
  }
  return activeTurnIds.at(-1) ?? null;
}

function findSubmissionTurn(rolloutPath, clientUserMessageId, expectedText, allowTextFallback = false) {
  const size = fs.statSync(rolloutPath).size;
  const maximumScan = 32 * 1024 * 1024;
  const scanStart = Math.max(0, size - maximumScan);
  const descriptor = fs.openSync(rolloutPath, 'r');
  let text;
  try {
    const data = Buffer.allocUnsafe(size - scanStart);
    fs.readSync(descriptor, data, 0, data.length, scanStart);
    text = data.toString('utf8');
  } finally {
    fs.closeSync(descriptor);
  }
  if (scanStart > 0) text = text.slice(text.indexOf('\n') + 1);

  let latestStartedTurnId = null;
  let userMessageOrdinal = 0;
  let match = null;
  for (const line of text.split('\n')) {
    if (!line) continue;
    let record;
    try { record = JSON.parse(line); } catch { continue; }
    const payload = record?.type === 'event_msg' ? record.payload : null;
    if (!payload) continue;
    if (payload.type === 'task_started' && typeof payload.turn_id === 'string') {
      latestStartedTurnId = payload.turn_id;
      userMessageOrdinal = 0;
      continue;
    }
    if (payload.type === 'user_message' && latestStartedTurnId) {
      userMessageOrdinal += 1;
      if (
        payload.client_id === clientUserMessageId ||
        (allowTextFallback && String(payload.message || '').trim() === expectedText.trim())
      ) {
        match = {
          turnId: latestStartedTurnId,
          text: String(payload.message || '').trim(),
          userMessageOrdinal,
          status: 'active',
          response: null,
          scanStart,
        };
      }
      continue;
    }
    if (!match || payload.turn_id !== match.turnId) continue;
    if (payload.type === 'task_complete') {
      match.status = 'completed';
      match.response = String(payload.last_agent_message || '').trim();
    } else if (payload.type === 'task_failed' || payload.type === 'turn_aborted') {
      match.status = 'failed';
      match.response = String(payload.message || '').trim();
    }
  }
  return match;
}

async function reconcileExistingSubmission(
  rolloutPath,
  threadId,
  command,
  text,
  clientUserMessageId,
  knownDelivery,
  onAccepted,
  blockingError,
) {
  // Codex Desktop currently assigns a fresh client_id when it promotes a
  // queued follow-up into a turn. For a durable queued receipt, the exact text
  // is therefore the only rollout correlation that survives a bridge restart.
  const match = findSubmissionTurn(
    rolloutPath,
    clientUserMessageId,
    text,
    knownDelivery === 'queued-turn',
  );
  if (!match) return null;
  if (match.text !== text.trim()) {
    fail('The Talkie submission id already belongs to another message.', 'submission-conflict');
  }

  const inferredDelivery = command === 'steer' || match.userMessageOrdinal > 1
    ? 'steered-active-turn'
    : command === 'queue'
      ? 'queued-turn'
      : 'started-turn';
  const delivery = knownDelivery || inferredDelivery;
  const accepted = acceptedDisposition(threadId, delivery, command, match.turnId);
  onAccepted?.(accepted);
  if (delivery === 'steered-active-turn') return accepted;
  if (match.status === 'failed') {
    fail(match.response || 'The existing Codex turn failed.', 'turn-failed');
  }
  const response = match.status === 'completed'
    ? match.response
    : await waitForTurn(
        rolloutPath,
        match.scanStart,
        match.turnId,
        blockingError,
      );
  if (!response) fail('Codex completed without a final answer.', 'empty-response');
  return {
    ok: true,
    threadId,
    turnId: match.turnId,
    delivery,
    requestedDelivery: command,
    response,
  };
}

function resolveDesktopTurnState(rolloutPath, snapshotRuntimeStatus) {
  const activeTurnId = latestActiveTurnId(rolloutPath);
  if (snapshotRuntimeStatus === 'active' && !activeTurnId) {
    fail('Codex Desktop reports an active task without a correlatable turn.', 'protocol-mismatch');
  }
  return {
    activeTurnId,
    decision: {
      snapshotRuntimeStatus: snapshotRuntimeStatus || 'unknown',
      rolloutActiveTurnId: activeTurnId,
    },
  };
}

function taskRolloutPath(threadId) {
  if (!/^[0-9a-f-]{36}$/i.test(threadId)) {
    fail('The Codex task id is invalid.', 'invalid-task-id');
  }
  const database = path.join(codexHome(), 'state_5.sqlite');
  if (!fs.existsSync(database)) {
    fail('Codex task catalog is unavailable.', 'catalog-unavailable');
  }
  const query = `SELECT rollout_path FROM threads WHERE id = '${threadId}' LIMIT 1;`;
  const rolloutPath = execFileSync('/usr/bin/sqlite3', ['-readonly', database, query], {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  }).trim();
  if (!rolloutPath) fail('The selected Codex task no longer exists.', 'stale-thread');
  return assertRolloutPath(rolloutPath, threadId);
}

/**
 * Reads only user-visible progress from the active turn. Commentary is the
 * same assistant text Codex Desktop presents during work; reasoning records
 * are deliberately ignored and never cross the bridge.
 */
function readTurnActivity(rolloutPath) {
  const size = fs.statSync(rolloutPath).size;
  const maximumScan = 32 * 1024 * 1024;
  const start = Math.max(0, size - maximumScan);
  const descriptor = fs.openSync(rolloutPath, 'r');
  let text;
  try {
    const data = Buffer.allocUnsafe(size - start);
    fs.readSync(descriptor, data, 0, data.length, start);
    text = data.toString('utf8');
  } finally {
    fs.closeSync(descriptor);
  }
  if (start > 0) text = text.slice(text.indexOf('\n') + 1);

  let turnId = null;
  let updates = [];
  let ordinal = 0;
  for (const line of text.split('\n')) {
    if (!line) continue;
    let record;
    try { record = JSON.parse(line); } catch { continue; }
    const payload = record?.type === 'event_msg' ? record.payload : null;
    if (payload?.type === 'task_started' && typeof payload.turn_id === 'string') {
      turnId = payload.turn_id;
      updates = [];
      ordinal = 0;
      continue;
    }
    if (!turnId || !payload) continue;

    if (payload.type === 'agent_message' && payload.phase === 'commentary') {
      const message = String(payload.message || '').trim();
      if (message) {
        ordinal += 1;
        updates.push({
          id: `${record.timestamp || 'progress'}-${ordinal}`,
          kind: 'commentary',
          text: message,
          timestamp: record.timestamp || null,
        });
      }
      continue;
    }

    if (payload.turn_id === turnId && payload.type === 'patch_apply_end' && payload.success) {
      ordinal += 1;
      updates.push({
        id: `${record.timestamp || 'patch'}-${ordinal}`,
        kind: 'tool',
        text: 'PATCH APPLIED',
        timestamp: record.timestamp || null,
      });
      continue;
    }

    if (payload.turn_id === turnId && payload.type === 'mcp_tool_call_end') {
      const tool = String(payload.invocation?.tool || payload.invocation?.server || 'TOOL')
        .replaceAll('_', ' ')
        .trim()
        .toUpperCase();
      ordinal += 1;
      updates.push({
        id: `${record.timestamp || 'tool'}-${ordinal}`,
        kind: 'tool',
        text: `${tool} COMPLETE`,
        timestamp: record.timestamp || null,
      });
      continue;
    }

    if (
      ['task_complete', 'task_failed', 'turn_aborted'].includes(payload.type) &&
      payload.turn_id === turnId
    ) {
      turnId = null;
      updates = [];
    }
  }

  return {
    ok: true,
    active: Boolean(turnId),
    turnId,
    updates: updates.slice(-4),
  };
}

function frame(message) {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  if (body.length === 0 || body.length > MAX_FRAME_BYTES) fail('Desktop IPC message is too large.');
  const output = Buffer.allocUnsafe(body.length + 4);
  output.writeUInt32LE(body.length, 0);
  body.copy(output, 4);
  return output;
}

class DesktopIPCClient {
  constructor(threadId) {
    this.threadId = threadId;
    this.socketPath = path.join(codexHome(), 'ipc', 'ipc.sock');
    this.clientId = 'initializing-client';
    this.ownerClientId = null;
    this.socket = null;
    this.buffer = Buffer.alloc(0);
    this.pending = new Map();
    this.snapshotWaiter = null;
  }

  async connect() {
    assertPrivateCodexSocket(this.socketPath);
    this.socket = net.connect(this.socketPath);
    this.socket.on('data', (chunk) => this.onData(chunk));
    this.socket.on('error', (error) => this.rejectAll(error));
    this.socket.on('close', () => this.rejectAll(new Error('Codex Desktop IPC connection closed.')));
    await new Promise((resolve, reject) => {
      this.socket.once('connect', resolve);
      this.socket.once('error', reject);
    });
    const initialized = await this.request('initialize', { clientType: 'speakeasy' }, {
      allowUninitialized: true,
      version: 0,
      timeoutMs: SNAPSHOT_TIMEOUT_MS,
    });
    if (initialized.resultType !== 'success' || typeof initialized.result?.clientId !== 'string') {
      fail('Codex Desktop rejected the Talkie bridge.', 'desktop-unavailable');
    }
    this.clientId = initialized.result.clientId;
  }

  async follow() {
    const snapshotPromise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.snapshotWaiter = null;
        reject(Object.assign(
          new Error('Open this task in Codex Desktop, then try the hotkey again.'),
          { code: 'task-owner-unavailable' },
        ));
      }, SNAPSHOT_TIMEOUT_MS);
      this.snapshotWaiter = {
        resolve: (snapshot) => {
          clearTimeout(timer);
          this.snapshotWaiter = null;
          resolve(snapshot);
        },
        reject,
      };
    });
    this.broadcast('thread-stream-following-changed', {
      conversationId: this.threadId,
      hostId: 'local',
      following: true,
    }, FOLLOW_VERSION);
    return snapshotPromise;
  }

  async startTurn(text, ownerClientId, clientUserMessageId) {
    const response = await this.request('thread-follower-start-turn', {
      conversationId: this.threadId,
      turnStartParams: {
        input: [{ type: 'text', text, text_elements: [] }],
        attachments: [],
        clientUserMessageId,
      },
    }, {
      targetClientId: ownerClientId,
      version: START_TURN_VERSION,
      timeoutMs: 30_000,
    });
    if (response.resultType !== 'success') {
      fail(`Codex Desktop could not start the turn: ${response.error || 'unknown error'}`, 'turn-start-failed');
    }
    const turnId = response.result?.result?.turn?.id;
    if (typeof turnId !== 'string' || turnId.length === 0) {
      fail('Codex Desktop returned an unreadable turn response.', 'protocol-mismatch');
    }
    return turnId;
  }

  async steerTurn(text, ownerClientId, state, clientUserMessageId) {
    const context = {
      prompt: text,
      workspaceRoots: state.cwd ? [state.cwd] : [],
      collaborationMode: state.latestCollaborationMode || null,
      commentAttachments: [],
      imageAttachments: [],
      fileAttachments: [],
      pastedTextAttachments: [],
      addedFiles: [],
      appshotContexts: [],
      mcpAppModelContextAttachments: [],
    };
    const response = await this.request('thread-follower-steer-turn', {
      conversationId: this.threadId,
      input: [{ type: 'text', text, text_elements: [] }],
      restoreMessage: {
        id: clientUserMessageId,
        text,
        context,
        cwd: state.cwd || '/',
        createdAt: Date.now(),
      },
      serviceTier: null,
      attachments: [],
      clientUserMessageId,
    }, {
      targetClientId: ownerClientId,
      version: STEER_TURN_VERSION,
      timeoutMs: 30_000,
    });
    if (response.resultType !== 'success') {
      fail(`Codex Desktop could not steer the active turn: ${response.error || 'unknown error'}`, 'turn-steer-failed');
    }
  }

  async queueTurn(text, ownerClientId, state, clientUserMessageId) {
    const existing = readQueuedFollowUps();
    const queuedBefore = existingQueuedFollowUp(existing, this.threadId, clientUserMessageId);
    if (queuedBefore) {
      if (String(queuedBefore.message?.text || '').trim() !== text.trim()) {
        fail('The Talkie submission id already belongs to another message.', 'submission-conflict');
      }
      return { messageId: clientUserMessageId, matchingPredecessors: queuedBefore.matchingPredecessors };
    }
    const message = makeQueuedFollowUp(text, state, clientUserMessageId);
    const matchingPredecessors = queuedTextPredecessorCount(existing, this.threadId, text);
    const queued = appendQueuedFollowUp(existing, this.threadId, message);
    const response = await this.request('thread-follower-set-queued-follow-ups-state', {
      conversationId: this.threadId,
      state: queued,
    }, {
      targetClientId: ownerClientId,
      version: QUEUED_FOLLOW_UPS_VERSION,
      timeoutMs: 30_000,
    });
    if (response.resultType !== 'success') {
      fail(`Codex Desktop could not queue the follow-up: ${response.error || 'unknown error'}`, 'turn-queue-failed');
    }
    return { messageId: message.id, matchingPredecessors };
  }

  broadcast(method, params, version) {
    this.send({
      type: 'broadcast',
      method,
      sourceClientId: this.clientId,
      params,
      version,
    });
  }

  request(method, params, options = {}) {
    if (!options.allowUninitialized && this.clientId === 'initializing-client') {
      fail('Desktop IPC client is not initialized.', 'desktop-unavailable');
    }
    const requestId = randomUUID();
    const timeoutMs = options.timeoutMs || 5_000;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        reject(Object.assign(new Error(`Timed out waiting for ${method}.`), { code: 'desktop-timeout' }));
      }, timeoutMs);
      this.pending.set(requestId, { resolve, reject, timer });
      this.send({
        type: 'request',
        requestId,
        sourceClientId: this.clientId,
        targetClientId: options.targetClientId,
        version: options.version || 0,
        method,
        params,
        timeoutMs,
      });
    });
  }

  send(message) {
    if (!this.socket?.writable) fail('Codex Desktop IPC is not connected.', 'desktop-unavailable');
    this.socket.write(frame(message));
  }

  onData(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    while (this.buffer.length >= 4) {
      const length = this.buffer.readUInt32LE(0);
      if (length === 0 || length > MAX_FRAME_BYTES) {
        this.rejectAll(new Error(`Invalid Desktop IPC frame length: ${length}`));
        this.socket?.destroy();
        return;
      }
      if (this.buffer.length < length + 4) return;
      const message = JSON.parse(this.buffer.subarray(4, length + 4).toString('utf8'));
      this.buffer = this.buffer.subarray(length + 4);
      this.onMessage(message);
    }
  }

  onMessage(message) {
    if (message.type === 'response') {
      const waiter = this.pending.get(message.requestId);
      if (waiter) {
        clearTimeout(waiter.timer);
        this.pending.delete(message.requestId);
        waiter.resolve(message);
      }
      return;
    }
    if (message.type !== 'broadcast' || message.method !== 'thread-stream-state-changed') return;
    if (message.version !== STREAM_VERSION) {
      this.snapshotWaiter?.reject(Object.assign(
        new Error('Codex Desktop task streaming protocol changed; update Talkie.'),
        { code: 'protocol-mismatch' },
      ));
      this.snapshotWaiter = null;
      return;
    }
    const { params } = message;
    if (
      params?.hostId !== 'local' ||
      params?.conversationId !== this.threadId ||
      params?.change?.type !== 'snapshot'
    ) return;
    this.ownerClientId = message.sourceClientId;
    this.snapshotWaiter?.resolve({
      ownerClientId: message.sourceClientId,
      state: params.change.conversationState,
    });
  }

  rejectAll(error) {
    for (const waiter of this.pending.values()) {
      clearTimeout(waiter.timer);
      waiter.reject(error);
    }
    this.pending.clear();
    this.snapshotWaiter?.reject(error);
    this.snapshotWaiter = null;
  }

  close() {
    if (this.clientId !== 'initializing-client' && this.socket?.writable) {
      this.broadcast('thread-stream-following-changed', {
        conversationId: this.threadId,
        hostId: 'local',
        following: false,
      }, FOLLOW_VERSION);
    }
    this.socket?.end();
  }
}

class AppServerClient {
  constructor() {
    this.process = null;
    this.stdoutBuffer = '';
    this.stderr = '';
    this.pending = new Map();
    this.nextRequestId = 1;
    this.closing = false;
    this.blockingError = null;
  }

  async connect() {
    const executable = codexExecutable();
    this.process = spawn(executable, ['app-server', '--listen', 'stdio://'], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: process.env,
    });
    this.process.stdout.setEncoding('utf8');
    this.process.stderr.setEncoding('utf8');
    this.process.stdout.on('data', (chunk) => this.onData(chunk));
    this.process.stderr.on('data', (chunk) => {
      this.stderr = `${this.stderr}${chunk}`.slice(-32 * 1024);
    });
    this.process.on('error', (error) => this.rejectAll(error));
    this.process.on('close', (code) => {
      if (!this.closing) {
        const detail = this.stderr.trim();
        this.rejectAll(Object.assign(
          new Error(detail || `Codex app-server exited with status ${code}.`),
          { code: 'app-server-unavailable' },
        ));
      }
    });
    await new Promise((resolve, reject) => {
      this.process.once('spawn', resolve);
      this.process.once('error', reject);
    });
    await this.request('initialize', {
      clientInfo: {
        name: 'talkie_command_deck',
        title: 'Talkie Command Deck',
        version: '1.0.0',
      },
    });
    this.notify('initialized', {});
  }

  async resume(threadId) {
    const result = await this.request('thread/resume', { threadId });
    const thread = result?.thread;
    if (!thread || thread.id !== threadId) {
      fail('Codex app-server returned the wrong task.', 'task-mismatch');
    }
    return { ...result, thread };
  }

  async startTurn(threadId, text, clientUserMessageId) {
    const result = await this.request('turn/start', {
      threadId,
      input: [{ type: 'text', text }],
      clientUserMessageId,
    });
    const turnId = result?.turn?.id;
    if (typeof turnId !== 'string' || turnId.length === 0) {
      fail('Codex app-server returned an unreadable turn response.', 'protocol-mismatch');
    }
    return turnId;
  }

  async steerTurn(threadId, expectedTurnId, text, clientUserMessageId) {
    const result = await this.request('turn/steer', {
      threadId,
      expectedTurnId,
      input: [{ type: 'text', text }],
      clientUserMessageId,
    });
    if (result?.turnId !== expectedTurnId) {
      fail('Codex app-server returned the wrong active turn.', 'protocol-mismatch');
    }
    return expectedTurnId;
  }

  request(method, params, timeoutMs = APP_SERVER_REQUEST_TIMEOUT_MS) {
    const id = this.nextRequestId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(Object.assign(new Error(`Timed out waiting for ${method}.`), { code: 'desktop-timeout' }));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer, method });
      this.send({ method, id, params });
    });
  }

  notify(method, params) {
    this.send({ method, params });
  }

  send(message) {
    if (!this.process?.stdin?.writable) {
      fail('Codex app-server is not connected.', 'app-server-unavailable');
    }
    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }

  onData(chunk) {
    this.stdoutBuffer += chunk;
    const lines = this.stdoutBuffer.split('\n');
    this.stdoutBuffer = lines.pop() || '';
    for (const line of lines) {
      if (!line.trim()) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        this.rejectAll(Object.assign(
          new Error('Codex app-server returned unreadable output.'),
          { code: 'protocol-mismatch' },
        ));
        continue;
      }
      if (message.id === undefined || message.method) {
        // Notifications are observed through the private transcript below. A
        // server-initiated approval request must never be approved by Talkie.
        if (message.id !== undefined && message.method) {
          this.blockingError = Object.assign(
            new Error('This Codex turn needs approval in Codex Desktop.'),
            { code: 'approval-required' },
          );
          this.rejectAll(this.blockingError);
        }
        continue;
      }
      const waiter = this.pending.get(message.id);
      if (!waiter) continue;
      clearTimeout(waiter.timer);
      this.pending.delete(message.id);
      if (message.error) {
        const messageText = message.error.message || `Codex app-server rejected ${waiter.method}.`;
        const serverCode = String(message.error.code || message.error.data?.code || '');
        const missingThread = waiter.method === 'thread/resume' && (
          /thread.*(?:not[ -]?found|does not exist|unknown)/i.test(messageText) ||
          /(?:not[ -]?found|does not exist|unknown).*thread/i.test(messageText) ||
          /thread.*not[ -]?found/i.test(serverCode)
        );
        waiter.reject(Object.assign(
          new Error(messageText),
          { code: missingThread ? 'stale-thread' : 'app-server-request-failed' },
        ));
      } else {
        waiter.resolve(message.result);
      }
    }
  }

  rejectAll(error) {
    for (const waiter of this.pending.values()) {
      clearTimeout(waiter.timer);
      waiter.reject(error);
    }
    this.pending.clear();
  }

  pendingBlockingError() {
    return this.blockingError;
  }

  close() {
    this.closing = true;
    this.rejectAll(new Error('Codex app-server connection closed.'));
    this.process?.stdin?.end();
    const process = this.process;
    const forceClose = setTimeout(() => process?.kill('SIGKILL'), 1_000);
    forceClose.unref?.();
  }
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function throwIfBlocked(blockingError) {
  const error = blockingError?.();
  if (error) throw error;
}

async function waitForTurn(rolloutPath, offset, turnId, blockingError) {
  const descriptor = fs.openSync(rolloutPath, 'r');
  let position = offset;
  let pending = '';
  const deadline = Date.now() + TURN_TIMEOUT_MS;
  try {
    while (Date.now() < deadline) {
      throwIfBlocked(blockingError);
      const size = fs.fstatSync(descriptor).size;
      if (size > position) {
        const chunk = Buffer.allocUnsafe(Math.min(size - position, 1024 * 1024));
        const count = fs.readSync(descriptor, chunk, 0, chunk.length, position);
        position += count;
        pending += chunk.subarray(0, count).toString('utf8');
        const lines = pending.split('\n');
        pending = lines.pop() || '';
        for (const line of lines) {
          if (!line) continue;
          let record;
          try { record = JSON.parse(line); } catch { continue; }
          const payload = record?.payload;
          if (record?.type !== 'event_msg' || !payload) continue;
          if (payload.type === 'task_complete' && payload.turn_id === turnId) {
            const response = String(payload.last_agent_message || '').trim();
            if (!response) fail('Codex completed without a final answer.', 'empty-response');
            return response;
          }
          if (
            (payload.type === 'task_failed' || payload.type === 'turn_aborted') &&
            payload.turn_id === turnId
          ) {
            fail(payload.message || 'The Codex turn failed.', 'turn-failed');
          }
        }
      }
      await sleep(150);
    }
  } finally {
    fs.closeSync(descriptor);
  }
  fail('Timed out waiting for the Codex response.', 'turn-timeout');
}

async function waitForQueuedTurn(
  rolloutPath,
  offset,
  text,
  matchingPredecessors = 0,
  clientUserMessageId = null,
  blockingError,
) {
  const descriptor = fs.openSync(rolloutPath, 'r');
  let position = offset;
  let pending = '';
  let latestStartedTurnId = null;
  let queuedTurnId = null;
  let remainingMatches = matchingPredecessors;
  const deadline = Date.now() + QUEUED_TURN_TIMEOUT_MS;
  try {
    while (Date.now() < deadline) {
      throwIfBlocked(blockingError);
      const size = fs.fstatSync(descriptor).size;
      if (size > position) {
        const chunk = Buffer.allocUnsafe(Math.min(size - position, 1024 * 1024));
        const count = fs.readSync(descriptor, chunk, 0, chunk.length, position);
        position += count;
        pending += chunk.subarray(0, count).toString('utf8');
        const lines = pending.split('\n');
        pending = lines.pop() || '';
        for (const line of lines) {
          if (!line) continue;
          let record;
          try { record = JSON.parse(line); } catch { continue; }
          const payload = record?.type === 'event_msg' ? record.payload : null;
          if (!payload) continue;
          if (payload.type === 'task_started' && typeof payload.turn_id === 'string') {
            latestStartedTurnId = payload.turn_id;
            continue;
          }
          if (
            !queuedTurnId &&
            latestStartedTurnId &&
            payload.type === 'user_message' &&
            (
              (clientUserMessageId && payload.client_id === clientUserMessageId) ||
              String(payload.message || '').trim() === text.trim()
            )
          ) {
            if (remainingMatches > 0) {
              remainingMatches -= 1;
              continue;
            }
            queuedTurnId = latestStartedTurnId;
            continue;
          }
          if (payload.type === 'task_complete' && payload.turn_id === queuedTurnId) {
            const response = String(payload.last_agent_message || '').trim();
            if (!response) fail('Codex completed without a final answer.', 'empty-response');
            return { turnId: queuedTurnId, response };
          }
          if (
            (payload.type === 'task_failed' || payload.type === 'turn_aborted') &&
            payload.turn_id === queuedTurnId
          ) {
            fail(payload.message || 'The queued Codex turn failed.', 'turn-failed');
          }
        }
      }
      await sleep(150);
    }
  } finally {
    fs.closeSync(descriptor);
  }
  fail('Timed out waiting for the queued Codex response.', 'turn-timeout');
}

async function waitForTaskToBecomeIdle(rolloutPath, blockingError) {
  const deadline = Date.now() + QUEUED_TURN_TIMEOUT_MS;
  while (Date.now() < deadline) {
    throwIfBlocked(blockingError);
    if (!latestActiveTurnId(rolloutPath)) return;
    await sleep(150);
  }
  fail('Timed out waiting for the active Codex turn to finish.', 'turn-timeout');
}

async function withClient(threadId, action) {
  const client = new DesktopIPCClient(threadId);
  try {
    await client.connect();
    const snapshot = await client.follow();
    return await action(client, snapshot);
  } finally {
    client.close();
  }
}

async function withAppServer(threadId, action) {
  const client = new AppServerClient();
  try {
    await client.connect();
    const resumed = await client.resume(threadId);
    return await action(client, resumed);
  } finally {
    client.close();
  }
}

function shouldUseAppServerFallback(error) {
  return [
    'task-owner-unavailable',
    'desktop-unavailable',
    'ENOENT',
    'ECONNREFUSED',
  ].includes(error?.code);
}

function acceptedDisposition(threadId, delivery, requestedDelivery, turnId, decision) {
  return {
    ok: true,
    phase: 'accepted',
    threadId,
    delivery,
    requestedDelivery,
    ...(turnId && { turnId }),
    ...(decision && { decision }),
  };
}

async function runDesktopCommand(
  command,
  threadId,
  text,
  clientUserMessageId,
  knownDelivery,
  onAccepted,
) {
  return withClient(threadId, async (client, snapshot) => {
    const state = snapshot.state || {};
    const rolloutPath = assertRolloutPath(state.rolloutPath, threadId);
    if (state.id !== threadId) fail('Codex Desktop returned the wrong task.', 'task-mismatch');
    if (command === 'validate') {
      return {
        ok: true,
        task: { id: state.id, title: state.title || 'Untitled task', cwd: state.cwd || '' },
      };
    }
    const reconciled = await reconcileExistingSubmission(
      rolloutPath,
      threadId,
      command,
      text,
      clientUserMessageId,
      knownDelivery,
      onAccepted,
    );
    if (reconciled) return reconciled;
    let offset = fs.statSync(rolloutPath).size;
    // The rollout is authoritative for activity. Desktop snapshots can lag the
    // open thread by a render tick; treating a stale "idle" snapshot as truth
    // starts a concurrent hidden turn instead of publishing a visible queue.
    const { activeTurnId, decision } = resolveDesktopTurnState(
      rolloutPath,
      state?.threadRuntimeStatus?.type,
    );

    if (command === 'steer') {
      if (!activeTurnId) {
        fail('The Codex task no longer has an active turn to steer.', 'turn-not-active');
      }
      try {
        await client.steerTurn(text, snapshot.ownerClientId, state, clientUserMessageId);
      } catch (error) {
        if (latestActiveTurnId(rolloutPath) !== activeTurnId) {
          fail('The Codex task no longer has the active turn Talkie tried to steer.', 'turn-not-active');
        }
        throw error;
      }
      const accepted = acceptedDisposition(
        threadId,
        'steered-active-turn',
        command,
        activeTurnId,
        decision,
      );
      onAccepted?.(accepted);
      return accepted;
    }

    if (command === 'queue' && activeTurnId) {
      // Publish the follow-up into Codex Desktop's native queue immediately so
      // it is visible beside messages queued from Desktop itself. The owner
      // starts it when the current turn becomes idle; Talkie keeps observing
      // until that exact instruction completes so async narration still works.
      const queued = await withQueuedFollowUpMutationLock(threadId, async () => {
        const queuedOffset = fs.statSync(rolloutPath).size;
        const queuedResult = await client.queueTurn(
          text,
          snapshot.ownerClientId,
          state,
          clientUserMessageId,
        );
        return { offset: queuedOffset, ...queuedResult };
      });
      onAccepted?.(acceptedDisposition(threadId, 'queued-turn', command, null, decision));
      const { turnId, response } = await waitForQueuedTurn(
        rolloutPath,
        queued.offset,
        text,
        queued.matchingPredecessors,
        clientUserMessageId,
      );
      return {
        ok: true,
        threadId,
        turnId,
        delivery: 'queued-turn',
        requestedDelivery: command,
        response,
        decision,
      };
    }

    let turnId;
    let delivery;
    if (activeTurnId) {
      try {
        await client.steerTurn(text, snapshot.ownerClientId, state, clientUserMessageId);
        turnId = activeTurnId;
        delivery = 'steered-active-turn';
      } catch (error) {
        const currentTurnId = latestActiveTurnId(rolloutPath);
        if (currentTurnId === activeTurnId) throw error;
        if (currentTurnId) {
          await client.steerTurn(text, snapshot.ownerClientId, state, clientUserMessageId);
          turnId = currentTurnId;
          delivery = 'steered-active-turn';
        } else {
          offset = fs.statSync(rolloutPath).size;
          turnId = await client.startTurn(text, snapshot.ownerClientId, clientUserMessageId);
          delivery = 'started-turn';
        }
      }
    } else {
      turnId = await client.startTurn(text, snapshot.ownerClientId, clientUserMessageId);
      delivery = 'started-turn';
    }
    onAccepted?.(acceptedDisposition(threadId, delivery, command, turnId, decision));
    const response = await waitForTurn(rolloutPath, offset, turnId);
    return {
      ok: true,
      threadId,
      turnId,
      delivery,
      requestedDelivery: command,
      response,
      decision,
    };
  });
}

async function startQueuedAppServerTurn(client, threadId, rolloutPath, text, clientUserMessageId) {
  const deadline = Date.now() + QUEUED_TURN_TIMEOUT_MS;
  while (Date.now() < deadline) {
    await waitForTaskToBecomeIdle(rolloutPath, () => client.pendingBlockingError());
    const refreshed = await client.resume(threadId);
    const activeTurn = [...(refreshed.thread?.turns || [])]
      .reverse()
      .find((turn) => turn?.status === 'inProgress');
    if (activeTurn?.id || latestActiveTurnId(rolloutPath)) continue;

    const offset = fs.statSync(rolloutPath).size;
    try {
      const turnId = await client.startTurn(threadId, text, clientUserMessageId);
      return { offset, turnId };
    } catch (error) {
      if (latestActiveTurnId(rolloutPath)) continue;
      throw error;
    }
  }
  fail('Timed out waiting to start the queued Codex turn.', 'turn-timeout');
}

async function runAppServerCommand(
  command,
  threadId,
  text,
  clientUserMessageId,
  knownDelivery,
  onAccepted,
) {
  return withAppServer(threadId, async (client, resumed) => {
    const thread = resumed.thread;
    const rolloutPath = assertRolloutPath(thread.path, threadId);
    if (command === 'validate') {
      return {
        ok: true,
        task: {
          id: thread.id,
          title: thread.name || thread.preview || 'Untitled task',
          cwd: thread.cwd || resumed.cwd || '',
        },
      };
    }
    const reconciled = await reconcileExistingSubmission(
      rolloutPath,
      threadId,
      command,
      text,
      clientUserMessageId,
      knownDelivery,
      onAccepted,
      () => client.pendingBlockingError(),
    );
    if (reconciled) return reconciled;
    let offset = fs.statSync(rolloutPath).size;
    const activeTurn = [...(thread.turns || [])].reverse().find((turn) => turn?.status === 'inProgress');
    const taskIsActive = thread?.status?.type === 'active';
    if (taskIsActive && !activeTurn?.id) {
      fail('Codex app-server reports an active task without a correlatable turn.', 'protocol-mismatch');
    }

    if (command === 'steer') {
      if (!activeTurn?.id) {
        fail('The Codex task no longer has an active turn to steer.', 'turn-not-active');
      }
      let turnId;
      try {
        turnId = await client.steerTurn(threadId, activeTurn.id, text, clientUserMessageId);
      } catch (error) {
        if (latestActiveTurnId(rolloutPath) !== activeTurn.id) {
          fail('The Codex task no longer has the active turn Talkie tried to steer.', 'turn-not-active');
        }
        throw error;
      }
      const accepted = acceptedDisposition(threadId, 'steered-active-turn', command, turnId);
      onAccepted?.(accepted);
      return accepted;
    }

    if (command === 'queue' && activeTurn?.id) {
      onAccepted?.(acceptedDisposition(threadId, 'queued-turn', command));
      const queued = await startQueuedAppServerTurn(
        client,
        threadId,
        rolloutPath,
        text,
        clientUserMessageId,
      );
      const response = await waitForTurn(
        rolloutPath,
        queued.offset,
        queued.turnId,
        () => client.pendingBlockingError(),
      );
      return {
        ok: true,
        threadId,
        turnId: queued.turnId,
        delivery: 'queued-turn',
        requestedDelivery: command,
        response,
      };
    }

    let turnId;
    let delivery;
    if (activeTurn?.id) {
      try {
        turnId = await client.steerTurn(threadId, activeTurn.id, text, clientUserMessageId);
        delivery = 'steered-active-turn';
      } catch (error) {
        const currentTurnId = latestActiveTurnId(rolloutPath);
        if (currentTurnId === activeTurn.id) throw error;
        if (currentTurnId) {
          const refreshed = await client.resume(threadId);
          const currentTurn = [...(refreshed.thread?.turns || [])]
            .reverse()
            .find((turn) => turn?.status === 'inProgress' && turn.id === currentTurnId);
          if (!currentTurn) throw error;
          turnId = await client.steerTurn(threadId, currentTurnId, text, clientUserMessageId);
          delivery = 'steered-active-turn';
        } else {
          offset = fs.statSync(rolloutPath).size;
          turnId = await client.startTurn(threadId, text, clientUserMessageId);
          delivery = 'started-turn';
        }
      }
    } else {
      turnId = await client.startTurn(threadId, text, clientUserMessageId);
      delivery = 'started-turn';
    }
    onAccepted?.(acceptedDisposition(threadId, delivery, command, turnId));
    const response = await waitForTurn(
      rolloutPath,
      offset,
      turnId,
      () => client.pendingBlockingError(),
    );
    return {
      ok: true,
      threadId,
      turnId,
      delivery,
      requestedDelivery: command,
      response,
    };
  });
}

async function main() {
  const [command, argument, rawClientUserMessageId, rawKnownDelivery] = process.argv.slice(2);
  if (command === 'list') {
    writeResult({ ok: true, tasks: listTasks(argument) });
    return;
  }
  if (command === 'activity' && argument) {
    writeResult(readTurnActivity(taskRolloutPath(argument)));
    return;
  }
  if ((command === 'validate' || command === 'submit' || command === 'steer' || command === 'queue') && argument) {
    const acceptsText = command === 'submit' || command === 'steer' || command === 'queue';
    const text = acceptsText ? (await readStdin()).trim() : '';
    if (acceptsText && !text) fail('The transcript is empty.', 'empty-transcript');
    const clientUserMessageId = acceptsText
      ? normalizeClientUserMessageId(rawClientUserMessageId)
      : undefined;
    const knownDelivery = acceptsText ? normalizeKnownDelivery(rawKnownDelivery) : null;
    const onAccepted = acceptsText ? (accepted) => writeResult(accepted) : undefined;
    let result;
    try {
      result = await runDesktopCommand(
        command,
        argument,
        text,
        clientUserMessageId,
        knownDelivery,
        onAccepted,
      );
    } catch (error) {
      if (!shouldUseAppServerFallback(error)) throw error;
      result = await runAppServerCommand(
        command,
        argument,
        text,
        clientUserMessageId,
        knownDelivery,
        onAccepted,
      );
    }
    writeResult(result);
    return;
  }
  fail(
    'Usage: codex-desktop-bridge.cjs list [limit] | activity|validate <task-id> | submit|steer|queue <task-id> [submission-id]',
    'usage',
  );
}

if (require.main === module) {
  main().catch((error) => {
    writeResult({
      ok: false,
      code: error?.code || 'bridge-failed',
      error: error instanceof Error ? error.message : String(error),
    });
    process.exitCode = 1;
  });
}

module.exports = {
  appendQueuedFollowUp,
  listTasks,
  makeQueuedFollowUp,
  projectName,
  readQueuedFollowUps,
  readTurnActivity,
  resolveDesktopTurnState,
  taskRolloutPath,
  withQueuedFollowUpMutationLock,
  waitForQueuedTurn,
};
