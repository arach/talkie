import { getTailscaleState, getStateMessage } from "../tailscale/status";
import { getDevices, pruneExpiredDevices } from "../devices/registry";
import { getOrCreateKeyPair } from "../crypto/store";
import { verifyRequest, authErrorResponse, isExemptPath } from "../auth/hmac";
import { ensureDirectories, BRIDGE_DATA_DIR } from "../paths";
import { sessionCache } from "../discovery/session-cache";
import { labsLog, clearLabsLog } from "./log";
import { healthRoute } from "./routes/health";
import { listSessionsRoute } from "./routes/sessions";
import {
  timelineRoute,
  messagesRoute,
  toolsRoute,
  summariesRoute,
  filesRoute,
  toolResultRoute,
} from "./routes/slices";

const DEFAULT_PORT = 8770;
const LABS_PID_FILE = `${BRIDGE_DATA_DIR}/labs.pid`;

const args = process.argv.slice(2);
const LOCAL_MODE = args.includes("--local") || args.includes("-l");

function parsePort(): number {
  const portArg = args.find((arg) => arg.startsWith("--port="));
  if (portArg) {
    const parsed = Number.parseInt(portArg.split("=")[1] ?? "", 10);
    if (!Number.isNaN(parsed)) return parsed;
  }

  const portIndex = args.findIndex((arg) => arg === "--port");
  if (portIndex >= 0 && args[portIndex + 1]) {
    const parsed = Number.parseInt(args[portIndex + 1], 10);
    if (!Number.isNaN(parsed)) return parsed;
  }

  return DEFAULT_PORT;
}

async function main() {
  const port = parsePort();

  await ensureDirectories();
  await clearLabsLog();
  labsLog.info("TalkieBridge Labs starting...");

  let hostname = "localhost";

  if (LOCAL_MODE) {
    labsLog.info("Running in LOCAL mode (Tailscale check skipped)");
  } else {
    const tailscaleState = await getTailscaleState();
    labsLog.info(`Tailscale: ${getStateMessage(tailscaleState)}`);

    if (tailscaleState.status !== "ready" && tailscaleState.status !== "no-peers") {
      labsLog.error("Cannot start labs: Tailscale is not ready");
      labsLog.error(getStateMessage(tailscaleState));
      labsLog.error("Tip: Use --local flag to run without Tailscale for testing");
      process.exit(1);
    }

    hostname = tailscaleState.hostname;
  }

  const keyPair = await getOrCreateKeyPair();
  labsLog.info(`Server public key: ${keyPair.publicKey.slice(0, 20)}...`);

  await pruneExpiredDevices();
  const devices = await getDevices();
  labsLog.info(`Paired devices: ${devices.length}`);

  await Bun.write(LABS_PID_FILE, process.pid.toString());
  labsLog.info(`PID ${process.pid} written to ${LABS_PID_FILE}`);

  const shutdown = async () => {
    labsLog.info("Shutting down labs...");
    sessionCache.shutdown();
    await Bun.write(LABS_PID_FILE, "").catch(() => {});
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  const server = Bun.serve({
    port,
    async fetch(req, server) {
      const url = new URL(req.url);
      const path = url.pathname;
      const method = req.method;
      const startTime = performance.now();

      labsLog.request(method, path);

      const logResponse = (response: Response) => {
        const duration = Math.round(performance.now() - startTime);
        labsLog.info(`${method} ${path} -> ${response.status} (${duration}ms)`);
        return response;
      };

      const clientIP = server.requestIP(req);
      const isLocalhost = clientIP?.address === "127.0.0.1" || clientIP?.address === "::1";

      try {
        if (!isLocalhost && !isExemptPath(path, method)) {
          const authResult = await verifyRequest(req);
          if (!authResult.authenticated) {
            labsLog.warn(`Auth failed: ${authResult.error} for ${path}`);
            return logResponse(authErrorResponse(authResult));
          }
        }

        if (path === "/health" && method === "GET") {
          return logResponse(healthRoute(port));
        }

        if (path === "/sessions" && method === "GET") {
          return logResponse(await listSessionsRoute(req));
        }

        const filesMatch = path.match(/^\/sessions\/([^/]+)\/files$/);
        if (filesMatch && method === "GET") {
          return logResponse(await filesRoute(req, filesMatch[1]));
        }

        const timelineMatch = path.match(/^\/sessions\/([^/]+)\/timeline$/);
        if (timelineMatch && method === "GET") {
          return logResponse(await timelineRoute(req, timelineMatch[1]));
        }

        const messagesMatch = path.match(/^\/sessions\/([^/]+)\/messages$/);
        if (messagesMatch && method === "GET") {
          return logResponse(await messagesRoute(req, messagesMatch[1]));
        }

        const toolsMatch = path.match(/^\/sessions\/([^/]+)\/tools$/);
        if (toolsMatch && method === "GET") {
          return logResponse(await toolsRoute(req, toolsMatch[1]));
        }

        const summariesMatch = path.match(/^\/sessions\/([^/]+)\/summaries$/);
        if (summariesMatch && method === "GET") {
          return logResponse(await summariesRoute(req, summariesMatch[1]));
        }

        const toolResultMatch = path.match(/^\/sessions\/([^/]+)\/tool-results\/([^/]+)$/);
        if (toolResultMatch && method === "GET") {
          return logResponse(
            await toolResultRoute(req, toolResultMatch[1], toolResultMatch[2])
          );
        }

        labsLog.warn(`404: ${path}`);
        return logResponse(Response.json({ error: "Not found" }, { status: 404 }));
      } catch (error) {
        const duration = Math.round(performance.now() - startTime);
        labsLog.error(`${method} ${path} -> ERROR (${duration}ms): ${error}`);
        return Response.json({ error: "Internal server error" }, { status: 500 });
      }
    },
  });

  labsLog.info(`TalkieBridge Labs running at http://${hostname}:${port}`);
  labsLog.info(`Local: http://localhost:${port}`);
  labsLog.info("HMAC authentication enabled");
  labsLog.info(`Labs PID file: ${LABS_PID_FILE}`);
}

main().catch((err) => {
  labsLog.error(`Failed to start labs: ${err}`);
  process.exit(1);
});
