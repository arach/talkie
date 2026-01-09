/**
 * Engagement-Aware Session Cache with Incremental Updates
 *
 * Polls for session updates while user is actively engaged.
 * Uses `find -newer` to efficiently detect changed files.
 * Goes idle after 5 minutes of no requests to conserve resources.
 */

import {
  discoverSessions,
  discoverPaths,
  getSession as getSessionDirect,
  type ClaudeSession,
  type PathEntry,
} from "./sessions";
import { log } from "../log";
import { spawn } from "bun";
import { homedir } from "os";
import { join } from "path";

const POLL_INTERVAL_MS = 60_000; // Poll every 60 seconds while engaged
const IDLE_TIMEOUT_MS = 5 * 60 * 1000; // Go idle after 5 minutes
const CLAUDE_PROJECTS_DIR = join(homedir(), ".claude", "projects");
const TIMESTAMP_FILE = "/tmp/talkie-cache-check";

type CacheState = "idle" | "polling";

class EngagementAwareCache {
  private state: CacheState = "idle";
  private cache: ClaudeSession[] = [];
  private pathsCache: PathEntry[] = [];
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
      await this.fullRefresh();
      return this.cache;
    }

    // If cache is empty (cold start), do initial scan
    if (this.cache.length === 0) {
      await this.fullRefresh();
    }

    return this.cache;
  }

  /**
   * Get all paths with their sessions (path-centric view)
   * @param forceRefresh - If true, bypasses cache entirely (deep sync)
   */
  async getPaths(forceRefresh = false): Promise<PathEntry[]> {
    this.touch();

    if (forceRefresh) {
      log.info("Deep sync: forcing full rescan (paths)");
      await this.fullRefresh();
      return this.pathsCache;
    }

    // If cache is empty (cold start), do initial scan
    if (this.pathsCache.length === 0) {
      await this.fullRefresh();
    }

    return this.pathsCache;
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
   * Full cache refresh - walks everything
   */
  private async fullRefresh(): Promise<void> {
    try {
      const start = Date.now();
      // Refresh both caches in parallel
      const [sessions, paths] = await Promise.all([
        discoverSessions(),
        discoverPaths(),
      ]);
      this.cache = sessions;
      this.pathsCache = paths;
      this.lastRefresh = Date.now();

      const totalSessions = paths.reduce((sum, p) => sum + p.sessions.length, 0);
      log.debug(
        `Cache refresh: ${paths.length} paths, ${totalSessions} sessions in ${Date.now() - start}ms`
      );
    } catch (err) {
      log.error(`Session refresh failed: ${err}`);
    }
  }

  /**
   * Check for changes using `find -newer` (efficient shell command)
   * Returns true if any .jsonl files were modified since last check
   */
  private async hasChanges(): Promise<boolean> {
    try {
      // First check - no timestamp file exists, need full refresh
      const timestampExists = await Bun.file(TIMESTAMP_FILE).exists();
      if (!timestampExists) {
        return true;
      }

      // Use find -newer to check for modified files
      const proc = spawn({
        cmd: [
          "find", CLAUDE_PROJECTS_DIR,
          "-name", "*.jsonl",
          "-newer", TIMESTAMP_FILE,
          "-type", "f"
        ],
        stdout: "pipe",
        stderr: "pipe",
      });

      const output = await new Response(proc.stdout).text();
      const changedFiles = output.trim().split("\n").filter(Boolean);

      if (changedFiles.length > 0) {
        log.debug(`Found ${changedFiles.length} changed files`);
        return true;
      }

      return false;
    } catch (err) {
      log.warn(`Change detection failed: ${err}`);
      return true; // Assume changes on error
    }
  }

  /**
   * Update timestamp file after successful refresh
   */
  private async touchTimestamp(): Promise<void> {
    try {
      await Bun.write(TIMESTAMP_FILE, Date.now().toString());
    } catch {
      // Ignore errors
    }
  }

  /**
   * Incremental refresh - only refresh if files changed
   */
  private async incrementalRefresh(): Promise<void> {
    const hasChanges = await this.hasChanges();

    if (hasChanges) {
      await this.fullRefresh();
      await this.touchTimestamp();
    }
    // Silent when no changes - no logging spam
  }

  /**
   * Start polling for updates
   * Note: Does NOT do initial refresh - callers handle that with await
   */
  private startPolling(): void {
    if (this.state === "polling") return;

    this.state = "polling";
    log.info("Engagement: active, starting session polling");

    // Poll periodically (incremental) - first poll after interval
    // Initial data load is handled by callers with proper await
    this.pollTimer = setInterval(async () => {
      // Check for idle timeout
      if (Date.now() - this.lastRequest > IDLE_TIMEOUT_MS) {
        this.stopPolling();
        return;
      }

      await this.incrementalRefresh();
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

    // Clear caches to free memory
    this.cache = [];
    this.pathsCache = [];
    this.lastRefresh = 0;
  }

  /**
   * Get cache metadata for debugging/UI
   */
  getStatus(): {
    state: CacheState;
    sessionCount: number;
    pathCount: number;
    lastRefresh: number;
    cacheAgeMs: number;
  } {
    return {
      state: this.state,
      sessionCount: this.cache.length,
      pathCount: this.pathsCache.length,
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
