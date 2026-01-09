/**
 * Windows Resource Routes (RESTful)
 *
 * GET  /windows                  - List all terminal windows
 * GET  /windows/:id              - Single window details
 * GET  /windows/:id/screenshot   - Window screenshot (JPEG)
 * GET  /windows/:id/content      - AX text content (future)
 * GET  /windows/captures         - Batch: all screenshots + AX
 *
 * Flow: Bridge (8765) → TalkieServer (8766) → XPC → TalkieLive
 */

import { log } from "../../log";
import { serviceUnavailable, serverError, notFound, notImplemented, proxyError, jpeg } from "./responses";

// ===== Types =====

export interface WindowInfo {
  windowID: number;
  title?: string;
  bounds?: { x: number; y: number; width: number; height: number };
}

export interface WindowsListResponse {
  windows: WindowInfo[];
}

export interface WindowResponse {
  window: WindowInfo;
}

export interface CapturesResponse {
  count: number;
  screenshots: Array<{
    windowID: number;
    data: string;
  }>;
}

// ===== Config =====

const TALKIESERVER_PORT = 8766;
const TALKIESERVER_URL = `http://127.0.0.1:${TALKIESERVER_PORT}`;

// ===== Proxy Helper =====

type ProxyResult<T> = T | Response;

/**
 * Wraps a TalkieServer proxy call with health check and error handling
 */
async function withTalkieServer<T>(
  operation: string,
  fn: () => Promise<T>
): Promise<ProxyResult<T>> {
  if (!(await checkTalkieServer())) {
    return serviceUnavailable("Talkie not running", "Start Talkie.app to enable window operations");
  }

  try {
    return await fn();
  } catch (error) {
    log.error(`${operation} failed: ${error}`);
    return serverError(`Failed to ${operation.toLowerCase()}`, String(error));
  }
}

async function checkTalkieServer(): Promise<boolean> {
  try {
    const response = await fetch(`${TALKIESERVER_URL}/health`, {
      signal: AbortSignal.timeout(2000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

// ===== Handlers =====

/**
 * GET /windows
 * List all terminal windows with metadata
 */
export async function listWindows(): Promise<ProxyResult<WindowsListResponse>> {
  log.info("GET /windows");

  return withTalkieServer("List windows", async () => {
    const response = await fetch(`${TALKIESERVER_URL}/windows/claude`);
    return await response.json() as WindowsListResponse;
  });
}

/**
 * GET /windows/:id
 * Get single window details
 */
export async function getWindow(windowId: string): Promise<ProxyResult<WindowResponse>> {
  log.info(`GET /windows/${windowId}`);

  return withTalkieServer("Get window", async () => {
    const response = await fetch(`${TALKIESERVER_URL}/windows/claude`);
    const data = await response.json() as WindowsListResponse;

    const window = data.windows?.find(w => w.windowID === parseInt(windowId, 10));
    if (!window) {
      return notFound("Window not found");
    }

    return { window };
  });
}

/**
 * GET /windows/:id/screenshot
 * Get window screenshot (returns JPEG)
 */
export async function getWindowScreenshot(windowId: string): Promise<Response> {
  log.info(`GET /windows/${windowId}/screenshot`);

  if (!(await checkTalkieServer())) {
    return serviceUnavailable("Talkie not running", "Start Talkie.app to enable window operations");
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/screenshot/window/${windowId}`);

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({})) as { error?: string };
      return proxyError(response.status, errorData.error || "Failed to capture window");
    }

    const imageData = await response.arrayBuffer();
    return jpeg(imageData);
  } catch (error) {
    log.error(`Failed to capture window: ${error}`);
    return serverError("Failed to capture window", String(error));
  }
}

/**
 * GET /windows/:id/content
 * Get window AX text content (placeholder for future)
 */
export function getWindowContent(windowId: string): Response {
  log.info(`GET /windows/${windowId}/content`);
  return notImplemented("Not implemented yet", "Use /windows/captures for batch AX data");
}

/**
 * GET /windows/captures
 * Batch capture: all terminal windows with screenshots + AX
 */
export async function captureAllWindows(): Promise<ProxyResult<CapturesResponse>> {
  log.info("GET /windows/captures");

  return withTalkieServer("Capture windows", async () => {
    const response = await fetch(`${TALKIESERVER_URL}/screenshot/terminals`);

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`TalkieServer error (${response.status}): ${errorText}`);
      return proxyError(response.status, "TalkieServer error", errorText);
    }

    const data = await response.json() as CapturesResponse;
    log.info(`GET /windows/captures - Success: ${data.count ?? data.screenshots?.length ?? 0} window(s) captured`);

    return data;
  });
}
