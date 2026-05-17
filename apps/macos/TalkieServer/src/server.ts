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
 *   Depends on: ~/.claude/projects/, TalkieServer (Swift), local network/Tailscale transport
 *
 * GATEWAY - External API translation
 *   Routes: /inference, /inference/providers, /inference/models
 *   Purpose: Unified interface to cloud inference providers (OpenAI, Anthropic)
 *   Depends on: API keys in environment (OPENAI_API_KEY, ANTHROPIC_API_KEY)
 *
 * WORKFLOWS - Portable workflow planning and runtime
 *   Routes: /workflows/portable/plan, /workflows/portable/run
 *   Purpose: Normalize TWF-like workflow definitions, classify portable vs native
 *            steps, and execute the truly portable subset inside the sidecar
 *
 * RUNNING:
 *   bun run src/server.ts --local        # Dev mode, port 8767
 *   bun run src/server.ts --nearby --allow-lan
 *                                       # Nearby bridge, port 8765 (LAN/Tailscale)
 *   bun run src/server.ts --local       # Also exposes /tmp/talkie-server.sock
 *
 * See ARCHITECTURE.md for full documentation.
 */

import { Elysia } from "elysia";
import { hostname as systemHostname } from "node:os";

import { bridge, sessionCache } from "./bridge";
import { gateway } from "./gateway";
import { extensions } from "./extensions";
import { workflows } from "./workflows";
import { getTailscaleState, getStateMessage, getTailscaleBindAddress } from "./tailscale/status";
import { getDevices, pruneExpiredDevices } from "./devices/registry";
import { getOrCreateKeyPair } from "./crypto/store";
import { verifyRequest, authErrorResponse, isExemptPath } from "./auth/hmac";
import {
  initLocalAuthToken,
  verifyLocalAuthToken,
  requiresLocalAuth,
  requiresLocalOnlyAuth,
  cleanupLocalAuthToken,
} from "./auth/local";
import { setAutoApprove } from "./bridge/routes/pair";
import { startBonjourAdvertisement } from "./bonjour";
import { log, clearLog } from "./log";
import { PID_FILE, LOCAL_AUTH_TOKEN_FILE, ensureDirectories } from "./paths";

// ===== CLI Args =====

const args = process.argv.slice(2);
const LOCAL_MODE = args.includes("--local") || args.includes("-l");
const NEARBY_MODE = args.includes("--nearby");
const ALLOW_LAN = args.includes("--allow-lan") || process.env.TALKIE_SERVER_ALLOW_LAN === "1";
const REQUIRE_APPROVAL = args.includes("--require-approval");
type ServerMode = "pairing" | "nearby" | "local_dev";
const SERVER_MODE: ServerMode = LOCAL_MODE ? "local_dev" : NEARBY_MODE ? "nearby" : "pairing";
const SERVER_INSTANCE_ID = process.env.TALKIE_SERVER_INSTANCE_ID || "standalone";
const UNIX_SOCKET_OVERRIDE = process.env.TALKIE_SERVER_UNIX_SOCKET?.trim();
const UNIX_SOCKET = UNIX_SOCKET_OVERRIDE || (LOCAL_MODE || args.includes("--unix")
  ? "/tmp/talkie-server.sock"
  : undefined);

// Port configuration (8765 for both local and production - macOS app expects this)
const DEFAULT_PORT = 8765;
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
  alternateHosts: [] as string[],
};

const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);

function appendAlternateHost(host: string | undefined): void {
  const normalized = host?.trim().replace(/\.$/, "");
  if (!normalized || normalized === serverConfig.hostname) {
    return;
  }
  if (!serverConfig.alternateHosts.includes(normalized)) {
    serverConfig.alternateHosts.push(normalized);
  }
}

function getLocalBonjourHostname(): string {
  const raw = systemHostname().trim().replace(/\.$/, "");
  if (!raw) {
    return "talkie-mac.local";
  }
  if (raw.includes(".")) {
    return raw;
  }
  return `${raw}.local`;
}

function getBonjourServiceName(): string {
  const raw = systemHostname().trim().replace(/\.$/, "");
  const shortName = raw.split(".")[0]?.replace(/-/g, " ").trim();
  return shortName ? `Talkie Bridge (${shortName})` : "Talkie Bridge";
}

function isLoopbackOrigin(origin: string): boolean {
  try {
    const url = new URL(origin);
    return (url.protocol === "http:" || url.protocol === "https:")
      && LOOPBACK_HOSTS.has(url.hostname);
  } catch {
    return false;
  }
}

// ===== Create Server =====

const app = new Elysia()
  // Shared state for plugins (use derive to get live values)
  .derive(() => ({
    hostname: serverConfig.hostname,
    alternateHosts: serverConfig.alternateHosts,
    port: serverConfig.port,
    mode: SERVER_MODE,
    instanceId: SERVER_INSTANCE_ID,
  }))

  // CORS for local development - manual implementation
  .onBeforeHandle(({ request, set }) => {
    if (!LOCAL_MODE) return;

    const origin = request.headers.get("origin");
    if (origin && !isLoopbackOrigin(origin)) {
      return Response.json(
        { error: "Forbidden origin" },
        { status: 403 }
      );
    }

    if (origin) {
      set.headers["Access-Control-Allow-Origin"] = origin;
      set.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS";
      set.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, X-Device-ID, X-Timestamp, X-Nonce, X-Signature";
    }

    // Handle preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: origin ? {
          "Access-Control-Allow-Origin": origin,
          "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Device-ID, X-Timestamp, X-Nonce, X-Signature",
        } : {}
      });
    }
  })

  // Log full request details (dev only)
  .onRequest(async ({ request }) => {
    if (!LOCAL_MODE) return;

    const url = new URL(request.url);
    const params = Object.fromEntries(url.searchParams);
    const hasParams = Object.keys(params).length > 0;

    if (request.method === "POST" || request.method === "PUT" || request.method === "PATCH") {
      const cloned = request.clone();
      const bodyText = await cloned.text();
      log.info(`→ ${request.method} ${url.pathname}${hasParams ? ` params=${JSON.stringify(params)}` : ''} body=${bodyText.slice(0, 500)}${bodyText.length > 500 ? '...' : ''}`);
    } else if (hasParams) {
      log.info(`→ ${request.method} ${url.pathname} params=${JSON.stringify(params)}`);
    }
  })

  // Strip trailing slashes
  .onRequest(({ request }) => {
    const url = new URL(request.url);
    if (url.pathname !== "/" && url.pathname.endsWith("/")) {
      url.pathname = url.pathname.slice(0, -1);
      return Response.redirect(url.toString(), 301);
    }
  })

  // Request timing
  .derive(() => ({
    requestStart: Date.now(),
  }))
  .onBeforeHandle(({ store }) => {
    // @ts-ignore - store timing
    store.requestStart = Date.now();
  })
  .onAfterHandle(({ request, response, set, store }) => {
    const url = new URL(request.url);
    const status = response instanceof Response ? response.status : (set.status || 200);
    // @ts-ignore - store timing
    const elapsed = Date.now() - (store.requestStart || Date.now());
    const timeStr = elapsed > 1000 ? `⚠️ ${elapsed}ms` : `${elapsed}ms`;

    if (LOCAL_MODE) {
      // Dev: full request → response logging
      if (response && typeof response === "object" && !(response instanceof Response)) {
        const payload = JSON.stringify(response);
        const truncated = payload.length > 1000 ? payload.slice(0, 1000) + `... (${payload.length} bytes)` : payload;
        log.info(`← ${request.method} ${url.pathname} ${status} (${timeStr}) ${truncated}`);
      } else {
        log.info(`← ${request.method} ${url.pathname} ${status} (${timeStr})`);
      }
    } else {
      // Prod: just method, path, status, timing
      log.info(`${request.method} ${url.pathname} → ${status} (${timeStr})`);
    }
  })

  // Auth middleware
  .onBeforeHandle(async ({ request }) => {
    const url = new URL(request.url);
    const path = url.pathname;
    const authHeader = request.headers.get("Authorization");

    if (requiresLocalOnlyAuth(path, request.method)) {
      if (verifyLocalAuthToken(authHeader)) {
        return;
      }

      log.warn(`Local-only auth failed for ${request.method} ${path}`);
      return Response.json(
        { error: "Unauthorized - local bearer token required" },
        { status: 401 }
      );
    }

    // Internal local bearer auth can be used in both local and production
    // for routes that are intended to be called by the macOS app on the same machine.
    if (requiresLocalAuth(path) && verifyLocalAuthToken(authHeader)) {
      return;
    }

    // Local mode: still require bearer token for sensitive gateway routes
    if (LOCAL_MODE) {
      if (requiresLocalAuth(path)) {
        if (!verifyLocalAuthToken(authHeader)) {
          log.warn(`Local auth failed for ${path}`);
          return Response.json(
            { error: "Unauthorized - invalid or missing bearer token" },
            { status: 401 }
          );
        }
      }
      return;
    }

    // Production mode: HMAC auth (exempt paths skip)
    if (isExemptPath(path, request.method)) {
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

  // ===== Mount Modules =====
  .use(bridge)
  .use(gateway)
  .use(extensions)
  .use(workflows);

// ===== Main =====

async function main() {
  if (NEARBY_MODE && !ALLOW_LAN) {
    log.error("Refusing to start nearby LAN mode without --allow-lan");
    log.error("Use default mode for Tailscale-only access, or pass --nearby --allow-lan for explicit LAN pairing.");
    process.exit(1);
  }

  await ensureDirectories();
  await clearLog();
  log.info("TalkieServer starting...");
  const bindAddress = LOCAL_MODE ? "127.0.0.1" : NEARBY_MODE ? "0.0.0.0" : await getTailscaleBindAddress();
  await initLocalAuthToken();

  // Configure pairing approval mode
  if (REQUIRE_APPROVAL) {
    setAutoApprove(false);
  }

  if (LOCAL_MODE) {
    log.info("Running in LOCAL mode (Tailscale check skipped)");
    log.info(`Token file: ${LOCAL_AUTH_TOKEN_FILE}`);
  } else if (NEARBY_MODE) {
    serverConfig.hostname = getLocalBonjourHostname();
    const tailscaleState = await getTailscaleState();
    if (tailscaleState.status === "ready" || tailscaleState.status === "no-peers") {
      appendAlternateHost(tailscaleState.hostname);
    }
    log.info("Running in NEARBY mode (explicit LAN/Tailscale interfaces, Bonjour discovery)");
    log.info(`Tailscale: ${getStateMessage(tailscaleState)}`);
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

  if (!bindAddress) {
    log.error("Cannot start: Could not determine a Tailscale bind address");
    log.error("Tip: Use --local flag to run without Tailscale for testing");
    process.exit(1);
  }

  log.info(`Hostname for pairing: ${serverConfig.hostname}`);
  log.info(`Bind address: ${bindAddress}`);

  // Initialize server key pair
  const keyPair = await getOrCreateKeyPair();
  log.info(`Server public key: ${keyPair.publicKey.slice(0, 20)}...`);

  // Prune expired devices on startup
  await pruneExpiredDevices();

  // Load paired devices
  const devices = await getDevices();
  log.info(`Paired devices: ${devices.length}`);

  let stopBonjour: (() => void) | undefined;

  // Write PID file
  await Bun.write(PID_FILE, process.pid.toString());
  log.info(`PID ${process.pid} written to ${PID_FILE}`);

  // Clean up on exit
  const shutdown = async () => {
    log.info("Shutting down...");
    stopBonjour?.();
    sessionCache.shutdown();
    await Bun.write(PID_FILE, "").catch(() => {});
    await cleanupLocalAuthToken();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  // Start HTTP server
  // SECURITY: Local dev is loopback-only and also exposes a Unix socket.
  // Nearby mode is explicit LAN mode and requires --allow-lan.
  // Production binds to the Tailscale IPv4 address so the bridge stays
  // reachable only on the tailnet.
  app.listen({ hostname: bindAddress, port: PORT });
  log.info(`TalkieServer HTTP at http://${bindAddress}:${PORT}`);
  if (!LOCAL_MODE) {
    log.info(`Tailscale hostname: ${serverConfig.hostname}`);
  }

  if (NEARBY_MODE) {
    stopBonjour = startBonjourAdvertisement({
      name: getBonjourServiceName(),
      hostname: serverConfig.hostname,
      port: PORT,
      mode: SERVER_MODE,
      route: serverConfig.alternateHosts.length > 0 ? "lan,tailscale" : "lan",
      capabilities: ["bridge", "pairing", "hyper-scan"],
    });
  }

  // Start Unix socket server (if enabled)
  if (UNIX_SOCKET) {
    // Remove stale socket file
    try {
      const fs = await import("node:fs/promises");
      await fs.unlink(UNIX_SOCKET).catch(() => {});
    } catch {}

    app.listen({ unix: UNIX_SOCKET });
    const { chmod } = await import("node:fs/promises");
    await chmod(UNIX_SOCKET, 0o600);
    log.info(`TalkieServer Unix socket at ${UNIX_SOCKET}`);
  }

  log.info(LOCAL_MODE ? "Auth: Bearer token (local mode)" : "Auth: HMAC enabled + local bearer for internal routes");
  log.info("Modules loaded: bridge, gateway, extensions, workflows");
  log.info(`Extensions WebSocket: ws://localhost:${PORT}/extensions`);

  // Initialize session cache (loads from disk if exists, builds quick if not)
  await sessionCache.warmup();
}

main().catch((err) => {
  log.error(`Failed to start: ${err}`);
  process.exit(1);
});
