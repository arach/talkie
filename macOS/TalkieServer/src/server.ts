/**
 * TalkieServer
 *
 * The unified TypeScript backend for Talkie. Runs as a single process
 * and serves two modules:
 *
 * BRIDGE - Local system integration
 *   Routes: /sessions, /windows, /match, /pair, /health, /headless
 *   Purpose: Claude CLI session discovery, window management, device pairing,
 *            terminal-to-session matching, message injection (UI or headless)
 *   Depends on: ~/.claude/projects/, TalkieServer (Swift), Tailscale
 *
 * GATEWAY - External API translation
 *   Routes: /inference, /inference/providers, /inference/models
 *   Purpose: Unified interface to cloud inference providers (OpenAI, Anthropic)
 *   Depends on: API keys in environment (OPENAI_API_KEY, ANTHROPIC_API_KEY)
 *
 * RUNNING:
 *   bun run src/server.ts --local        # Dev mode, port 8767
 *   bun run src/server.ts                # Production, port 8765 (needs Tailscale)
 *   bun run src/server.ts --local --unix # With Unix socket at /tmp/talkie-server.sock
 *
 * See ARCHITECTURE.md for full documentation.
 */

import { Elysia } from "elysia";

import { bridge, sessionCache } from "./bridge";
import { gateway } from "./gateway";
import { getTailscaleState, getStateMessage } from "./tailscale/status";
import { getDevices, pruneExpiredDevices } from "./devices/registry";
import { getOrCreateKeyPair } from "./crypto/store";
import { verifyRequest, authErrorResponse, isExemptPath } from "./auth/hmac";
import { log, clearLog } from "./log";
import { PID_FILE, ensureDirectories } from "./paths";

// ===== CLI Args =====

const args = process.argv.slice(2);
const LOCAL_MODE = args.includes("--local") || args.includes("-l");
const UNIX_SOCKET = args.includes("--unix")
  ? "/tmp/talkie-server.sock"
  : undefined;

// Port configuration
const DEFAULT_PORT = LOCAL_MODE ? 8767 : 8765;
const portArgIndex = args.findIndex((a) => a === "--port" || a === "-p");
const PORT =
  portArgIndex !== -1 && args[portArgIndex + 1]
    ? parseInt(args[portArgIndex + 1], 10)
    : DEFAULT_PORT;

// ===== Server Config =====

// Hostname will be updated after Tailscale check in main()
// Using object so state reference stays valid after update
const serverConfig = {
  hostname: "localhost",
  port: PORT,
};

// ===== Create Server =====

const app = new Elysia()
  // Shared state for plugins (use derive to get live values)
  .derive(() => ({
    hostname: serverConfig.hostname,
    port: serverConfig.port,
  }))

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
  .onAfterHandle(({ request, response, set }) => {
    const url = new URL(request.url);
    const status = set.status || 200;
    log.info(`${request.method} ${url.pathname} → ${status}`);

    // Log full response JSON for debugging (set TALKIE_DEBUG=1 to enable)
    const debugEnabled = LOCAL_MODE || process.env.TALKIE_DEBUG === "1";
    if (debugEnabled && response && typeof response === "object" && !(response instanceof Response)) {
      log.debug(`Response: ${JSON.stringify(response)}`);
    }
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

  // ===== Debug Routes =====
  .get("/debug/cache", () => sessionCache.getStatus())

  // ===== Devices (shared) =====
  .get("/devices", async () => {
    const devices = await getDevices();
    return { devices };
  })

  // ===== Mount Modules =====
  .use(bridge)
  .use(gateway);

// ===== Main =====

async function main() {
  await ensureDirectories();
  await clearLog();
  log.info("TalkieServer starting...");

  if (LOCAL_MODE) {
    log.info("Running in LOCAL mode (Tailscale check skipped)");
  } else {
    const tailscaleState = await getTailscaleState();
    log.info(`Tailscale: ${getStateMessage(tailscaleState)}`);

    if (tailscaleState.status !== "ready" && tailscaleState.status !== "no-peers") {
      log.error("Cannot start: Tailscale is not ready");
      log.error(getStateMessage(tailscaleState));
      log.error("Tip: Use --local flag to run without Tailscale for testing");
      process.exit(1);
    }

    serverConfig.hostname = tailscaleState.hostname;
  }

  log.info(`Hostname for pairing: ${serverConfig.hostname}`);

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

  // Start HTTP server
  app.listen(PORT);
  log.info(`TalkieServer HTTP at http://${serverConfig.hostname}:${PORT}`);
  log.info(`Local: http://localhost:${PORT}`);

  // Start Unix socket server (if enabled)
  if (UNIX_SOCKET) {
    // Remove stale socket file
    try {
      const fs = await import("node:fs/promises");
      await fs.unlink(UNIX_SOCKET).catch(() => {});
    } catch {}

    app.listen({ unix: UNIX_SOCKET });
    log.info(`TalkieServer Unix socket at ${UNIX_SOCKET}`);
  }

  log.info(LOCAL_MODE ? "Auth: DISABLED (local mode)" : "Auth: HMAC enabled");
  log.info("Modules loaded: bridge, gateway");
}

main().catch((err) => {
  log.error(`Failed to start: ${err}`);
  process.exit(1);
});
