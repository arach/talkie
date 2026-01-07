/**
 * Window & Screenshot Routes
 *
 * GET /windows             - Full metadata for all windows (360° view)
 * GET /windows/captures    - Screenshots + AX data for terminal windows
 * GET /windows/:id/screenshot - Single window screenshot (JPEG)
 *
 * Routes forward to TalkieServer (8766) → XPC → TalkieLive
 */

import { log } from "../log";

// TalkieServer (Talkie main app) handles requests via XPC to TalkieLive
const TALKIESERVER_PORT = 8766;
const TALKIESERVER_URL = `http://127.0.0.1:${TALKIESERVER_PORT}`;

/**
 * Check if TalkieServer is running
 */
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

/**
 * GET /windows
 * Full 360° description of all terminal windows
 * Returns metadata, titles, bounds, app info
 */
export async function windowsRoute(req: Request): Promise<Response> {
  log.info("Windows metadata request");

  if (!(await checkTalkieServer())) {
    return Response.json(
      { error: "Talkie not running", hint: "Start Talkie to enable window listing" },
      { status: 503 }
    );
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/windows/claude`);
    const data = await response.json();
    return Response.json(data);
  } catch (error) {
    log.error(`Windows list failed: ${error}`);
    return Response.json({ error: "Failed to list windows" }, { status: 500 });
  }
}

/**
 * GET /windows/captures
 * Screenshots + AX JSON for all terminal windows
 * Returns array with window info and base64-encoded images
 */
export async function windowsCapturesRoute(req: Request): Promise<Response> {
  log.info("Windows captures request (screenshots + AX)");

  if (!(await checkTalkieServer())) {
    return Response.json(
      { error: "Talkie not running", hint: "Start Talkie to enable screenshots" },
      { status: 503 }
    );
  }

  try {
    const response = await fetch(`${TALKIESERVER_URL}/screenshot/terminals`);
    const data = await response.json();
    return Response.json(data);
  } catch (error) {
    log.error(`Windows captures failed: ${error}`);
    return Response.json({ error: "Failed to capture windows" }, { status: 500 });
  }
}

/**
 * GET /windows/:id/screenshot
 * Single window screenshot (returns JPEG image)
 */
export async function windowScreenshotRoute(req: Request, windowId: string): Promise<Response> {
  log.info(`Window screenshot request: ${windowId}`);

  if (!(await checkTalkieServer())) {
    return Response.json(
      { error: "Talkie not running", hint: "Start Talkie to enable screenshots" },
      { status: 503 }
    );
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

    // Return the JPEG image directly
    const imageData = await response.arrayBuffer();
    return new Response(imageData, {
      headers: {
        "Content-Type": "image/jpeg",
        "Content-Length": imageData.byteLength.toString(),
      },
    });
  } catch (error) {
    log.error(`Window screenshot failed: ${error}`);
    return Response.json({ error: "Failed to capture window" }, { status: 500 });
  }
}

// Legacy exports for backwards compatibility
export const screenshotTerminalsRoute = windowsCapturesRoute;
export const screenshotWindowRoute = windowScreenshotRoute;
export const claudeWindowsRoute = windowsRoute;
