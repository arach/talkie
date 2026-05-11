import { del, list, put } from '@vercel/blob';
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

export type WorkflowRunStatus =
  | 'queued'
  | 'claimed'
  | 'running'
  | 'completed'
  | 'failed'
  | 'cancelled';

export interface WorkflowRunRecord {
  id: string;
  workflowId: string;
  workflowName: string;
  workflowIcon?: string;
  memoId: string;
  status: WorkflowRunStatus;
  executionClass: 'macOnly';
  routingMode: 'any';
  requestedByDeviceId?: string;
  claimedByDeviceId?: string;
  leaseToken?: string;
  leaseExpiresAt?: string;
  backendId?: string;
  output?: string;
  finalOutputs?: Record<string, string>;
  stepOutputsJSON?: string;
  errorMessage?: string;
  createdAt: string;
  updatedAt: string;
  runDate: string;
}

export interface WorkflowRunEvent {
  id: string;
  runId: string;
  type: 'created' | 'claimed' | 'started' | 'released' | 'completed' | 'failed';
  status: WorkflowRunStatus;
  createdAt: string;
  deviceId?: string;
  message?: string;
}

export interface ExecutorRecord {
  deviceId: string;
  name: string;
  platform: string;
  status: string;
  priority: number;
  capabilities: string[];
  installId?: string;
  appVersion?: string;
  tailscaleHostname?: string;
  metadata?: Record<string, string>;
  claimedRunId?: string;
  lastHeartbeatAt: string;
  heartbeatExpiresAt: string;
}

export interface CreateWorkflowRunInput {
  workflowId: string;
  workflowName: string;
  workflowIcon?: string;
  memoId: string;
  requestedByDeviceId?: string;
}

export interface ExecutorRegistrationInput {
  deviceId: string;
  name: string;
  platform: string;
  status: string;
  priority: number;
  capabilities: string[];
  installId?: string;
  appVersion?: string;
  tailscaleHostname?: string;
  metadata?: Record<string, string>;
}

export interface ExecutorHeartbeatInput {
  deviceId: string;
  status: string;
  claimedRunId?: string;
  metadata?: Record<string, string>;
}

export interface ClaimRunResult {
  granted: boolean;
  reason?: string;
  leaseToken?: string;
  leaseExpiresAt?: string;
}

export interface LeaseRenewalResult {
  ok: boolean;
  reason?: string;
  leaseExpiresAt?: string;
}

export interface WorkflowRunDetails {
  run: WorkflowRunRecord;
  events: WorkflowRunEvent[];
}

interface RunLockRecord {
  runId: string;
  deviceId: string;
  leaseToken: string;
  backendId?: string;
  claimedAt: string;
  expiresAt: string;
  updatedAt: string;
}

interface StorageEntry<T> {
  pathname: string;
  uploadedAt: Date;
  value: T;
}

interface StorageDriver {
  readJSON<T>(pathname: string): Promise<T | null>;
  writeJSON<T>(pathname: string, value: T, options?: { allowOverwrite?: boolean }): Promise<void>;
  delete(pathname: string): Promise<void>;
  listJSON<T>(prefix: string): Promise<Array<StorageEntry<T>>>;
}

const WORKFLOW_QUEUE_PREFIX = 'workflow-control/v1';
const LEASE_DURATION_MS = 30_000;
const EXECUTOR_HEARTBEAT_MS = 120_000;

export class WorkflowQueueError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message);
    this.name = 'WorkflowQueueError';
  }
}

class JsonCipher {
  private readonly key: Buffer;

  constructor(secret: string) {
    this.key = createHash('sha256').update(secret).digest();
  }

  encrypt(plaintext: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
    const authTag = cipher.getAuthTag();
    return Buffer.concat([iv, authTag, encrypted]).toString('base64url');
  }

  decrypt(payload: string): string {
    const buffer = Buffer.from(payload, 'base64url');
    const iv = buffer.subarray(0, 12);
    const authTag = buffer.subarray(12, 28);
    const encrypted = buffer.subarray(28);
    const decipher = createDecipheriv('aes-256-gcm', this.key, iv);
    decipher.setAuthTag(authTag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8');
  }
}

class BlobStorageDriver implements StorageDriver {
  constructor(private readonly cipher: JsonCipher) {}

  async readJSON<T>(pathname: string): Promise<T | null> {
    const blob = await this.findBlob(pathname);
    if (!blob) {
      return null;
    }

    const response = await fetch(blob.url, { cache: 'no-store' });
    if (!response.ok) {
      throw new Error(`Failed to read blob ${pathname}: ${response.status}`);
    }

    const ciphertext = await response.text();
    return JSON.parse(this.cipher.decrypt(ciphertext)) as T;
  }

  async writeJSON<T>(pathname: string, value: T, options?: { allowOverwrite?: boolean }): Promise<void> {
    const ciphertext = this.cipher.encrypt(JSON.stringify(value));
    await put(pathname, ciphertext, {
      access: 'public',
      addRandomSuffix: false,
      allowOverwrite: options?.allowOverwrite ?? false,
      contentType: 'application/json',
    });
  }

  async delete(pathname: string): Promise<void> {
    try {
      await del(pathname);
    } catch {
      // Treat missing blobs as already deleted.
    }
  }

  async listJSON<T>(prefix: string): Promise<Array<StorageEntry<T>>> {
    let cursor: string | undefined;
    const entries: Array<StorageEntry<T>> = [];

    do {
      const response = await list({ prefix, cursor, limit: 1000 });
      for (const blob of response.blobs) {
        const blobResponse = await fetch(blob.url, { cache: 'no-store' });
        if (!blobResponse.ok) {
          continue;
        }

        const ciphertext = await blobResponse.text();
        entries.push({
          pathname: blob.pathname,
          uploadedAt: new Date(blob.uploadedAt),
          value: JSON.parse(this.cipher.decrypt(ciphertext)) as T,
        });
      }
      cursor = response.cursor;
      if (!response.hasMore) {
        break;
      }
    } while (cursor);

    return entries;
  }

  private async findBlob(pathname: string) {
    const response = await list({ prefix: pathname, limit: 10 });
    return response.blobs.find((blob) => blob.pathname == pathname) ?? null;
  }
}

class LocalStorageDriver implements StorageDriver {
  constructor(private readonly rootDirectory: string) {}

  async readJSON<T>(pathname: string): Promise<T | null> {
    try {
      const file = await fs.readFile(this.absolutePath(pathname), 'utf8');
      return JSON.parse(file) as T;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code == 'ENOENT') {
        return null;
      }
      throw error;
    }
  }

  async writeJSON<T>(pathname: string, value: T, options?: { allowOverwrite?: boolean }): Promise<void> {
    const absolutePath = this.absolutePath(pathname);
    await fs.mkdir(path.dirname(absolutePath), { recursive: true });

    if (options?.allowOverwrite === false) {
      const handle = await fs.open(absolutePath, 'wx').catch((error) => {
        if ((error as NodeJS.ErrnoException).code == 'EEXIST') {
          throw new Error(`Path already exists: ${pathname}`);
        }
        throw error;
      });
      if (handle) {
        await handle.writeFile(JSON.stringify(value, null, 2), 'utf8');
        await handle.close();
        return;
      }
    }

    await fs.writeFile(absolutePath, JSON.stringify(value, null, 2), 'utf8');
  }

  async delete(pathname: string): Promise<void> {
    await fs.rm(this.absolutePath(pathname), { force: true });
  }

  async listJSON<T>(prefix: string): Promise<Array<StorageEntry<T>>> {
    const directory = this.absolutePath(prefix);
    const files = await this.walk(directory);
    const entries: Array<StorageEntry<T>> = [];

    for (const file of files) {
      const relativePath = path.relative(this.rootDirectory, file);
      const contents = await fs.readFile(file, 'utf8');
      const stat = await fs.stat(file);
      entries.push({
        pathname: relativePath,
        uploadedAt: stat.mtime,
        value: JSON.parse(contents) as T,
      });
    }

    return entries;
  }

  private absolutePath(pathname: string): string {
    return path.join(this.rootDirectory, pathname);
  }

  private async walk(directory: string): Promise<string[]> {
    try {
      const entries = await fs.readdir(directory, { withFileTypes: true });
      const files = await Promise.all(
        entries.map(async (entry) => {
          const entryPath = path.join(directory, entry.name);
          if (entry.isDirectory()) {
            return this.walk(entryPath);
          }
          return [entryPath];
        })
      );
      return files.flat();
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code == 'ENOENT') {
        return [];
      }
      throw error;
    }
  }
}

function createStorageDriver(): StorageDriver {
  const forceLocal = process.env.WORKFLOW_QUEUE_STORAGE == 'local';
  if (!forceLocal && process.env.BLOB_READ_WRITE_TOKEN) {
    const secret = process.env.WORKFLOW_QUEUE_SECRET ?? process.env.BLOB_READ_WRITE_TOKEN;
    return new BlobStorageDriver(new JsonCipher(secret));
  }

  const rootDirectory = process.env.WORKFLOW_QUEUE_LOCAL_DIR ?? path.join(process.cwd(), '.workflow-queue');
  return new LocalStorageDriver(rootDirectory);
}

export class WorkflowQueueService {
  private readonly driver: StorageDriver;
  private readonly scopeSalt: string;

  constructor(driver: StorageDriver = createStorageDriver()) {
    this.driver = driver;
    this.scopeSalt =
      process.env.WORKFLOW_QUEUE_SCOPE_SALT ??
      process.env.WORKFLOW_QUEUE_SECRET ??
      process.env.BLOB_READ_WRITE_TOKEN ??
      'talkie-local-workflow-scope';
  }

  async createRun(userId: string, input: CreateWorkflowRunInput): Promise<WorkflowRunRecord> {
    const now = new Date().toISOString();
    const run: WorkflowRunRecord = {
      id: randomUUID(),
      workflowId: input.workflowId,
      workflowName: input.workflowName,
      workflowIcon: input.workflowIcon,
      memoId: input.memoId,
      status: 'queued',
      executionClass: 'macOnly',
      routingMode: 'any',
      requestedByDeviceId: input.requestedByDeviceId,
      createdAt: now,
      updatedAt: now,
      runDate: now,
    };

    await this.writeRun(userId, run);
    await this.appendEvent(userId, run.id, {
      type: 'created',
      status: 'queued',
      message: 'Run queued for the next available Mac.',
    });
    return run;
  }

  async listRuns(userId: string, memoId?: string): Promise<WorkflowRunRecord[]> {
    const entries = await this.driver.listJSON<WorkflowRunRecord>(this.runsPrefix(userId));
    const runs: WorkflowRunRecord[] = [];

    for (const entry of entries) {
      if (memoId && entry.value.memoId != memoId) {
        continue;
      }
      runs.push(await this.reconcileRunLease(userId, entry.value));
    }

    return runs.sort((left, right) => Date.parse(right.updatedAt) - Date.parse(left.updatedAt));
  }

  async getRunDetails(userId: string, runId: string): Promise<WorkflowRunDetails | null> {
    const run = await this.readRun(userId, runId);
    if (!run) {
      return null;
    }

    return {
      run: await this.reconcileRunLease(userId, run),
      events: await this.listEvents(userId, runId),
    };
  }

  async registerExecutor(userId: string, input: ExecutorRegistrationInput): Promise<{ deviceId: string; heartbeatExpiresAt: string }> {
    const now = new Date();
    const record: ExecutorRecord = {
      deviceId: input.deviceId,
      name: input.name,
      platform: input.platform,
      status: input.status,
      priority: input.priority,
      capabilities: input.capabilities,
      installId: input.installId,
      appVersion: input.appVersion,
      tailscaleHostname: input.tailscaleHostname,
      metadata: input.metadata,
      lastHeartbeatAt: now.toISOString(),
      heartbeatExpiresAt: new Date(now.getTime() + EXECUTOR_HEARTBEAT_MS).toISOString(),
    };

    await this.driver.writeJSON(this.executorPath(userId, input.deviceId), record, { allowOverwrite: true });
    return { deviceId: input.deviceId, heartbeatExpiresAt: record.heartbeatExpiresAt };
  }

  async heartbeatExecutor(
    userId: string,
    input: ExecutorHeartbeatInput
  ): Promise<{ ok: boolean; heartbeatExpiresAt: string }> {
    const existing = (await this.driver.readJSON<ExecutorRecord>(this.executorPath(userId, input.deviceId))) ?? {
      deviceId: input.deviceId,
      name: 'Talkie Mac',
      platform: 'macos',
      status: input.status,
      priority: 100,
      capabilities: ['workflow'],
      installId: undefined,
      appVersion: undefined,
      tailscaleHostname: undefined,
      metadata: undefined,
      claimedRunId: undefined,
      lastHeartbeatAt: '',
      heartbeatExpiresAt: '',
    };

    const now = new Date();
    const updated: ExecutorRecord = {
      ...existing,
      status: input.status,
      claimedRunId: input.claimedRunId,
      metadata: {
        ...(existing.metadata ?? {}),
        ...(input.metadata ?? {}),
      },
      lastHeartbeatAt: now.toISOString(),
      heartbeatExpiresAt: new Date(now.getTime() + EXECUTOR_HEARTBEAT_MS).toISOString(),
    };

    await this.driver.writeJSON(this.executorPath(userId, input.deviceId), updated, { allowOverwrite: true });
    return { ok: true, heartbeatExpiresAt: updated.heartbeatExpiresAt };
  }

  async listClaimableRuns(userId: string, limit = 20): Promise<WorkflowRunRecord[]> {
    const runs = await this.listRuns(userId);
    return runs
      .filter((run) => run.status == 'queued' && run.executionClass == 'macOnly' && run.routingMode == 'any')
      .sort((left, right) => Date.parse(left.createdAt) - Date.parse(right.createdAt))
      .slice(0, limit);
  }

  async claimRun(userId: string, runId: string, deviceId: string, backendId?: string): Promise<ClaimRunResult> {
    const run = await this.readRun(userId, runId);
    if (!run) {
      throw new WorkflowQueueError('Workflow run not found.', 404);
    }

    const reconciledRun = await this.reconcileRunLease(userId, run);
    if (reconciledRun.status != 'queued') {
      return { granted: false, reason: 'Workflow run is no longer claimable.' };
    }

    const now = new Date();
    const leaseToken = randomUUID();
    const expiresAt = new Date(now.getTime() + LEASE_DURATION_MS).toISOString();
    const lock: RunLockRecord = {
      runId,
      deviceId,
      leaseToken,
      backendId,
      claimedAt: now.toISOString(),
      expiresAt,
      updatedAt: now.toISOString(),
    };

    const lockPath = this.lockPath(userId, runId);
    try {
      await this.driver.writeJSON(lockPath, lock, { allowOverwrite: false });
    } catch {
      const existingLock = await this.readLock(userId, runId);
      if (existingLock && !this.isExpired(existingLock.expiresAt)) {
        return { granted: false, reason: 'Workflow run is already claimed.' };
      }

      if (existingLock) {
        await this.driver.delete(lockPath);
        await this.driver.writeJSON(lockPath, lock, { allowOverwrite: false });
      } else {
        throw new WorkflowQueueError('Unable to claim workflow run.', 409);
      }
    }

    try {
      const updatedRun: WorkflowRunRecord = {
        ...reconciledRun,
        status: 'claimed',
        claimedByDeviceId: deviceId,
        leaseToken,
        leaseExpiresAt: expiresAt,
        backendId,
        updatedAt: now.toISOString(),
      };
      await this.writeRun(userId, updatedRun);
      await this.appendEvent(userId, runId, {
        type: 'claimed',
        status: 'claimed',
        deviceId,
        message: 'Mac claimed the queued run.',
      });
      return { granted: true, leaseToken, leaseExpiresAt: expiresAt };
    } catch (error) {
      await this.driver.delete(lockPath);
      throw error;
    }
  }

  async startRun(userId: string, runId: string, deviceId: string, leaseToken: string, backendId?: string): Promise<void> {
    await this.assertLockOwnership(userId, runId, deviceId, leaseToken);
    const run = await this.requireRun(userId, runId);
    const now = new Date().toISOString();

    await this.writeRun(userId, {
      ...run,
      status: 'running',
      backendId: backendId ?? run.backendId,
      updatedAt: now,
    });
    await this.appendEvent(userId, runId, {
      type: 'started',
      status: 'running',
      deviceId,
      message: 'Mac started executing the workflow.',
    });
  }

  async renewLease(userId: string, runId: string, deviceId: string, leaseToken: string): Promise<LeaseRenewalResult> {
    const lock = await this.assertLockOwnership(userId, runId, deviceId, leaseToken);
    const expiresAt = new Date(Date.now() + LEASE_DURATION_MS).toISOString();
    const refreshedLock: RunLockRecord = {
      ...lock,
      expiresAt,
      updatedAt: new Date().toISOString(),
    };

    await this.driver.writeJSON(this.lockPath(userId, runId), refreshedLock, { allowOverwrite: true });

    const run = await this.requireRun(userId, runId);
    await this.writeRun(userId, {
      ...run,
      leaseExpiresAt: expiresAt,
      updatedAt: new Date().toISOString(),
    });

    return { ok: true, leaseExpiresAt: expiresAt };
  }

  async releaseRun(userId: string, runId: string, deviceId: string, leaseToken: string, reason?: string): Promise<void> {
    await this.assertLockOwnership(userId, runId, deviceId, leaseToken);
    const run = await this.requireRun(userId, runId);
    await this.driver.delete(this.lockPath(userId, runId));

    const now = new Date().toISOString();
    await this.writeRun(userId, {
      ...run,
      status: 'queued',
      claimedByDeviceId: undefined,
      leaseToken: undefined,
      leaseExpiresAt: undefined,
      backendId: undefined,
      updatedAt: now,
    });
    await this.appendEvent(userId, runId, {
      type: 'released',
      status: 'queued',
      deviceId,
      message: reason ?? 'Run returned to the queue.',
    });
  }

  async completeRun(
    userId: string,
    runId: string,
    deviceId: string,
    leaseToken: string,
    backendId: string | undefined,
    finalOutputs: Record<string, string>,
    output?: string,
    stepOutputsJSON?: string
  ): Promise<WorkflowRunRecord> {
    await this.assertLockOwnership(userId, runId, deviceId, leaseToken);
    const run = await this.requireRun(userId, runId);
    const now = new Date().toISOString();
    const completedRun: WorkflowRunRecord = {
      ...run,
      status: 'completed',
      claimedByDeviceId: deviceId,
      leaseToken: undefined,
      leaseExpiresAt: undefined,
      backendId,
      finalOutputs,
      output: output ?? this.preferredOutput(finalOutputs),
      stepOutputsJSON,
      errorMessage: undefined,
      updatedAt: now,
      runDate: now,
    };

    await this.writeRun(userId, completedRun);
    await this.driver.delete(this.lockPath(userId, runId));
    await this.appendEvent(userId, runId, {
      type: 'completed',
      status: 'completed',
      deviceId,
      message: 'Workflow run completed successfully.',
    });
    return completedRun;
  }

  async failRun(
    userId: string,
    runId: string,
    deviceId: string,
    leaseToken: string,
    backendId: string | undefined,
    message: string
  ): Promise<WorkflowRunRecord> {
    await this.assertLockOwnership(userId, runId, deviceId, leaseToken);
    const run = await this.requireRun(userId, runId);
    const now = new Date().toISOString();
    const failedRun: WorkflowRunRecord = {
      ...run,
      status: 'failed',
      claimedByDeviceId: deviceId,
      leaseToken: undefined,
      leaseExpiresAt: undefined,
      backendId,
      output: message,
      errorMessage: message,
      updatedAt: now,
      runDate: now,
    };

    await this.writeRun(userId, failedRun);
    await this.driver.delete(this.lockPath(userId, runId));
    await this.appendEvent(userId, runId, {
      type: 'failed',
      status: 'failed',
      deviceId,
      message,
    });
    return failedRun;
  }

  private async listEvents(userId: string, runId: string): Promise<WorkflowRunEvent[]> {
    const entries = await this.driver.listJSON<WorkflowRunEvent>(this.eventsPrefix(userId, runId));
    return entries
      .map((entry) => entry.value)
      .sort((left, right) => Date.parse(left.createdAt) - Date.parse(right.createdAt));
  }

  private async appendEvent(
    userId: string,
    runId: string,
    input: Omit<WorkflowRunEvent, 'id' | 'runId' | 'createdAt'>
  ): Promise<void> {
    const createdAt = new Date().toISOString();
    const event: WorkflowRunEvent = {
      id: randomUUID(),
      runId,
      createdAt,
      ...input,
    };
    const timestamp = createdAt.replaceAll(':', '-');
    await this.driver.writeJSON(
      `${this.eventsPrefix(userId, runId)}${timestamp}-${event.id}.json`,
      event,
      { allowOverwrite: false }
    );
  }

  private async requireRun(userId: string, runId: string): Promise<WorkflowRunRecord> {
    const run = await this.readRun(userId, runId);
    if (!run) {
      throw new WorkflowQueueError('Workflow run not found.', 404);
    }
    return run;
  }

  private async readRun(userId: string, runId: string): Promise<WorkflowRunRecord | null> {
    return this.driver.readJSON<WorkflowRunRecord>(this.runPath(userId, runId));
  }

  private async writeRun(userId: string, run: WorkflowRunRecord): Promise<void> {
    await this.driver.writeJSON(this.runPath(userId, run.id), run, { allowOverwrite: true });
  }

  private async readLock(userId: string, runId: string): Promise<RunLockRecord | null> {
    return this.driver.readJSON<RunLockRecord>(this.lockPath(userId, runId));
  }

  private async assertLockOwnership(
    userId: string,
    runId: string,
    deviceId: string,
    leaseToken: string
  ): Promise<RunLockRecord> {
    const lock = await this.readLock(userId, runId);
    if (!lock) {
      throw new WorkflowQueueError('Workflow run lease is no longer valid.', 409);
    }

    if (this.isExpired(lock.expiresAt)) {
      await this.driver.delete(this.lockPath(userId, runId));
      throw new WorkflowQueueError('Workflow run lease expired.', 409);
    }

    if (lock.deviceId != deviceId || lock.leaseToken != leaseToken) {
      throw new WorkflowQueueError('Workflow run lease belongs to another executor.', 409);
    }

    return lock;
  }

  private async reconcileRunLease(userId: string, run: WorkflowRunRecord): Promise<WorkflowRunRecord> {
    if (run.status != 'claimed' && run.status != 'running') {
      return run;
    }

    const lock = await this.readLock(userId, run.id);
    if (!lock || this.isExpired(lock.expiresAt) || lock.leaseToken != run.leaseToken) {
      if (lock && this.isExpired(lock.expiresAt)) {
        await this.driver.delete(this.lockPath(userId, run.id));
      }

      const releasedRun: WorkflowRunRecord = {
        ...run,
        status: 'queued',
        claimedByDeviceId: undefined,
        leaseToken: undefined,
        leaseExpiresAt: undefined,
        backendId: undefined,
        updatedAt: new Date().toISOString(),
      };
      await this.writeRun(userId, releasedRun);
      return releasedRun;
    }

    if (run.leaseExpiresAt != lock.expiresAt) {
      const refreshedRun: WorkflowRunRecord = {
        ...run,
        leaseExpiresAt: lock.expiresAt,
      };
      await this.writeRun(userId, refreshedRun);
      return refreshedRun;
    }

    return run;
  }

  private preferredOutput(finalOutputs: Record<string, string>): string | undefined {
    const priorityKeys = ['OUTPUT', 'PREVIOUS_OUTPUT', 'final', 'summary', 'result'];
    for (const key of priorityKeys) {
      const value = finalOutputs[key]?.trim();
      if (value) {
        return value;
      }
    }

    const candidates = Object.entries(finalOutputs)
      .filter(([key, value]) => key != 'WORKFLOW_NAME' && value.trim().length > 0)
      .sort((left, right) => right[1].length - left[1].length);
    return candidates[0]?.[1];
  }

  private userScope(userId: string): string {
    const digest = createHash('sha256').update(`${this.scopeSalt}:${userId}`).digest('hex');
    return `${WORKFLOW_QUEUE_PREFIX}/${digest.slice(0, 32)}`;
  }

  private runsPrefix(userId: string): string {
    return `${this.userScope(userId)}/runs/`;
  }

  private runPath(userId: string, runId: string): string {
    return `${this.runsPrefix(userId)}${runId}.json`;
  }

  private eventsPrefix(userId: string, runId: string): string {
    return `${this.userScope(userId)}/events/${runId}/`;
  }

  private lockPath(userId: string, runId: string): string {
    return `${this.userScope(userId)}/locks/${runId}.json`;
  }

  private executorPath(userId: string, deviceId: string): string {
    return `${this.userScope(userId)}/executors/${deviceId}.json`;
  }

  private isExpired(isoTimestamp: string): boolean {
    return Date.parse(isoTimestamp) <= Date.now();
  }
}
