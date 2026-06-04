import { existsSync, watch, type FSWatcher } from "node:fs";
import path from "node:path";
import { log } from "../../log";
import {
  companionStateRoute,
  resolveRuntimeSignalFilePaths,
  resolveSettingsFilePath,
  type CompanionStateResponse,
} from "./companion";

type CompanionEventsSocket = {
  send(payload: string): void;
  close(): void;
  data?: unknown;
  raw?: object;
};

type CompanionSubscriptionOptions = {
  deviceId?: string;
  deviceClass?: "ipad" | "iphone";
};

type SocketState = {
  inflight: boolean;
  lastSerializedState?: string;
  pendingReason?: string;
  pollTimer?: ReturnType<typeof setTimeout>;
  refreshTimer?: ReturnType<typeof setTimeout>;
  settingsWatcher?: FSWatcher;
  runtimeWatchers: FSWatcher[];
};

type CompanionEventEnvelope = {
  type: "companion:ready" | "companion:update" | "companion:error";
  snapshot?: CompanionStateResponse;
  reason?: string;
  error?: string;
};

const ACTIVE_POLL_INTERVAL_MS = 1000;
const IDLE_POLL_INTERVAL_MS = 30000;
const RETRY_POLL_INTERVAL_MS = 5000;
const SETTINGS_REFRESH_DEBOUNCE_MS = 250;
const RUNTIME_REFRESH_DEBOUNCE_MS = 40;

const socketStateByKey = new WeakMap<object, SocketState>();

export const companionEventsSocket = {
  open(ws: CompanionEventsSocket) {
    const socketKey = rawSocketKey(ws);
    socketStateByKey.set(socketKey, { inflight: false, runtimeWatchers: [] });
    attachSettingsWatcher(ws);
    attachRuntimeWatchers(ws);
    void publishSnapshot(ws, "initial");
  },

  message(ws: CompanionEventsSocket, rawMessage: unknown) {
    let message: { type?: string } | null = null;

    try {
      if (typeof rawMessage === "string") {
        message = JSON.parse(rawMessage);
      } else if (rawMessage instanceof Buffer) {
        message = JSON.parse(rawMessage.toString());
      } else if (rawMessage && typeof rawMessage === "object") {
        message = rawMessage as { type?: string };
      }
    } catch {
      sendEnvelope(ws, {
        type: "companion:error",
        error: "Invalid companion event message",
      });
      return;
    }

    if (message?.type === "companion:refresh") {
      void publishSnapshot(ws, "requested");
    }
  },

  close(ws: CompanionEventsSocket) {
    teardownSocket(ws);
  },
};

function rawSocketKey(ws: CompanionEventsSocket): object {
  return ws.raw ?? ws;
}

function subscriptionOptions(ws: CompanionEventsSocket): CompanionSubscriptionOptions {
  const query = ((ws as any).data?.query ?? {}) as Record<string, string | undefined>;
  const deviceId = typeof query.deviceId === "string" && query.deviceId.trim().length > 0
    ? query.deviceId.trim()
    : undefined;
  const deviceClass = query.deviceClass === "ipad" || query.deviceClass === "iphone"
    ? query.deviceClass
    : undefined;

  return { deviceId, deviceClass };
}

function attachSettingsWatcher(ws: CompanionEventsSocket) {
  const socketKey = rawSocketKey(ws);
  const state = socketStateByKey.get(socketKey);
  const settingsFilePath = resolveSettingsFilePath();

  if (!state || !settingsFilePath) {
    return;
  }

  const settingsDirectory = path.dirname(settingsFilePath);
  const settingsFilename = path.basename(settingsFilePath);

  try {
    const watcher = watch(settingsDirectory, (_eventType, changedFile) => {
      const changedName = typeof changedFile === "string"
        ? changedFile
        : changedFile?.toString();

      if (changedName && changedName !== settingsFilename) {
        return;
      }

      scheduleImmediateRefresh(ws, "settings", SETTINGS_REFRESH_DEBOUNCE_MS);
    });

    watcher.on("error", (error) => {
      log.warn(`Companion events settings watcher failed: ${error}`);
    });

    state.settingsWatcher = watcher;
  } catch (error) {
    log.warn(`Companion events could not watch settings: ${error}`);
  }
}

function attachRuntimeWatchers(ws: CompanionEventsSocket) {
  const socketKey = rawSocketKey(ws);
  const state = socketStateByKey.get(socketKey);

  if (!state) {
    return;
  }

  const watchedDirectories = new Map<string, Set<string>>();

  for (const filePath of resolveRuntimeSignalFilePaths()) {
    const directory = path.dirname(filePath);
    if (!existsSync(directory)) {
      continue;
    }

    const filenames = watchedDirectories.get(directory) ?? new Set<string>();
    filenames.add(path.basename(filePath));
    watchedDirectories.set(directory, filenames);
  }

  for (const [directory, filenames] of watchedDirectories.entries()) {
    try {
      const watcher = watch(directory, (_eventType, changedFile) => {
        const changedName = typeof changedFile === "string"
          ? changedFile
          : changedFile?.toString();

        if (changedName && !filenames.has(changedName)) {
          return;
        }

        scheduleImmediateRefresh(ws, "runtime", RUNTIME_REFRESH_DEBOUNCE_MS);
      });

      watcher.on("error", (error) => {
        log.warn(`Companion events runtime watcher failed: ${error}`);
      });

      state.runtimeWatchers.push(watcher);
    } catch (error) {
      log.warn(`Companion events could not watch runtime signals: ${error}`);
    }
  }
}

function scheduleImmediateRefresh(
  ws: CompanionEventsSocket,
  reason: string,
  debounceMs = SETTINGS_REFRESH_DEBOUNCE_MS
) {
  const socketKey = rawSocketKey(ws);
  const state = socketStateByKey.get(socketKey);

  if (!state) {
    return;
  }

  if (state.refreshTimer) {
    clearTimeout(state.refreshTimer);
  }

  state.refreshTimer = setTimeout(() => {
    state.refreshTimer = undefined;
    void publishSnapshot(ws, reason);
  }, debounceMs);
}

function scheduleNextPoll(ws: CompanionEventsSocket, snapshot?: CompanionStateResponse, retry = false) {
  const socketKey = rawSocketKey(ws);
  const state = socketStateByKey.get(socketKey);

  if (!state) {
    return;
  }

  if (state.pollTimer) {
    clearTimeout(state.pollTimer);
  }

  const hasActiveRuntime = (snapshot?.shortcutStates?.length ?? 0) > 0;
  const intervalMs = retry
    ? RETRY_POLL_INTERVAL_MS
    : hasActiveRuntime
      ? ACTIVE_POLL_INTERVAL_MS
      : IDLE_POLL_INTERVAL_MS;

  state.pollTimer = setTimeout(() => {
    void publishSnapshot(ws, "poll");
  }, intervalMs);
}

async function publishSnapshot(ws: CompanionEventsSocket, reason: string) {
  const socketKey = rawSocketKey(ws);
  const state = socketStateByKey.get(socketKey);

  if (!state) {
    return;
  }

  if (state.inflight) {
    if (!state.pendingReason || state.pendingReason === "poll" || reason === "requested") {
      state.pendingReason = reason;
    }
    return;
  }

  state.inflight = true;

  try {
    const snapshot = await companionStateRoute(subscriptionOptions(ws));
    const serializedSnapshot = JSON.stringify(snapshot);
    const isInitial = state.lastSerializedState === undefined;

    if (isInitial || state.lastSerializedState !== serializedSnapshot || reason === "requested") {
      state.lastSerializedState = serializedSnapshot;
      sendEnvelope(ws, {
        type: isInitial ? "companion:ready" : "companion:update",
        snapshot,
        reason,
      });
    }

    scheduleNextPoll(ws, snapshot);
  } catch (error) {
    log.warn(`Companion events snapshot failed: ${error}`);
    sendEnvelope(ws, {
      type: "companion:error",
      error: error instanceof Error ? error.message : String(error),
      reason,
    });
    scheduleNextPoll(ws, undefined, true);
  } finally {
    const latestState = socketStateByKey.get(socketKey);
    if (latestState) {
      latestState.inflight = false;
      const pendingReason = latestState.pendingReason;
      latestState.pendingReason = undefined;

      if (pendingReason) {
        void publishSnapshot(ws, pendingReason);
      }
    }
  }
}

function sendEnvelope(ws: CompanionEventsSocket, payload: CompanionEventEnvelope) {
  try {
    ws.send(JSON.stringify(payload));
  } catch (error) {
    log.warn(`Companion events send failed: ${error}`);
    teardownSocket(ws);

    try {
      ws.close();
    } catch {}
  }
}

function teardownSocket(ws: CompanionEventsSocket) {
  const socketKey = rawSocketKey(ws);
  const state = socketStateByKey.get(socketKey);

  if (!state) {
    return;
  }

  if (state.pollTimer) {
    clearTimeout(state.pollTimer);
  }

  if (state.refreshTimer) {
    clearTimeout(state.refreshTimer);
  }

  try {
    state.settingsWatcher?.close();
  } catch {}

  for (const watcher of state.runtimeWatchers) {
    try {
      watcher.close();
    } catch {}
  }

  socketStateByKey.delete(socketKey);
}
