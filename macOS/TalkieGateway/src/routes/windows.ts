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

import { log } from "../log";

const TALKIESERVER_PORT = 8766;
const TALKIESERVER_URL = `http://127.0.0.1:${TALKIESERVER_PORT}`;

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

function serviceUnavailable(): Response {
  return Response.json(
    {
      error: "Talkie not running",
      hint: "Start Talkie.app to enable window operations"
    },
    { status: 503 }
  );
}

/**
 * GET /windows
 * List all terminal windows with metadata
 */
export async function listWindows(req: Request): Promise<Response> {
  log.info("GET /windows");

  if (!(await checkTalkieServer())) {
    return serviceUnavailable();
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/windows/claude`);
    const data = await response.json();
    return Response.json(data);
  } catch (error) {
    log.error(`Failed to list windows: ${error}`);
    return Response.json({ error: "Failed to list windows" }, { status: 500 });
  }
}

/**
 * GET /windows/:id
 * Get single window details
 */
export async function getWindow(req: Request, windowId: string): Promise<Response> {
  log.info(`GET /windows/${windowId}`);

  if (!(await checkTalkieServer())) {
    return serviceUnavailable();
  }

  try {
    // Get all windows and filter to the requested one
    const response = await fetch(`${TALKIESERVER_URL}/windows/claude`);
    const data = await response.json() as { windows?: Array<{ windowID: number }> };

    const window = data.windows?.find(w => w.windowID === parseInt(windowId, 10));
    if (!window) {
      return Response.json({ error: "Window not found" }, { status: 404 });
    }

    return Response.json({ window });
  } catch (error) {
    log.error(`Failed to get window: ${error}`);
    return Response.json({ error: "Failed to get window" }, { status: 500 });
  }
}

/**
 * GET /windows/:id/screenshot
 * Get window screenshot (returns JPEG)
 */
export async function getWindowScreenshot(req: Request, windowId: string): Promise<Response> {
  log.info(`GET /windows/${windowId}/screenshot`);

  if (!(await checkTalkieServer())) {
    return serviceUnavailable();
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/screenshot/window/${windowId}`);

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      return Response.json(
        { error: errorData.error || "Failed to capture window" },
        { status: response.status }
      );
    }

    const imageData = await response.arrayBuffer();
    return new Response(imageData, {
      headers: {
        "Content-Type": "image/jpeg",
        "Content-Length": imageData.byteLength.toString(),
        "Cache-Control": "no-cache",
      },
    });
  } catch (error) {
    log.error(`Failed to capture window: ${error}`);
    return Response.json({ error: "Failed to capture window" }, { status: 500 });
  }
}

/**
 * GET /windows/:id/content
 * Get window AX text content (placeholder for future)
 */
export async function getWindowContent(req: Request, windowId: string): Promise<Response> {
  log.info(`GET /windows/${windowId}/content`);

  // TODO: Implement AX content extraction via XPC
  return Response.json(
    { error: "Not implemented yet", hint: "Use /windows/captures for batch AX data" },
    { status: 501 }
  );
}

/**
 * GET /windows/captures
 * Batch capture: all terminal windows with screenshots + AX
 */
export async function captureAllWindows(req: Request): Promise<Response> {
  log.info("GET /windows/captures - Requesting terminal screenshots from TalkieServer");

  if (!(await checkTalkieServer())) {
    log.warn("GET /windows/captures - TalkieServer not available on port 8766");
    return serviceUnavailable();
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/screenshot/terminals`);

    if (!response.ok) {
      const errorText = await response.text();
      log.error(`TalkieServer error (${response.status}): ${errorText}`);
      return Response.json(
        { error: "TalkieServer error", details: errorText },
        { status: response.status }
      );
    }

    const data = await response.json();
    const count = data?.count ?? data?.screenshots?.length ?? 0;
    log.info(`GET /windows/captures - Success: ${count} window(s) captured`);

    return Response.json(data);
  } catch (error) {
    log.error(`Failed to capture windows: ${error}`);
    return Response.json(
      { error: "Failed to capture windows", details: String(error) },
      { status: 500 }
    );
  }
}
