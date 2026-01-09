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
import { headlessRoute, headlessStatusRoute } from "./routes/headless";
import {
  matchRoute,
  matchScanRoute,
  matchConfirmRoute,
  matchConfirmedRoute,
  matchDeleteRoute,
} from "./routes/match";
import {
  devicesListRoute,
  deviceRemoveRoute,
  devicesRevokeAllRoute,
} from "./routes/devices";
import { statsRoute } from "./routes/stats";
import {
  listWindows,
  getWindow,
  getWindowScreenshot,
  getWindowContent,
  captureAllWindows,
} from "./routes/windows";

// Re-export session cache for server.ts
export { sessionCache } from "../discovery/session-cache";

/**
 * Bridge plugin - local system integration routes
 */
export const bridge = new Elysia({ name: "bridge" })
  // ===== Health =====
  .get("/health", ({ hostname }) => healthRoute(hostname))

  // ===== Sessions =====
  .get("/paths", ({ query }) => pathsRoute(
    query.refresh === "deep",
    query.limit ? parseInt(query.limit, 10) : 15,
    query.sessionsPerPath ? parseInt(query.sessionsPerPath, 10) : 5
  ), {
    query: t.Object({
      refresh: t.Optional(t.String()),
      limit: t.Optional(t.String()),
      sessionsPerPath: t.Optional(t.String()),
    }),
  })
  .get("/sessions", ({ query }) => sessionsRoute(
    query.refresh === "deep",
    query.limit ? parseInt(query.limit, 10) : 50
  ), {
    query: t.Object({
      refresh: t.Optional(t.String()),
      limit: t.Optional(t.String()),
    }),
  })
  .get("/sessions/:id", ({ params, query }) =>
    sessionMessagesRoute(params.id, {
      limit: query.limit ? parseInt(query.limit, 10) : 50,
      before: query.before,
      refresh: query.refresh === "deep",
    }), {
    params: t.Object({
      id: t.String(),
    }),
    query: t.Object({
      limit: t.Optional(t.String()),
      before: t.Optional(t.String()),
      refresh: t.Optional(t.String()),
    }),
  })
  .get("/sessions/:id/messages", ({ params, query }) =>
    sessionMessagesRoute(params.id, {
      limit: query.limit ? parseInt(query.limit, 10) : 50,
      before: query.before,
      refresh: query.refresh === "deep",
    }), {
    params: t.Object({
      id: t.String(),
    }),
    query: t.Object({
      limit: t.Optional(t.String()),
      before: t.Optional(t.String()),
      refresh: t.Optional(t.String()),
    }),
  })
  .get("/sessions/:id/metadata", ({ params, query }) =>
    sessionMetadataRoute(params.id, query.refresh === "deep"), {
    params: t.Object({
      id: t.String(),
    }),
    query: t.Object({
      refresh: t.Optional(t.String()),
    }),
  })
  .get("/sessions/:id/entry/:index", ({ params }) =>
    sessionEntryRoute(params.id, parseInt(params.index, 10)), {
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

  // ===== Headless =====
  .post("/headless", ({ body }) => headlessRoute(body), {
    body: t.Object({
      sessionId: t.String(),
      message: t.String(),
      projectDir: t.Optional(t.String()),
      stream: t.Optional(t.Boolean()),
    }),
  })
  .get("/headless/status", () => headlessStatusRoute())

  // ===== Pairing =====
  .post("/pair", ({ body }) => pairRoute(body), {
    body: t.Object({
      deviceId: t.String(),
      publicKey: t.String(),
      name: t.String(),
    }),
  })
  .get("/pair/info", ({ hostname, port }) => pairInfoRoute(hostname, port))
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
  .get("/match", ({ query }) => matchRoute(query.fresh === "true"), {
    query: t.Object({
      fresh: t.Optional(t.String()),
    }),
  })
  .post("/match/scan", () => matchScanRoute())
  .post("/match/confirm", ({ body }) => matchConfirmRoute(body), {
    body: t.Object({
      terminalFingerprint: t.String(),
      sessionId: t.String(),
    }),
  })
  .get("/match/confirmed", () => matchConfirmedRoute())
  .delete("/match/confirmed/:fingerprint", ({ params }) =>
    matchDeleteRoute(decodeURIComponent(params.fingerprint)), {
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
  .delete("/devices/:id", ({ params }) => deviceRemoveRoute(params.id), {
    params: t.Object({
      id: t.String(),
    }),
  })
  .delete("/devices", () => devicesRevokeAllRoute())

  // ===== Stats =====
  .get("/stats", () => statsRoute());
