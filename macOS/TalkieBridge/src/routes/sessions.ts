import { parseTranscript } from "../discovery/sessions";
import { sessionCache } from "../discovery/session-cache";
import { log } from "../log";

/**
 * List all sessions
 * GET /sessions
 * Query params:
 *   - refresh=deep  Force full rescan (bypass cache)
 */
export async function sessionsRoute(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const forceRefresh = url.searchParams.get("refresh") === "deep";

  const sessions = await sessionCache.getSessions(forceRefresh);
  const status = sessionCache.getStatus();

  const response = {
    sessions: sessions.map((s) => ({
      id: s.id,
      folderName: s.folderName,
      project: s.project,
      projectPath: s.projectPath,
      isLive: s.isLive,
      lastSeen: s.lastSeen,
      messageCount: s.messageCount,
    })),
    meta: {
      count: sessions.length,
      fromCache: !forceRefresh && status.state === "polling",
      cacheAgeMs: status.cacheAgeMs,
      syncedAt: status.lastRefresh
        ? new Date(status.lastRefresh).toISOString()
        : null,
    },
  };

  log.info(
    `Sessions: ${sessions.length} sessions (cache: ${status.state}, age: ${status.cacheAgeMs}ms)`
  );

  return Response.json(response);
}

/**
 * Get messages for a specific session
 * GET /sessions/:id/messages?limit=50&before=timestamp
 * Query params:
 *   - limit         Number of messages to return (default 50)
 *   - before        Return messages before this timestamp
 *   - refresh=deep  Force cache bypass for session lookup
 */
export async function sessionMessagesRoute(
  req: Request,
  sessionId: string
): Promise<Response> {
  const url = new URL(req.url);
  const limit = parseInt(url.searchParams.get("limit") || "50", 10);
  const before = url.searchParams.get("before") || undefined;
  const forceRefresh = url.searchParams.get("refresh") === "deep";

  const session = await sessionCache.getSession(sessionId, forceRefresh);

  if (!session) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  const messages = await parseTranscript(session.transcriptPath, limit, before);

  return Response.json({
    session: {
      id: session.id,
      project: session.project,
      projectPath: session.projectPath,
      isLive: session.isLive,
      lastSeen: session.lastSeen,
    },
    messages,
  });
}
