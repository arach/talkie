import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";

const CLAUDE_PROJECTS_DIR = `${process.env.HOME}/.claude/projects`;

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
 * Checks multiple files since the main UUID.jsonl may not have sessionId
 */
async function extractSessionMetadata(
  projectDir: string,
  transcriptPath: string
): Promise<{ sessionId?: string; cwd?: string } | null> {
  try {
    // First check if the transcript filename is a UUID
    const filename = transcriptPath.split('/').pop()?.replace('.jsonl', '') || '';
    if (isUUID(filename)) {
      console.log(`[metadata] Filename is UUID: ${filename}`);
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
              console.log(`[metadata] Found cwd from ${file}: ${entry.cwd}`);
              return { sessionId: filename, cwd: entry.cwd };
            }
          }
        }
      }
      // No cwd found, just return the UUID
      return { sessionId: filename, cwd: undefined };
    }

    // Otherwise try to extract from the file content
    const file = Bun.file(transcriptPath);
    const text = await file.text();
    const firstLine = text.split("\n")[0];
    if (!firstLine) {
      console.log(`[metadata] No first line in ${transcriptPath}`);
      return null;
    }

    const entry = JSON.parse(firstLine);
    const result = {
      sessionId: entry.sessionId,
      cwd: entry.cwd,
    };

    if (result.sessionId) {
      console.log(`[metadata] ${transcriptPath.split('/').pop()}: sessionId=${result.sessionId}, cwd=${result.cwd}`);
    } else {
      console.log(`[metadata] ${transcriptPath.split('/').pop()}: no sessionId found, keys: ${Object.keys(entry).join(', ')}`);
    }

    return result;
  } catch (e) {
    console.log(`[metadata] Error parsing ${transcriptPath}: ${e}`);
    return null;
  }
}

/**
 * Discover all Claude sessions from ~/.claude/projects/
 */
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
    console.error("Error reading Claude projects directory:", err);
  }

  // Sort by lastSeen, most recent first
  sessions.sort(
    (a, b) => new Date(b.lastSeen).getTime() - new Date(a.lastSeen).getTime()
  );

  return sessions;
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

        // Claude transcript format varies, handle common cases
        if (entry.type === "human" || entry.role === "user") {
          messages.push({
            role: "user",
            content: extractContent(entry),
            timestamp: entry.timestamp || new Date().toISOString(),
          });
        } else if (entry.type === "assistant" || entry.role === "assistant") {
          const msg: Message = {
            role: "assistant",
            content: extractContent(entry),
            timestamp: entry.timestamp || new Date().toISOString(),
          };

          // Extract tool calls if present
          if (entry.tool_calls || entry.toolCalls) {
            msg.toolCalls = (entry.tool_calls || entry.toolCalls).map(
              (tc: any) => ({
                name: tc.name || tc.function?.name,
                input: tc.input || tc.function?.arguments,
                output: tc.output,
              })
            );
          }

          messages.push(msg);
        }
      } catch {
        // Skip malformed lines
        continue;
      }
    }
  } catch (err) {
    console.error("Error parsing transcript:", err);
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
 * Get a specific session by ID
 */
export async function getSession(
  sessionId: string
): Promise<ClaudeSession | null> {
  const sessions = await discoverSessions();
  return sessions.find((s) => s.id === sessionId) || null;
}
