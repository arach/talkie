/**
 * Mac Stats Route
 *
 * GET /stats - Returns lightweight stats about Claude sessions on Mac
 *
 * This is a FAST endpoint - reads only metadata, not full session data.
 * iOS can poll this frequently without impacting server performance.
 */

import { sessionCache } from "../../discovery/session-cache";

// ===== Types =====

export interface MacStats {
  // Counts (from cache metadata - instant)
  projects: number;
  sessions: number;

  // Cache info
  lastSync: string;
  cacheAgeMs: number;
  syncing: boolean;

  // Server
  uptime: number;
}

// Track server start time
const serverStartTime = Date.now();

// ===== Handler =====

/**
 * GET /stats
 * Returns lightweight Mac stats - reads only metadata, no data loading
 */
export async function statsRoute(): Promise<MacStats> {
  if (process.env.TALKIE_SERVER_ENABLE_CLAUDE_SESSIONS !== "1") {
    return {
      projects: 0,
      sessions: 0,
      lastSync: "disabled",
      cacheAgeMs: -1,
      syncing: false,
      uptime: Date.now() - serverStartTime,
    };
  }

  // This only reads meta.json - doesn't load paths or sessions
  const status = await sessionCache.getStatus();

  return {
    projects: status.pathCount,
    sessions: status.sessionCount,
    lastSync: status.lastRefresh > 0
      ? new Date(status.lastRefresh).toISOString()
      : "never",
    cacheAgeMs: status.cacheAgeMs,
    syncing: status.isRefreshing,
    uptime: Date.now() - serverStartTime,
  };
}
