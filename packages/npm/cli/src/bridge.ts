import {
  resolveService,
  getUid,
} from "./commands/dev/services";
import { findLatestBuild, launchViaLaunchd } from "./commands/dev/start";
import { BRIDGE_PORTS } from "./ports";

/**
 * Call a method on a ServiceBridge via WebSocket JSON-RPC.
 * Bun has native WebSocket client support.
 */
export function callBridge(
  port: number,
  method: string,
  params?: Record<string, unknown>,
  timeoutMs = 30000
): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const id = crypto.randomUUID();
    const timer = setTimeout(() => {
      reject(new Error(`Bridge call '${method}' timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);

    ws.onopen = () => {
      const request: Record<string, unknown> = { id, method };
      if (params) request.params = params;
      ws.send(JSON.stringify(request));
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(String(event.data)) as Record<string, unknown>;
        // Skip progress events from streaming handlers — wait for final result
        if (data.event) return;
        clearTimeout(timer);
        if (data.error) {
          reject(new Error(String(data.error)));
        } else {
          resolve((data.result as Record<string, unknown>) ?? {});
        }
        ws.close();
      } catch (e) {
        clearTimeout(timer);
        reject(new Error(`Invalid response: ${e}`));
        ws.close();
      }
    };

    ws.onerror = () => {
      clearTimeout(timer);
      reject(new Error(`Cannot connect to service on port ${port}. It may still be starting — try again in a few seconds.`));
    };

    ws.onclose = () => {
      clearTimeout(timer);
    };
  });
}

/**
 * Call a method on a ServiceBridge via WebSocket JSON-RPC with streaming progress.
 * Messages with an `event` field are progress events; messages with `result` or `error` are final.
 * The timeout resets on each progress event (the sync is alive, just slow).
 */
export function callBridgeStreaming(
  port: number,
  method: string,
  params: Record<string, unknown> | undefined,
  onProgress: (event: string, data: Record<string, unknown>) => void,
  timeoutMs = 120000
): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const id = crypto.randomUUID();
    let timer = setTimeout(() => {
      reject(new Error(`Bridge call '${method}' timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    const resetTimeout = () => {
      clearTimeout(timer);
      timer = setTimeout(() => {
        reject(new Error(`Bridge call '${method}' timed out after ${timeoutMs}ms`));
      }, timeoutMs);
    };

    const ws = new WebSocket(`ws://127.0.0.1:${port}`);

    ws.onopen = () => {
      const request: Record<string, unknown> = { id, method };
      if (params) request.params = params;
      ws.send(JSON.stringify(request));
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(String(event.data)) as Record<string, unknown>;

        // Progress event — forward and keep listening
        if (data.event) {
          resetTimeout();
          onProgress(
            String(data.event),
            (data.data as Record<string, unknown>) ?? {}
          );
          return;
        }

        // Final response
        clearTimeout(timer);
        if (data.error) {
          reject(new Error(String(data.error)));
        } else {
          resolve((data.result as Record<string, unknown>) ?? {});
        }
        ws.close();
      } catch (e) {
        clearTimeout(timer);
        reject(new Error(`Invalid response: ${e}`));
        ws.close();
      }
    };

    ws.onerror = () => {
      clearTimeout(timer);
      reject(
        new Error(
          `WebSocket error — is the service running? (ws://127.0.0.1:${port})`
        )
      );
    };

    ws.onclose = () => {
      clearTimeout(timer);
    };
  });
}

/** Check if a service is running — checks for a live process, not just launchd registration. */
export function isServiceRunning(serviceName: string): boolean {
  const service = resolveService(serviceName);
  if (!service) return false;

  // Check launchd — but verify the PID is actually alive
  if (service.launchdLabel) {
    const uid = getUid();
    const result = Bun.spawnSync(
      ["launchctl", "print", `gui/${uid}/${service.launchdLabel}`],
      { stdout: "pipe", stderr: "pipe" }
    );
    if (result.exitCode === 0) {
      // Extract PID from launchctl print output
      const output = result.stdout.toString();
      const pidMatch = output.match(/pid\s*=\s*(\d+)/);
      if (pidMatch) {
        // Verify the PID is actually alive
        const kill0 = Bun.spawnSync(["kill", "-0", pidMatch[1]], { stderr: "pipe" });
        if (kill0.exitCode === 0) return true;
      }
      // Registered but no live PID — stale registration
    }
  }

  // Fallback: check if process is running by name
  const execName = service.appName.replace(".app", "");
  const pgrep = Bun.spawnSync(["pgrep", "-x", execName]);
  return pgrep.exitCode === 0;
}

/** Check if a bridge port is actually accepting connections. */
export function isBridgeReady(port: number): boolean {
  try {
    const nc = Bun.spawnSync(
      ["nc", "-z", "127.0.0.1", String(port)],
      { stdout: "pipe", stderr: "pipe", timeout: 2000 }
    );
    return nc.exitCode === 0;
  } catch {
    return false;
  }
}

/** Get the bridge port for a service, if it has one. */
function bridgePortFor(serviceName: string): number | null {
  const key = serviceName.toLowerCase() as keyof typeof BRIDGE_PORTS;
  return BRIDGE_PORTS[key] ?? null;
}

/** Wait for a bridge port to accept connections. */
function waitForBridge(port: number, maxWaitMs = 8000): boolean {
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    if (isBridgeReady(port)) return true;
    Bun.sleepSync(500);
  }
  return false;
}

/** Ensure a service is running — tries launchd first, falls back to `open`.
 *  For services with a bridge port, waits until the port is ready. */
export function ensureServiceRunning(
  serviceName: string
): { ok: boolean; error?: string; started?: boolean } {
  const port = bridgePortFor(serviceName);

  // If already running and bridge is ready, we're good
  if (isServiceRunning(serviceName)) {
    if (port && !isBridgeReady(port)) {
      // Process exists but bridge not ready — wait briefly
      if (waitForBridge(port, 3000)) return { ok: true };
      // Process running but bridge dead — stale process
      return { ok: false, error: `${serviceName} process is running but bridge port ${port} is not responding. Try: talkie-dev stop ${serviceName} && talkie-dev start ${serviceName}` };
    }
    return { ok: true };
  }

  const service = resolveService(serviceName);
  if (!service) return { ok: false, error: `${serviceName} service not found in config` };

  const build = findLatestBuild(service);
  if (!build) {
    return {
      ok: false,
      error: `No ${service.name} build found. Run: talkie-dev build ${serviceName}`,
    };
  }

  // Try launchd first (for services with MachServices)
  if (service.launchdLabel && service.machServices) {
    const result = launchViaLaunchd(service, build.path);
    if (result.success && port) {
      if (waitForBridge(port)) return { ok: true, started: true };
    } else if (result.success) {
      Bun.sleepSync(1000);
      if (isServiceRunning(serviceName)) return { ok: true, started: true };
    }
  }

  // Fallback: launch via `open` (works reliably for all services including TalkieSync)
  const openResult = Bun.spawnSync(["open", build.path]);
  if (openResult.exitCode === 0) {
    if (port) {
      if (waitForBridge(port)) return { ok: true, started: true };
      return { ok: false, error: `${service.name} launched but bridge not ready on port ${port} after 8s` };
    }
    // No bridge port — just check process
    for (let i = 0; i < 6; i++) {
      Bun.sleepSync(500);
      if (isServiceRunning(serviceName)) return { ok: true, started: true };
    }
    return { ok: false, error: `${service.name} launched but not responding after 3s` };
  }

  return { ok: false, error: `Failed to launch ${service.name}` };
}
