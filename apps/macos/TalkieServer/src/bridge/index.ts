/**
 * Bridge Module
 *
 * Local system integration - everything that talks to the Mac itself.
 *
 * ROUTES:
 *   /health              - Server health check
 *   /sessions            - Claude Code session discovery
 *   /sessions/:id        - Session messages and metadata
 *   /sessions/:id/message - Send message (routes to UI or headless)
 *   /windows             - Terminal window management
 *   /pair                - iOS ↔ Mac device pairing
 *   /match               - Terminal-to-session matching
 *   /headless            - Direct Claude CLI invocation
 *
 * DEPENDS ON:
 *   ~/.claude/projects/  - Session transcripts (read)
 *   TalkieServer (Swift) - Window operations via port 8766
 *   Tailscale            - Remote access authentication
 */

import { Elysia, t } from "elysia";

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
import { memoAttachmentsUploadRoute } from "./routes/memo-attachments";
import {
  composeCommandRoute,
  composeRevisionRoute,
  composeBorrowedProviderRoute,
  composeDirectOptionsRoute,
} from "./routes/compose";
import { ingestRoute } from "./routes/ingest";
import { ttsRoute } from "./routes/tts";
import { headlessRoute, headlessStatusRoute } from "./routes/headless";
import { cliRoute } from "./routes/remote-cli";
import { scoutHandoffRoute, scoutHandoffStatusRoute } from "./routes/scout-handoff";
import {
  companionStateRoute,
  companionTriggerRoute,
  companionActivateAppRoute,
  companionTrackpadRoute,
  companionPasteImageRoute,
} from "./routes/companion";
import { companionEventsSocket } from "./routes/companion-events";
import { companionScreenStreamSocket } from "./routes/screen-stream";
import {
  matchRoute,
  matchScanRoute,
  matchConfirmRoute,
  matchConfirmedRoute,
  matchDeleteRoute,
} from "./routes/match";
import {
  deviceSetupStateRoute,
  devicesListRoute,
  deviceRemoveRoute,
  devicesRevokeAllRoute,
} from "./routes/devices";
import {
  securityEventAckRoute,
  securityEventCreateRoute,
  securityEventsRoute,
} from "./routes/security";
import { statsRoute } from "./routes/stats";
import { notFound } from "./routes/responses";
import {
  listWindows,
  getWindow,
  getWindowScreenshot,
  getWindowContent,
  captureAllWindows,
} from "./routes/windows";

// Re-export session cache for server.ts
export { sessionCache } from "../discovery/session-cache";

const ENABLE_CLAUDE_SESSIONS = process.env.TALKIE_SERVER_ENABLE_CLAUDE_SESSIONS === "1";

/**
 * Bridge plugin - local system integration routes
 */
export const bridge = new Elysia({ name: "bridge" })
  // ===== Health =====
  .get("/health", ({ hostname, port, mode, instanceId }) => healthRoute(hostname, port, mode, instanceId))

  // ===== Sessions =====
  .get("/paths", ({ query }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return {
        paths: [],
        meta: {
          pathCount: 0,
          totalPaths: 0,
          sessionCount: 0,
          fromCache: false,
          cacheAgeMs: -1,
          syncedAt: null,
        },
      };
    }
    return pathsRoute(
      query.refresh === "deep",
      query.limit ? parseInt(query.limit, 10) : 15,
      query.sessionsPerPath ? parseInt(query.sessionsPerPath, 10) : 5
    );
  }, {
    query: t.Object({
      refresh: t.Optional(t.String()),
      limit: t.Optional(t.String()),
      sessionsPerPath: t.Optional(t.String()),
    }),
  })
  .get("/sessions", ({ query }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return {
        sessions: [],
        meta: {
          count: 0,
          total: 0,
          fromCache: false,
          cacheAgeMs: -1,
          syncedAt: null,
        },
      };
    }
    return sessionsRoute(
      query.refresh === "deep",
      query.limit ? parseInt(query.limit, 10) : 50
    );
  }, {
    query: t.Object({
      refresh: t.Optional(t.String()),
      limit: t.Optional(t.String()),
    }),
  })
  .get("/sessions/:id", ({ params, query }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return sessionMessagesRoute(params.id, {
      limit: query.limit ? parseInt(query.limit, 10) : 50,
      before: query.before,
      refresh: query.refresh === "deep",
    });
  }, {
    params: t.Object({
      id: t.String(),
    }),
    query: t.Object({
      limit: t.Optional(t.String()),
      before: t.Optional(t.String()),
      refresh: t.Optional(t.String()),
    }),
  })
  .get("/sessions/:id/messages", ({ params, query }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return sessionMessagesRoute(params.id, {
      limit: query.limit ? parseInt(query.limit, 10) : 50,
      before: query.before,
      refresh: query.refresh === "deep",
    });
  }, {
    params: t.Object({
      id: t.String(),
    }),
    query: t.Object({
      limit: t.Optional(t.String()),
      before: t.Optional(t.String()),
      refresh: t.Optional(t.String()),
    }),
  })
  .get("/sessions/:id/metadata", ({ params, query }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return sessionMetadataRoute(params.id, query.refresh === "deep");
  }, {
    params: t.Object({
      id: t.String(),
    }),
    query: t.Object({
      refresh: t.Optional(t.String()),
    }),
  })
  .get("/sessions/:id/entry/:index", ({ params }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return sessionEntryRoute(params.id, parseInt(params.index, 10));
  }, {
    params: t.Object({
      id: t.String(),
      index: t.String(),
    }),
  })
  .post("/sessions/:id/message", async ({ params, request }) => {
    // Parse body manually to avoid Elysia consuming the stream
    const body = await request.json();
    return sendMessageRoute(params.id, body);
  }, {
    params: t.Object({
      id: t.String(),
    }),
  })
  .post("/memos/:memoId/attachments", async ({ params, request }) => {
    // Parse body manually to avoid consuming the request stream before HMAC
    // verification has a chance to hash it.
    const body = await request.json();
    return memoAttachmentsUploadRoute(
      params.memoId,
      body,
      request.headers.get("X-Device-ID")
    );
  }, {
    params: t.Object({
      memoId: t.String(),
    }),
  })
  .post("/compose/revision", async ({ request }) => {
    // Parse body manually to avoid consuming the request stream before HMAC
    // verification has a chance to hash it.
    const body = await request.json();
    return composeRevisionRoute(body);
  })
  .post("/compose/command", async ({ request }) => {
    const body = await request.json();
    return composeCommandRoute(body);
  })
  .post("/compose/options", () => {
    return composeDirectOptionsRoute();
  })
  .post("/compose/provider", async ({ request }) => {
    const body = await request.json();
    return composeBorrowedProviderRoute(request.headers.get("X-Device-ID"), body);
  })

  // ===== Content Ingestion =====
  .post("/ingest", async ({ request }) => {
    const body = await request.json();
    return ingestRoute(body, request.headers.get("X-Device-ID"));
  })

  // ===== Text-to-Speech =====
  .post("/tts", async ({ request }) => {
    const body = await request.json();
    return ttsRoute(body);
  })

  // ===== Headless =====
  .post("/headless", async ({ request }) => {
    const body = await request.json();
    return headlessRoute(body);
  })
  .get("/headless/status", () => headlessStatusRoute())

  // ===== Remote CLI =====
  .post("/cli", async ({ request }) => {
    const body = await request.json();
    return cliRoute(body);
  })

  // ===== Scout Handoff =====
  .post("/handoff/scout", async ({ request }) => {
    const body = await request.json();
    return scoutHandoffRoute(body);
  })
  .get("/handoff/scout/status", () => scoutHandoffStatusRoute())

  // ===== Pairing =====
  .post("/pair", ({ body }) => pairRoute(body), {
    body: t.Object({
      deviceId: t.String(),
      publicKey: t.String(),
      name: t.String(),
    }),
  })
  .get("/pair/info", ({ hostname, alternateHosts, port, mode }) => pairInfoRoute(hostname, alternateHosts, port, mode))
  .get("/pair/pending", () => pairPendingRoute())
  .post("/pair/:deviceId/approve", ({ params }) => pairApproveRoute(params.deviceId), {
    params: t.Object({
      deviceId: t.String(),
    }),
  })
  .post("/pair/:deviceId/reject", ({ params }) => pairRejectRoute(params.deviceId), {
    params: t.Object({
      deviceId: t.String(),
    }),
  })

  // ===== Legacy inject =====
  .post("/inject", ({ body }) => sendMessageRoute(undefined, body), {
    body: t.Object({
      message: t.String(),
      sessionId: t.Optional(t.String()),
      projectDir: t.Optional(t.String()),
    }),
  })

  // ===== Match =====
  .get("/match", ({ query }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return matchRoute(query.fresh === "true");
  }, {
    query: t.Object({
      fresh: t.Optional(t.String()),
    }),
  })
  .post("/match/scan", () => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return matchScanRoute();
  })
  .post("/match/confirm", ({ body }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return matchConfirmRoute(body);
  }, {
    body: t.Object({
      terminalFingerprint: t.String(),
      sessionId: t.String(),
    }),
  })
  .get("/match/confirmed", () => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return matchConfirmedRoute();
  })
  .delete("/match/confirmed/:fingerprint", ({ params }) => {
    if (!ENABLE_CLAUDE_SESSIONS) {
      return notFound("Claude sessions are disabled on this server.");
    }
    return matchDeleteRoute(decodeURIComponent(params.fingerprint));
  }, {
    params: t.Object({
      fingerprint: t.String(),
    }),
  })

  // ===== Windows =====
  .get("/windows", () => listWindows())
  .get("/windows/captures", () => captureAllWindows())
  .get("/windows/:id", ({ params }) => getWindow(params.id), {
    params: t.Object({
      id: t.String(),
    }),
  })
  .get("/windows/:id/screenshot", ({ params }) => getWindowScreenshot(params.id), {
    params: t.Object({
      id: t.String(),
    }),
  })
  .get("/windows/:id/content", ({ params }) => getWindowContent(params.id), {
    params: t.Object({
      id: t.String(),
    }),
  })

  // ===== Devices =====
  .get("/devices", () => devicesListRoute())
  .post("/devices/setup-state", async ({ request }) => {
    const body = await request.json();
    return deviceSetupStateRoute(request.headers.get("X-Device-ID"), body);
  })
  .delete("/devices/:id", ({ params }) => deviceRemoveRoute(params.id), {
    params: t.Object({
      id: t.String(),
    }),
  })
  .delete("/devices", () => devicesRevokeAllRoute())

  // ===== Security Events =====
  .get("/security/events", ({ query }) => securityEventsRoute({
    deviceId: typeof query.deviceId === "string" ? query.deviceId : undefined,
    includeAcknowledged: typeof query.includeAcknowledged === "string" ? query.includeAcknowledged : undefined,
    limit: typeof query.limit === "string" ? query.limit : undefined,
  }), {
    query: t.Object({
      deviceId: t.Optional(t.String()),
      includeAcknowledged: t.Optional(t.String()),
      limit: t.Optional(t.String()),
    }),
  })
  .post("/security/events", async ({ request }) => {
    const body = await request.json();
    return securityEventCreateRoute(body);
  })
  .post("/security/events/:id/ack", async ({ params, request }) => {
    const body = await request.json().catch(() => ({}));
    return securityEventAckRoute(params.id, request.headers.get("X-Device-ID"), body);
  }, {
    params: t.Object({
      id: t.String(),
    }),
  })

  // ===== Companion =====
  .get("/companion/state", async ({ query }) => companionStateRoute({
    deviceId: typeof query.deviceId === "string" ? query.deviceId : undefined,
    deviceClass: query.deviceClass === "ipad" || query.deviceClass === "iphone" ? query.deviceClass : undefined,
  }), {
    query: t.Object({
      deviceId: t.Optional(t.String()),
      deviceClass: t.Optional(t.String()),
    }),
  })
  .post("/companion/trigger", async ({ request }) => {
    const body = await request.json();
    return companionTriggerRoute(body);
  })
  .post("/companion/activate-app", async ({ request }) => {
    const body = await request.json();
    return companionActivateAppRoute(body);
  })
  .post("/companion/trackpad", async ({ request }) => {
    const body = await request.json();
    return companionTrackpadRoute(body);
  })
  .post("/companion/paste-image", async ({ request }) => {
    const body = await request.json();
    return companionPasteImageRoute(body);
  })
  .ws("/companion/events", companionEventsSocket)
  .ws("/companion/screen", companionScreenStreamSocket)

  // ===== Stats =====
  .get("/stats", () => statsRoute());
