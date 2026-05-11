/**
 * Session Metadata Routes
 *
 * GET /sessions/:id/metadata    - Get full metadata for a session
 * GET /sessions/:id/entry/:idx  - Get raw entry at a specific index
 */

import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { getSession } from "../../discovery/sessions";
import { log } from "../../log";
import { notFound, serverError } from "./responses";

// ===== Types =====

export interface FileInfo {
  name: string;
  path: string;
  sizeBytes: number;
  modifiedAt: string;
  isSession: boolean;
}

export interface EntryInfo {
  index: number;
  type: string;
  timestamp?: string;
  sessionId?: string;
  cwd?: string;
  summary?: string;
  keys: string[];
  sizeBytes: number;
}

export interface SessionMetadata {
  session: {
    id: string;
    project: string;
    projectPath: string;
    folderName: string;
    isLive: boolean;
    lastSeen: string;
  };
  files: FileInfo[];
  entries: EntryInfo[];
  stats: {
    totalEntries: number;
    entryTypes: Record<string, number>;
    firstEntry: string | null;
    lastEntry: string | null;
    fileSizeBytes: number;
  };
}

export interface EntryResponse {
  index: number;
  entry: unknown;
}

// ===== Config =====

const CLAUDE_PROJECTS_DIR = `${process.env.HOME}/.claude/projects`;

// ===== Helpers =====

/**
 * Extract readable text from Claude's content format
 */
function extractTextContent(content: unknown): string {
  if (typeof content === "string") {
    return content.substring(0, 200);
  }

  if (Array.isArray(content)) {
    const texts = content
      .map((block: { type?: string; text?: string; name?: string }) => {
        if (typeof block === "string") return block;
        if (block.type === "text" && block.text) return block.text;
        if (block.type === "tool_use") return `[Tool: ${block.name}]`;
        if (block.type === "tool_result") return `[Tool Result]`;
        return "";
      })
      .filter(Boolean);
    return texts.join(" ").substring(0, 200);
  }

  if (content && typeof content === "object") {
    const obj = content as { text?: string; content?: unknown };
    if (obj.text) return String(obj.text).substring(0, 200);
    if (obj.content) return extractTextContent(obj.content);
  }

  return "";
}

// ===== Handlers =====

/**
 * GET /sessions/:id/metadata
 * Get full metadata for a session including all JSONL entries
 */
export async function sessionMetadataRoute(
  sessionId: string,
  _refresh: boolean = false
): Promise<SessionMetadata | Response> {
  const session = await getSession(sessionId);

  if (!session) {
    return notFound("Session not found");
  }

  try {
    const projectDir = join(CLAUDE_PROJECTS_DIR, session.folderName);

    // Get all files in the project directory
    const fileNames = await readdir(projectDir);
    const files: FileInfo[] = [];

    for (const fileName of fileNames) {
      const filePath = join(projectDir, fileName);
      const stats = await stat(filePath);
      if (stats.isFile()) {
        files.push({
          name: fileName,
          path: filePath,
          sizeBytes: stats.size,
          modifiedAt: stats.mtime.toISOString(),
          isSession: filePath === session.transcriptPath,
        });
      }
    }

    // Parse all entries from the session file
    const entries: EntryInfo[] = [];
    const entryTypes: Record<string, number> = {};
    let firstEntry: string | null = null;
    let lastEntry: string | null = null;
    let fileSizeBytes = 0;

    const file = Bun.file(session.transcriptPath);
    fileSizeBytes = file.size;
    const text = await file.text();
    const lines = text.trim().split("\n").filter(Boolean);

    for (let i = 0; i < lines.length; i++) {
      try {
        const line = lines[i];
        const entry = JSON.parse(line) as {
          type?: string;
          role?: string;
          timestamp?: string;
          sessionId?: string;
          cwd?: string;
          content?: unknown;
          message?: { content?: unknown };
          tool_calls?: Array<{ name?: string; function?: { name?: string } }>;
          path?: string;
        };
        const entryType = entry.type || entry.role || "unknown";

        entryTypes[entryType] = (entryTypes[entryType] || 0) + 1;

        if (entry.timestamp) {
          if (!firstEntry) firstEntry = entry.timestamp;
          lastEntry = entry.timestamp;
        }

        let summary = "";
        if (entry.content) {
          summary = extractTextContent(entry.content);
        } else if (entry.message?.content) {
          summary = extractTextContent(entry.message.content);
        } else if (entry.tool_calls) {
          summary = `Tools: ${entry.tool_calls.map((t) => t.name || t.function?.name).join(", ")}`;
        } else if (entry.cwd) {
          summary = `cwd: ${entry.cwd}`;
        } else if (entry.path) {
          summary = `Path: ${entry.path}`;
        }

        entries.push({
          index: i,
          type: entryType,
          timestamp: entry.timestamp,
          sessionId: entry.sessionId,
          cwd: entry.cwd,
          summary: summary || undefined,
          keys: Object.keys(entry),
          sizeBytes: line.length,
        });
      } catch {
        entries.push({
          index: i,
          type: "parse_error",
          keys: [],
          sizeBytes: lines[i].length,
        });
      }
    }

    return {
      session: {
        id: session.id,
        project: session.project,
        projectPath: session.projectPath,
        folderName: session.folderName,
        isLive: session.isLive,
        lastSeen: session.lastSeen,
      },
      files,
      entries,
      stats: {
        totalEntries: entries.length,
        entryTypes,
        firstEntry,
        lastEntry,
        fileSizeBytes,
      },
    };
  } catch (err) {
    log.error(`Error getting session metadata: ${err}`);
    return serverError("Failed to get metadata", String(err));
  }
}

/**
 * GET /sessions/:id/entry/:index
 * Get raw entry at a specific index
 */
export async function sessionEntryRoute(
  sessionId: string,
  entryIndex: number
): Promise<EntryResponse | Response> {
  const session = await getSession(sessionId);

  if (!session) {
    return notFound("Session not found");
  }

  try {
    const file = Bun.file(session.transcriptPath);
    const text = await file.text();
    const lines = text.trim().split("\n").filter(Boolean);

    if (entryIndex < 0 || entryIndex >= lines.length) {
      return notFound("Entry index out of range");
    }

    const entry = JSON.parse(lines[entryIndex]);
    return { index: entryIndex, entry };
  } catch (err) {
    return serverError("Failed to get entry", String(err));
  }
}
