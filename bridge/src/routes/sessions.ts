import {
  discoverSessions,
  getSession,
  parseTranscript,
} from "../discovery/sessions";
import { log } from "../log";

/**
 * List all sessions
 * GET /sessions
 */
export async function sessionsRoute(req: Request): Promise<Response> {
  const sessions = await discoverSessions();

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
  };

  // Log sessions for debugging
  log.info(`Sessions: returning ${sessions.length} sessions`);
  console.log(JSON.stringify(response, null, 2));

  return Response.json(response);
}

/**
 * Get messages for a specific session
 * GET /sessions/:id/messages?limit=50&before=timestamp
 */
export async function sessionMessagesRoute(
  req: Request,
  sessionId: string
): Promise<Response> {
  const session = await getSession(sessionId);

  if (!session) {
    return Response.json({ error: "Session not found" }, { status: 404 });
  }

  const url = new URL(req.url);
  const limit = parseInt(url.searchParams.get("limit") || "50", 10);
  const before = url.searchParams.get("before") || undefined;

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
