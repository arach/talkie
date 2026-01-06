import { Elysia } from "elysia";

import { getTailscaleState, getStateMessage } from "./tailscale/status";
import { healthRoute } from "./routes/health";
import { pathsRoute, sessionsRoute, sessionMessagesRoute } from "./routes/sessions";
import { sessionMetadataRoute, sessionEntryRoute } from "./routes/metadata";
import {
  pairRoute,
  pairInfoRoute,
  pairPendingRoute,
  pairApproveRoute,
  pairRejectRoute,
} from "./routes/pair";
import { sendMessageRoute } from "./routes/message";
import { headlessRoute, headlessStatusRoute } from "./routes/headless";
import {
  matchRoute,
  matchScanRoute,
  matchConfirmRoute,
  matchConfirmedRoute,
  matchDeleteRoute,
} from "./routes/match";
import {
  listWindows,
  getWindow,
  getWindowScreenshot,
  getWindowContent,
  captureAllWindows,
} from "./routes/windows";
import { getDevices, pruneExpiredDevices } from "./devices/registry";
import { getOrCreateKeyPair } from "./crypto/store";
import { verifyRequest, authErrorResponse, isExemptPath } from "./auth/hmac";
import { log, clearLog } from "./log";
import { PID_FILE, ensureDirectories } from "./paths";
import { sessionCache } from "./discovery/session-cache";

// Parse CLI args
const args = process.argv.slice(2);
const LOCAL_MODE = args.includes("--local") || args.includes("-l");

// Port configuration
const DEFAULT_PORT = LOCAL_MODE ? 8767 : 8765;
const portArgIndex = args.findIndex((a) => a === "--port" || a === "-p");
const PORT =
  portArgIndex !== -1 && args[portArgIndex + 1]
    ? parseInt(args[portArgIndex + 1], 10)
    : DEFAULT_PORT;

// Store hostname for routes
let hostname = "localhost";

// Create Elysia app
const app = new Elysia()
  // Strip trailing slashes
  .onRequest(({ request }) => {
    const url = new URL(request.url);
    if (url.pathname !== "/" && url.pathname.endsWith("/")) {
      url.pathname = url.pathname.slice(0, -1);
      return Response.redirect(url.toString(), 301);
    }
  })
  // Request logging
  .onBeforeHandle(({ request }) => {
    const url = new URL(request.url);
    log.request(request.method, url.pathname);
  })
  .onAfterHandle(({ request, response }) => {
    const url = new URL(request.url);
    // @ts-ignore
    log.info(`${request.method} ${url.pathname} → ${response?.status || 200}`);
  })
  // Auth middleware
  .onBeforeHandle(async ({ request }) => {
    const url = new URL(request.url);
    const path = url.pathname;

    if (LOCAL_MODE || isExemptPath(path, request.method)) {
      return;
    }

    const authResult = await verifyRequest(request);
    if (!authResult.authenticated) {
      log.warn(`Auth failed: ${authResult.error} for ${path}`);
      return authErrorResponse(authResult);
    }
  })
  // Error handler
  .onError(({ error, request }) => {
    const url = new URL(request.url);
    log.error(`${request.method} ${url.pathname} → ERROR: ${error}`);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  })

  // Health
  .get("/health", ({ request }) => healthRoute(request, hostname))

  // Debug
  .get("/debug/cache", () => sessionCache.getStatus())

  // Sessions
  .get("/paths", ({ request }) => pathsRoute(request))
  .get("/sessions", ({ request }) => sessionsRoute(request))
  .get("/sessions/:id", ({ request, params }) => sessionMessagesRoute(request, params.id))
  .get("/sessions/:id/messages", ({ request, params }) => sessionMessagesRoute(request, params.id))
  .get("/sessions/:id/metadata", ({ request, params }) => sessionMetadataRoute(request, params.id))
  .get("/sessions/:id/entry/:index", ({ request, params }) =>
    sessionEntryRoute(request, params.id, parseInt(params.index, 10))
  )
  .post("/sessions/:id/message", ({ request, params }) => sendMessageRoute(request, params.id))

  // Headless
  .post("/headless", ({ request }) => headlessRoute(request))
  .get("/headless/status", ({ request }) => headlessStatusRoute(request))

  // Pairing
  .post("/pair", ({ request }) => pairRoute(request))
  .get("/pair/info", ({ request }) => pairInfoRoute(request, hostname))
  .get("/pair/pending", ({ request }) => pairPendingRoute(request))
  .post("/pair/:deviceId/approve", ({ request, params }) => pairApproveRoute(request, params.deviceId))
  .post("/pair/:deviceId/reject", ({ request, params }) => pairRejectRoute(request, params.deviceId))

  // Devices
  .get("/devices", async () => {
    const devices = await getDevices();
    return { devices };
  })

  // Legacy inject
  .post("/inject", ({ request }) => sendMessageRoute(request))

  // Match endpoints
  .get("/match", ({ request }) => matchRoute(request))
  .post("/match/scan", ({ request }) => matchScanRoute(request))
  .post("/match/confirm", ({ request }) => matchConfirmRoute(request))
  .get("/match/confirmed", ({ request }) => matchConfirmedRoute(request))
  .delete("/match/confirmed/:fingerprint", ({ request, params }) =>
    matchDeleteRoute(request, decodeURIComponent(params.fingerprint))
  )

  // Windows
  .get("/windows", ({ request }) => listWindows(request))
  .get("/windows/captures", ({ request }) => captureAllWindows(request))
  .get("/windows/:id", ({ request, params }) => getWindow(request, params.id))
  .get("/windows/:id/screenshot", ({ request, params }) => getWindowScreenshot(request, params.id))
  .get("/windows/:id/content", ({ request, params }) => getWindowContent(request, params.id));

// Main
async function main() {
  await ensureDirectories();
  await clearLog();
  log.info("TalkieBridge starting...");

  if (LOCAL_MODE) {
    log.info("Running in LOCAL mode (Tailscale check skipped)");
  } else {
    const tailscaleState = await getTailscaleState();
    log.info(`Tailscale: ${getStateMessage(tailscaleState)}`);

    if (tailscaleState.status !== "ready" && tailscaleState.status !== "no-peers") {
      log.error("Cannot start bridge: Tailscale is not ready");
      log.error(getStateMessage(tailscaleState));
      log.error("Tip: Use --local flag to run without Tailscale for testing");
      process.exit(1);
    }

    hostname = tailscaleState.hostname;
  }

  // Initialize server key pair
  const keyPair = await getOrCreateKeyPair();
  log.info(`Server public key: ${keyPair.publicKey.slice(0, 20)}...`);

  // Prune expired devices on startup
  await pruneExpiredDevices();

  // Load paired devices
  const devices = await getDevices();
  log.info(`Paired devices: ${devices.length}`);

  // Write PID file
  await Bun.write(PID_FILE, process.pid.toString());
  log.info(`PID ${process.pid} written to ${PID_FILE}`);

  // Clean up on exit
  const shutdown = async () => {
    log.info("Shutting down...");
    sessionCache.shutdown();
    await Bun.write(PID_FILE, "").catch(() => {});
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  // Start server
  app.listen(PORT);

  log.info(`TalkieBridge running at http://${hostname}:${PORT}`);
  log.info(`Local: http://localhost:${PORT}`);
  log.info(LOCAL_MODE ? "Auth: DISABLED (local mode)" : "Auth: HMAC enabled");
}

main().catch((err) => {
  log.error(`Failed to start: ${err}`);
  process.exit(1);
});
