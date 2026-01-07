import { sessionCache } from "../../discovery/session-cache";
import { labsLog } from "../log";

/**
 * List sessions for the Labs explorer
 * GET /sessions
 * Query params:
 *   - refresh=deep  Force full rescan (bypass cache)
 */
export async function listSessionsRoute(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const forceRefresh = url.searchParams.get("refresh") === "deep";

  const sessions = await sessionCache.getSessions(forceRefresh);
  const status = sessionCache.getStatus();

  const response = {
    sessions: sessions.map((session) => ({
      id: session.id,
      folderName: session.folderName,
      project: session.project,
      projectPath: session.projectPath,
      isLive: session.isLive,
      lastSeen: session.lastSeen,
      messageCount: session.messageCount,
    })),
    meta: {
      count: sessions.length,
      fromCache: !forceRefresh && status.state === "polling",
      cacheAgeMs: status.cacheAgeMs,
      syncedAt: status.lastRefresh ? new Date(status.lastRefresh).toISOString() : null,
    },
  };

  labsLog.info(
    `Labs sessions: ${sessions.length} (cache: ${status.state}, age: ${status.cacheAgeMs}ms)`
  );

  return Response.json(response);
}
