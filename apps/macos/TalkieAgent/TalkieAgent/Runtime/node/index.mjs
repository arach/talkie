#!/usr/bin/env node
import { spawn } from 'node:child_process';
import {
  closeSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const runtimeDir = dirname(fileURLToPath(import.meta.url));
const version = readPackageVersion();
const jobStorePath = process.env.TALKIE_AGENT_ACTIVITY_STORE
  ?? process.env.TALKIE_WALKIE_JOB_STORE
  ?? join(homedir(), 'Library', 'Application Support', 'Talkie', 'Walkie', 'jobs.json');
const runtimeBase = {
  id: 'walkie-node-dispatcher',
  name: 'Walkie Runtime Dispatcher',
  version,
  capabilities: ['readOnlyData', 'longRunningJobs', 'codeExecution'],
};
const jobs = loadJobs();
let pending = '';
let queue = Promise.resolve();

if (process.argv[2] === '--run-invocation' || process.argv[2] === '--run-job') {
  runInvocationWorker(process.argv[3])
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(`[TalkieAgentRuntime] worker failed: ${error?.message ?? error}`);
      process.exit(1);
    });
} else {
  process.stdin.setEncoding('utf8');

  process.stdin.on('data', (chunk) => {
    pending += chunk;
    drainLines();
  });

  process.stdin.on('end', () => {
    const line = pending.trim();
    pending = '';
    if (line.length > 0) {
      enqueueLine(line);
    }
  });

  process.stdin.on('error', (error) => {
    console.error(`[TalkieAgentRuntime] stdin error: ${error?.message ?? error}`);
  });
}

function drainLines() {
  let newlineIndex = pending.indexOf('\n');
  while (newlineIndex !== -1) {
    const line = pending.slice(0, newlineIndex).trim();
    pending = pending.slice(newlineIndex + 1);
    if (line.length > 0) {
      enqueueLine(line);
    }
    newlineIndex = pending.indexOf('\n');
  }
}

function enqueueLine(line) {
  queue = queue
    .then(() => handleLine(line))
    .catch((error) => {
      writeResponse({ ok: false, error: error?.message ?? String(error) });
    });
}

async function handleLine(line) {
  let request;
  try {
    request = JSON.parse(line);
  } catch (error) {
    writeResponse({ ok: false, error: `Invalid JSON: ${error.message}` });
    return;
  }

  try {
    const runtime = await runtimeInfo();
    switch (request?.op) {
      case 'ping':
        writeResponse({ ok: true, pid: process.pid, version, runtime });
        break;
      case 'status':
        {
          const activities = listActivities();
          writeResponse({ ok: true, pid: process.pid, version, runtime, activities, jobs: activities });
        }
        break;
      case 'invoke':
        {
          const activity = await invoke(request?.invocation ?? request?.job, runtime);
          writeResponse({ ok: true, runtime, activity, job: activity });
        }
        break;
      case 'startJob':
        {
          const activity = await invoke(request?.job ?? request?.invocation, runtime);
          writeResponse({ ok: true, runtime, activity, job: activity });
        }
        break;
      case 'retryInvocation':
      case 'retryJob':
        {
          const activity = await retryInvocation(request?.sessionId, runtime);
          writeResponse({ ok: true, runtime, activity, job: activity });
        }
        break;
      case 'runQueuedInvocations':
      case 'runQueuedJobs':
        {
          const activities = await runQueuedInvocations(runtime);
          writeResponse({ ok: true, runtime, activities, jobs: activities });
        }
        break;
      case 'listActivities':
      case 'listJobs':
        {
          const activities = listActivities();
          writeResponse({ ok: true, runtime, activities, jobs: activities });
        }
        break;
      case 'activityStatus':
      case 'jobStatus':
        {
          const activity = activityStatus(request?.sessionId);
          writeResponse({ ok: true, runtime, activity, job: activity });
        }
        break;
      case 'cancelInvocation':
      case 'cancelJob':
        {
          const activity = cancelInvocation(request?.sessionId);
          writeResponse({ ok: true, runtime, activity, job: activity });
        }
        break;
      default:
        writeResponse({ ok: false, error: `Unsupported op: ${String(request?.op ?? '')}` });
        break;
    }
  } catch (error) {
    writeResponse({ ok: false, error: error?.message ?? String(error) });
  }
}

async function runtimeInfo() {
  return {
    ...runtimeBase,
    scoutBridge: await agentSessionsAvailable() ? 'configured' : 'pending',
  };
}

async function agentSessionsAvailable() {
  try {
    await loadAgentSessionsPackage();
    return true;
  } catch {
    return false;
  }
}

async function loadAgentSessionsPackage() {
  const configuredModule = process.env.TALKIE_AGENT_SESSIONS_MODULE;
  const workspace = workspaceCwd();
  const workspaceParent = dirname(workspace);
  const candidates = [
    configuredModule,
    join(workspace, 'node_modules', '@openscout', 'agent-sessions', 'dist', 'index.js'),
    join(workspaceParent, 'openscout', 'packages', 'agent-sessions', 'dist', 'index.js'),
    join(workspaceParent, 'openscout', 'packages', 'agent-sessions', 'src', 'index.ts'),
  ].filter(Boolean);

  try {
    return await import('@openscout/agent-sessions');
  } catch {
    // Fall through to explicit local candidates.
  }

  for (const candidate of candidates) {
    if (typeof candidate === 'string' && existsSync(candidate)) {
      return import(pathToFileURL(candidate).href);
    }
  }

  throw new Error('Could not load @openscout/agent-sessions.');
}

function writeResponse(response) {
  process.stdout.write(`${JSON.stringify(response)}\n`);
}

async function invoke(invocation, runtime) {
  validateInvocation(invocation);

  const sessionId = `walkie-${invocation.id}`;
  const now = new Date().toISOString();
  const adapterType = resolveAdapterType(invocation);
  const bridgeReady = runtime.scoutBridge === 'configured';
  const conversationId = conversationIdFor(invocation);
  const parentRecord = continuationRecordFor(invocation, conversationId);
  const agentSessionId = parentRecord?.agentSessionId ?? `${sessionId}-agent`;
  const isContinuation = parentRecord != null;
  const record = {
    id: invocation.id,
    sessionId,
    conversationId,
    parentSessionId: normalizeString(invocation.parentSessionId),
    continuedFromSessionId: parentRecord?.sessionId ?? null,
    source: normalizeString(invocation.source) ?? 'voice',
    state: bridgeReady ? 'working' : 'failed',
    ack: bridgeReady
      ? isContinuation
        ? 'Continuing in the same Agent Session. I will report back here.'
        : 'On it. I sent that to an Agent Session and will report back here.'
      : 'I captured that executor request, but the Scout agent session package is not installed for this runtime.',
    providerId: invocation.channel?.executorProviderId ?? adapterType,
    modelId: invocation.channel?.executorModelId ?? null,
    channelCode: invocation.channel?.code ?? null,
    instruction: invocation.instruction,
    transcript: invocation.transcript,
    topLevelModel: invocation.topLevelModel ?? null,
    runtimeId: runtime.id,
    runtimeName: runtime.name,
    executorAdapterType: adapterType,
    agentSessionId,
    output: null,
    spokenSummary: null,
    bridgeStatus: runtime.scoutBridge,
    createdAt: now,
    updatedAt: now,
    error: bridgeReady ? null : 'Missing @openscout/agent-sessions dependency.',
  };

  jobs.set(sessionId, record);
  persistRecord(record);

  if (bridgeReady) {
    spawnWorker(sessionId);
  }

  return publicActivity(record);
}

async function retryInvocation(sessionId, runtime) {
  const record = requireRecord(sessionId);
  const bridgeReady = runtime.scoutBridge === 'configured';
  record.executorAdapterType = record.executorAdapterType ?? resolveAdapterType(record);
  record.providerId = record.providerId ?? record.executorAdapterType;
  record.runtimeId = runtime.id;
  record.runtimeName = runtime.name;
  record.bridgeStatus = runtime.scoutBridge;
  record.updatedAt = new Date().toISOString();
  record.error = bridgeReady ? null : 'Missing @openscout/agent-sessions dependency.';
  record.output = null;
  record.state = bridgeReady ? 'working' : 'failed';
  record.ack = bridgeReady
    ? 'On it. I restarted this in an Agent Session.'
    : 'I could not restart this because the Scout agent session package is not installed for this runtime.';
  persistRecord(record);

  if (bridgeReady) {
    spawnWorker(sessionId);
  }

  return publicActivity(record);
}

async function runQueuedInvocations(runtime) {
  const queued = Array.from(jobs.values())
    .filter((job) => job.state === 'acked')
    .map((job) => job.sessionId);
  const restarted = [];

  for (const sessionId of queued) {
    restarted.push(await retryInvocation(sessionId, runtime));
  }

  return restarted;
}

function spawnWorker(sessionId) {
  const child = spawn(process.argv[0], [fileURLToPath(import.meta.url), '--run-invocation', sessionId], {
    cwd: workspaceCwd(),
    env: process.env,
    detached: true,
    stdio: 'ignore',
  });
  child.unref();
}

async function runInvocationWorker(sessionId) {
  const record = requireRecord(sessionId);
  const adapterType = record.executorAdapterType ?? resolveAdapterType(record);
  const sessionPackage = await loadAgentSessionsPackage();
  const registry = new sessionPackage.SessionRegistry({
    adapters: adapterFactories(sessionPackage),
  });
  const workspace = workspaceCwd();
  const agentSessionId = record.agentSessionId ?? `${record.sessionId}-agent`;
  const outputChunks = [];
  let terminalStatus = null;

  record.state = 'working';
  record.executorAdapterType = adapterType;
  record.providerId = record.providerId ?? adapterType;
  record.agentSessionId = agentSessionId;
  record.bridgeStatus = 'configured';
  record.updatedAt = new Date().toISOString();
  record.error = null;
  persistRecord(record);

  const unsubscribe = registry.onEvent(({ event }) => {
    const latest = jobs.get(sessionId);
    if (!latest) {
      return;
    }

    latest.updatedAt = new Date().toISOString();

    if (event.event === 'session:update') {
      latest.agentSessionStatus = event.session.status;
      latest.agentSessionName = event.session.name;
      latest.agentSessionThreadId = normalizeString(event.session.providerMeta?.threadId);
      latest.agentSessionProviderMeta = event.session.providerMeta ?? null;
      latest.modelId = latest.modelId ?? event.session.model ?? null;
    } else if (event.event === 'block:delta' && typeof event.text === 'string') {
      outputChunks.push(event.text);
      latest.output = outputChunks.join('');
    } else if (event.event === 'turn:end') {
      terminalStatus = event.status;
      latest.state = event.status === 'completed' ? 'done' : 'failed';
      latest.output = finalOutput(registry, agentSessionId, outputChunks);
      latest.spokenSummary = spokenSummaryForOutput(latest.output);
      latest.error = event.status === 'completed' ? null : `Agent session ended with status: ${event.status}`;
    } else if (event.event === 'turn:error') {
      terminalStatus = 'failed';
      latest.state = 'failed';
      latest.error = event.message;
    }

    persistRecord(latest);
  });

  try {
    await registry.createSession(adapterType, {
      sessionId: agentSessionId,
      name: `Talkie ${record.channelCode ?? 'executor'} ${record.id}`,
      cwd: workspace,
      env: process.env,
      options: adapterOptions(record, workspace),
    });

    registry.send({
      sessionId: agentSessionId,
      text: promptForRecord(record, workspace),
    });

    await waitForTerminalTurn(() => terminalStatus);
  } catch (error) {
    const latest = jobs.get(sessionId) ?? record;
    latest.state = 'failed';
    latest.updatedAt = new Date().toISOString();
    latest.error = error?.message ?? String(error);
    latest.output = (latest.output ?? outputChunks.join('')) || null;
    persistRecord(latest);
  } finally {
    unsubscribe();
    await registry.shutdown().catch(() => undefined);
  }
}

function adapterFactories(sessionPackage) {
  return {
    codex: sessionPackage.createCodexAdapter,
    'claude-code': sessionPackage.createClaudeCodeAdapter,
    opencode: sessionPackage.createOpencodeAdapter,
    pi: sessionPackage.createPiAdapter,
    echo: sessionPackage.createEchoAdapter,
  };
}

function adapterOptions(record, workspace) {
  const model = process.env.TALKIE_AGENT_SESSION_MODEL ?? record.modelId ?? undefined;
  const systemPrompt = [
    'You are the Talkie executor running inside an OpenScout Agent Session.',
    'You receive one user request that was routed to background work.',
    'Be direct, report what you did, and do not modify files unless the request explicitly asks for changes.',
    `Workspace: ${workspace}`,
  ].join('\n');
  const options = { systemPrompt };

  if (model) {
    options.model = model;
  }

  return options;
}

function promptForRecord(record, workspace) {
  const context = conversationContextFor(record);
  return [
    'Talkie executor request',
    '',
    `Workspace: ${workspace}`,
    `Channel: ${record.channelCode ?? 'CH-01'}`,
    `Conversation: ${conversationIdFor(record)}`,
    record.parentSessionId ? `Parent session: ${record.parentSessionId}` : null,
    '',
    context.length > 0 ? 'Recent conversation context:' : null,
    ...context,
    '',
    'User transcript:',
    record.transcript ?? '',
    '',
    'Executor instruction:',
    record.instruction,
    '',
    'Return a concise result that Talkie can show in Agent Home.',
  ].filter((line) => line != null).join('\n');
}

function conversationContextFor(record) {
  const conversationId = conversationIdFor(record);
  const priorRecords = Array.from(loadJobs().values())
    .filter((candidate) => candidate.sessionId !== record.sessionId)
    .filter((candidate) => conversationIdFor(candidate) === conversationId)
    .sort((a, b) => String(a.createdAt ?? '').localeCompare(String(b.createdAt ?? '')))
    .slice(-6);

  return priorRecords.flatMap((candidate, index) => {
    const request = normalizeString(candidate.transcript) ?? normalizeString(candidate.instruction) ?? '';
    const result = normalizeString(candidate.spokenSummary)
      ?? normalizeString(candidate.output)
      ?? normalizeString(candidate.error)
      ?? normalizeString(candidate.ack)
      ?? '';
    return [
      `Turn ${index + 1} - ${candidate.state ?? 'unknown'} - ${candidate.sessionId}`,
      `User: ${truncateText(request, 900)}`,
      `Result: ${truncateText(result, 1_400)}`,
      '',
    ];
  });
}

function continuationRecordFor(invocation, conversationId) {
  const parentSessionId = normalizeString(invocation.parentSessionId);
  if (!parentSessionId) {
    return null;
  }

  const record = jobs.get(parentSessionId);
  if (!record) {
    return null;
  }

  return conversationIdFor(record) === conversationId ? record : null;
}

function finalOutput(registry, agentSessionId, fallbackChunks) {
  const snapshot = registry.getSessionSnapshot(agentSessionId);
  const lastTurn = snapshot?.turns?.at(-1);
  const parts = [];

  for (const blockState of lastTurn?.blocks ?? []) {
    const block = blockState.block;
    if ((block.type === 'text' || block.type === 'reasoning') && block.text?.trim()) {
      parts.push(block.text.trim());
    } else if (block.type === 'error' && block.message?.trim()) {
      parts.push(block.message.trim());
    }
  }

  return parts.join('\n\n').trim() || fallbackChunks.join('').trim() || null;
}

function spokenSummaryForOutput(output) {
  const text = normalizeString(output);
  if (!text) {
    return null;
  }

  const lines = text
    .split(/\r?\n/g)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('```'));
  const usefulLines = lines.filter((line, index) => {
    if (index > 0) {
      return true;
    }
    return !isBoilerplateSummaryLine(line) || lines.length === 1;
  });
  const selected = usefulLines
    .slice(0, 5)
    .map((line) => line
      .replace(/^[-*]\s+/, '')
      .replace(/\*\*/g, '')
      .replace(/`/g, ''))
    .join(' ');

  return truncateText(selected.replace(/\s+/g, ' '), 360);
}

function isBoilerplateSummaryLine(line) {
  return /^inspected\b.*\bno files modified\.?$/i.test(line)
    || /^read-only inspection done\.?\s+no files modified\.?$/i.test(line)
    || /^no files (were )?modified\.?$/i.test(line);
}

async function waitForTerminalTurn(getStatus) {
  const timeoutMs = Number(process.env.TALKIE_AGENT_SESSION_TIMEOUT_MS ?? 10 * 60 * 1000);
  const startedAt = Date.now();

  while (!getStatus()) {
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error(`Agent session timed out after ${timeoutMs}ms.`);
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}

function resolveAdapterType(source) {
  const configured = process.env.TALKIE_AGENT_SESSION_ADAPTER
    ?? source?.executorAdapterType
    ?? source?.channel?.executorRuntimeId
    ?? source?.providerId
    ?? source?.channel?.executorProviderId;
  const normalized = normalizeAdapterType(configured);
  return normalized ?? 'codex';
}

function normalizeAdapterType(value) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return null;
  }

  const raw = value.trim().toLowerCase();
  if (['codex', 'openai', 'gpt'].includes(raw)) {
    return 'codex';
  }
  if (['claude', 'claude-code', 'anthropic'].includes(raw)) {
    return 'claude-code';
  }
  if (['opencode', 'open-code'].includes(raw)) {
    return 'opencode';
  }
  if (['pi', 'pisdk'].includes(raw)) {
    return 'pi';
  }
  if (raw === 'echo') {
    return 'echo';
  }
  return null;
}

function activityStatus(sessionId) {
  const record = requireRecord(sessionId);
  return publicActivity(record);
}

function listActivities() {
  return Array.from(jobs.values())
    .sort((a, b) => String(b.updatedAt ?? '').localeCompare(String(a.updatedAt ?? '')))
    .map(publicActivity);
}

function cancelInvocation(sessionId) {
  const record = requireRecord(sessionId);
  record.state = 'failed';
  record.updatedAt = new Date().toISOString();
  record.error = 'Cancelled before executor completion.';
  persistRecord(record);
  return publicActivity(record);
}

function publicActivity(record) {
  return {
    id: record.id,
    sessionId: record.sessionId,
    conversationId: conversationIdFor(record),
    parentSessionId: record.parentSessionId ?? null,
    continuedFromSessionId: record.continuedFromSessionId ?? null,
    source: record.source ?? null,
    state: record.state,
    ack: record.ack,
    providerId: record.providerId,
    modelId: record.modelId,
    topLevelProviderId: record.topLevelModel?.providerId ?? null,
    topLevelProviderName: record.topLevelModel?.providerName ?? null,
    topLevelModelId: record.topLevelModel?.modelId ?? null,
    runtimeId: record.runtimeId ?? runtimeBase.id,
    runtimeName: record.runtimeName ?? runtimeBase.name,
    channelCode: record.channelCode,
    instruction: record.instruction,
    transcript: record.transcript,
    output: record.output ?? null,
    spokenSummary: record.spokenSummary ?? spokenSummaryForOutput(record.output),
    bridgeStatus: record.bridgeStatus,
    executorAdapterType: record.executorAdapterType ?? null,
    agentSessionId: record.agentSessionId ?? null,
    agentSessionThreadId: record.agentSessionThreadId ?? null,
    agentSessionStatus: record.agentSessionStatus ?? null,
    agentSessionName: record.agentSessionName ?? null,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    error: record.error ?? null,
  };
}

function conversationIdFor(source) {
  const explicit = normalizeString(source?.conversationId);
  if (explicit) {
    return explicit;
  }

  const channelCode = normalizeString(source?.channelCode ?? source?.channel?.code);
  if (channelCode) {
    return `channel-${slugify(channelCode)}`;
  }

  const channelId = normalizeString(source?.channel?.id);
  if (channelId) {
    return `channel-${channelId.toLowerCase()}`;
  }

  const id = normalizeString(source?.id ?? source?.sessionId);
  return id ? `activity-${slugify(id)}` : 'agent-home-main';
}

function normalizeString(value) {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function slugify(value) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'unknown';
}

function truncateText(value, maxLength) {
  if (value.length <= maxLength) {
    return value;
  }

  return `${value.slice(0, Math.max(0, maxLength - 3)).trimEnd()}...`;
}

function validateInvocation(invocation) {
  if (!invocation || typeof invocation !== 'object') {
    throw new Error('invoke requires an invocation object.');
  }
  if (!invocation.id || typeof invocation.id !== 'string') {
    throw new Error('invocation.id is required.');
  }
  if (!invocation.instruction || typeof invocation.instruction !== 'string') {
    throw new Error('invocation.instruction is required.');
  }
}

function requireRecord(sessionId) {
  if (!sessionId || typeof sessionId !== 'string') {
    throw new Error('sessionId is required.');
  }
  const record = jobs.get(sessionId);
  if (!record) {
    throw new Error(`Unknown sessionId: ${sessionId}`);
  }
  return record;
}

function loadJobs() {
  try {
    if (!existsSync(jobStorePath)) {
      return new Map();
    }
    const raw = JSON.parse(readFileSync(jobStorePath, 'utf8'));
    if (!raw || typeof raw !== 'object') {
      return new Map();
    }
    return new Map(Object.entries(raw));
  } catch (error) {
    console.error(`[TalkieAgentRuntime] could not read job store: ${error?.message ?? error}`);
    return new Map();
  }
}

function persistRecord(record) {
  jobs.set(record.sessionId, record);
  withStoreLock(() => {
    const latest = loadJobs();
    latest.set(record.sessionId, record);
    writeJobs(latest);
  });
}

function writeJobs(jobMap) {
  const dir = dirname(jobStorePath);
  mkdirSync(dir, { recursive: true });
  const raw = Object.fromEntries(jobMap.entries());
  const tempPath = `${jobStorePath}.${process.pid}.${Date.now()}.tmp`;
  writeFileSync(tempPath, `${JSON.stringify(raw, null, 2)}\n`, 'utf8');
  renameSync(tempPath, jobStorePath);
}

function withStoreLock(work) {
  const lockPath = `${jobStorePath}.lock`;
  const startedAt = Date.now();
  let fd = null;

  while (fd == null) {
    try {
      mkdirSync(dirname(jobStorePath), { recursive: true });
      fd = openSync(lockPath, 'wx');
    } catch (error) {
      if (error?.code !== 'EEXIST') {
        throw error;
      }
      if (Date.now() - startedAt > 5_000) {
        throw new Error(`Timed out waiting for activity store lock: ${lockPath}`);
      }
      sleepSync(25);
    }
  }

  try {
    return work();
  } finally {
    closeSync(fd);
    try {
      unlinkSync(lockPath);
    } catch {
      // If the lock was already cleared, the next writer can continue.
    }
  }
}

function sleepSync(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function workspaceCwd() {
  const configured = process.env.TALKIE_WALKIE_EXECUTOR_CWD;
  if (configured && existsSync(configured)) {
    return configured;
  }

  let cursor = runtimeDir;
  for (let index = 0; index < 10; index += 1) {
    if (existsSync(join(cursor, 'AGENTS.md')) && existsSync(join(cursor, 'apps', 'macos'))) {
      return cursor;
    }
    const next = dirname(cursor);
    if (next === cursor) {
      break;
    }
    cursor = next;
  }

  return process.cwd();
}

function readPackageVersion() {
  try {
    const packageJsonPath = join(runtimeDir, 'package.json');
    const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));
    return packageJson.version ?? '0.0.0';
  } catch {
    return '0.0.0';
  }
}
