/**
 * Engagement-Aware Session Cache
 *
 * Polls for session updates while user is actively engaged.
 * Goes idle after 5 minutes of no requests to conserve resources.
 * Supports forced "deep sync" to bypass cache entirely.
 */

import {
  discoverSessions,
  getSession as getSessionDirect,
  type ClaudeSession,
} from "./sessions";
import { log } from "../log";

const POLL_INTERVAL_MS = 3_000; // Poll every 3 seconds while engaged
const IDLE_TIMEOUT_MS = 5 * 60 * 1000; // Go idle after 5 minutes

type CacheState = "idle" | "polling";

class EngagementAwareCache {
  private state: CacheState = "idle";
  private cache: ClaudeSession[] = [];
  private lastRefresh = 0;
  private lastRequest = 0;
  private pollTimer: ReturnType<typeof setInterval> | null = null;

  /**
   * Get all sessions. Fast path returns from cache.
   * @param forceRefresh - If true, bypasses cache entirely (deep sync)
   */
  async getSessions(forceRefresh = false): Promise<ClaudeSession[]> {
    this.touch();

    if (forceRefresh) {
      log.info("Deep sync: forcing full rescan");
      await this.refresh();
      return this.cache;
    }

    // If cache is empty (cold start), do initial scan
    if (this.cache.length === 0) {
      await this.refresh();
    }

    return this.cache;
  }

  /**
   * Get a single session by ID
   * Tries cache first, then falls back to direct lookup
   * @param forceRefresh - If true, bypasses cache entirely
   */
  async getSession(
    id: string,
    forceRefresh = false
  ): Promise<ClaudeSession | null> {
    if (forceRefresh) {
      // For single session deep refresh, just fetch that one directly
      return getSessionDirect(id);
    }

    const sessions = await this.getSessions();

    // Try exact match first
    let session = sessions.find((s) => s.id === id);
    if (session) return session;

    // Try matching by folder name (in case ID format differs)
    session = sessions.find((s) => s.folderName === id);
    if (session) {
      log.debug(`Session found by folderName fallback: ${id}`);
      return session;
    }

    // Last resort: try direct lookup (bypasses cache)
    log.debug(`Session not in cache, trying direct lookup: ${id}`);
    const directSession = await getSessionDirect(id);
    if (directSession) {
      log.info(`Session found via direct lookup: ${id}`);
    }
    return directSession;
  }

  /**
   * Record a request (keeps polling alive)
   */
  private touch(): void {
    this.lastRequest = Date.now();

    if (this.state === "idle") {
      this.startPolling();
    }
  }

  /**
   * Force a cache refresh
   */
  private async refresh(): Promise<void> {
    try {
      const start = Date.now();
      this.cache = await discoverSessions();
      this.lastRefresh = Date.now();
      log.debug(
        `Session cache refreshed: ${this.cache.length} sessions in ${Date.now() - start}ms`
      );
    } catch (err) {
      log.error(`Session refresh failed: ${err}`);
      // Keep stale cache rather than clearing on error
    }
  }

  /**
   * Start polling for updates
   */
  private startPolling(): void {
    if (this.state === "polling") return;

    this.state = "polling";
    log.info("Engagement: active, starting session polling");

    // Immediate first refresh
    this.refresh();

    // Poll periodically
    this.pollTimer = setInterval(async () => {
      // Check for idle timeout
      if (Date.now() - this.lastRequest > IDLE_TIMEOUT_MS) {
        this.stopPolling();
        return;
      }

      await this.refresh();
    }, POLL_INTERVAL_MS);
  }

  /**
   * Stop polling and clear cache
   */
  private stopPolling(): void {
    if (this.state === "idle") return;

    this.state = "idle";
    log.info("Engagement: idle, stopping session polling");

    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }

    // Clear cache to free memory
    this.cache = [];
    this.lastRefresh = 0;
  }

  /**
   * Get cache metadata for debugging/UI
   */
  getStatus(): {
    state: CacheState;
    sessionCount: number;
    lastRefresh: number;
    cacheAgeMs: number;
  } {
    return {
      state: this.state,
      sessionCount: this.cache.length,
      lastRefresh: this.lastRefresh,
      cacheAgeMs: this.lastRefresh ? Date.now() - this.lastRefresh : -1,
    };
  }

  /**
   * Clean shutdown
   */
  shutdown(): void {
    this.stopPolling();
  }
}

// Singleton export
export const sessionCache = new EngagementAwareCache();
