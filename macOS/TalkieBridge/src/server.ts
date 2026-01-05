import { getTailscaleState, getStateMessage } from "./tailscale/status";
import { healthRoute } from "./routes/health";
import { sessionsRoute, sessionMessagesRoute } from "./routes/sessions";
import { sessionMetadataRoute, sessionEntryRoute } from "./routes/metadata";
import {
  pairRoute,
  pairInfoRoute,
  pairPendingRoute,
  pairApproveRoute,
  pairRejectRoute,
} from "./routes/pair";
import { sendMessageRoute } from "./routes/message";
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

const PORT = 8765;

// Parse CLI args
const args = process.argv.slice(2);
const LOCAL_MODE = args.includes("--local") || args.includes("-l");

async function main() {
  // Ensure data directories exist
  await ensureDirectories();
  await clearLog();
  log.info("TalkieBridge starting...");

  let hostname = "localhost";

  if (LOCAL_MODE) {
    log.info("Running in LOCAL mode (Tailscale check skipped)");
  } else {
    // Check Tailscale state
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
  process.on("SIGINT", async () => {
    log.info("Shutting down...");
    sessionCache.shutdown();
    await Bun.write(PID_FILE, "").catch(() => {});
    process.exit(0);
  });

  process.on("SIGTERM", async () => {
    log.info("Shutting down...");
    sessionCache.shutdown();
    await Bun.write(PID_FILE, "").catch(() => {});
    process.exit(0);
  });

  // Start HTTP server
  const server = Bun.serve({
    port: PORT,
    async fetch(req) {
      const url = new URL(req.url);
      const path = url.pathname;
      const method = req.method;
      const startTime = performance.now();

      log.request(method, path);

      const logResponse = (response: Response) => {
        const duration = Math.round(performance.now() - startTime);
        log.info(`${method} ${path} → ${response.status} (${duration}ms)`);
        return response;
      };

      try {
        // HMAC Authentication (unless exempt endpoint)
        if (!isExemptPath(path, method)) {
          const authResult = await verifyRequest(req);
          if (!authResult.authenticated) {
            log.warn(`Auth failed: ${authResult.error} for ${path}`);
            return logResponse(authErrorResponse(authResult));
          }
        }

        // Health check
        if (path === "/health" && method === "GET") {
          return logResponse(healthRoute(req, hostname));
        }

        // Debug: cache status
        if (path === "/debug/cache" && method === "GET") {
          return logResponse(Response.json(sessionCache.getStatus()));
        }

        // Sessions
        if (path === "/sessions" && method === "GET") {
          return logResponse(await sessionsRoute(req));
        }

        // Match /sessions/:id/messages
        const messagesMatch = path.match(/^\/sessions\/([^/]+)\/messages$/);
        if (messagesMatch && method === "GET") {
          return logResponse(await sessionMessagesRoute(req, messagesMatch[1]));
        }

        // Match /sessions/:id/metadata
        const metadataMatch = path.match(/^\/sessions\/([^/]+)\/metadata$/);
        if (metadataMatch && method === "GET") {
          return logResponse(await sessionMetadataRoute(req, metadataMatch[1]));
        }

        // Match /sessions/:id/entry/:index
        const entryMatch = path.match(/^\/sessions\/([^/]+)\/entry\/(\d+)$/);
        if (entryMatch && method === "GET") {
          return logResponse(await sessionEntryRoute(req, entryMatch[1], parseInt(entryMatch[2], 10)));
        }

        // Match /sessions/:id
        const sessionMatch = path.match(/^\/sessions\/([^/]+)$/);
        if (sessionMatch && method === "GET") {
          return logResponse(await sessionMessagesRoute(req, sessionMatch[1]));
        }

        // POST /sessions/:id/message - Send text to a Claude session
        // Empty text with submit triggers Enter key only (for submit without new text)
        const sendMessageMatch = path.match(/^\/sessions\/([^/]+)\/message$/);
        if (sendMessageMatch && method === "POST") {
          return logResponse(await sendMessageRoute(req, sendMessageMatch[1]));
        }

        // Pairing endpoints
        if (path === "/pair" && method === "POST") {
          return logResponse(await pairRoute(req));
        }

        if (path === "/pair/info" && method === "GET") {
          return logResponse(await pairInfoRoute(req, hostname));
        }

        if (path === "/pair/pending" && method === "GET") {
          return logResponse(await pairPendingRoute(req));
        }

        // Match /pair/:deviceId/approve
        const approveMatch = path.match(/^\/pair\/([^/]+)\/approve$/);
        if (approveMatch && method === "POST") {
          return logResponse(await pairApproveRoute(req, approveMatch[1]));
        }

        // Match /pair/:deviceId/reject
        const rejectMatch = path.match(/^\/pair\/([^/]+)\/reject$/);
        if (rejectMatch && method === "POST") {
          return logResponse(await pairRejectRoute(req, rejectMatch[1]));
        }

        // Devices endpoint
        if (path === "/devices" && method === "GET") {
          const devices = await getDevices();
          return logResponse(Response.json({ devices }));
        }

        // Legacy /inject endpoint (use /sessions/:id/message instead)
        if (path === "/inject" && method === "POST") {
          return logResponse(await sendMessageRoute(req));
        }

        // Match endpoints - fuzzy terminal-to-session matching
        if (path === "/match" && method === "GET") {
          return logResponse(await matchRoute(req));
        }

        if (path === "/match/scan" && method === "POST") {
          return logResponse(await matchScanRoute(req));
        }

        if (path === "/match/confirm" && method === "POST") {
          return logResponse(await matchConfirmRoute(req));
        }

        if (path === "/match/confirmed" && method === "GET") {
          return logResponse(await matchConfirmedRoute(req));
        }

        // Match /match/confirmed/:fingerprint for DELETE
        const deleteMatch = path.match(/^\/match\/confirmed\/(.+)$/);
        if (deleteMatch && method === "DELETE") {
          return logResponse(await matchDeleteRoute(req, decodeURIComponent(deleteMatch[1])));
        }

        // Windows Resource (RESTful)
        // GET /windows - List all terminal windows
        if (path === "/windows" && method === "GET") {
          return logResponse(await listWindows(req));
        }

        // GET /windows/captures - Batch: all screenshots + AX
        if (path === "/windows/captures" && method === "GET") {
          return logResponse(await captureAllWindows(req));
        }

        // GET /windows/:id/screenshot - Window screenshot (JPEG)
        const windowScreenshotMatch = path.match(/^\/windows\/(\d+)\/screenshot$/);
        if (windowScreenshotMatch && method === "GET") {
          return logResponse(await getWindowScreenshot(req, windowScreenshotMatch[1]));
        }

        // GET /windows/:id/content - Window AX content
        const windowContentMatch = path.match(/^\/windows\/(\d+)\/content$/);
        if (windowContentMatch && method === "GET") {
          return logResponse(await getWindowContent(req, windowContentMatch[1]));
        }

        // GET /windows/:id - Single window details
        const windowMatch = path.match(/^\/windows\/(\d+)$/);
        if (windowMatch && method === "GET") {
          return logResponse(await getWindow(req, windowMatch[1]));
        }

        // 404 for unknown routes
        log.warn(`404: ${path}`);
        return logResponse(Response.json({ error: "Not found" }, { status: 404 }));
      } catch (error) {
        const duration = Math.round(performance.now() - startTime);
        log.error(`${method} ${path} → ERROR (${duration}ms): ${error}`);
        return Response.json(
          { error: "Internal server error" },
          { status: 500 }
        );
      }
    },
  });

  log.info(`TalkieBridge running at http://${hostname}:${PORT}`);
  log.info(`Local: http://localhost:${PORT}`);
  log.info("HMAC authentication enabled");
}

main().catch((err) => {
  log.error(`Failed to start: ${err}`);
  process.exit(1);
});
