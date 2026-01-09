/**
 * Session Routes
 *
 * GET /paths              - List all paths with their sessions (path-centric view)
 * GET /sessions           - List all sessions (flat view)
 * GET /sessions/:id       - Get messages for a specific session
 * GET /sessions/:id/messages - Alias for above
 */

import { parseTranscript } from "../../discovery/sessions";
import { sessionCache } from "../../discovery/session-cache";
import { log } from "../../log";
import { notFound } from "./responses";

// ===== Types =====

export interface SessionQueryOptions {
  limit?: number;
  before?: string;
  refresh?: boolean;
}

export interface SessionSummary {
  id: string;
  lastSeen: string;
  messageCount: number;
  isLive: boolean;
  lastMessage?: string;
  title?: string;
}

export interface PathInfo {
  path: string;
  name: string;
  folderName: string;
  sessions: SessionSummary[];
  lastSeen: string;
  isLive: boolean;
}

export interface PathsResponse {
  paths: PathInfo[];
  meta: {
    pathCount: number;
    totalPaths: number;
    sessionCount: number;
    fromCache: boolean;
    cacheAgeMs: number;
    syncedAt: string | null;
  };
}

export interface SessionInfo {
  id: string;
  folderName: string;
  project: string;
  projectPath: string;
  isLive: boolean;
  lastSeen: string;
  messageCount: number;
}

export interface SessionsResponse {
  sessions: SessionInfo[];
  meta: {
    count: number;
    total: number;
    fromCache: boolean;
    cacheAgeMs: number;
    syncedAt: string | null;
  };
}

export interface SessionMessagesResponse {
  session: {
    id: string;
    project: string;
    projectPath: string;
    isLive: boolean;
    lastSeen: string;
  };
  messages: Array<{
    role: string;
    content: string;
    timestamp?: string;
  }>;
}

// ===== Handlers =====

/**
 * GET /paths
 * List paths with their sessions
 * @param forceRefresh - Force cache refresh
 * @param limit - Max paths to return (default 15 for fast initial load)
 * @param sessionsPerPath - Max sessions per path (default 5)
 */
export async function pathsRoute(
  forceRefresh: boolean = false,
  limit: number = 15,
  sessionsPerPath: number = 5
): Promise<PathsResponse> {
  const allPaths = await sessionCache.getPaths(forceRefresh);
  const paths = allPaths.slice(0, limit);
  const status = await sessionCache.getStatus();

  const totalSessions = paths.reduce((sum, p) => sum + Math.min(p.sessions.length, sessionsPerPath), 0);

  const response: PathsResponse = {
    paths: paths.map((p) => ({
      path: p.path,
      name: p.name,
      folderName: p.folderName,
      sessions: p.sessions.slice(0, sessionsPerPath).map((s) => ({
        id: s.id,
        lastSeen: s.lastSeen,
        messageCount: s.messageCount,
        isLive: s.isLive,
        lastMessage: s.lastMessage,
        title: s.title,
      })),
      lastSeen: p.lastSeen,
      isLive: p.isLive,
    })),
    meta: {
      pathCount: paths.length,
      totalPaths: allPaths.length, // Total available
      sessionCount: totalSessions,
      fromCache: !forceRefresh && status.state === "polling",
      cacheAgeMs: status.cacheAgeMs,
      syncedAt: status.lastRefresh
        ? new Date(status.lastRefresh).toISOString()
        : null,
    },
  };

  log.info(
    `Paths: ${paths.length} paths, ${totalSessions} sessions (cache: ${status.state}, age: ${status.cacheAgeMs}ms)`
  );

  for (const p of paths.slice(0, 3)) {
    log.info(`  → ${p.name}: ${p.sessions.length} sessions, live=${p.isLive}`);
  }

  return response;
}

/**
 * GET /sessions
 * List sessions (flat view)
 * @param forceRefresh - Force cache refresh
 * @param limit - Max sessions to return (default 50 for fast initial load)
 */
export async function sessionsRoute(
  forceRefresh: boolean = false,
  limit: number = 50
): Promise<SessionsResponse> {
  const allSessions = await sessionCache.getSessions(forceRefresh);
  const sessions = allSessions.slice(0, limit);
  const status = await sessionCache.getStatus();

  const response: SessionsResponse = {
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
      total: allSessions.length, // Total available
      fromCache: !forceRefresh && status.state === "polling",
      cacheAgeMs: status.cacheAgeMs,
      syncedAt: status.lastRefresh
        ? new Date(status.lastRefresh).toISOString()
        : null,
    },
  };

  log.info(
    `Sessions: ${sessions.length}/${allSessions.length} (cache: ${status.state}, age: ${status.cacheAgeMs}ms)`
  );

  return response;
}

/**
 * GET /sessions/:id/messages
 * Get messages for a specific session
 */
export async function sessionMessagesRoute(
  sessionId: string,
  options: SessionQueryOptions = {}
): Promise<SessionMessagesResponse | Response> {
  const { limit = 50, before, refresh = false } = options;

  // Try to get session, with fallback to force refresh
  let session = await sessionCache.getSession(sessionId, refresh);

  if (!session && !refresh) {
    log.info(`Session ${sessionId} not in cache, trying force refresh`);
    session = await sessionCache.getSession(sessionId, true);
  }

  if (!session) {
    log.warn(`Session not found after all attempts: ${sessionId}`);
    return notFound("Session not found");
  }

  const messages = await parseTranscript(session.transcriptPath, limit, before);

  return {
    session: {
      id: session.id,
      project: session.project,
      projectPath: session.projectPath,
      isLive: session.isLive,
      lastSeen: session.lastSeen,
    },
    messages,
  };
}
