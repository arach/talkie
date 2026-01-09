import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";
import { log } from "../log";

const CLAUDE_PROJECTS_DIR = `${process.env.HOME}/.claude/projects`;

// In-memory cache for metadata to avoid redundant file reads during refresh
// Cleared at the start of each full refresh
const metadataCache = new Map<string, { sessionId?: string; cwd?: string; title?: string } | null>();

/** Clear metadata cache (call at start of refresh) */
export function clearMetadataCache(): void {
  metadataCache.clear();
}

export interface ClaudeSession {
  id: string;              // Actual Claude session UUID
  folderName: string;      // Encoded path (e.g., "-Users-arach-dev-talkie")
  project: string;         // Display name (e.g., "talkie")
  projectPath: string;     // Full path (e.g., "/Users/arach/dev/talkie")
  isLive: boolean;
  lastSeen: string;
  messageCount: number;
  transcriptPath: string;
}

/** A single session (conversation) within a path */
export interface Session {
  id: string;              // Session UUID
  lastSeen: string;        // ISO timestamp
  messageCount: number;
  isLive: boolean;
  transcriptPath: string;
  lastMessage?: string;    // Preview of most recent message (first 100 chars)
  title?: string;          // Session title/name if available
}

/** A path (working directory) with all its sessions */
export interface PathEntry {
  path: string;            // Full path (e.g., "/Users/arach/dev/talkie")
  name: string;            // Display name (e.g., "talkie")
  folderName: string;      // Encoded folder name for lookups
  sessions: Session[];     // All sessions in this path, sorted by lastSeen
  lastSeen: string;        // Most recent session's lastSeen
  isLive: boolean;         // True if any session is live
}

export interface Message {
  role: "user" | "assistant";
  content: string;
  timestamp: string;
  toolCalls?: ToolCall[];
}

export interface ToolCall {
  name: string;
  input?: unknown;
  output?: unknown;
}

/**
 * Convert Claude's encoded folder name back to a path
 * e.g., "-Users-arach-dev-talkie" -> "/Users/arach/dev/talkie"
 */
function folderToPath(folder: string): string {
  // Handle leading dash (represents leading /)
  if (folder.startsWith("-")) {
    return "/" + folder.slice(1).replace(/-/g, "/");
  }
  return folder.replace(/-/g, "/");
}

/**
 * Get a display name for a project path
 */
function getDisplayName(projectPath: string): string {
  return projectPath.split("/").pop() || projectPath;
}

/**
 * Check if Claude is currently running (any instance)
 */
async function isClaudeRunning(): Promise<boolean> {
  const result = await $`pgrep -f "claude"`.quiet().nothrow();
  return result.exitCode === 0;
}

/**
 * Find the most recent .jsonl file in a project directory
 */
async function findLatestTranscript(
  projectDir: string
): Promise<{ path: string; mtime: Date } | null> {
  try {
    const files = await readdir(projectDir);
    const jsonlFiles = files.filter((f) => f.endsWith(".jsonl"));

    if (jsonlFiles.length === 0) return null;

    let latest: { path: string; mtime: Date } | null = null;

    for (const file of jsonlFiles) {
      const filePath = join(projectDir, file);
      const stats = await stat(filePath);
      if (!latest || stats.mtime > latest.mtime) {
        latest = { path: filePath, mtime: stats.mtime };
      }
    }

    return latest;
  } catch {
    return null;
  }
}

/**
 * Find ALL .jsonl transcript files in a project directory
 * Returns them sorted by mtime (most recent first)
 */
async function findAllTranscripts(
  projectDir: string
): Promise<{ path: string; mtime: Date; filename: string }[]> {
  try {
    const files = await readdir(projectDir);
    const jsonlFiles = files.filter((f) => f.endsWith(".jsonl"));

    if (jsonlFiles.length === 0) return [];

    const transcripts: { path: string; mtime: Date; filename: string }[] = [];

    for (const file of jsonlFiles) {
      const filePath = join(projectDir, file);
      const stats = await stat(filePath);
      transcripts.push({
        path: filePath,
        mtime: stats.mtime,
        filename: file.replace(".jsonl", ""),
      });
    }

    // Sort by mtime descending (most recent first)
    transcripts.sort((a, b) => b.mtime.getTime() - a.mtime.getTime());

    return transcripts;
  } catch {
    return [];
  }
}

/**
 * Count messages in a JSONL transcript file
 */
async function countMessages(transcriptPath: string): Promise<number> {
  try {
    const file = Bun.file(transcriptPath);
    const text = await file.text();
    const lines = text.trim().split("\n").filter(Boolean);
    return lines.length;
  } catch {
    return 0;
  }
}

/**
 * Check if a string is a UUID pattern (8-4-4-4-12 hex)
 */
function isUUID(str: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str);
}

/**
 * Extract session metadata from JSONL files in a project directory
 * Uses cache to avoid redundant file reads during refresh cycle
 */
async function extractSessionMetadata(
  projectDir: string,
  transcriptPath: string
): Promise<{ sessionId?: string; cwd?: string; title?: string } | null> {
  // Check cache first
  const cacheKey = transcriptPath;
  if (metadataCache.has(cacheKey)) {
    return metadataCache.get(cacheKey)!;
  }

  try {
    // First check if the transcript filename is a UUID
    const filename = transcriptPath.split('/').pop()?.replace('.jsonl', '') || '';
    if (isUUID(filename)) {
      // Try to find cwd from another file in the same directory
      const files = await readdir(projectDir);
      for (const file of files) {
        if (file.startsWith('agent-') && file.endsWith('.jsonl')) {
          const agentPath = join(projectDir, file);
          const agentFile = Bun.file(agentPath);
          const text = await agentFile.text();
          const firstLine = text.split("\n")[0];
          if (firstLine) {
            const entry = JSON.parse(firstLine);
            if (entry.cwd) {
              const result = { sessionId: filename, cwd: entry.cwd };
              metadataCache.set(cacheKey, result);
              return result;
            }
          }
        }
      }
      // No cwd found, just return the UUID
      const result = { sessionId: filename, cwd: undefined };
      metadataCache.set(cacheKey, result);
      return result;
    }

    // Otherwise try to extract from the file content
    const file = Bun.file(transcriptPath);
    const text = await file.text();
    const firstLine = text.split("\n")[0];
    if (!firstLine) {
      metadataCache.set(cacheKey, null);
      return null;
    }

    const entry = JSON.parse(firstLine);
    const result = {
      sessionId: entry.sessionId,
      cwd: entry.cwd,
      title: entry.title || entry.sessionTitle || entry.name,
    };

    metadataCache.set(cacheKey, result);
    return result;
  } catch (e) {
    log.debug(`[metadata] Error parsing ${transcriptPath}: ${e}`);
    return null;
  }
}

/**
 * Get all project directories (fast, no parsing)
 */
export async function getProjectDirs(): Promise<string[]> {
  try {
    const projectFolders = await readdir(CLAUDE_PROJECTS_DIR);
    const dirs: string[] = [];
    for (const folder of projectFolders) {
      const projectDir = join(CLAUDE_PROJECTS_DIR, folder);
      const stats = await stat(projectDir);
      if (stats.isDirectory()) {
        dirs.push(projectDir);
      }
    }
    return dirs;
  } catch {
    return [];
  }
}

/**
 * Discover all Claude sessions from ~/.claude/projects/
 */
/**
 * Quick discovery - folder names and mtimes only, no file parsing
 * Returns in <100ms for instant UI response
 */
export async function discoverPathsQuick(): Promise<PathEntry[]> {
  const paths: PathEntry[] = [];
  const claudeRunning = await isClaudeRunning();
  const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);

  try {
    const projectFolders = await readdir(CLAUDE_PROJECTS_DIR);

    for (const folder of projectFolders) {
      const projectDir = join(CLAUDE_PROJECTS_DIR, folder);

      try {
        const dirStats = await stat(projectDir);
        if (!dirStats.isDirectory()) continue;

        // Just get most recent file mtime - no parsing
        const files = await readdir(projectDir);
        const jsonlFiles = files.filter((f) => f.endsWith(".jsonl"));
        if (jsonlFiles.length === 0) continue;

        let latestMtime = new Date(0);
        for (const file of jsonlFiles) {
          const fileStat = await stat(join(projectDir, file));
          if (fileStat.mtime > latestMtime) {
            latestMtime = fileStat.mtime;
          }
        }

        const pathStr = folderToPath(folder);
        const isLive = claudeRunning && latestMtime > thirtyMinutesAgo;

        paths.push({
          path: pathStr,
          name: getDisplayName(pathStr),
          folderName: folder,
          sessions: [], // Empty - will be filled by full mode
          lastSeen: latestMtime.toISOString(),
          isLive,
        });
      } catch {
        continue;
      }
    }
  } catch (err) {
    log.error(`Quick discovery failed: ${err}`);
  }

  // Sort by lastSeen descending
  paths.sort((a, b) => new Date(b.lastSeen).getTime() - new Date(a.lastSeen).getTime());

  return paths;
}

export async function discoverSessions(): Promise<ClaudeSession[]> {
  const sessions: ClaudeSession[] = [];
  const claudeRunning = await isClaudeRunning();

  try {
    const projectFolders = await readdir(CLAUDE_PROJECTS_DIR);

    for (const folder of projectFolders) {
      const projectDir = join(CLAUDE_PROJECTS_DIR, folder);

      try {
        const stats = await stat(projectDir);
        if (!stats.isDirectory()) continue;

        const transcript = await findLatestTranscript(projectDir);
        if (!transcript) continue;

        // Extract metadata from JSONL file (includes sessionId UUID and cwd)
        const metadata = await extractSessionMetadata(projectDir, transcript.path);
        const sessionId = metadata?.sessionId || folder; // Fallback to folder name

        // Use cwd from metadata if available (more accurate than decoding folder name)
        const projectPath = metadata?.cwd || folderToPath(folder);
        const messageCount = await countMessages(transcript.path);

        // A session is "live" if Claude is running AND the file was modified recently (within 30 min)
        const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);
        const isLive = claudeRunning && transcript.mtime > thirtyMinutesAgo;

        sessions.push({
          id: sessionId, // Use actual Claude session UUID
          folderName: folder, // Encoded path for terminal matching
          project: getDisplayName(projectPath),
          projectPath,
          isLive,
          lastSeen: transcript.mtime.toISOString(),
          messageCount,
          transcriptPath: transcript.path,
        });
      } catch (err) {
        // Skip inaccessible directories
        continue;
      }
    }
  } catch (err) {
    log.error(`Error reading Claude projects directory: ${err}`);
  }

  // Sort by lastSeen, most recent first
  sessions.sort(
    (a, b) => new Date(b.lastSeen).getTime() - new Date(a.lastSeen).getTime()
  );

  return sessions;
}

/**
 * Discover all paths and their sessions from ~/.claude/projects/
 * Returns path-centric data with all sessions per path
 */
export async function discoverPaths(): Promise<PathEntry[]> {
  const paths: PathEntry[] = [];
  const claudeRunning = await isClaudeRunning();
  const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);

  try {
    const projectFolders = await readdir(CLAUDE_PROJECTS_DIR);

    for (const folder of projectFolders) {
      const projectDir = join(CLAUDE_PROJECTS_DIR, folder);

      try {
        const stats = await stat(projectDir);
        if (!stats.isDirectory()) continue;

        const transcripts = await findAllTranscripts(projectDir);
        if (transcripts.length === 0) continue;

        // Get path from first transcript's metadata (most recent)
        const firstMetadata = await extractSessionMetadata(projectDir, transcripts[0].path);
        const pathStr = firstMetadata?.cwd || folderToPath(folder);

        // Build sessions array
        const sessions: Session[] = [];
        for (const transcript of transcripts) {
          // Get session ID from filename if UUID, otherwise from metadata
          let sessionId: string;
          if (isUUID(transcript.filename)) {
            sessionId = transcript.filename;
          } else {
            const meta = await extractSessionMetadata(projectDir, transcript.path);
            sessionId = meta?.sessionId || transcript.filename;
          }

          const messageCount = await countMessages(transcript.path);
          const isLive = claudeRunning && transcript.mtime > thirtyMinutesAgo;
          
          // Get metadata including title if available
          const metadata = await extractSessionMetadata(projectDir, transcript.path);
          
          // Get last message preview (most recent message, up to 100 chars)
          let lastMessage: string | undefined;
          let title: string | undefined = metadata?.title;
          
          try {
            const messages = await parseTranscript(transcript.path, 1);
            if (messages.length > 0) {
              const content = messages[messages.length - 1].content;
              lastMessage = content.length > 100 ? content.substring(0, 100) + "…" : content;
              
              // If no title from metadata, use first user message as title (up to 60 chars)
              if (!title && messages.length > 0) {
                const firstUserMessage = messages.find(m => m.role === "user");
                if (firstUserMessage) {
                  title = firstUserMessage.content.length > 60 
                    ? firstUserMessage.content.substring(0, 60) + "…" 
                    : firstUserMessage.content;
                }
              }
            }
          } catch {
            // Ignore errors reading messages - it's optional
          }

          sessions.push({
            id: sessionId,
            lastSeen: transcript.mtime.toISOString(),
            messageCount,
            isLive,
            transcriptPath: transcript.path,
            lastMessage,
            title,
          });
        }

        // Path is live if any session is live
        const anyLive = sessions.some((s) => s.isLive);

        paths.push({
          path: pathStr,
          name: getDisplayName(pathStr),
          folderName: folder,
          sessions,
          lastSeen: sessions[0].lastSeen, // Most recent session
          isLive: anyLive,
        });
      } catch (err) {
        // Skip inaccessible directories
        continue;
      }
    }
  } catch (err) {
    log.error(`Error reading Claude projects directory: ${err}`);
  }

  // Sort paths by lastSeen (most recent first)
  paths.sort(
    (a, b) => new Date(b.lastSeen).getTime() - new Date(a.lastSeen).getTime()
  );

  return paths;
}

/**
 * Parse messages from a JSONL transcript file
 */
export async function parseTranscript(
  transcriptPath: string,
  limit: number = 50,
  before?: string
): Promise<Message[]> {
  const messages: Message[] = [];

  try {
    const file = Bun.file(transcriptPath);
    const text = await file.text();
    const lines = text.trim().split("\n").filter(Boolean);

    for (const line of lines) {
      try {
        const entry = JSON.parse(line);

        // Claude Code JSONL format: { type: "user"|"assistant", message: { role, content }, timestamp }
        // Also handle legacy formats with type: "human" or direct role/content

        const entryType = entry.type;
        const messageRole = entry.message?.role;

        if (entryType === "user" || entryType === "human" || messageRole === "user") {
          // Skip tool_result entries - they're system responses, not user messages
          const content = entry.message?.content || entry.content;
          if (Array.isArray(content)) {
            const isToolResult = content.some((c: any) => c.type === "tool_result");
            if (isToolResult) continue; // Skip tool results
          }

          // Extract and check if there's actual text content
          const textContent = extractUserText(entry);
          if (!textContent || textContent.trim() === "") continue; // Skip empty

          messages.push({
            role: "user",
            content: textContent,
            timestamp: entry.timestamp || new Date().toISOString(),
          });
        } else if (entryType === "assistant" || messageRole === "assistant") {
          const msg: Message = {
            role: "assistant",
            content: extractContent(entry),
            timestamp: entry.timestamp || new Date().toISOString(),
          };

          // Extract tool calls if present (from message object or entry directly)
          const toolCalls = entry.message?.tool_calls || entry.tool_calls || entry.toolCalls;
          if (toolCalls) {
            msg.toolCalls = toolCalls.map((tc: any) => ({
              name: tc.name || tc.function?.name,
              input: tc.input || tc.function?.arguments,
              output: tc.output,
            }));
          }

          messages.push(msg);
        }
      } catch {
        // Skip malformed lines
        continue;
      }
    }
  } catch (err) {
    log.error(`Error parsing transcript: ${err}`);
  }

  // Filter by 'before' timestamp if provided
  let filtered = messages;
  if (before) {
    const beforeDate = new Date(before);
    filtered = messages.filter((m) => new Date(m.timestamp) < beforeDate);
  }

  // Return most recent messages up to limit
  return filtered.slice(-limit);
}

/**
 * Extract only user-typed text (not tool results or system content)
 */
function extractUserText(entry: any): string {
  const content = entry.message?.content || entry.content;

  if (typeof content === "string") {
    return content;
  }

  if (Array.isArray(content)) {
    // Only extract text blocks, skip tool_result, images, etc.
    return content
      .filter((c: any) => c.type === "text")
      .map((c: any) => c.text || "")
      .join(" ")
      .trim();
  }

  return "";
}

/**
 * Extract content from various Claude transcript formats
 */
function extractContent(entry: any): string {
  if (typeof entry.content === "string") {
    return entry.content;
  }
  if (Array.isArray(entry.content)) {
    return entry.content
      .map((c: any) => {
        if (typeof c === "string") return c;
        if (c.type === "text") return c.text;
        if (c.type === "thinking") {
          // Show thinking summary (truncated)
          const thinking = c.thinking || "";
          if (thinking.length > 200) {
            return `💭 ${thinking.slice(0, 200)}...`;
          }
          return thinking ? `💭 ${thinking}` : "";
        }
        if (c.type === "tool_use") {
          // Show tool name with more context
          const inputPreview = c.input ? formatToolInput(c.input) : "";
          return inputPreview ? `🔧 ${c.name}: ${inputPreview}` : `🔧 ${c.name}`;
        }
        if (c.type === "tool_result") {
          // Extract text from tool result
          const resultText = extractToolResultText(c.content);
          return resultText ? `📋 ${resultText}` : "";
        }
        return "";
      })
      .filter(Boolean)
      .join("\n\n");
  }
  if (entry.message) {
    return extractContent(entry.message);
  }
  return "";
}

/**
 * Format tool input for preview (max 100 chars)
 */
function formatToolInput(input: any): string {
  if (typeof input === "string") {
    return input.length > 100 ? input.slice(0, 100) + "..." : input;
  }
  if (typeof input === "object") {
    // Common patterns
    if (input.command) return input.command.slice(0, 80);
    if (input.file_path) return input.file_path;
    if (input.pattern) return input.pattern;
    if (input.query) return input.query.slice(0, 80);
    // Fallback to first string value
    for (const val of Object.values(input)) {
      if (typeof val === "string" && val.length > 0) {
        return val.length > 80 ? val.slice(0, 80) + "..." : val;
      }
    }
  }
  return "";
}

/**
 * Extract text from tool result content
 */
function extractToolResultText(content: any): string {
  if (typeof content === "string") {
    return content.length > 200 ? content.slice(0, 200) + "..." : content;
  }
  if (Array.isArray(content)) {
    // Find first text content
    for (const c of content) {
      if (typeof c === "string") return c.slice(0, 200);
      if (c.type === "text" && c.text) return c.text.slice(0, 200);
    }
  }
  if (content?.type === "text" && content.text) {
    return content.text.slice(0, 200);
  }
  return "";
}

/**
 * Get a specific session by ID (or folder name)
 * Searches ALL transcripts across all projects, not just the latest per project
 */
export async function getSession(
  sessionId: string
): Promise<ClaudeSession | null> {
  // First try quick lookup via discoverSessions (latest sessions only)
  const latestSessions = await discoverSessions();

  let session = latestSessions.find((s) => s.id === sessionId);
  if (session) return session;

  session = latestSessions.find((s) => s.folderName === sessionId);
  if (session) return session;

  // Not found in latest sessions - search ALL transcripts
  log.debug(`[getSession] Session ${sessionId} not in latest, searching all transcripts...`);

  const claudeRunning = await isClaudeRunning();
  const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);

  try {
    const projectFolders = await readdir(CLAUDE_PROJECTS_DIR);

    for (const folder of projectFolders) {
      const projectDir = join(CLAUDE_PROJECTS_DIR, folder);

      try {
        const stats = await stat(projectDir);
        if (!stats.isDirectory()) continue;

        const transcripts = await findAllTranscripts(projectDir);

        for (const transcript of transcripts) {
          // Check if filename matches (for UUID-named files)
          if (transcript.filename === sessionId) {
            const metadata = await extractSessionMetadata(projectDir, transcript.path);
            const projectPath = metadata?.cwd || folderToPath(folder);
            const messageCount = await countMessages(transcript.path);
            const isLive = claudeRunning && transcript.mtime > thirtyMinutesAgo;

            log.debug(`[getSession] Found session ${sessionId} via filename match in ${folder}`);
            return {
              id: sessionId,
              folderName: folder,
              project: getDisplayName(projectPath),
              projectPath,
              isLive,
              lastSeen: transcript.mtime.toISOString(),
              messageCount,
              transcriptPath: transcript.path,
            };
          }

          // Check if metadata sessionId matches
          const metadata = await extractSessionMetadata(projectDir, transcript.path);
          if (metadata?.sessionId === sessionId) {
            const projectPath = metadata?.cwd || folderToPath(folder);
            const messageCount = await countMessages(transcript.path);
            const isLive = claudeRunning && transcript.mtime > thirtyMinutesAgo;

            log.debug(`[getSession] Found session ${sessionId} via metadata match in ${folder}`);
            return {
              id: sessionId,
              folderName: folder,
              project: getDisplayName(projectPath),
              projectPath,
              isLive,
              lastSeen: transcript.mtime.toISOString(),
              messageCount,
              transcriptPath: transcript.path,
            };
          }
        }
      } catch {
        continue;
      }
    }
  } catch (err) {
    log.error(`[getSession] Error searching all transcripts: ${err}`);
  }

  log.debug(`[getSession] Session ${sessionId} not found anywhere`);
  return null;
}

/**
 * Parse a single session file and return a ClaudeSession
 * Used for incremental cache updates
 */
export async function parseSessionFile(
  transcriptPath: string
): Promise<ClaudeSession | null> {
  try {
    const fileStat = await stat(transcriptPath);

    // Extract folder name from path
    // Path format: ~/.claude/projects/<folder>/<filename>.jsonl
    const parts = transcriptPath.split("/");
    const folder = parts[parts.length - 2];
    const filename = parts[parts.length - 1].replace(".jsonl", "");
    const projectDir = parts.slice(0, -1).join("/");

    // Get session ID
    let sessionId: string;
    if (isUUID(filename)) {
      sessionId = filename;
    } else {
      const metadata = await extractSessionMetadata(projectDir, transcriptPath);
      sessionId = metadata?.sessionId || filename;
    }

    // Get metadata
    const metadata = await extractSessionMetadata(projectDir, transcriptPath);
    const projectPath = metadata?.cwd || folderToPath(folder);

    // Count messages and check if live
    const messageCount = await countMessages(transcriptPath);
    const claudeRunning = await isClaudeRunning();
    const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);
    const isLive = claudeRunning && fileStat.mtime > thirtyMinutesAgo;

    return {
      id: sessionId,
      folderName: folder,
      project: getDisplayName(projectPath),
      projectPath,
      isLive,
      lastSeen: fileStat.mtime.toISOString(),
      messageCount,
      transcriptPath,
    };
  } catch (err) {
    log.warn(`[parseSessionFile] Failed to parse ${transcriptPath}: ${err}`);
    return null;
  }
}
