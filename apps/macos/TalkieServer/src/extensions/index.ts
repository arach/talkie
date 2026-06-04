/**
 * Extensions Module
 *
 * WebSocket-based API for external applications to access Talkie's capabilities.
 *
 * ROUTES:
 *   WS /extensions - WebSocket endpoint for extensions
 *   GET /extensions/token - Get auth token (for UI display)
 *   GET /extensions/status - List connected extensions
 *
 * PROTOCOL (v2):
 *   ext:*        - Connection lifecycle (auth)
 *   transcribe:* - Voice transcription
 *   llm:*        - Language model operations (via Gateway)
 *   diff:*       - Text diff computation
 *   storage:*    - Clipboard and memo storage
 *
 * LEGACY (v1):
 *   draft:*      - Backward compatibility with old API
 */

import { Elysia } from "elysia";
import { log } from "../log";
import { getAuthToken, getAuthTimeout } from "./auth";
import { PROTOCOL_VERSION, CAPABILITIES } from "./types";
import type {
  ExtensionConnection,
  InboundMessage,
  OutboundMessage,
} from "./types";
import {
  handleAuth,
  handleLLMComplete,
  handleLLMRevise,
  handleDiffCompute,
  handleClipboardWrite,
  handleClipboardRead,
  handleMemoSave,
  handleTranscribePreflight,
  handleTranscribeStart,
  handleTranscribeStop,
  handleLegacyRefine,
  handleLegacyUpdate,
  handleLegacyAcceptReject,
  handleLegacySave,
  handleLegacyCapture,
  type HandlerContext,
} from "./handlers";

// ===== Connection Registry =====

const connections = new Map<string, ExtensionConnection>();
const wsMap = new Map<string, any>(); // WebSocket instances by connection ID
const wsToId = new WeakMap<object, string>(); // Reverse lookup: ws → connectionId
const authTimers = new Map<string, Timer>(); // Auth timeout timers

function generateConnectionId(): string {
  return crypto.randomUUID();
}

function registerConnection(id: string, ws: any): ExtensionConnection {
  const connection: ExtensionConnection = {
    id,
    name: "Unknown",
    authenticated: false,
    capabilities: [],
    grantedCapabilities: [],
    connectedAt: new Date(),
  };

  connections.set(id, connection);
  wsMap.set(id, ws);
  wsToId.set(ws, id); // Reverse lookup for message handler

  // Set auth timeout
  const timer = setTimeout(() => {
    const conn = connections.get(id);
    if (conn && !conn.authenticated) {
      log.warn(`Extensions: Connection ${id} timed out waiting for auth`);
      sendToConnection(id, {
        type: "error",
        error: "Authentication timeout",
        code: "AUTH_TIMEOUT",
      });
      closeConnection(id);
    }
  }, getAuthTimeout());

  authTimers.set(id, timer);

  return connection;
}

function closeConnection(id: string): void {
  connections.delete(id);

  const timer = authTimers.get(id);
  if (timer) {
    clearTimeout(timer);
    authTimers.delete(id);
  }

  const ws = wsMap.get(id);
  if (ws) {
    try {
      ws.close();
    } catch {}
    wsMap.delete(id);
  }
}

function sendToConnection(id: string, message: OutboundMessage): void {
  const ws = wsMap.get(id);
  if (ws) {
    try {
      ws.send(JSON.stringify(message));
    } catch (error) {
      log.error(`Extensions: Failed to send to ${id}: ${error}`);
    }
  }
}

// ===== Message Router =====

async function handleMessage(
  connectionId: string,
  rawMessage: string
): Promise<void> {
  const connection = connections.get(connectionId);
  if (!connection) {
    log.warn(`Extensions: Message from unknown connection ${connectionId}`);
    return;
  }

  let message: InboundMessage;
  try {
    message = JSON.parse(rawMessage);
  } catch (error) {
    sendToConnection(connectionId, {
      type: "error",
      error: "Invalid JSON",
      code: "PARSE_ERROR",
    });
    return;
  }

  const ctx: HandlerContext = {
    connection,
    send: (msg) => sendToConnection(connectionId, msg),
  };

  // Handle based on message type
  switch (message.type) {
    // ===== Auth =====
    case "ext:connect": {
      const success = handleAuth(
        ctx,
        message.name,
        message.capabilities,
        message.token,
        message.version
      );
      if (success) {
        // Clear auth timeout
        const timer = authTimers.get(connectionId);
        if (timer) {
          clearTimeout(timer);
          authTimers.delete(connectionId);
        }
      }
      break;
    }

    // ===== Transcription =====
    case "transcribe:preflight":
      await handleTranscribePreflight(ctx);
      break;

    case "transcribe:start":
      await handleTranscribeStart(ctx);
      break;

    case "transcribe:stop":
      await handleTranscribeStop(ctx);
      break;

    // ===== LLM =====
    case "llm:complete":
      await handleLLMComplete(ctx, message);
      break;

    case "llm:revise":
      await handleLLMRevise(ctx, message);
      break;

    // ===== Diff =====
    case "diff:compute":
      handleDiffCompute(ctx, message);
      break;

    // ===== Storage =====
    case "storage:clipboard:write":
      await handleClipboardWrite(ctx, message);
      break;

    case "storage:clipboard:read":
      await handleClipboardRead(ctx);
      break;

    case "storage:memo:save":
      await handleMemoSave(ctx, message);
      break;

    // ===== Legacy v1 =====
    case "draft:update":
      handleLegacyUpdate(ctx, message.content);
      break;

    case "draft:refine":
      await handleLegacyRefine(ctx, message.instruction, message.constraints);
      break;

    case "draft:accept":
      handleLegacyAcceptReject(ctx, true);
      break;

    case "draft:reject":
      handleLegacyAcceptReject(ctx, false);
      break;

    case "draft:save":
      await handleLegacySave(ctx, message.destination);
      break;

    case "draft:capture":
      await handleLegacyCapture(ctx, message.action);
      break;

    default:
      log.warn(`Extensions: Unknown message type: ${(message as any).type}`);
      ctx.send({
        type: "error",
        error: `Unknown message type: ${(message as any).type}`,
        code: "UNKNOWN_MESSAGE",
      });
  }
}

// ===== HTTP Routes =====

function tokenRoute(): { token: string } {
  return { token: getAuthToken() };
}

function statusRoute(): {
  connections: number;
  authenticated: number;
  extensions: Array<{
    id: string;
    name: string;
    capabilities: string[];
    connectedAt: string;
  }>;
} {
  const authenticated = Array.from(connections.values()).filter(
    (c) => c.authenticated
  );

  return {
    connections: connections.size,
    authenticated: authenticated.length,
    extensions: authenticated.map((c) => ({
      id: c.id,
      name: c.name,
      capabilities: c.grantedCapabilities,
      connectedAt: c.connectedAt.toISOString(),
    })),
  };
}

// ===== Elysia Plugin =====

/**
 * The extensions WS auth token (and connection status) is for LOCAL UI display
 * only — the Mac app fetches it from http://localhost:8765. The whole
 * /extensions prefix is exempt from HMAC auth (the WS does its own token
 * handshake), so without this gate a LAN attacker (NEARBY mode binds 0.0.0.0)
 * could lift the token and drive the extension WS (clipboard read, LLM calls).
 * Gate token/status to a loopback peer. A null peer IP (unix socket / agent)
 * is treated as local; only a concrete non-loopback address is rejected.
 */
function isLoopbackPeer(server: unknown, request: Request): boolean {
  try {
    const ip = (server as { requestIP?: (req: Request) => { address?: string } | null } | undefined)
      ?.requestIP?.(request)?.address;
    if (!ip) return true;
    return ip === "127.0.0.1" || ip === "::1" || ip === "::ffff:127.0.0.1";
  } catch {
    return true;
  }
}

const FORBIDDEN_REMOTE = new Response(
  JSON.stringify({ error: "Forbidden - loopback only" }),
  { status: 403, headers: { "Content-Type": "application/json" } }
);

export const extensions = new Elysia({ name: "extensions" })
  // HTTP routes with explicit CORS headers for local development
  .get("/extensions/token", ({ request, server }) => {
    if (!isLoopbackPeer(server, request)) {
      log.warn("Extensions: rejected non-loopback /extensions/token request");
      return FORBIDDEN_REMOTE;
    }
    const origin = request.headers.get("origin");
    const body = JSON.stringify(tokenRoute());
    return new Response(body, {
      headers: {
        "Content-Type": "application/json",
        ...(origin && { "Access-Control-Allow-Origin": origin }),
      },
    });
  })
  .get("/extensions/status", ({ request, server }) => {
    if (!isLoopbackPeer(server, request)) {
      log.warn("Extensions: rejected non-loopback /extensions/status request");
      return FORBIDDEN_REMOTE;
    }
    const origin = request.headers.get("origin");
    const body = JSON.stringify(statusRoute());
    return new Response(body, {
      headers: {
        "Content-Type": "application/json",
        ...(origin && { "Access-Control-Allow-Origin": origin }),
      },
    });
  })

  // WebSocket endpoint
  .ws("/extensions", {
    open(ws) {
      const id = generateConnectionId();
      // Use raw WebSocket for stable reference (Elysia wraps it differently per handler)
      const rawWs = (ws as any).raw;
      if (rawWs) {
        wsToId.set(rawWs, id);
      }

      const connection = registerConnection(id, ws);
      log.info(`Extensions: New connection ${id}`);

      // Send auth challenge
      ws.send(
        JSON.stringify({
          type: "auth:required",
          version: PROTOCOL_VERSION,
          capabilities: [...CAPABILITIES],
        })
      );
    },

    message(ws, rawMessage) {
      // Get connection ID via raw WebSocket (stable across Elysia handler invocations)
      const rawWs = (ws as any).raw;
      const id = rawWs ? wsToId.get(rawWs) : undefined;
      if (!id) {
        log.error("Extensions: Message from ws without connectionId");
        return;
      }

      // Handle as string
      const messageStr =
        typeof rawMessage === "string"
          ? rawMessage
          : rawMessage instanceof Buffer
            ? rawMessage.toString()
            : JSON.stringify(rawMessage);

      handleMessage(id, messageStr);
    },

    close(ws) {
      const rawWs = (ws as any).raw;
      const id = rawWs ? wsToId.get(rawWs) : undefined;
      if (id) {
        const connection = connections.get(id);
        log.info(
          `Extensions: Connection closed - ${connection?.name || id}`
        );
        closeConnection(id);
      }
    },
  });

// ===== Exports =====

export { getAuthToken } from "./auth";
export type { ExtensionConnection } from "./types";
