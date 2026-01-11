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

export const extensions = new Elysia({ name: "extensions" })
  // HTTP routes
  .get("/extensions/token", () => tokenRoute())
  .get("/extensions/status", () => statusRoute())

  // WebSocket endpoint
  .ws("/extensions", {
    open(ws) {
      const id = generateConnectionId();
      // Store ID on ws for later retrieval
      (ws as any).connectionId = id;

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
      const id = (ws as any).connectionId;
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
      const id = (ws as any).connectionId;
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
