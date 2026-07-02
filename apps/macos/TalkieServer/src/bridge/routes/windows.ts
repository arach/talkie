/**
 * Windows Resource Routes (RESTful)
 *
 * GET  /windows                  - List all terminal windows
 * GET  /windows/:id              - Single window details
 * GET  /windows/:id/screenshot   - Window screenshot (JPEG)
 * GET  /windows/:id/content      - AX text content (future)
 * GET  /windows/captures         - Batch: all screenshots + AX
 *
 * Flow: Bridge (8765) → TalkieAgent (8767), with Talkie.app fallback for older agents
 */

import { log } from "../../log";
import { talkieServerFetch } from "../talkie-local-client";
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
const TALKIEAGENT_PORT = 8767;
const TALKIEAGENT_URL = `http://127.0.0.1:${TALKIEAGENT_PORT}/v1/agent`;

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

async function tryAgentRoute(path: string): Promise<Response | null> {
  try {
    const response = await fetch(`${TALKIEAGENT_URL}${path}`, {
      signal: AbortSignal.timeout(5000),
    });
    if (response.status === 404) {
      return null;
    }
    return response;
  } catch (error) {
    log.debug(`Agent window route unavailable, falling back to Talkie.app: ${error}`);
    return null;
  }
}

async function agentJSON<T>(
  path: string,
  operation: string
): Promise<ProxyResult<T> | null> {
  const response = await tryAgentRoute(path);
  if (!response) {
    return null;
  }

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    log.warn(`Agent ${operation} returned ${response.status}: ${errorText}`);
    return proxyError(response.status, `Agent ${operation} failed`, errorText);
  }

  return await response.json() as T;
}

// ===== Handlers =====

/**
 * GET /windows
 * List all terminal windows with metadata
 */
export async function listWindows(): Promise<ProxyResult<WindowsListResponse>> {
  log.info("GET /windows");

  const agentResult = await agentJSON<WindowsListResponse>("/windows/claude", "list windows");
  if (agentResult) {
    return agentResult;
  }

  return withTalkieServer("List windows", async () => {
    const response = await talkieServerFetch(`${TALKIESERVER_URL}/windows/claude`);
    return await response.json() as WindowsListResponse;
  });
}

/**
 * GET /windows/:id
 * Get single window details
 */
export async function getWindow(windowId: string): Promise<ProxyResult<WindowResponse>> {
  log.info(`GET /windows/${windowId}`);

  const agentResult = await agentJSON<WindowsListResponse>("/windows/claude", "get window");
  if (agentResult instanceof Response) {
    return agentResult;
  }
  if (agentResult) {
    const window = agentResult.windows?.find(w => w.windowID === parseInt(windowId, 10));
    return window ? { window } : notFound("Window not found");
  }

  return withTalkieServer("Get window", async () => {
    const response = await talkieServerFetch(`${TALKIESERVER_URL}/windows/claude`);
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

  const agentResponse = await tryAgentRoute(`/screenshot/window/${windowId}`);
  if (agentResponse) {
    if (!agentResponse.ok) {
      const errorText = await agentResponse.text().catch(() => "");
      return proxyError(agentResponse.status, "Agent window screenshot failed", errorText);
    }
    return agentResponse;
  }

  if (!(await checkTalkieServer())) {
    return serviceUnavailable("Talkie not running", "Start Talkie.app to enable window operations");
  }

  try {
    const response = await talkieServerFetch(`${TALKIESERVER_URL}/screenshot/window/${windowId}`);

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

  const agentResponse = await tryAgentRoute("/screenshot/terminals");
  if (agentResponse) {
    if (!agentResponse.ok) {
      const errorText = await agentResponse.text().catch(() => "");
      return proxyError(agentResponse.status, "Agent window captures failed", errorText);
    }
    return agentResponse;
  }

  return withTalkieServer("Capture windows", async () => {
    const response = await talkieServerFetch(`${TALKIESERVER_URL}/screenshot/terminals`);

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
