/**
 * File-Based Session Cache
 *
 * Principle: The cache is NEVER in the critical path of serving requests.
 *
 * - On startup: load existing cache from disk (instant)
 * - Background worker updates cache periodically
 * - Requests always read from cache - never wait on any cache operation
 */

import {
  discoverSessions,
  discoverPaths,
  discoverPathsQuick,
  getSession as getSessionDirect,
  parseSessionFile,
  clearMetadataCache,
  type ClaudeSession,
  type PathEntry,
} from "./sessions";
import { log } from "../log";
import { spawn } from "bun";
import { homedir } from "os";
import { join, dirname } from "path";
import { mkdir } from "fs/promises";

// Cache location
const CACHE_DIR = join(homedir(), ".talkie", "cache");
const PATHS_FILE = join(CACHE_DIR, "paths.json");
const SESSIONS_FILE = join(CACHE_DIR, "sessions.json");
const META_FILE = join(CACHE_DIR, "meta.json");
const TIMESTAMP_FILE = join(CACHE_DIR, ".last-build");

// Timing
const POLL_INTERVAL_MS = 60_000; // Check for changes every 60 seconds
const CLAUDE_PROJECTS_DIR = join(homedir(), ".claude", "projects");

interface CacheMeta {
  lastBuild: string;
  sessionCount: number;
  pathCount: number;
}

/**
 * Background cache builder - completely separate from request handling
 */
class CacheBuilder {
  private building = false;
  private pollTimer: ReturnType<typeof setInterval> | null = null;

  /**
   * Ensure cache directory exists
   */
  async ensureDir(): Promise<void> {
    await mkdir(CACHE_DIR, { recursive: true });
  }

  /**
   * Load existing cache from disk (for serving)
   * Returns true if cache exists
   */
  async loadFromDisk(): Promise<boolean> {
    try {
      const exists = await Bun.file(PATHS_FILE).exists();
      if (!exists) {
        log.info("Cache: no existing cache on disk");
        return false;
      }

      const meta = await Bun.file(META_FILE).json() as CacheMeta;
      log.info(`Cache: loaded from disk (${meta.pathCount} paths, ${meta.sessionCount} sessions, built ${meta.lastBuild})`);
      return true;
    } catch (err) {
      log.warn(`Cache: failed to load from disk: ${err}`);
      return false;
    }
  }

  /**
   * Quick build - folder names only, top 10 by mtime
   * Used for cold start when no cache exists
   */
  async quickBuild(): Promise<void> {
    const start = Date.now();
    try {
      const paths = await discoverPathsQuick();
      // Take top 10 by lastSeen
      const topPaths = paths.slice(0, 10);

      await this.saveCache(topPaths, []);
      log.info(`Cache: quick build done (${topPaths.length} paths in ${Date.now() - start}ms)`);
    } catch (err) {
      log.error(`Cache: quick build failed: ${err}`);
    }
  }

  /**
   * Full build - scans everything
   * Called on cold start or when forced
   */
  async fullBuild(): Promise<void> {
    if (this.building) {
      log.debug("Cache: build already in progress, skipping");
      return;
    }

    this.building = true;
    const start = Date.now();

    try {
      clearMetadataCache();
      const [sessions, paths] = await Promise.all([
        discoverSessions(),
        discoverPaths(),
      ]);

      await this.saveCache(paths, sessions);
      await this.touchTimestamp();

      const elapsed = Date.now() - start;
      log.info(`Cache: full build done (${paths.length} paths, ${sessions.length} sessions in ${elapsed}ms)`);
    } catch (err) {
      log.error(`Cache: full build failed: ${err}`);
    } finally {
      this.building = false;
    }
  }

  /**
   * Incremental build - only re-parse changed files
   */
  async incrementalBuild(): Promise<void> {
    if (this.building) return;

    const changedFiles = await this.getChangedFiles();
    if (changedFiles.length === 0) return;

    this.building = true;
    const start = Date.now();

    try {
      // Load current cache
      const paths = await this.loadPaths();
      const sessions = await this.loadSessions();

      // Parse only changed files
      for (const filePath of changedFiles) {
        try {
          const session = await parseSessionFile(filePath);
          if (!session) continue;

          // Update sessions array
          const sessionIdx = sessions.findIndex((s) => s.id === session.id);
          if (sessionIdx >= 0) {
            sessions[sessionIdx] = session;
          } else {
            sessions.push(session);
          }

          // Update paths array
          const pathEntry = paths.find((p) => p.folderName === session.folderName);
          if (pathEntry) {
            const pathSessionIdx = pathEntry.sessions.findIndex((s) => s.id === session.id);
            if (pathSessionIdx >= 0) {
              pathEntry.sessions[pathSessionIdx] = session;
            } else {
              pathEntry.sessions.push(session);
            }
            // Update path lastSeen
            if (new Date(session.lastSeen) > new Date(pathEntry.lastSeen)) {
              pathEntry.lastSeen = session.lastSeen;
            }
          }
        } catch (err) {
          log.warn(`Cache: failed to parse ${filePath}: ${err}`);
        }
      }

      // Re-sort sessions by lastSeen
      sessions.sort((a, b) => new Date(b.lastSeen).getTime() - new Date(a.lastSeen).getTime());

      // Re-sort paths by lastSeen
      paths.sort((a, b) => new Date(b.lastSeen).getTime() - new Date(a.lastSeen).getTime());

      await this.saveCache(paths, sessions);
      await this.touchTimestamp();

      log.info(`Cache: incremental build done (${changedFiles.length} files in ${Date.now() - start}ms)`);
    } catch (err) {
      log.error(`Cache: incremental build failed: ${err}`);
    } finally {
      this.building = false;
    }
  }

  /**
   * Get list of files changed since last build
   */
  private async getChangedFiles(): Promise<string[]> {
    try {
      const timestampExists = await Bun.file(TIMESTAMP_FILE).exists();
      if (!timestampExists) {
        // No timestamp means we need a full build
        log.debug("Cache: no timestamp file, triggering full build");
        this.fullBuild(); // fire and forget
        return [];
      }

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
      const files = output.trim().split("\n").filter(Boolean);

      if (files.length > 0) {
        log.debug(`Cache: ${files.length} changed files detected`);
      }

      return files;
    } catch (err) {
      log.warn(`Cache: change detection failed: ${err}`);
      return [];
    }
  }

  /**
   * Load paths from cache file
   */
  private async loadPaths(): Promise<PathEntry[]> {
    try {
      const exists = await Bun.file(PATHS_FILE).exists();
      if (!exists) return [];
      return await Bun.file(PATHS_FILE).json() as PathEntry[];
    } catch {
      return [];
    }
  }

  /**
   * Load sessions from cache file
   */
  private async loadSessions(): Promise<ClaudeSession[]> {
    try {
      const exists = await Bun.file(SESSIONS_FILE).exists();
      if (!exists) return [];
      return await Bun.file(SESSIONS_FILE).json() as ClaudeSession[];
    } catch {
      return [];
    }
  }

  /**
   * Save cache to disk
   */
  private async saveCache(paths: PathEntry[], sessions: ClaudeSession[]): Promise<void> {
    await this.ensureDir();

    const meta: CacheMeta = {
      lastBuild: new Date().toISOString(),
      pathCount: paths.length,
      sessionCount: sessions.length,
    };

    await Promise.all([
      Bun.write(PATHS_FILE, JSON.stringify(paths)),
      Bun.write(SESSIONS_FILE, JSON.stringify(sessions)),
      Bun.write(META_FILE, JSON.stringify(meta)),
    ]);
  }

  /**
   * Update timestamp file after successful build
   */
  private async touchTimestamp(): Promise<void> {
    try {
      await Bun.write(TIMESTAMP_FILE, Date.now().toString());
    } catch {
      // Ignore errors
    }
  }

  /**
   * Start periodic refresh
   */
  startPolling(): void {
    if (this.pollTimer) return;

    log.info("Cache: polling started");
    this.pollTimer = setInterval(() => {
      this.incrementalBuild();
    }, POLL_INTERVAL_MS);
  }

  /**
   * Stop polling
   */
  stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
      log.info("Cache: polling stopped");
    }
  }

  /**
   * Get build status
   */
  getStatus(): { building: boolean; polling: boolean } {
    return {
      building: this.building,
      polling: this.pollTimer !== null,
    };
  }
}

/**
 * Cache reader - serves requests from cache files
 * Never waits on cache builder
 */
class CacheReader {
  /**
   * Get paths - reads from cache file
   */
  async getPaths(): Promise<PathEntry[]> {
    try {
      const exists = await Bun.file(PATHS_FILE).exists();
      if (!exists) return [];
      return await Bun.file(PATHS_FILE).json() as PathEntry[];
    } catch {
      return [];
    }
  }

  /**
   * Get sessions - reads from cache file
   */
  async getSessions(): Promise<ClaudeSession[]> {
    try {
      const exists = await Bun.file(SESSIONS_FILE).exists();
      if (!exists) return [];
      return await Bun.file(SESSIONS_FILE).json() as ClaudeSession[];
    } catch {
      return [];
    }
  }

  /**
   * Get cache metadata
   */
  async getMeta(): Promise<CacheMeta | null> {
    try {
      const exists = await Bun.file(META_FILE).exists();
      if (!exists) return null;
      return await Bun.file(META_FILE).json() as CacheMeta;
    } catch {
      return null;
    }
  }
}

// Singletons
const builder = new CacheBuilder();
const reader = new CacheReader();

/**
 * Session cache - public API
 * Combines builder and reader with simple interface
 */
export const sessionCache = {
  /**
   * Initialize cache on server startup
   */
  async warmup(): Promise<void> {
    await builder.ensureDir();

    const hasCache = await builder.loadFromDisk();

    if (hasCache) {
      // Cache exists - serve immediately, refresh in background
      builder.incrementalBuild(); // fire and forget
    } else {
      // Cold start - quick build, then full in background
      await builder.quickBuild();
      builder.fullBuild(); // fire and forget
    }

    builder.startPolling();
  },

  /**
   * Get paths - always returns immediately from cache
   * @param forceRefresh - if true, schedules a rebuild (but still returns cached data)
   */
  async getPaths(forceRefresh = false): Promise<PathEntry[]> {
    if (forceRefresh) {
      builder.fullBuild(); // fire and forget
    }
    return reader.getPaths();
  },

  /**
   * Get sessions - always returns immediately from cache
   * @param forceRefresh - if true, schedules a rebuild (but still returns cached data)
   */
  async getSessions(forceRefresh = false): Promise<ClaudeSession[]> {
    if (forceRefresh) {
      builder.fullBuild(); // fire and forget
    }
    return reader.getSessions();
  },

  /**
   * Get single session by ID
   */
  async getSession(id: string, forceRefresh = false): Promise<ClaudeSession | null> {
    if (forceRefresh) {
      // For single session, go direct
      return getSessionDirect(id);
    }

    const sessions = await reader.getSessions();

    // Try exact match
    let session = sessions.find((s) => s.id === id);
    if (session) return session;

    // Try folderName match
    session = sessions.find((s) => s.folderName === id);
    if (session) return session;

    // Fallback to direct lookup
    return getSessionDirect(id);
  },

  /**
   * Get cache status
   */
  async getStatus(): Promise<{
    state: string;
    sessionCount: number;
    pathCount: number;
    lastRefresh: number;
    cacheAgeMs: number;
    isRefreshing: boolean;
  }> {
    const meta = await reader.getMeta();
    const builderStatus = builder.getStatus();

    return {
      state: builderStatus.polling ? "polling" : "idle",
      sessionCount: meta?.sessionCount ?? 0,
      pathCount: meta?.pathCount ?? 0,
      lastRefresh: meta ? new Date(meta.lastBuild).getTime() : 0,
      cacheAgeMs: meta ? Date.now() - new Date(meta.lastBuild).getTime() : -1,
      isRefreshing: builderStatus.building,
    };
  },

  /**
   * Shutdown - stop polling
   */
  shutdown(): void {
    builder.stopPolling();
  },
};
